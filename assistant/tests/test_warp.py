"""Tool `warp` de Laura contra un CLI warp falso (sin Olimpo ni red)."""
import json
import stat
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura.tools import warp as w  # noqa: E402


@pytest.fixture
def falso(tmp_path, monkeypatch):
    registro = tmp_path / "llamadas.txt"
    respuesta = tmp_path / "respuesta.json"
    exe = tmp_path / "warp"
    exe.write_text(f'#!/bin/sh\necho "$@" >> {registro}\n[ "$2" = "-" ] && cat >> {registro}\ncat {respuesta}\n')
    exe.chmod(exe.stat().st_mode | stat.S_IXUSR)
    monkeypatch.setattr(w, "_bin", lambda: str(exe))

    def responder(d):
        respuesta.write_text(json.dumps(d))
    responder({"ok": True})
    return responder, lambda: registro.read_text()


def test_texto_va_por_stdin(falso):
    responder, llamadas = falso
    r = w.warp("texto", texto="la wifi es Patata")
    assert r["ok"] and r["resumen"] == "Texto al móvil"
    assert "texto - --json --origen laura" in llamadas() and "la wifi es Patata" in llamadas()


def test_buscar_claro_y_dudoso(falso):
    responder, _ = falso
    responder({"ok": True, "claro": True, "candidatos": [{"nombre": "Redes P3.pdf", "ruta": "/h/Redes P3.pdf"}]})
    assert w.warp("buscar", consulta="pdf redes")["decir"] == "Encontré Redes P3.pdf."
    responder({"ok": True, "claro": False, "candidatos": [{"nombre": "a.pdf"}, {"nombre": "b.pdf"}]})
    assert w.warp("buscar", consulta="pdf")["decir"] == "Hay varios: a.pdf; b.pdf. ¿Cuál?"
    responder({"ok": True, "claro": False, "candidatos": []})
    assert w.warp("buscar", consulta="nada")["decir"] == "No encuentro nada parecido."


def test_archivo_y_errores(falso):
    responder, llamadas = falso
    responder({"ok": True, "tipo": "archivo", "enviado": {"nombre": "x.pdf"}})
    assert w.warp("archivo", ruta="/h/x.pdf")["resumen"] == "x.pdf al móvil"
    assert "archivo /h/x.pdf" in llamadas()
    assert not w.warp("archivo")["ok"]
    assert not w.warp("texto", texto="  ")["ok"]
    assert not w.warp("borrar_todo")["ok"]
    responder({"ok": False, "error": "La Pi no responde"})
    assert w.warp("portapapeles") == {"ok": False, "error": "La Pi no responde"}


def test_nota_md_se_sube_y_se_borra(monkeypatch):
    vistos = {}

    def falso_warp(*args, entrada=None):
        ruta = Path(args[1])
        vistos.update(args=args, nombre=ruta.name, contenido=ruta.read_text(encoding="utf-8"), ruta=ruta)
        return {"ok": True, "tipo": "archivo"}
    monkeypatch.setattr(w, "_warp", falso_warp)
    r = w.warp("nota", texto="# Prompt\nHaz una landing", nombre="prompt landing/../BarberBot.md")
    assert r["ok"] and r["resumen"] == "prompt-landingBarberBot.md al móvil"
    assert vistos["args"][0] == "archivo" and vistos["contenido"] == "# Prompt\nHaz una landing\n"
    assert not vistos["ruta"].exists()
    assert w.warp("nota", texto="hola")["resumen"] == "nota-de-laura.md al móvil"
    assert not w.warp("nota", texto=" ")["ok"]


def test_listar_no_envia_y_lee_nombres(falso):
    responder, llamadas = falso
    responder({"ok": True, "carpeta": "/h/Descargas", "total": 2, "claro": False,
               "candidatos": [{"nombre": "WhatsApp Image 1.jpeg", "ruta": "/h/Descargas/WhatsApp Image 1.jpeg"},
                              {"nombre": "factura.pdf", "ruta": "/h/Descargas/factura.pdf"}]})
    r = w.warp("listar", carpeta="Descargas")
    assert r["decir"] == "Lo más reciente: WhatsApp Image 1.jpeg; factura.pdf. ¿Cuál mando?"
    assert "listar Descargas --json --origen laura" in llamadas()
    responder({"ok": True, "carpeta": "/h/Vacía", "total": 0, "candidatos": []})
    assert w.warp("listar", carpeta="Vacía")["decir"] == "Vacía está vacía."


def test_buscar_acotado_a_una_carpeta(falso):
    responder, llamadas = falso
    responder({"ok": True, "claro": False, "candidatos": [{"nombre": "a.jpeg"}, {"nombre": "b.jpeg"}]})
    w.warp("buscar", consulta="capturas de whatsapp", carpeta="Descargas")
    assert "buscar capturas de whatsapp --carpeta Descargas --json" in llamadas()


def test_archivo_sin_ruta_pero_con_descripcion_busca_primero(monkeypatch):
    llamadas = []
    respuestas = {"buscar": {"ok": True, "claro": True, "candidatos": [{"nombre": "Redes.pdf", "ruta": "/h/Redes.pdf"}]},
                  "archivo": {"ok": True, "tipo": "archivo", "enviado": {"nombre": "Redes.pdf"}}}

    def falso_warp(*args, entrada=None):
        llamadas.append(args)
        return respuestas[args[0]]
    monkeypatch.setattr(w, "_warp", falso_warp)
    r = w.warp("archivo", consulta="pdf práctica de redes", carpeta="Descargas")
    assert r["resumen"] == "Redes.pdf al móvil"
    assert llamadas == [("buscar", "pdf práctica de redes", "--carpeta", "Descargas"), ("archivo", "/h/Redes.pdf")]
    respuestas["buscar"] = {"ok": True, "claro": False, "candidatos": [{"nombre": "a.pdf"}, {"nombre": "b.pdf"}]}
    assert w.warp("archivo", consulta="pdf")["decir"] == "Hay varios: a.pdf; b.pdf. ¿Cuál?"
