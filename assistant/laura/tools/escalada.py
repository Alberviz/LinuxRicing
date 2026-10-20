"""Tools de escalada a agentes grandes y consulta de trabajos en segundo plano."""
from __future__ import annotations

import time

from . import tool


@tool("escalar_a_gemini",
      "Manda a Gemini un cambio de tamaño MEDIO en código o configuración: un widget, un script, un ajuste, un fichero. Ej.: «reloj en formato 12 horas», «color de la barra», «que el widget de tareas muestre las hechas», «arregla el script de la batería». Úsala en vez de decir «no puedo».",
      {"peticion": {"type": "string", "description": "petición en una frase"},
       "motivo": {"type": "string", "description": "por qué no puedes tú (breve)"}},
      required=["peticion"], icon="auto_awesome", effect="escalate:gemini")
def escalar_a_gemini(peticion: str, motivo: str = "") -> dict:
    """Solo marca la intención; el daemon pide confirmación por voz y lanza el
    trabajo en segundo plano (ver laura.escalation / laura.jobs)."""
    return {"ok": True, "escalate": True, "peticion": peticion, "motivo": motivo,
            "resumen": "Necesito ayuda de Gemini para esto"}


@tool("escalar_a_claude",
      "Manda a Claude un trabajo GORDO de programación: feature nueva, varios archivos, refactor, tema o modo completo. Ej.: «tema de colores nuevo para toda la shell», «implementa un modo concentración». Lo medio va a escalar_a_gemini.",
      {"peticion": {"type": "string", "description": "petición en una frase"},
       "motivo": {"type": "string", "description": "por qué no puedes tú (breve)"}},
      required=["peticion"], icon="psychology_alt", effect="escalate:claude")
def escalar_a_claude(peticion: str, motivo: str = "") -> dict:
    return {"ok": True, "escalate": True, "peticion": peticion, "motivo": motivo,
            "resumen": "Necesito ayuda de Claude para esto"}


@tool("estado_trabajos",
      "Cómo van los trabajos mandados a Gemini/Claude («cómo va lo que mandé», «ya ha terminado Claude»).",
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
