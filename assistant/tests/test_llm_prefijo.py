from __future__ import annotations

import json
from unittest.mock import MagicMock

import pytest

from laura import llm
from laura.tools import sistema


def test_envolver_sin_contexto():
    assert llm.envolver("hola", "") == "hola"
    assert llm.envolver("hola", "   ") == "hola"
    assert llm.envolver("hola", None) == "hola"


def test_envolver_con_contexto():
    ctx = "Ahora mismo es lunes 10 de noviembre de 2026, 18:30."
    esperado = f"<contexto>\n{ctx}\n</contexto>\n\nhola"
    assert llm.envolver("hola", ctx) == esperado
    assert llm.envolver("hola", f"  {ctx}  ") == esperado


def test_contexto_turno(monkeypatch):
    monkeypatch.setattr(sistema, "fecha_hora_texto", lambda: "lunes 10 de noviembre de 2026, 18:30")
    monkeypatch.setattr(llm.memory, "prompt_block", lambda user_text: f"hechos para {user_text}")

    ctx = llm.contexto_turno("consulta")
    assert "Ahora mismo es lunes 10 de noviembre de 2026, 18:30." in ctx
    assert "hechos para consulta" in ctx


def test_system_y_tools_identicos_aunque_cambie_hora(monkeypatch):
    monkeypatch.setattr(llm.memory, "prompt_block", lambda _: "")

    monkeypatch.setattr(sistema, "fecha_hora_texto", lambda: "18:30")
    session1 = llm.Session()
    session1.refresh_system("hola")
    session1.add("user", "hola")
    body1 = json.loads(llm._ollama_body(session1, False).decode())

    monkeypatch.setattr(sistema, "fecha_hora_texto", lambda: "18:31")
    session2 = llm.Session()
    session2.refresh_system("hola")
    session2.add("user", "hola")
    body2 = json.loads(llm._ollama_body(session2, False).decode())

    # messages[0] de la sesión no se toca al hacer refresh_system
    assert session1.messages[0] == session2.messages[0]

    # En el cuerpo enviado a Ollama, el system y las tools son exactamente idénticos
    assert body1["messages"][0] == body2["messages"][0]
    assert body1["tools"] == body2["tools"]

    # El contexto dinámico solo varía en el mensaje user
    assert body1["messages"][1]["content"] != body2["messages"][1]["content"]
    assert "18:30" in body1["messages"][1]["content"]
    assert "18:31" in body2["messages"][1]["content"]


def test_contexto_solo_en_ultimo_mensaje_usuario_y_historial_limpio(monkeypatch):
    monkeypatch.setattr(sistema, "fecha_hora_texto", lambda: "18:30")
    monkeypatch.setattr(llm.memory, "prompt_block", lambda _: "hecho_importante")

    session = llm.Session()
    # Turno 1
    session.refresh_system("primer turno")
    session.add("user", "primer turno")
    session.add("assistant", "respuesta 1")

    # Turno 2
    monkeypatch.setattr(sistema, "fecha_hora_texto", lambda: "18:35")
    session.refresh_system("segundo turno")
    session.add("user", "segundo turno")

    # En la sesión, todos los mensajes de usuario quedan limpios
    assert session.messages[1] == {"role": "user", "content": "primer turno"}
    assert session.messages[2] == {"role": "assistant", "content": "respuesta 1"}
    assert session.messages[3] == {"role": "user", "content": "segundo turno"}

    # Al generar los mensajes para Ollama, solo el último lleva el contexto
    msgs = llm._mensajes(session)
    assert msgs[1]["content"] == "primer turno"
    assert "<contexto>" not in msgs[1]["content"]
    assert msgs[2]["content"] == "respuesta 1"
    assert "<contexto>" in msgs[3]["content"]
    assert "segundo turno" in msgs[3]["content"]
    assert "18:35" in msgs[3]["content"]
    assert "hecho_importante" in msgs[3]["content"]

    # El historial original sigue limpio tras llamar a _mensajes
    assert session.messages[3]["content"] == "segundo turno"


def test_converse_mantiene_historial_limpio(monkeypatch):
    monkeypatch.setattr(sistema, "fecha_hora_texto", lambda: "18:30")
    monkeypatch.setattr(llm.memory, "prompt_block", lambda _: "")

    fake_resp = {
        "message": {"role": "assistant", "content": "Hola Alberto"},
        "prompt_eval_count": 100,
        "prompt_eval_duration": 50000000,
    }
    monkeypatch.setattr(llm, "_post", lambda body, etiqueta, timeout=None: fake_resp)

    session = llm.Session()
    res, actions, esc = llm.converse(session, "hola que tal")

    assert res == "Hola Alberto"
    assert esc is None
    # El usuario en messages queda sin etiquetas de contexto
    assert session.messages[1] == {"role": "user", "content": "hola que tal"}
    assert session.turn_ctx != ""
    assert "18:30" in session.turn_ctx
