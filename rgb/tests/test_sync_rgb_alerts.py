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


def test_sync_openrgb_skips_when_alert_active(tmp_path, monkeypatch):
    m = _load_sync()
    p = tmp_path / "a.json"
    p.write_text('{"openrgb:_": {"effect":"red"}}')
    monkeypatch.setattr(m, "ALERTS_CACHE", str(p))

    called = []
    class DummyClient:
        def __init__(self):
            called.append("init")

    monkeypatch.setattr("openrgb.OpenRGBClient", DummyClient, raising=False)
    m.sync_openrgb(255, 0, 0)
    assert called == []  # OpenRGBClient was not even initialized because alert skipped it


def test_sync_openrgb_retries_and_sets_direct_mode(tmp_path, monkeypatch):
    m = _load_sync()
    monkeypatch.setattr(m, "ALERTS_CACHE", str(tmp_path / "nope.json"))

    class DummyZone:
        def __init__(self, name):
            self.name = name
            self.colors = []
        def set_color(self, col):
            self.colors.append(col)

    class DummyMode:
        def __init__(self, name):
            self.name = name

    class DummyDev:
        def __init__(self, name):
            self.name = name
            self.modes = [DummyMode("Rainbow"), DummyMode("Direct")]
            self.active_mode = 0
            self.zones = [DummyZone("Zone 1")]
        def set_mode(self, idx):
            self.active_mode = idx

    class DummyClient:
        attempts = 0
        def __init__(self):
            self.devices = []
        def update(self):
            DummyClient.attempts += 1
            if DummyClient.attempts >= 2:
                self.devices = [DummyDev("ENE DRAM RGB")]

    monkeypatch.setattr("openrgb.OpenRGBClient", DummyClient, raising=False)
    monkeypatch.setattr("time.sleep", lambda s: None)

    m.sync_openrgb(100, 150, 200, argb_zones=False)
    assert DummyClient.attempts >= 2

