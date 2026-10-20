"""Tools que lanzan trabajos en segundo plano: investigar y pedir_a_aurora."""
from __future__ import annotations

from ..config import CFG
from . import tool


def _manager():
    from .. import jobs
    if jobs.MANAGER is None:
        raise RuntimeError("el gestor de trabajos no está activo")
    return jobs.MANAGER


@tool("investigar",
      "Investiga un tema en Internet EN SEGUNDO PLANO y deja el resultado en el panel y en una nota («investiga qué es X», «averigua cómo funciona Y a fondo»). No es para datos rápidos (usa buscar_web).",
      {"tema": {"type": "string", "description": "qué investigar, en una frase"}},
      required=["tema"], icon="travel_explore")
def investigar(tema: str) -> dict:
    destino = CFG.get("background", {}).get("investigar", "gemini")
    if destino not in ("gemini", "laura"):
        destino = "gemini"
    jid = _manager().start(destino, tema, kind="investigar", titulo=f"Investigar: {tema}")
    return {"ok": True, "id": jid, "resumen": "Investigando en segundo plano",
            "nota": "Dile a Alberto solo «Me pongo con ello» (una frase); el resultado le llegará al panel."}


@tool("pedir_a_aurora",
      "Pide algo a Aurora, la asistente personal de Alberto: Google Calendar, correo, Drive, recados y cualquier cosa larga («pregúntale a Aurora qué tengo mañana», «dile a Aurora que me cree un evento»). Va en segundo plano.",
      {"peticion": {"type": "string", "description": "lo que Alberto quiere, tal cual"}},
      required=["peticion"], icon="support_agent")
def pedir_a_aurora(peticion: str) -> dict:
    jid = _manager().start("aurora", peticion, kind="aurora", titulo=f"Aurora: {peticion}")
    return {"ok": True, "id": jid, "resumen": "Se lo pido a Aurora",
            "nota": "Dile a Alberto solo «Se lo pido a Aurora» (una frase)."}
