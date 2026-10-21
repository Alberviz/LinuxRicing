"""Registro de herramientas de Laura.

Cada tool se declara con `@tool(...)`: nombre, descripción y parámetros (el
esquema que se le pasa a Ollama), icono de la píldora del overlay y, si
procede, un `effect` que el bucle de `converse()` interpreta en lugar de
seguir con normalidad:

    effect="escalate:gemini" | "escalate:claude"
        la tool no ejecuta nada: marca la intención. `converse()` corta la
        ronda y devuelve la escalada para que el ciclo pida confirmación por
        voz antes de lanzar el trabajo en segundo plano.

Las tools se agrupan por área en módulos de este paquete; importarlos aquí
las registra. `assistant/tools.py` es una fachada que reexporta TOOLS y
run_tool para quien lo importaba antes (el eval).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable


@dataclass
class Tool:
    name: str
    fn: Callable
    schema: dict
    icon: str = "bolt"
    effect: str | None = None
    wants_apps: bool = False


REGISTRY: dict[str, Tool] = {}


def tool(name: str, description: str, props: dict | None = None,
         required: list[str] | None = None, icon: str = "bolt",
         effect: str | None = None, wants_apps: bool = False):
    params: dict = {"type": "object", "properties": props or {}}
    if required:
        params["required"] = required
    schema = {"type": "function",
              "function": {"name": name, "description": description,
                           "parameters": params}}

    def deco(fn):
        REGISTRY[name] = Tool(name, fn, schema, icon, effect, wants_apps)
        return fn
    return deco


def effect_of(name: str) -> str | None:
    t = REGISTRY.get(name)
    return t.effect if t else None


def run_tool(name: str, args: dict, apps: dict) -> dict:
    t = REGISTRY.get(name)
    if t is None:
        return {"ok": False, "error": f"herramienta desconocida: {name}"}
    try:
        if t.wants_apps:
            return t.fn(args.get("nombre", ""), apps)
        return t.fn(**args)
    except Exception as e:  # noqa: BLE001 — un fallo no debe tumbar el daemon
        return {"ok": False, "error": str(e)}


def accion_overlay(name: str, result: dict) -> dict:
    """Traduce un tool_call ejecutado a `{icon, text}` para el overlay."""
    t = REGISTRY.get(name)
    return {
        "icon": t.icon if t else "bolt",
        "text": result.get("resumen") or name.replace("_", " ").capitalize(),
    }


# Importar los módulos registra sus tools (el orden fija el de TOOLS).
from . import sistema, tareas, memoria, avisos, web, dispositivos, escalada, segundo_plano, workspace  # noqa: E402,F401

TOOLS = [t.schema for t in REGISTRY.values()]
DISPATCH = {n: t.fn for n, t in REGISTRY.items()}
TOOL_ICONS = {n: t.icon for n, t in REGISTRY.items()}
