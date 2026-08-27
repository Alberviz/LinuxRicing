def test_module_exposes_paths_and_defaults(bl):
    assert bl.CONFIG_PATH.endswith("battery-lighting.json")
    assert isinstance(bl.DEFAULTS, dict)
    assert bl.DEFAULTS["poll"] == {"idle_seconds": 60, "charging_seconds": 3}
    assert bl.DEFAULTS["critical_threshold"] == 10
    assert any(r["id"] == "akko-low" for r in bl.DEFAULTS["rules"])


def test_main_help_returns_zero(bl, capsys):
    assert bl.main(["--help"]) == 0
    assert "battery-lighting" in capsys.readouterr().out
