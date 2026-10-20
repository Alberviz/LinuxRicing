"""Tools de temporizadores y recordatorios."""
from __future__ import annotations

import time
from datetime import datetime

from .. import avisos
from . import tool


def _cuando(due: float) -> str:
    resto = due - time.time()
    if resto < 90:
        return f"en {max(1, round(resto))} segundos"
    if resto < 3600 * 2:
        return f"en {round(resto / 60)} minutos"
    return "a las " + datetime.fromtimestamp(due).strftime("%H:%M")


@tool("temporizador", "Pone un temporizador que avisa por voz al terminar. Úsala con «ponme un temporizador de 10 minutos».",
      {"minutos": {"type": "number", "description": "duración en minutos (admite decimales, 0.5 = 30 s)"},
       "etiqueta": {"type": "string", "description": "para qué es (opcional), p. ej. «pasta»"}},
      required=["minutos"], icon="timer")
def temporizador(minutos: float, etiqueta: str = "") -> dict:
    due = avisos.parse_cuando(float(minutos))
    a = avisos.crear("temporizador", etiqueta or "temporizador", due)
    return {"ok": True, "id": a["id"], "resumen": f"Temporizador {_cuando(due)}"}


@tool("recordatorio",
      "Crea un recordatorio que Laura dirá en voz alta a su hora. Úsala con «recuérdame llamar a mi madre a las 18:30» o «avísame en 20 minutos de sacar la ropa».",
      {"texto": {"type": "string", "description": "qué hay que recordar"},
       "hora": {"type": "string", "description": "hora del día «HH:MM» (24 h) o número de minutos desde ahora"}},
      required=["texto", "hora"], icon="alarm")
def recordatorio(texto: str, hora: str) -> dict:
    try:
        due = avisos.parse_cuando(hora)
    except ValueError:
        return {"ok": False, "error": f"no entiendo la hora «{hora}»; usa HH:MM o minutos"}
    a = avisos.crear("recordatorio", texto, due)
    return {"ok": True, "id": a["id"], "resumen": f"Recordatorio {_cuando(due)}"}


@tool("listar_avisos", "Lista los temporizadores y recordatorios pendientes.", icon="list_alt")
def listar_avisos() -> dict:
    items = [{"id": a["id"], "tipo": a["tipo"], "texto": a["texto"], "cuando": _cuando(a["due"])}
             for a in avisos.listar()]
    return {"ok": True, "avisos": items, "resumen": f"{len(items)} avisos pendientes"}


@tool("cancelar_aviso", "Cancela un temporizador o recordatorio por su id o por parte de su texto; «todos» cancela todos.",
      {"aviso": {"type": "string", "description": "id, parte del texto, o «todos»"}},
      required=["aviso"], icon="alarm_off")
def cancelar_aviso(aviso: str) -> dict:
    c = avisos.cancelar(aviso)
    if not c:
        return {"ok": False, "error": "no encuentro ese aviso"}
    return {"ok": True, "cancelados": [a["texto"] for a in c], "resumen": f"{len(c)} aviso(s) cancelado(s)"}
