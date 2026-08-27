import json


def _cfg_one_low():
    return {"poll": {"idle_seconds": 60, "charging_seconds": 3}, "critical_threshold": 10,
            "rules": [{"id": "r", "source": "mchose_mouse", "trigger": "low", "threshold": 20,
                       "actions": [{"target": "mchose_base", "effect": "red_breathing"}]}]}


def test_tick_writes_alerts_for_active_rule(bl, monkeypatch):
    monkeypatch.setattr(bl, "theme_primary_rgb", lambda: (1, 2, 3))
    applied = []
    monkeypatch.setattr(bl, "apply_zone", lambda zk, act, th: applied.append((zk, act and act["effect"])))
    monkeypatch.setattr(bl, "send_notification", lambda *a, **k: None)
    tele = {"akko_keyboard": {"level": None, "charging": False, "connected": False},
            "mchose_mouse": {"level": 15, "charging": False, "connected": True},
            "v9_headset": {"level": None, "charging": False, "connected": False}}
    out = bl.tick(_cfg_one_low(), tele)
    assert "mchose_base:_" in out
    assert json.loads(open(bl.ALERTS_CACHE).read())["mchose_base:_"]["effect"] == "red_breathing"
    assert ("mchose_base:_", "red_breathing") in applied


def test_tick_releases_zone_when_rule_clears(bl, monkeypatch):
    monkeypatch.setattr(bl, "theme_primary_rgb", lambda: (1, 2, 3))
    with open(bl.ALERTS_CACHE, "w") as f:
        json.dump({"mchose_base:_": {"effect": "red_breathing", "trigger": "low",
                                     "source": "mchose_mouse", "level": 15}}, f)
    released = []
    monkeypatch.setattr(bl, "apply_zone", lambda zk, act, th: released.append((zk, act)))
    monkeypatch.setattr(bl, "send_notification", lambda *a, **k: None)
    tele = {"akko_keyboard": {"level": None, "charging": False, "connected": False},
            "mchose_mouse": {"level": 80, "charging": False, "connected": True},
            "v9_headset": {"level": None, "charging": False, "connected": False}}
    out = bl.tick(_cfg_one_low(), tele)
    assert out == {}
    assert ("mchose_base:_", None) in released       # None -> repinta al tema
    assert json.loads(open(bl.ALERTS_CACHE).read()) == {}


def test_tick_only_applies_changed_zones(bl, monkeypatch):
    monkeypatch.setattr(bl, "theme_primary_rgb", lambda: (1, 2, 3))
    with open(bl.ALERTS_CACHE, "w") as f:
        json.dump({"mchose_base:_": {"effect": "red_breathing", "trigger": "low",
                                     "source": "mchose_mouse", "level": 15}}, f)
    applied = []
    monkeypatch.setattr(bl, "apply_zone", lambda zk, act, th: applied.append(zk))
    monkeypatch.setattr(bl, "send_notification", lambda *a, **k: None)
    tele = {"akko_keyboard": {"level": None, "charging": False, "connected": False},
            "mchose_mouse": {"level": 14, "charging": False, "connected": True},
            "v9_headset": {"level": None, "charging": False, "connected": False}}
    bl.tick(_cfg_one_low(), tele)
    assert applied == []              # misma effect/trigger -> no reescribe hardware


def test_main_dump_prints_json(bl, monkeypatch, capsys):
    monkeypatch.setattr(bl, "read_telemetry", lambda: {
        "akko_keyboard": {"level": None, "charging": False, "connected": False},
        "mchose_mouse": {"level": None, "charging": False, "connected": False},
        "v9_headset": {"level": None, "charging": False, "connected": False}})
    assert bl.main(["--dump"]) == 0
    json.loads(capsys.readouterr().out)   # salida es JSON válido
