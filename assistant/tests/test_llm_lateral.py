from __future__ import annotations

import json
from unittest.mock import MagicMock

import pytest

from laura import llm, resumen_correo
from laura.config import CFG
from laura.tools import activas


def test_chat_lateral_coincide_prefijo_con_session(monkeypatch):
    cuerpos = []

    def mock_post(body, etiqueta, timeout=None):
        cuerpos.append(json.loads(body) if isinstance(body, (bytes, str)) else body)
        return {"message": {"role": "assistant", "content": "resultado ok"}}

    monkeypatch.setattr(llm, "_post", mock_post)

    session = llm.Session()
    res = llm.chat_lateral("Resume este texto", "test_etiqueta")

    assert res == "resultado ok"
    assert len(cuerpos) == 1
    cuerpo = cuerpos[0]

    # Mismo system base que Session
    assert cuerpo["messages"][0] == session.messages[0]
    # Mismas tools base (activas(""))
    assert cuerpo["tools"] == activas("")
    # Instrucciones de usuario precedidas por la marca de tarea interna
    user_msg = cuerpo["messages"][1]
    assert user_msg["role"] == "user"
    assert "[Tarea interna: no uses herramientas]" in user_msg["content"]
    assert "Resume este texto" in user_msg["content"]


def test_chat_lateral_respaldo_sin_tools_si_tool_calls_o_vacio(monkeypatch):
    cuerpos = []

    def mock_post(body, etiqueta, timeout=None):
        data = json.loads(body) if isinstance(body, (bytes, str)) else body
        cuerpos.append(data)
        if len(cuerpos) == 1:
            # Primera llamada: devuelve tool_calls indebidos
            return {
                "message": {
                    "role": "assistant",
                    "content": "",
                    "tool_calls": [{"function": {"name": "ejecutar_comando", "arguments": {}}}],
                }
            }
        # Segunda llamada (respaldo): devuelve texto limpio
        return {"message": {"role": "assistant", "content": "respuesta de respaldo"}}

    monkeypatch.setattr(llm, "_post", mock_post)

    res = llm.chat_lateral("Haz algo", "etiqueta_respaldo")

    assert res == "respuesta de respaldo"
    assert len(cuerpos) == 2
    # El primer intento llevaba tools
    assert "tools" in cuerpos[0]
    # El respaldo no lleva tools
    assert "tools" not in cuerpos[1]


def test_chat_lateral_formato_json_y_opciones(monkeypatch):
    cuerpos = []

    def mock_post(body, etiqueta, timeout=None):
        cuerpos.append(json.loads(body) if isinstance(body, (bytes, str)) else body)
        return {"message": {"role": "assistant", "content": '{"ok": true}'}}

    monkeypatch.setattr(llm, "_post", mock_post)

    res = llm.chat_lateral("Extrae datos", "etiqueta_json", fmt="json", temperature=0.1, num_predict=120)

    assert res == '{"ok": true}'
    assert len(cuerpos) == 1
    cuerpo = cuerpos[0]
    assert cuerpo["format"] == "json"
    assert cuerpo["options"]["temperature"] == 0.1
    assert cuerpo["options"]["num_predict"] == 120


def test_summarize_for_voice_usa_chat_lateral(monkeypatch):
    llamadas = []

    def mock_chat_lateral(instrucciones, etiqueta, **kwargs):
        llamadas.append((instrucciones, etiqueta, kwargs))
        return "Alberto, Claude ha terminado de organizar los archivos."

    monkeypatch.setattr(llm, "chat_lateral", mock_chat_lateral)

    res = llm.summarize_for_voice("Detalle técnico muy extenso...", quien="Claude")
    assert res == "Alberto, Claude ha terminado de organizar los archivos."
    assert len(llamadas) == 1
    assert "Claude" in llamadas[0][0]
    assert llamadas[0][1] == "resumen_claude"


def test_answer_from_sources_usa_chat_lateral(monkeypatch):
    llamadas = []

    def mock_chat_lateral(instrucciones, etiqueta, **kwargs):
        llamadas.append((instrucciones, etiqueta, kwargs))
        return "El núcleo de Linux es monolítico.\n- Característica 1"

    monkeypatch.setattr(llm, "chat_lateral", mock_chat_lateral)

    res = llm.answer_from_sources("linux", [{"titulo": "Kernel", "fragmento": "Es un núcleo..."}])
    assert "El núcleo de Linux es monolítico" in res
    assert len(llamadas) == 1
    assert "nota escrita" in llamadas[0][0]
    assert llamadas[0][1] == "investigar"


def test_resumen_correo_llm_usa_chat_lateral(monkeypatch):
    llamadas = []

    def mock_chat_lateral(instrucciones, etiqueta, **kwargs):
        llamadas.append((instrucciones, etiqueta, kwargs))
        return json.dumps({
            "correos": [
                {"id": "msg1", "frase": "un correo de Marta sobre la entrega", "importante": True}
            ]
        })

    monkeypatch.setattr(llm, "chat_lateral", mock_chat_lateral)

    correos = [{"id": "msg1", "de": "Marta <marta@uni.es>", "asunto": "Entrega", "cuerpo": "Hola Alberto"}]
    res = resumen_correo._llm(correos)

    assert "msg1" in res
    assert res["msg1"]["frase"] == "un correo de Marta sobre la entrega"
    assert res["msg1"]["importante"] is True
    assert len(llamadas) == 1
    assert llamadas[0][1] == "resumen_correo"
    assert llamadas[0][2].get("fmt") == "json"
