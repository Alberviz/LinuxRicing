"""Tools de hologramas + warp con número, contra un warp falso y una escena con bus de prueba."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura import holo  # noqa: E402
from laura.tools import holo as th  # noqa: E402
from laura.tools import warp as w  # noqa: E402


@pytest.fixture
def entorno(monkeypatch):
    ev = []
    esc = holo.Escena(emit=lambda **e: ev.append(e), preparar=lambda r, t: {"tipo": t, "src": r})
    monkeypatch.setattr(holo, "escena", lambda: esc)
    llamadas = []
    resp = {"listar": {"ok": True, "carpeta": "/h/Descargas", "candidatos": [
        {"ruta": "/h/Descargas/WhatsApp 21.04.jpg", "nombre": "WhatsApp 21.04.jpg", "tamano": 1, "modificado": 1},
        {"ruta": "/h/Descargas/practica3.pdf", "nombre": "practica3.pdf", "tamano": 1, "modificado": 1}]},
        "archivo": {"ok": True, "enviado": {"nombre": "x"}}}

    def falso(*args, entrada=None):
        llamadas.append(args)
        return resp.get(args[0], {"ok": True, "candidatos": []})
    monkeypatch.setattr(w, "_warp", falso)
    return esc, ev, llamadas


def test_mostrar_archivos(entorno):
    esc, ev, llamadas = entorno
    r = th.mostrar_archivos(carpeta="Descargas")
    assert r["ok"] and r["n"] == 2 and r["decir"] == "Tienes dos cosas; la más reciente es WhatsApp 21.04."
    assert llamadas[0] == ("listar", "Descargas") and ev[-1]["op"] == "list"


def test_abrir_y_enviar_esa(entorno):
    esc, ev, llamadas = entorno
    th.mostrar_archivos(carpeta="Descargas")
    assert th.abrir(numeros=[1])["decir"] == "Ahí lo tienes."
    r = w.warp("archivo")                       # «envía esa al móvil»
    assert r["ok"] and llamadas[-1][:2] == ("archivo", "/h/Descargas/WhatsApp 21.04.jpg")
    assert ev[-1]["op"] == "sent"


def test_enviar_por_numero(entorno):
    esc, ev, llamadas = entorno
    th.mostrar_archivos()
    assert w.warp("archivo", numero=2)["ok"] and llamadas[-1][1] == "/h/Descargas/practica3.pdf"
    assert not w.warp("archivo", numero=7)["ok"]


def test_warp_listar_tambien_rellena_la_escena(entorno):
    esc, ev, _ = entorno
    w.warp("listar", carpeta="Descargas")
    assert esc.resolver(1).nombre == "WhatsApp 21.04.jpg"


def test_cerrar_holo(entorno):
    esc, ev, _ = entorno
    th.mostrar_archivos()
    th.abrir(numeros=[1, 2])
    assert th.cerrar_holo()["ok"] and ev[-1]["op"] == "clear"


def test_registradas():
    from laura.tools import REGISTRY
    assert {"mostrar_archivos", "abrir", "cerrar_holo"} <= set(REGISTRY)
    assert "numero" in REGISTRY["warp"].schema["function"]["parameters"]["properties"]


def test_bus_on_connect(tmp_path):
    import socket
    from laura.events import EventBus
    bus = EventBus(str(tmp_path / "ev.sock"))
    bus.on_connect.append(lambda: {"type": "holo", "op": "snapshot"})
    bus.start()
    c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    c.connect(str(tmp_path / "ev.sock"))
    c.settimeout(2)
    assert b'"op": "snapshot"' in c.recv(4096)
    bus.close()


def test_resultados_serializables(entorno):
    import json
    th.mostrar_archivos()
    json.dumps(th.abrir(numeros=[1, 2]), ensure_ascii=False)
    json.dumps(th.cerrar_holo(), ensure_ascii=False)
