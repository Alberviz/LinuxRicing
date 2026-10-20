"""Tools de memoria persistente."""
from __future__ import annotations

from .. import memory
from . import tool


@tool("recordar",
      "Guarda un hecho sobre Alberto: «recuerda que…», «apunta que no me gusta…». Frase corta.",
      {"hecho": {"type": "string", "description": "el hecho a recordar, en una frase corta"}},
      required=["hecho"], icon="bookmark_add")
def recordar(hecho: str) -> dict:
    nuevo = memory.add(hecho)
    return {"ok": True, "resumen": "Recordado" if nuevo else "Ya lo sabía",
            "nota": "Confirma en una frase corta."}


@tool("olvidar", "Borra de la memoria un hecho sobre Alberto («olvida que…»).",
      {"hecho": {"type": "string", "description": "el hecho o tema a olvidar"}},
      required=["hecho"], icon="bookmark_remove")
def olvidar(hecho: str) -> dict:
    b = memory.forget(hecho)
    if not b:
        return {"ok": False, "error": "no tenía nada guardado sobre eso"}
    return {"ok": True, "olvidados": b, "resumen": "Olvidado"}


@tool("que_sabes_de_mi", "Lista lo que recuerdas de Alberto («qué sabes de mí»).",
      icon="psychology")
def que_sabes_de_mi() -> dict:
    hs = [t for _, t in memory.all_facts()]
    return {"ok": True, "hechos": hs, "resumen": f"{len(hs)} cosas recordadas"}
