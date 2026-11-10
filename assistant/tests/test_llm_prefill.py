"""Tests para métricas de prefill y _post unificado en llm.py."""
from __future__ import annotations

import io
import json
import urllib.request
import pytest

from laura import llm


def test_texto_prefill_formato_correcto():
    res = {
        "prompt_eval_count": 7682,
        "prompt_eval_duration": 2980000000,
    }
    linea = llm.texto_prefill("chat", res)
    assert linea == "ollama[chat]: prefill 7682 tok en 2.98 s"


def test_texto_prefill_duracion_pequena():
    res = {
        "prompt_eval_count": 500,
        "prompt_eval_duration": 50000000,
    }
    linea = llm.texto_prefill("precalentar", res)
    assert linea == "ollama[precalentar]: prefill 500 tok en 0.05 s"


@pytest.mark.parametrize("caso", [
    {},
    {"prompt_eval_count": 100},
    {"prompt_eval_duration": 2000000000},
    {"prompt_eval_count": None, "prompt_eval_duration": 2000000000},
    {"prompt_eval_count": 100, "prompt_eval_duration": None},
    None,
    "no es dict",
    [1, 2, 3],
])
def test_texto_prefill_campos_faltantes_o_invalidos(caso):
    assert llm.texto_prefill("chat", caso) is None


def test_texto_prefill_valores_no_numericos():
    res = {
        "prompt_eval_count": "mil",
        "prompt_eval_duration": "mucho",
    }
    assert llm.texto_prefill("chat", res) is None


def test_log_prefill(monkeypatch):
    mensajes = []
    monkeypatch.setattr(llm, "log", lambda msg: mensajes.append(msg))

    llm.log_prefill("test", {"prompt_eval_count": 42, "prompt_eval_duration": 1000000000})
    assert mensajes == ["ollama[test]: prefill 42 tok en 1.00 s"]

    # Con dict sin métricas, no debe loguear nada
    llm.log_prefill("test", {})
    assert len(mensajes) == 1


def test_post_realiza_peticion_y_loguea(monkeypatch):
    mensajes = []
    monkeypatch.setattr(llm, "log", lambda msg: mensajes.append(msg))

    cuerpo_respuesta = {
        "message": {"role": "assistant", "content": "Hola"},
        "prompt_eval_count": 1234,
        "prompt_eval_duration": 500000000,
    }
    peticiones_hechas = []

    class FakeResponse:
        def __init__(self, data: dict):
            self._raw = json.dumps(data).encode()

        def read(self):
            return self._raw

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

    def fake_urlopen(req, timeout=None):
        peticiones_hechas.append({"req": req, "timeout": timeout, "data": req.data})
        return FakeResponse(cuerpo_respuesta)

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    # 1. Probar pasando dict
    res = llm._post({"model": "test"}, "etiqueta_dict", timeout=12)
    assert res == cuerpo_respuesta
    assert peticiones_hechas[-1]["timeout"] == 12
    assert peticiones_hechas[-1]["req"].headers["Content-type"] == "application/json"
    assert json.loads(peticiones_hechas[-1]["data"].decode()) == {"model": "test"}
    assert "ollama[etiqueta_dict]: prefill 1234 tok en 0.50 s" in mensajes

    # 2. Probar pasando bytes
    res2 = llm._post(b'{"raw": true}', "etiqueta_bytes")
    assert res2 == cuerpo_respuesta
    assert peticiones_hechas[-1]["data"] == b'{"raw": true}'
    assert "ollama[etiqueta_bytes]: prefill 1234 tok en 0.50 s" in mensajes


def test_ollama_chat_usa_post(monkeypatch):
    llamadas_post = []

    def fake_post(body, etiqueta, timeout=None):
        llamadas_post.append({"body": body, "etiqueta": etiqueta, "timeout": timeout})
        return {"message": {"role": "assistant", "content": "Ok"}}

    monkeypatch.setattr(llm, "_post", fake_post)

    session = llm.Session()
    res = llm.ollama_chat(session)

    assert res == {"message": {"role": "assistant", "content": "Ok"}}
    assert len(llamadas_post) == 1
    assert llamadas_post[0]["etiqueta"] == "chat"
    assert isinstance(llamadas_post[0]["body"], bytes)


def test_stream_round_loguea_prefill_al_terminar(monkeypatch):
    mensajes = []
    monkeypatch.setattr(llm, "log", lambda msg: mensajes.append(msg))

    chunks = [
        {"message": {"role": "assistant", "content": "Hola "}, "done": False},
        {"message": {"role": "assistant", "content": "Alberto."}, "done": False},
        {
            "done": True,
            "prompt_eval_count": 7682,
            "prompt_eval_duration": 2980000000,
        },
    ]

    def fake_stream(session, cancel):
        for c in chunks:
            yield c

    monkeypatch.setattr(llm, "_ollama_stream", fake_stream)

    session = llm.Session()
    frases = []
    contenido, calls = llm._stream_round(session, on_sentence=lambda s: frases.append(s), cancel=None)

    assert contenido == "Hola Alberto."
    assert calls == []
    assert "ollama[chat]: prefill 7682 tok en 2.98 s" in mensajes
