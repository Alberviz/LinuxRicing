import importlib.util
from pathlib import Path

_SR = Path(__file__).resolve().parents[1] / "sync-rgb.py"


def _load_sync():
    spec = importlib.util.spec_from_file_location("sync_rgb", _SR)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def test_battery_alert_zones_empty_without_file(tmp_path, monkeypatch):
    m = _load_sync()
    monkeypatch.setattr(m, "ALERTS_CACHE", str(tmp_path / "nope.json"))
    assert m.battery_alert_zones() == set()


def test_battery_alert_zones_parses(tmp_path, monkeypatch):
    m = _load_sync()
    p = tmp_path / "a.json"
    p.write_text('{"mchose_base:_": {"effect":"red_breathing"}, "akko_keyboard:keys": {}}')
    monkeypatch.setattr(m, "ALERTS_CACHE", str(p))
    assert m.battery_alert_zones() == {"mchose_base:_", "akko_keyboard:keys"}
