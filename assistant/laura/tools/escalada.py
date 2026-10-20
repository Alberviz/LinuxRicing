"""Tools de escalada a agentes grandes y consulta de trabajos en segundo plano."""
from __future__ import annotations

import time

from . import tool


@tool("escalar_a_gemini",
      "Escala a Gemini las tareas de tamaño MEDIO: cambiar un widget, un script, "
      "un ajuste de configuración o un fichero concreto del ecosistema. NO la "
      "uses para preguntas simples ni para buscar datos (para eso está buscar_web). "
      "No resuelvas tú misma estas peticiones con una respuesta improvisada.",
      {"peticion": {"type": "string", "description": "la petición de Alberto, resumida en una frase clara"},
       "motivo": {"type": "string", "description": "por qué no puedes hacerlo tú misma (breve)"}},
      required=["peticion"], icon="auto_awesome", effect="escalate:gemini")
def escalar_a_gemini(peticion: str, motivo: str = "") -> dict:
    """Solo marca la intención; el daemon pide confirmación por voz y lanza el
    trabajo en segundo plano (ver laura.escalation / laura.jobs)."""
    return {"ok": True, "escalate": True, "peticion": peticion, "motivo": motivo,
            "resumen": "Necesito ayuda de Gemini para esto"}


@tool("escalar_a_claude",
      "Escala a Claude Code las tareas GORDAS: features nuevas, cambios en varios "
      "archivos, refactors o cualquier trabajo de programación sustancial. Para "
      "cambios pequeños o medios usa escalar_a_gemini. No resuelvas tú misma estas "
      "peticiones.",
      {"peticion": {"type": "string", "description": "la petición de Alberto, resumida en una frase clara"},
       "motivo": {"type": "string", "description": "por qué no puedes hacerlo tú misma (breve)"}},
      required=["peticion"], icon="psychology_alt", effect="escalate:claude")
def escalar_a_claude(peticion: str, motivo: str = "") -> dict:
    return {"ok": True, "escalate": True, "peticion": peticion, "motivo": motivo,
            "resumen": "Necesito ayuda de Claude para esto"}


@tool("estado_trabajos",
      "Dice cómo van los trabajos que Alberto mandó a Gemini o Claude en segundo plano. Úsala con «cómo va lo que mandé».",
      icon="pending_actions")
def estado_trabajos() -> dict:
    from ..jobs import list_jobs
    js = list_jobs(5)
    if not js:
        return {"ok": True, "trabajos": [], "resumen": "Sin trabajos"}
    out = []
    for j in js:
        t = {"id": j["id"], "destino": j["destino"], "peticion": j["peticion"],
             "estado": j["estado"],
             "hace_minutos": round((time.time() - j["inicio"]) / 60, 1)}
        if j.get("resumen"):
            t["resumen"] = j["resumen"]
        out.append(t)
    return {"ok": True, "trabajos": out, "resumen": f"{len(out)} trabajos"}
