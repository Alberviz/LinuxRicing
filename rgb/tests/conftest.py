import importlib.util
import os
from importlib.machinery import SourceFileLoader
from pathlib import Path
import pytest

_SRC = Path(__file__).resolve().parents[1] / "battery-lighting"


def _load():
    loader = SourceFileLoader("battery_lighting", str(_SRC))
    spec = importlib.util.spec_from_loader("battery_lighting", loader)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def bl(monkeypatch, tmp_path):
    mod = _load()
    monkeypatch.setattr(mod, "CONFIG_PATH", str(tmp_path / "battery-lighting.json"))
    monkeypatch.setattr(mod, "ALERTS_CACHE", str(tmp_path / "battery_alerts.json"))
    monkeypatch.setattr(mod, "BATTERY_CACHE", str(tmp_path / "mchose_battery.json"))
    monkeypatch.setattr(mod, "STATE_CACHE", str(tmp_path / "battery_lighting_state.json"))
    monkeypatch.setattr(mod, "LOG_FILE", str(tmp_path / "battery_lighting.log"))
    monkeypatch.setattr(mod, "AKKO_CONFIG_LEGACY", str(tmp_path / "akko-config.json"))
    monkeypatch.setattr(mod, "MCHOSE_CONFIG_LEGACY", str(tmp_path / "mchose-config.json"))
    return mod
