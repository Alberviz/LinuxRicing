"""Tool `spotify`: traduce acciones a llamadas al CLI spotify-tele (falso, sin Spotify)."""
import stat
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura.tools import spotify as t  # noqa: E402


@pytest.fixture(autouse=True)
def sin_alias_reales(monkeypatch):
    """Los tests no dependen de los alias de config.toml."""
    monkeypatch.setattr(t, "_alias", lambda: {})


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


ALIAS = {"lo de siempre": "RealG4lifebaby", "reggaeton": "RealG4lifebaby", "regueton": "RealG4lifebaby",
         "nuestra historia": "Nuestra historia 💖", "con mi novia": "Nuestra historia 💖", "bonita": "Nuestra historia 💖"}


@pytest.fixture
def falso(monkeypatch):
    """_cmd falso que registra los argumentos y contesta según el subcomando."""
    llamadas, respuestas = [], {}
    def cmd(*a, **k):
        llamadas.append(list(a))
        return respuestas.get(a[0], {"ok": True, "puesto": {"nombre": a[1] if len(a) > 1 else ""}, "ahora": {}})
    monkeypatch.setattr(t, "_cmd", cmd)
    monkeypatch.setattr(t, "_alias", lambda: {t._clave(k): v for k, v in ALIAS.items()})
    t._PENDIENTE.clear()
    return llamadas, respuestas


@pytest.mark.parametrize("que,esperado", [
    ("mi playlist de reguetón", "RealG4lifebaby"), ("reggaeton", "RealG4lifebaby"), ("lo de siempre", "RealG4lifebaby"),
    ("la playlist que tengo con mi novia", "Nuestra historia 💖"), ("la playlist bonita", "Nuestra historia 💖"),
    ("nuestrahistoria", None), ("Nuestra Historia", "Nuestra historia 💖"),
])
def test_alias(falso, que, esperado):
    llamadas, _ = falso
    t.spotify("poner", que=que, donde="tele")
    assert llamadas[-1][1] == (esperado or que)
    if esperado:
        assert llamadas[-1][3] == "playlist"


def test_lo_mas_nuevo_de_lo_de_siempre(falso):
    llamadas, _ = falso
    r = t.spotify("poner", que="lo más nuevo de lo de siempre", donde="tele")
    assert llamadas == [["poner", "RealG4lifebaby", "--tipo", "playlist", "--donde", "tele", "--orden", "recientes", "--desde-inicio"]]
    assert "lo último que añadiste" in r["decir"]
    t.spotify("poner", que="lo de siempre", recientes=True)
    assert llamadas[-1][-2:] == ["recientes", "--desde-inicio"]


def test_lo_mas_nuevo_de_una_playlist_sin_alias(falso):
    llamadas, resp = falso
    resp["encontrar"] = {"ok": True, "encontrado": {"nombre": "Drill Elite ", "uri": "spotify:playlist:X", "tipo": "playlist"}}
    r = t.spotify("poner", que="las últimas de drill elite")
    assert llamadas[0] == ["encontrar", "drill elite", "--tipo", "auto"]
    assert llamadas[1][:2] == ["poner", "spotify:playlist:X"] and "recientes" in llamadas[1]
    assert "Drill Elite" in r["decir"]


ULT = {"ok": True, "encontrado": {"nombre": "FILIPENSES", "uri": "spotify:album:4DMT", "tipo": "album", "de": "La Pantera",
                                  "clase": "álbum", "anio": 2026, "mes": 11, "dia": 6}}


@pytest.mark.parametrize("kw", [
    {"accion": "poner", "que": "el último álbum de La Pantera"},
    {"accion": "buscar", "que": "La Pantera", "ultimo": True, "tipo": "album"},
    {"accion": "buscar", "que": "último disco de la pantera"},
])
def test_ultimo_album_pregunta_y_luego_pone(falso, kw):
    llamadas, resp = falso
    resp["ultimo"] = ULT
    r = t.spotify(**kw, donde="tele")
    assert llamadas[0][0] == "ultimo" and llamadas[0][1].lower() == "la pantera" and llamadas[0][-1] == "album"
    assert r["ok"] and "«FILIPENSES»" in r["decir"] and "6 de noviembre de 2026" in r["decir"] and r["decir"].endswith("¿Lo pongo?")
    r = t.spotify("poner_lo_encontrado")
    assert llamadas[-1] == ["poner", "spotify:album:4DMT", "--tipo", "album", "--donde", "tele"]
    assert r["decir"].startswith("Poniendo FILIPENSES")
    assert not t.spotify("poner_lo_encontrado")["ok"]  # ya no queda nada pendiente


