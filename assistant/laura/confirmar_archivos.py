"""Confirmación de planes de archivos por voz o panel, sin audio ni STT (se inyectan).

`escalation.py` la usa con el micro y la voz reales; los tests, con funciones falsas."""
from __future__ import annotations

import re
from typing import Callable

from . import archivos

_SI = {"si", "sí", "vale", "adelante", "hazlo", "dale", "venga", "claro", "correcto", "confirmo",
       "confirmado", "ok", "perfecto"}
_NO = {"no", "nanay", "olvidalo", "olvídalo", "cancela", "cancelar", "cancélalo", "cancelalo",
       "mejor", "nada", "para"}


def interpretar(texto: str) -> bool | None:
    """«sí / vale / hazlo» -> True; «no / cancela / mejor no» -> False; otra cosa -> None.
    Solo frases cortas (máx. 4 palabras sin «Laura»): una frase larga no es un sí o no."""
    palabras = [w for w in re.findall(r"[\wáéíóúüñ]+", (texto or "").lower()) if w != "laura"]
    if not palabras or len(palabras) > 4:
        return None
    if palabras[0] in _NO:
        return False
    if any(w in _SI for w in palabras):
        return True
    return None


def confirmar(plan, escena, decir: Callable[[str], None],
              escuchar: Callable[[object], str | None],
              cancelado: Callable[[], bool] = lambda: False) -> str:
    """Pregunta, escucha un sí/no a la vez que espera al panel (`plan.evento`) y resuelve el plan.

    `decir(texto)` habla; `escuchar(evento)` devuelve la frase dicha, o None si hubo silencio o
    se activó `evento` (lo resolvió el panel). Devuelve el estado final del plan."""
    decir(plan.pregunta())
    # Si se corta el ciclo (pulsar «escribir», el atajo, «para») el plan NO se cancela: sigue
    # pendiente y visible hasta que se confirme, se cancele de verdad o caduque.
    if cancelado():
        return plan.estado
    if not plan.evento.is_set():
        frase = escuchar(plan.evento)
        if cancelado():
            return plan.estado
    else:
        frase = None
    if plan.evento.is_set():                       # lo resolvió el panel (o caducó)
        if plan.mensaje:
            decir(plan.mensaje)
        return plan.estado
    if not frase:
        decir("Lo dejo pendiente en el panel.")
        return plan.estado
    res = escena.resolver_plan(plan.id, bool(interpretar(frase)))   # ambiguo = no
    decir(res.get("decir") or res.get("error") or "Hecho.")
    return plan.estado


def grace_escucha(grace: float, espera_larga: bool, escena_activa: bool) -> float:
    """Segundos de silencio que Laura aguanta antes de cerrar el ciclo. Con hologramas en
    pantalla Alberto mira la lista antes de decir qué hacer: se espera el triple."""
    if escena_activa:
        return grace * 3
    return grace * 2 if espera_larga else grace


def responder_pendiente(texto: str, escena, decir: Callable[[str], None]) -> bool:
    """Si hay un plan pendiente y `texto` es un sí/no claro, lo resuelve sin pasar por el LLM.
    Devuelve True si lo ha gestionado (Alberto contestó tarde, tras «lo dejo pendiente»)."""
    plan = archivos.pendiente()
    if plan is None:
        return False
    r = interpretar(texto)
    if r is None:
        return False
    res = escena.resolver_plan(plan.id, r)
    decir(res.get("decir") or res.get("error") or "Hecho.")
    return True
