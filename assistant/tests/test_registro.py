from __future__ import annotations

import json
from unittest.mock import MagicMock

import pytest

from laura import config, llm, registro


def test_apuntar_crea_archivo_y_escribe_jsonl(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "DATA_DIR", tmp_path)

    registro.apuntar(
        texto="sube el volumen",
        via="rapido",
        tools=[{"tool": "volumen", "args": {"porcentaje": 10}}],
        respuesta="",
        segundos=0.005,
    )

    archivo = tmp_path / "interacciones.jsonl"
    assert archivo.exists()
    lineas = archivo.read_text(encoding="utf-8").strip().splitlines()
    assert len(lineas) == 1

    d = json.loads(lineas[0])
    assert "fecha" in d
    assert d["texto"] == "sube el volumen"
    assert d["via"] == "rapido"
    assert d["tools"] == [{"tool": "volumen", "args": {"porcentaje": 10}}]
    assert d["respuesta"] == ""
    assert d["segundos"] == 0.005


def test_apuntar_nunca_falla(monkeypatch):
    def fallo(*args, **kwargs):
        raise PermissionError("Permiso denegado simulado")

    monkeypatch.setattr("builtins.open", fallo)

    # No debe lanzar excepción
    registro.apuntar(texto="test", via="llm", tools=[], respuesta="ok", segundos=0.1)


def test_converse_devuelve_tool_y_args_en_acciones(monkeypatch):
    session = llm.Session()
    rondas = [
        {
            "message": {
                "role": "assistant",
                "content": "",
                "tool_calls": [{
                    "id": "1",
                    "function": {"name": "volumen", "arguments": {"porcentaje": 10}}
                }],
            }
        },
        {
            "message": {
                "role": "assistant",
                "content": "Volumen subido.",
            }
        },
    ]

    monkeypatch.setattr(llm, "_post", lambda b, e, timeout=None: rondas.pop(0))
    monkeypatch.setattr(llm.tools_mod, "run_tool", lambda name, args, apps: {
        "ok": True,
        "resumen": "Volumen 50%",
    })

    reply, actions, esc = llm.converse(session, "sube el volumen un 10")

    assert reply == "Volumen subido."
    assert len(actions) == 1
    assert actions[0]["tool"] == "volumen"
    assert actions[0]["args"] == {"porcentaje": 10}
