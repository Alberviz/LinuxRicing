"""Tools de escalada a agentes grandes y consulta de trabajos en segundo plano."""
from __future__ import annotations

import time

from . import tool


@tool("escalar_a_gemini",
      "Manda a Gemini (subagente de análisis, lectura de proyectos y código medio) una tarea técnica media: analizar un repositorio o aplicación (como Krakount o LinuxRicing), leer código/tareas en profundidad, modificar scripts o widgets, o cuando Alberto pida levantar un agente de Gemini.",
      {"peticion": {"type": "string", "description": "petición detallada para el agente Gemini"},
       "motivo": {"type": "string", "description": "por qué se delega a Gemini (breve)"}},
      required=["peticion"], icon="auto_awesome", effect="escalate:gemini")
def escalar_a_gemini(peticion: str, motivo: str = "") -> dict:
    """Solo marca la intención; el daemon pide confirmación por voz y lanza el
    trabajo en segundo plano (ver laura.escalation / laura.jobs)."""
    return {"ok": True, "escalate": True, "peticion": peticion, "motivo": motivo,
            "resumen": "Se lo paso a Gemini"}


@tool("escalar_a_claude",
      "Manda a Claude (subagente de desarrollo pesado) un trabajo grande de programación: desarrollar una aplicación («quiero desarrollar una aplicación…»), proyectos nuevos, features grandes en múltiples ficheros, refactorizaciones complejas, o cuando Alberto pida levantar un agente de Claude.",
      {"peticion": {"type": "string", "description": "petición detallada para el agente Claude"},
       "motivo": {"type": "string", "description": "por qué se delega a Claude (breve)"}},
      required=["peticion"], icon="psychology_alt", effect="escalate:claude")
def escalar_a_claude(peticion: str, motivo: str = "") -> dict:
    return {"ok": True, "escalate": True, "peticion": peticion, "motivo": motivo,
            "resumen": "Se lo paso a Claude"}


@tool("estado_trabajos",
      "Cómo van los trabajos mandados a Gemini/Claude («cómo va lo que mandé», «ya ha terminado Claude»).",
      icon="pending_actions")
def estado_trabajos() -> dict:
    from ..jobs import list_jobs
    js = list_jobs(5, horas=48)
    if not js:
        return {"ok": True, "trabajos": [], "resumen": "Sin trabajos"}
    out = []
    for j in js:
        t = {"id": j["id"], "destino": j["destino"], "peticion": j["titulo"],
             "estado": j["estado"],
             "hace_minutos": round((time.time() - j["inicio"]) / 60, 1)}
        if j.get("resumen"):
            t["resumen"] = j["resumen"]
        out.append(t)
    return {"ok": True, "trabajos": out, "resumen": f"{len(out)} trabajos"}
