from __future__ import annotations

import json
from unittest.mock import MagicMock

import pytest

from laura import llm


def test_compactar_turno_filtra_claves_y_mantiene_json_valido():
    payload_original = {
        "ok": True,
        "resumen": "3 canciones en la cola",
        "decir": "He puesto 3 canciones",
        "error": None,
        "candidatos": ["c1", "c2"],
        "pregunta": "¿Quieres continuar?",
        "canciones_completas": [{"id": 1, "track": "..."}] * 50,
        "metadatos_pesados": {"vram": 12345, "debug": True},
    }
    messages = [
        {"role": "system", "content": "system prompt"},
        {"role": "user", "content": "pon música"},
        {"role": "assistant", "content": "", "tool_calls": [{"id": "c1", "function": {"name": "cola_dj"}}]},
        {"role": "tool", "name": "cola_dj", "content": json.dumps(payload_original)},
        {"role": "assistant", "content": "Listo."},
    ]

    llm._compactar_turno(messages, desde=1)

    tool_msg = messages[3]
    parsed = json.loads(tool_msg["content"])

    # Claves conservadas
    assert parsed["ok"] is True
    assert parsed["resumen"] == "3 canciones en la cola"
    assert parsed["decir"] == "He puesto 3 canciones"
    assert parsed["candidatos"] == ["c1", "c2"]
    assert parsed["pregunta"] == "¿Quieres continuar?"

    # Claves filtradas
    assert "canciones_completas" not in parsed
    assert "metadatos_pesados" not in parsed


def test_compactar_turno_respeta_desde():
    tool_vieja = {"ok": True, "resumen": "viejo", "ignorado": "debe mantenerse"}
    tool_nueva = {"ok": True, "resumen": "nuevo", "ignorado": "debe eliminarse"}
    messages = [
        {"role": "tool", "name": "t1", "content": json.dumps(tool_vieja)},
        {"role": "user", "content": "turno 2"},
        {"role": "tool", "name": "t2", "content": json.dumps(tool_nueva)},
    ]

    llm._compactar_turno(messages, desde=1)

    assert "ignorado" in json.loads(messages[0]["content"])
    assert "ignorado" not in json.loads(messages[2]["content"])


def test_converse_compacta_al_terminar_turno_normal(monkeypatch):
    session = llm.Session()
    rondas = [
        # Ronda 1: tool call
        {
            "message": {
                "role": "assistant",
                "content": "",
                "tool_calls": [{
                    "id": "1",
                    "function": {"name": "ejecutar_comando", "arguments": {"comando": "uptime"}}
                }],
            }
        },
        # Ronda 2: respuesta final
        {
            "message": {
                "role": "assistant",
                "content": "El sistema lleva 2 horas encendido.",
            }
        },
    ]

    def mock_post(body, etiqueta, timeout=None):
        return rondas.pop(0)

    monkeypatch.setattr(llm, "_post", mock_post)
    monkeypatch.setattr(llm.tools_mod, "run_tool", lambda name, args, apps: {
        "ok": True,
        "resumen": "up 2 hours",
        "salida_completa_muy_larga": "x" * 5000,
    })

    reply, actions, esc = llm.converse(session, "cuánto lleva encendido")

    assert reply == "El sistema lleva 2 horas encendido."
    assert esc is None

    # Comprobar que en el historial el tool message fue compactado
    tool_msgs = [m for m in session.messages if m.get("role") == "tool"]
    assert len(tool_msgs) == 1
    content = json.loads(tool_msgs[0]["content"])
    assert content["ok"] is True
    assert content["resumen"] == "up 2 hours"
    assert "salida_completa_muy_larga" not in content


def test_converse_no_compacta_en_escaladas(monkeypatch):
    session = llm.Session()
    mock_resp = {
        "message": {
            "role": "assistant",
            "content": "",
            "tool_calls": [{
                "id": "1",
                "function": {
                    "name": "escalar_a_gemini",
                    "arguments": {"peticion": "reloj", "motivo": "widget"}
                }
            }],
        }
    }
    monkeypatch.setattr(llm, "_post", lambda b, e, timeout=None: mock_resp)
    monkeypatch.setattr(llm.tools_mod, "run_tool", lambda name, args, apps: {
        "ok": True,
        "resumen": "escalar",
        "contexto_completo": "no compactar en escalada",
    })

    reply, actions, esc = llm.converse(session, "cambia el reloj")

    assert esc is not None
    assert esc["destino"] == "gemini"

    tool_msgs = [m for m in session.messages if m.get("role") == "tool"]
    assert len(tool_msgs) == 1
    content = json.loads(tool_msgs[0]["content"])
    # En escaladas, el resultado no se compacta porque puede hacer falta
    assert "contexto_completo" in content
