import json


def _write(bl, obj):
    with open(bl.CONFIG_PATH, "w") as f:
        json.dump(obj, f)


def test_module_exposes_paths_and_defaults(bl):
    assert bl.CONFIG_PATH.endswith("battery-lighting.json")
    assert isinstance(bl.DEFAULTS, dict)
    assert bl.DEFAULTS["poll"] == {"idle_seconds": 60, "charging_seconds": 3}
    assert bl.DEFAULTS["critical_threshold"] == 10
    assert any(r["id"] == "akko-low" for r in bl.DEFAULTS["rules"])


def test_main_help_returns_zero(bl, capsys):
    assert bl.main(["--help"]) == 0
    assert "battery-lighting" in capsys.readouterr().out


def test_missing_file_yields_defaults(bl):
    cfg = bl.load_config()
    assert cfg["rules"] == bl.DEFAULTS["rules"]


def test_garbage_file_yields_defaults(bl):
    with open(bl.CONFIG_PATH, "w") as f:
        f.write("{not json")
    assert bl.load_config()["rules"] == bl.DEFAULTS["rules"]


def test_validate_drops_unknown_source_keeps_rest(bl):
    raw = {"rules": [
        {"id": "bad", "source": "toaster", "trigger": "low", "threshold": 20, "actions": []},
        {"id": "ok", "source": "v9_headset", "trigger": "low", "threshold": 15,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]},
    ]}
    cfg, errors = bl.validate_config(raw)
    ids = [r["id"] for r in cfg["rules"]]
    assert ids == ["ok"]
    assert any("toaster" in e for e in errors)


def test_validate_drops_invalid_effect_for_target(bl):
    raw = {"rules": [{"id": "r", "source": "v9_headset", "trigger": "low", "threshold": 20,
                      "actions": [
                          {"target": "magichome", "effect": "battery_meter"},   # inválido en magichome
                          {"target": "magichome", "effect": "red"},
                      ]}]}
    cfg, errors = bl.validate_config(raw)
    effs = [a["effect"] for a in cfg["rules"][0]["actions"]]
    assert effs == ["red"]


def test_validate_low_threshold_clamped_5_40(bl):
    raw = {"rules": [{"id": "r", "source": "v9_headset", "trigger": "low", "threshold": 999,
                      "actions": [{"target": "mchose_base", "effect": "red_static"}]}]}
    cfg, _ = bl.validate_config(raw)
    assert cfg["rules"][0]["threshold"] == 40


def test_validate_both_zone_allowed_only_for_akko(bl):
    raw = {"rules": [{"id": "r", "source": "akko_keyboard", "trigger": "low", "threshold": 20,
                      "actions": [{"target": "mchose_base", "zone": "both", "effect": "red_static"}]}]}
    cfg, _ = bl.validate_config(raw)
    assert "zone" not in cfg["rules"][0]["actions"][0] or cfg["rules"][0]["actions"][0]["zone"] is None