def test_lo_ultimo_de_un_artista(falso):
    llamadas, resp = falso
    resp["encontrar"] = {"ok": True, "encontrado": {"nombre": "La Pantera", "uri": "spotify:artist:Y", "tipo": "artista"}}
    resp["ultimo"] = ULT
    r = t.spotify("poner", que="lo último de la pantera")
    assert [l[0] for l in llamadas] == ["encontrar", "ultimo"] and llamadas[1][-1] == "cualquiera"
    assert "¿Lo pongo?" in r["decir"]


def test_buscar_generico(falso):
    llamadas, resp = falso
    resp["encontrar"] = {"ok": True, "encontrado": {"nombre": "Mbappe", "uri": "spotify:track:Z", "tipo": "cancion", "de": "Eladio"}}
    assert t.spotify("buscar", que="mbappe")["decir"] == "He encontrado «Mbappe» de Eladio. ¿La pongo?"


def test_cola_nueva_y_limpiar(falso):
    llamadas, resp = falso
    resp["cola"] = {"ok": True, "total": 3, "reproduciendo": {"nombre": "Dakiti"}}
    r = t.spotify("cola_nueva", que="Dakiti, Memorias, Sparks", donde="tele")
    assert llamadas[0] == ["cola", "nueva", "Dakiti", "Memorias", "Sparks", "--donde", "tele"]
    assert "Puesta la cola con 3 canciones" in r["decir"]

    r_clean = t.spotify("cola_limpiar")
    assert llamadas[1] == ["cola", "limpiar"]
    assert "vaciada" in r_clean["decir"]


def test_crear_y_anadir_playlist(falso):
    llamadas, resp = falso
    resp["playlist"] = {"ok": True, "uri": "spotify:playlist:NEW"}
    r = t.spotify("crear_playlist", que="Cyberpunk Focus")
    assert llamadas[0] == ["playlist", "crear", "Cyberpunk Focus"]
    assert "He creado la playlist «Cyberpunk Focus»" in r["decir"]

    r_add = t.spotify("anadir_a_playlist", que="Turbo Killer", valor="Cyberpunk Focus")
    assert llamadas[1] == ["playlist", "anadir", "Cyberpunk Focus", "Turbo Killer"]
    assert "Añadida «Turbo Killer» a la playlist «Cyberpunk Focus»" in r_add["decir"]


def test_sincronizar_youtube(falso):
    llamadas, resp = falso
    resp["playlist"] = {"ok": True, "anadidas": 5}
    r = t.spotify("sincronizar_youtube")
    assert llamadas[0] == ["playlist", "sync-todo"]
    assert "5 canciones añadidas" in r["decir"]



def test_lo_mas_nuevo_de_un_alias_aunque_lo_mande_como_buscar_ultimo(falso):
    """Sesión real: «pon en la tele lo más nuevo de lo de siempre» llegó como buscar(que='lo de siempre', ultimo=True)."""
    llamadas, _ = falso
    t.spotify("buscar", que="lo de siempre", ultimo=True, donde="tele")
    assert llamadas == [["poner", "RealG4lifebaby", "--tipo", "playlist", "--donde", "tele", "--orden", "recientes", "--desde-inicio"]]


def test_sin_aleatorio(falso):
    llamadas, _ = falso
    t.spotify("poner", que="drill elite", tipo="playlist", aleatorio=False)
    assert llamadas[-1][-1] == "--en-orden"
    t.spotify("poner", que="drill elite", aleatorio=True)
    assert llamadas[-1][-1] == "--aleatorio"


def test_lo_ultimo_de_una_playlist_que_no_es_artista(falso):
    llamadas, resp = falso
    resp["ultimo"] = {"ok": False, "error": "no encuentro al artista"}
    resp["encontrar"] = {"ok": True, "encontrado": {"nombre": "Drill Elite", "uri": "spotify:playlist:D", "tipo": "playlist"}}
    t.spotify("buscar", que="Drill Elite", ultimo=True)
    assert [l[0] for l in llamadas] == ["ultimo", "encontrar", "poner"] and "recientes" in llamadas[-1]
