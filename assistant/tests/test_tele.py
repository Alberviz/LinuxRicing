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


# ───────────── mandar_a_tele ─────────────
@pytest.fixture
def mandar(entorno, monkeypatch, tmp_path):
    """playerctl/wl-paste/hyprctl falsos: `sh` responde según un dict {comando: salida}."""
    respuestas: dict[str, str] = {}
    ordenes: list[str] = []

    def sh(*cmd):
        clave = " ".join(cmd)
        ordenes.append(clave)
        return respuestas.get(clave, "")
    monkeypatch.setattr(t, "_sh", sh)
    entorno_devs = {"devices": [{"name": "Comedor", "uuid": "u1"}], "active": None, "error": None}
    (Path(os.environ["XDG_RUNTIME_DIR"]) / "cast-helper" / "state.json").write_text(json.dumps(entorno_devs))
    return types.SimpleNamespace(r=respuestas, ordenes=ordenes, llamadas=entorno.llamadas, tmp=tmp_path)


def _player(m, p, status, url, pos="0", title=""):
    m.r["playerctl -l"] = (m.r.get("playerctl -l", "") + "\n" + p).strip()
    m.r[f"playerctl -p {p} status"] = status
    m.r[f"playerctl -p {p} metadata xesam:url"] = url
    m.r[f"playerctl -p {p} position"] = pos
    m.r[f"playerctl -p {p} metadata xesam:title"] = title


def test_manda_el_video_del_navegador(mandar):
    _player(mandar, "chromium.instance1", "Playing", "https://www.youtube.com/watch?v=abc", "754.2", "Un vídeo")
    r = t.mandar_a_tele("video")
    assert r["ok"]
    assert mandar.llamadas() == ["cast Comedor https://www.youtube.com/watch?v=abc --start 754 --title Un vídeo"]
    assert "playerctl -p chromium.instance1 pause" in mandar.ordenes


def test_prefiere_el_que_suena_y_archivo_local(mandar):
    _player(mandar, "chromium.instance1", "Paused", "https://www.youtube.com/watch?v=x")
    _player(mandar, "mpv", "Playing", "file:///home/a/Pel%C3%ADcula.mkv", "2")
    assert t.mandar_a_tele("video")["ok"]
    assert mandar.llamadas() == ["cast Comedor /home/a/Película.mkv"]


def test_spotify_no_es_video(mandar):
    _player(mandar, "spotify", "Playing", "https://open.spotify.com/track/1")
    r = t.mandar_a_tele("video")
    assert not r["ok"] and "Spotify" in r["error"] and mandar.llamadas() == []


def test_portapapeles_y_nada(mandar):
    assert not t.mandar_a_tele("video")["ok"]
    mandar.r["wl-paste -n"] = "https://vimeo.com/123"
    assert t.mandar_a_tele("video")["ok"] and mandar.llamadas() == ["cast Comedor https://vimeo.com/123"]


def test_destino_explicito(mandar):
    f = mandar.tmp / "peli.mp4"
    f.write_text("x")
    assert t.mandar_a_tele("video", str(f))["ok"]
    assert not t.mandar_a_tele("video", "/no/existe.mkv")["ok"]
    assert mandar.llamadas() == [f"cast Comedor {f}"]


def test_pantalla_y_escritorio(mandar):
    assert t.mandar_a_tele("pantalla")["ok"]
    assert t.mandar_a_tele("escritorio", "3")["ok"]
    mandar.r["hyprctl activeworkspace -j"] = '{"id": 2}'
    assert t.mandar_a_tele("escritorio")["ok"]
    assert mandar.llamadas() == ["mirror start --source monitor", "mirror start --source workspace:3",
                                 "mirror start --source workspace:2"]
