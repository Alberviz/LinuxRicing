"""Tool cola_dj: Laura hace de puente con un subagente DJ que elige las canciones (ver laura/dj.py)."""
from __future__ import annotations

from . import tool


@tool("cola_dj",
      "Monta una cola de Spotify con canciones que elige un DJ (subagente) cuando Alberto pide un TIPO de música "
      "o N canciones sin nombrarlas: «ponme 10 canciones de reggaeton antiguo en la cola», «hazme una cola para "
      "estudiar», «añade 5 temas parecidos a esto». Va en segundo plano. Pasa el pedido tal cual. "
      "modo: nueva = empieza ya; anadir = detrás de lo que suena (si no lo dice, se decide solo). "
      "donde=tele si dice «en la tele».",
      {"pedido": {"type": "string", "description": "lo que pide Alberto, tal cual (estilo, época, ánimo…)"},
       "cantidad": {"type": "integer", "description": "número de canciones (por defecto 15)"},
       "modo": {"type": "string", "enum": ["nueva", "anadir"]},
       "donde": {"type": "string", "enum": ["tele", "pc", "actual"]}},
      required=["pedido"], icon="queue_music")
def cola_dj(pedido: str, cantidad: int | None = None, modo: str | None = None, donde: str | None = None) -> dict:
    from .. import dj, jobs
    if not (pedido or "").strip():
        return {"ok": False, "error": "¿qué tipo de música quieres?"}
    if jobs.MANAGER is None:
        return {"ok": False, "error": "el gestor de trabajos no está activo"}
    n = dj.cantidad(cantidad)
    jid = jobs.MANAGER.start("gemini", pedido.strip(), kind="dj", titulo=f"DJ: {pedido.strip()}",
                             data={"cantidad": n, "modo": modo, "donde": donde})
    return {"ok": True, "id": jid, "resumen": f"El DJ prepara {n} canciones",
            "nota": "Dile a Alberto solo «Se lo pido al DJ, en unos segundos lo tienes» (una frase). "
                    "Laura avisará cuando la cola esté puesta."}
