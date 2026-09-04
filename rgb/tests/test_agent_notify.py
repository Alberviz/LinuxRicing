import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
import pytest

_SRC = Path(__file__).resolve().parents[1] / "agent-notify"


def _load():
    loader = SourceFileLoader("agent_notify", str(_SRC))
    spec = importlib.util.spec_from_loader("agent_notify", loader)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def an():
    return _load()


def test_build_agent_data_has_all_contract_keys(an):
    d = an.build_agent_data(name="Claude", status="Completado", task="rgb refactor",
                            duration="2m 14s", address="0x1", ws=3, terminal="kitty")
    for k in ("id", "name", "task", "status", "dir", "ws", "address", "duration", "terminal"):
        assert k in d
    assert d["task"] == "rgb refactor"
    assert d["ws"] == 3
    assert d["id"].startswith("agent-")


def test_task_defaults_to_status_when_absent(an):
    d = an.build_agent_data(name="X", status="Completado", task=None,
                            duration="", address="", ws=1, terminal="")
    assert d["task"] == "Completado"


def test_parser_notify_accepts_task_flag(an):
    args = an.build_parser().parse_args(["notify", "-n", "Claude", "-t", "mi tarea"])
    assert args.name == "Claude"
    assert args.task == "mi tarea"


def test_parser_run_captures_remainder(an):
    args = an.build_parser().parse_args(["run", "-n", "Claude", "--", "echo", "hi"])
    assert args.name == "Claude"
    assert args.command[-2:] == ["echo", "hi"]


def test_window_fallback_without_hyprctl(an, monkeypatch):
    def boom(*a, **k):
        raise FileNotFoundError("hyprctl")
    monkeypatch.setattr(an.subprocess, "run", boom)
    win = an.get_hyprland_window()
    assert win["ws_id"] == 1
    assert win["address"] == ""


def test_run_wrapper_propagates_exit_code(an, monkeypatch):
    monkeypatch.setattr(an, "start_agent", lambda **k: None)
    monkeypatch.setattr(an, "finish_agent", lambda **k: None)

    class R:  # fake CompletedProcess
        returncode = 7
    monkeypatch.setattr(an.subprocess, "run", lambda *a, **k: R())
    with pytest.raises(SystemExit) as e:
        an.run_wrapped_command(["false"], name="Claude")
    assert e.value.code == 7


def test_hook_prompt_starts_agent_from_stdin(an, monkeypatch):
    calls = {}
    monkeypatch.setattr(an, "start_agent", lambda **k: calls.update(k))
    monkeypatch.setattr(an.sys.stdin, "isatty", lambda: False)
    monkeypatch.setattr(an.sys.stdin, "read", lambda: '{"cwd":"/tmp/proj","prompt":"haz X"}')
    an.cmd_hook("prompt")
    assert calls["name"] == "Claude"
    assert calls["task"] == "haz X"
    assert calls["cwd"] == "/tmp/proj"


def test_set_config_writes_key(an, monkeypatch, tmp_path):
    cfg = tmp_path / "agents-config.json"
    monkeypatch.setattr(an, "AGENTS_CONFIG", cfg)
    an.set_config("runningStyle", "breathe")
    import json
    assert json.loads(cfg.read_text())["runningStyle"] == "breathe"


def test_run_with_no_command_exits_nonzero(an, monkeypatch):
    import sys as sys_module
    monkeypatch.setattr(sys_module, "argv", ["agent-notify", "run"])
    with pytest.raises(SystemExit) as e:
        an.main()
    assert e.value.code == 1


def test_is_hook_managed(an):
    assert an._is_hook_managed(["/path/to/claude"], "Claude") is True
    assert an._is_hook_managed(["/path/to/agy"], "Antigravity") is True
    assert an._is_hook_managed(["/path/to/agy", "-c"], "Antigravity") is True
    assert an._is_hook_managed(["/usr/bin/make", "-j4"], "Compiler") is False
    assert an._is_hook_managed(["/bin/sh"], "Build") is False


def test_run_wrapper_hook_managed_starts_session_not_running(an, monkeypatch):
    session_started = []
    agent_started = []
    monkeypatch.setattr(an, "start_session", lambda **k: session_started.append(k))
    monkeypatch.setattr(an, "stop_session", lambda **k: None)
    monkeypatch.setattr(an, "start_agent", lambda **k: agent_started.append(k))
    monkeypatch.setattr(an, "finish_agent", lambda **k: None)

    class R:
        returncode = 0
    monkeypatch.setattr(an.subprocess, "run", lambda *a, **k: R())
    with pytest.raises(SystemExit):
        an.run_wrapped_command(["/usr/local/bin/agy"], name="Antigravity")

    assert len(session_started) == 1
    assert len(agent_started) == 0  # Does NOT mark running on launch!


