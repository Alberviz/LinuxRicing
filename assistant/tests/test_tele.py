"""Tool `tele`: estado y mandos contra un cast-helper falso (sin red, sin Chromecast)."""
import json
import os
import stat
import sys
import types
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura.tools import tele as t  # noqa: E402


@pytest.fixture
def entorno(tmp_path, monkeypatch):
    run = tmp_path / "run"
    (run / "cast-helper").mkdir(parents=True)
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(run))
    registro = tmp_path / "llamadas.txt"
    exe = tmp_path / "cast-helper"
    exe.write_text(f'#!/bin/sh\necho "$@" >> {registro}\necho \'{{"ok": true}}\'\n')
    exe.chmod(exe.stat().st_mode | stat.S_IXUSR)
    monkeypatch.setattr(t, "_bin", lambda: str(exe))

    def estado(active):
        (run / "cast-helper" / "state.json").write_text(json.dumps({"devices": [], "active": active, "error": None}))
    estado({"title": "Wicked", "state": "PLAYING", "position": 100.0, "duration": 9000.0, "volume": 80})
    return types.SimpleNamespace(estado=estado, llamadas=lambda: registro.read_text().splitlines() if registro.exists() else [])


def test_estado(entorno):
    r = t.tele("estado")
    assert r["ok"] and "Wicked" in r["decir"] and "reproduciendo" in r["decir"] and "volumen 80" in r["decir"]


def test_estado_en_reposo_y_sin_daemon(entorno):
    entorno.estado(None)
    assert t.tele("estado")["decir"] == "La tele está en reposo."
    os.unlink(Path(os.environ["XDG_RUNTIME_DIR"]) / "cast-helper" / "state.json")
    assert not t.tele("estado")["ok"]


@pytest.mark.parametrize("accion,valor,esperado", [
    ("pausar", None, "pause"), ("reanudar", None, "play"), ("parar", None, "stop"), ("silenciar", None, "mute"),
    ("volumen", 40, "volume 40"), ("saltar", 30, "seek 130"), ("saltar", -200, "seek 0"), ("ir_a", 600, "seek 600"),
])
def test_mandos(entorno, accion, valor, esperado):
    assert t.tele(accion, valor)["ok"]
    assert entorno.llamadas() == [esperado]


def test_validaciones(entorno):
    assert not t.tele("volumen", 150)["ok"] and not t.tele("volumen")["ok"] and not t.tele("saltar")["ok"]
    assert not t.tele("hackear")["ok"]
    assert entorno.llamadas() == []
    entorno.estado(None)
    assert "nada reproduciendo" in t.tele("pausar")["error"] and entorno.llamadas() == []
