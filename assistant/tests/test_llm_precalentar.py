from __future__ import annotations

import json
from unittest.mock import MagicMock

import pytest

from laura import llm
from laura.config import CFG
from laura.tools import activas


def test_precalentar_construye_cuerpo_con_num_predict_1_y_prefijo_session(monkeypatch):
    cuerpos = []

    def mock_post(body, etiqueta, timeout=None):
        cuerpos.append((json.loads(body) if isinstance(body, (bytes, str)) else body, etiqueta))
        return {"message": {"role": "assistant", "content": ""}}

    monkeypatch.setattr(llm, "_post", mock_post)
    llm._ultimo_calentado = 0.0

    ok = llm.precalentar(ahora=100.0)
    assert ok is True
    assert len(cuerpos) == 1
    cuerpo, etiqueta = cuerpos[0]

    assert etiqueta == "precalentar"
    assert cuerpo["options"]["num_predict"] == 1
    session = llm.Session()
    assert cuerpo["messages"][0] == session.messages[0]
    assert cuerpo["tools"] == activas("")


def test_precalentar_limite_30_segundos(monkeypatch):
    monkeypatch.setattr(llm, "_post", lambda b, e, timeout=None: {"message": {}})
    llm._ultimo_calentado = 0.0

    assert llm.precalentar(ahora=1000.0) is True
    assert llm.precalentar(ahora=1010.0) is False
    assert llm.precalentar(ahora=1029.0) is False
    assert llm.precalentar(ahora=1030.1) is True


def test_precalentar_nunca_lanza_excepciones(monkeypatch):
    def fallo(*args, **kwargs):
        raise ConnectionRefusedError("Ollama desconectado")

    monkeypatch.setattr(llm, "_post", fallo)
    llm._ultimo_calentado = 0.0

    # No debe propagar la excepción
    ok = llm.precalentar(ahora=2000.0)
    assert ok is False


def test_keep_alive_configuracion(monkeypatch):
    cuerpos = []

    def mock_post(body, etiqueta, timeout=None):
        cuerpos.append(json.loads(body) if isinstance(body, (bytes, str)) else body)
        return {"message": {"role": "assistant", "content": "ok"}}

    monkeypatch.setattr(llm, "_post", mock_post)

    # 1. Con keep_alive en config
    monkeypatch.setitem(CFG["llm"], "keep_alive", "15m")
    session = llm.Session()
    body1 = json.loads(llm._ollama_body(session, False).decode())
    assert body1.get("keep_alive") == "15m"

    llm.chat_lateral("tarea", "test_ka")
    assert cuerpos[-1].get("keep_alive") == "15m"

    # 2. Sin keep_alive
    monkeypatch.delitem(CFG["llm"], "keep_alive", raising=False)
    body2 = json.loads(llm._ollama_body(session, False).decode())
    assert "keep_alive" not in body2
