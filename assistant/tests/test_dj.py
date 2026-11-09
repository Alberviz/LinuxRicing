"""DJ de colas: prompt, parseo de la respuesta del subagente, motores y flujo completo (sin Spotify ni agentes)."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura import dj  # noqa: E402
from laura.tools import spotify as sp  # noqa: E402


def test_cantidad():
    assert dj.cantidad(None) == 15 and dj.cantidad("10") == 10 and dj.cantidad(1) == 3 and dj.cantidad(500) == 40


def test_prompt_solo_mete_lo_que_suena_si_se_refiere_a_ello():
    s = {"cancion": "Gasolina", "artista": "Daddy Yankee"}
    assert "Gasolina" not in dj.prompt("reggaeton antiguo", 10, s)
    p = dj.prompt("5 parecidas a esto", 5, s)
    assert "Gasolina" in p and "5 canciones" in p


@pytest.mark.parametrize("texto", [
    '{"titulo": "Old school", "canciones": [{"titulo": "Gasolina", "artista": "Daddy Yankee"}, {"titulo": "Gasolina", "artista": "Daddy Yankee"}, {"titulo": "Rakata", "artista": "Wisin & Yandel"}]}',
    '```json\n{"titulo": "Old school", "canciones": [{"titulo": "Gasolina", "artista": "Daddy Yankee"}, {"titulo": "Rakata", "artista": "Wisin & Yandel"}]}\n```',
    '{"type": "result", "result": "{\\"titulo\\": \\"Old school\\", \\"canciones\\": [{\\"titulo\\": \\"Gasolina\\", \\"artista\\": \\"Daddy Yankee\\"}, {\\"titulo\\": \\"Rakata\\", \\"artista\\": \\"Wisin & Yandel\\"}]}"}',
])
def test_parse(texto):
    d = dj.parse(texto)
    assert d["titulo"] == "Old school" and [c["titulo"] for c in d["canciones"]] == ["Gasolina", "Rakata"]


def test_parse_basura():
    assert dj.parse("") is None and dj.parse("no sé") is None and dj.parse('{"canciones": []}') is None


def test_elegir_cae_al_respaldo(monkeypatch):
    usados = []
    def lanzar(m, texto, timeout, cancel):
        usados.append(m["motor"])
        if m["motor"] == "gemini":
            return {"ok": False, "error": "Gemini no respondió"}
        return {"ok": True, "texto": '{"titulo": "X", "canciones": [{"titulo": "A", "artista": "B"}]}'}
    monkeypatch.setattr(dj, "_lanzar", lanzar)
    r = dj.elegir("lo-fi", 5)
    assert r["ok"] and r["motor"] == "claude" and usados == ["gemini", "claude"]


@pytest.mark.parametrize("sonando,esperado", [(True, "anadir"), (False, "nueva")])
def test_ejecutar(monkeypatch, sonando, esperado):
    llamadas = []
    def cmd(*a, **k):
        llamadas.append(list(a))
        if a[0] == "estado":
            return {"ok": True, "abierto": True, "sonando": sonando, "cancion": "Algo"}
        return {"ok": True, "reproduciendo": {"nombre": "Gasolina", "de": "Daddy Yankee"},
                "encoladas": [{"nombre": "Rakata", "de": "Wisin & Yandel"}], "total": 2}
    monkeypatch.setattr(sp, "_cmd", cmd)
    monkeypatch.setattr(dj, "elegir", lambda *a, **k: {"ok": True, "motor": "gemini", "titulo": "Old school 🔥",
        "canciones": [{"titulo": "Gasolina", "artista": "Daddy Yankee"}, {"titulo": "Rakata", "artista": "Wisin & Yandel"},
                      {"titulo": "Inventada", "artista": "Nadie"}]})
    r = dj.ejecutar("reggaeton antiguo", 3, donde="tele")
    assert llamadas[1][:2] == ["cola", esperado]
    assert llamadas[1][2:5] == ["Gasolina Daddy Yankee", "Rakata Wisin & Yandel", "Inventada Nadie"]
    assert ("--donde" in llamadas[1]) == (esperado == "nueva")
    assert r["ok"] and "No encontradas en Spotify: 1" in r["texto"] and "🔥" not in r["resumen"]
    assert ("empieza con Gasolina" in r["resumen"]) == (esperado == "nueva")
