"""Tool `spotify`: traduce acciones a llamadas al CLI spotify-tele (falso, sin Spotify)."""
import stat
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura.tools import spotify as t  # noqa: E402


@pytest.fixture
def cli(tmp_path, monkeypatch):
    reg = tmp_path / "llamadas.txt"
    exe = tmp_path / "spotify-tele"
    exe.write_text(f"""#!/bin/sh
printf '%s|' "$@" >> {reg}; echo >> {reg}
case "$1" in
  poner) echo '{{"ok": true, "puesto": {{"nombre": "RealG4lifebaby"}}, "ahora": {{"dispositivo": "Comedor", "cancion": "Mbappe", "sonando": true}}}}';;
  estado) echo '{{"ok": true, "abierto": true, "cancion": "Mbappe", "artista": "Eladio", "dispositivo": "Comedor", "sonando": true}}';;
  *) echo '{{"ok": true, "ahora": {{"cancion": "Otra", "artista": "X", "sonando": true}}}}';;
esac
""")
    exe.chmod(exe.stat().st_mode | stat.S_IXUSR)
    monkeypatch.setattr(t, "_bin", lambda: str(exe))
    return lambda: [l.rstrip("|") for l in reg.read_text().splitlines()] if reg.exists() else []


def test_poner_en_la_tele_desde_inicio(cli):
    r = t.spotify("poner", que="realg4life", tipo="playlist", donde="tele", desde_inicio=True)
    assert r["ok"] and "RealG4lifebaby" in r["decir"] and "Comedor" in r["decir"]
    assert cli() == ["poner|realg4life|--tipo|playlist|--donde|tele|--desde-inicio"]


def test_poner_por_defecto_y_sin_que(cli):
    assert t.spotify("poner", que="bad bunny")["ok"]
    assert not t.spotify("poner")["ok"]
    assert cli() == ["poner|bad bunny|--tipo|auto|--donde|actual"]


@pytest.mark.parametrize("kw,esperado", [
    ({"accion": "pasar_a_tele"}, "pasar|tele"), ({"accion": "pasar_al_pc"}, "pasar|pc"),
    ({"accion": "reiniciar_cancion"}, "control|reiniciar"),
    ({"accion": "aleatorio_no"}, "control|aleatorio|no"), ({"accion": "repetir_cancion"}, "control|repetir|cancion"),
    ({"accion": "volumen", "valor": 30}, "control|volumen|30"), ({"accion": "anadir_a_la_cola", "que": "mbappe"}, "control|cola|mbappe"),
    ({"accion": "poner_a_continuacion", "que": "mbappe"}, "control|despues|mbappe"),
    ({"accion": "me_gusta"}, "control|me_gusta"), ({"accion": "temporizador", "valor": "20"}, "control|temporizador|20"),
])
def test_mandos(cli, kw, esperado):
    assert t.spotify(**kw)["ok"]
    assert cli() == [esperado]


def test_que_suena_y_validaciones(cli):
    assert "Mbappe" in t.spotify("que_suena")["decir"]
    assert not t.spotify("volumen")["ok"] and not t.spotify("anadir_a_la_cola")["ok"] and not t.spotify("hackear")["ok"]
    assert cli() == ["estado"]


@pytest.mark.parametrize("que,tipo,esperado", [
    ("playlist: RealG4Life", None, ("RealG4Life", "playlist")),
    ("mi playlist de RealG4Life", None, ("RealG4Life", "playlist")),
    ("Playlist Relaxing Jazz", "auto", ("Relaxing Jazz", "playlist")),
    ("canción: Mbappe", None, ("Mbappe", "cancion")),
    ("álbum: Thriller", "album", ("Thriller", "album")),
    ("bad bunny", None, ("bad bunny", None)),
    ("playlist", None, ("playlist", None)),
])
def test_limpiar_prefijo_de_tipo(que, tipo, esperado):
    assert t._limpiar_que(que, tipo) == esperado


def test_poner_quita_el_prefijo(cli):
    assert t.spotify("poner", que="playlist: RealG4Life", donde="tele")["ok"]
    assert cli() == ["poner|RealG4Life|--tipo|playlist|--donde|tele"]


def test_poner_con_candidatos_pregunta(tmp_path, monkeypatch):
    monkeypatch.setattr(t, "_cmd", lambda *a, **k: {"ok": False, "error": "no tengo", "candidatos": ["RealG4lifebaby", "la miaa_real"]})
    r = t.spotify("poner", que="playlist: Reality for Life")
    assert not r["ok"] and "RealG4lifebaby o la miaa_real" in r["decir"]


def test_poner_sin_nombre_no_deja_hueco(monkeypatch):
    monkeypatch.setattr(t, "_cmd", lambda *a, **k: {"ok": True, "puesto": {"nombre": ""}, "ahora": {"dispositivo": "Comedor", "volumen": 3}})
    r = t.spotify("poner", que="RealG4Life", donde="tele")
    assert "Poniendo RealG4Life en la tele (Comedor)." in r["decir"] and "3 %" in r["decir"]