def test_cmd_hook_antigravity_outputs_valid_json(an, monkeypatch, capsys):
    calls = {}
    monkeypatch.setattr(an, "start_agent", lambda **k: calls.update(k))
    monkeypatch.setattr(an.sys.stdin, "isatty", lambda: False)
    monkeypatch.setattr(an.sys.stdin, "read", lambda: '{"conversationId":"abc-123","workspacePaths":["/tmp"]}')
    an.cmd_hook("prompt")
    assert calls["name"] == "Antigravity"
    captured = capsys.readouterr()
    import json
    parsed = json.loads(captured.out.strip())
    assert "injectSteps" in parsed


def test_cmd_hook_antigravity_invocation_greater_than_zero_skips_start(an, monkeypatch, capsys):
    calls = []
    monkeypatch.setattr(an, "start_agent", lambda **k: calls.append(k))
    monkeypatch.setattr(an.sys.stdin, "isatty", lambda: False)
    monkeypatch.setattr(an.sys.stdin, "read", lambda: '{"conversationId":"abc-123","workspacePaths":["/tmp"],"invocationNum":2}')
    an.cmd_hook("prompt")
    # Intermediate steps (tool calls) must NOT re-call start_agent
    assert len(calls) == 0
    captured = capsys.readouterr()
    import json
    parsed = json.loads(captured.out.strip())
    assert "injectSteps" in parsed


def test_start_agent_preserves_start_time(an, tmp_path, monkeypatch):
    import json
    monkeypatch.setattr(an, "STATE_DIR", tmp_path)
    monkeypatch.setattr(an, "quickshell_ipc", lambda *a, **k: None)
    monkeypatch.setattr(an, "get_hyprland_window", lambda **k: {
        "address": "0x123", "ws_id": 1, "class": "foot", "title": "foot", "pid": 100
    })

    # First call
    an.start_agent(name="Antigravity", task="Step 1")
    state_file = tmp_path / "123.json"
    assert state_file.exists()
    first_time = json.loads(state_file.read_text())["startTime"]

    # Second call some time later
    monkeypatch.setattr(an.time, "time", lambda: (first_time / 1000) + 100)
    an.start_agent(name="Antigravity", task="Step 2")
    preserved_time = json.loads(state_file.read_text())["startTime"]
    assert preserved_time == first_time


def test_start_session_persists_to_disk_and_sends_ipc(an, tmp_path, monkeypatch):
    import json
    ipc_calls = []
    sessions_dir = tmp_path / "sessions"
    monkeypatch.setattr(an, "STATE_DIR", tmp_path)
    monkeypatch.setattr(an, "SESSIONS_DIR", sessions_dir)
    monkeypatch.setattr(an, "quickshell_ipc", lambda method, data: ipc_calls.append((method, data)))
    monkeypatch.setattr(an, "get_hyprland_window", lambda **k: {
        "address": "0xabc", "ws_id": 2, "class": "kitty", "title": "kitty", "pid": 200
    })

    data = an.start_session(name="Antigravity", target_pid=200)
    assert (sessions_dir / "abc.json").exists()
    saved = json.loads((sessions_dir / "abc.json").read_text())
    assert saved["name"] == "Antigravity"
    assert saved["status"] == "session"
    assert len(ipc_calls) == 1
    assert ipc_calls[0][0] == "sessionStart"


def test_stop_session_unlinks_disk_and_sends_ipc(an, tmp_path, monkeypatch):
    ipc_calls = []
    sessions_dir = tmp_path / "sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)
    (sessions_dir / "abc.json").write_text("{}")

    monkeypatch.setattr(an, "STATE_DIR", tmp_path)
    monkeypatch.setattr(an, "SESSIONS_DIR", sessions_dir)
    monkeypatch.setattr(an, "quickshell_ipc", lambda method, data: ipc_calls.append((method, data)))

    an.stop_session(name="Antigravity", address="0xabc")
    assert not (sessions_dir / "abc.json").exists()
    assert len(ipc_calls) == 1
    assert ipc_calls[0][0] == "sessionStop"


def test_finish_agent_refreshes_session(an, tmp_path, monkeypatch):
    session_calls = []
    monkeypatch.setattr(an, "STATE_DIR", tmp_path)
    monkeypatch.setattr(an, "SESSIONS_DIR", tmp_path / "sessions")
    monkeypatch.setattr(an, "quickshell_ipc", lambda *a, **k: None)
    monkeypatch.setattr(an, "send_desktop_notification", lambda *a, **k: None)
    monkeypatch.setattr(an, "get_hyprland_window", lambda **k: {
        "address": "0xdef", "ws_id": 3, "class": "kitty", "title": "kitty", "pid": 300
    })
    monkeypatch.setattr(an, "start_session", lambda **k: session_calls.append(k))

    an.finish_agent(name="Claude", status="Completado")
    assert len(session_calls) == 1
    assert session_calls[0]["name"] == "Claude"


