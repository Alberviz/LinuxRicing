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
