"""Atajos rápidos sin LLM para comandos comunes (música, volumen, brillo, hora, bloqueo, captura)."""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from typing import Callable

_NUMEROS = {
    "cinco": 5, "diez": 10, "quince": 15, "veinte": 20, "veinticinco": 25,
    "treinta": 30, "cuarenta": 40, "cincuenta": 50,
}
_PRE = re.compile(r"^(?:(?:oye|eh|venga|vale|bueno|a ver|mira|laura|uf|(?:esto\s+)?suena\s+muy\s+(?:alto|fuerte))\s+)+")
_POST = re.compile(r"(?:\s+(?:por favor|porfa|anda|ya|laura|gracias))+$")


def normalizar(texto: str) -> str:
    """Minúsculas, sin tildes, sin puntuación y sin muletillas al inicio o final."""
    t = unicodedata.normalize("NFD", texto.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    t = re.sub(r"[^a-z0-9%\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    t = _PRE.sub("", t)
    t = _POST.sub("", t)
    return t.strip()


@dataclass(frozen=True)
class Atajo:
    tool: str
    args: dict = field(default_factory=dict)


_N = (r"(?:\s+(?:un poco|un poquito|(?:(?:en\s+)?un\s+)?(?P<n>\d{1,3}|" + "|".join(_NUMEROS)
      + r")(?:\s*%|\s+por\s*ciento)?))?")


def _num(m: re.Match, defecto: int = 10) -> int:
    v = m.group("n")
    if not v:
        return defecto
    return int(v) if v.isdigit() else _NUMEROS[v]


_REGLAS: list[tuple[str, Callable[[re.Match], Atajo]]] = [
    (r"(?:pon(?:me)?\s+)?pausa(?:la)?(?:\s+(?:a\s+)?(?:la\s+)?(?:musica|cancion))?|pon (?:la )?musica en pausa"
     r"|reanuda(?:\s+la\s+(?:musica|cancion))?|dale al play",
     lambda m: Atajo("control_musica", {"accion": "reproducir_pausar"})),
    (r"(?:pasa a la |pon la )?siguiente(?: cancion)?|salta(?:te)?(?: esta| la)? cancion",
     lambda m: Atajo("control_musica", {"accion": "siguiente"})),
    (r"(?:pon la |vuelve a la )?cancion anterior|(?:pon la |vuelve a la )anterior",
     lambda m: Atajo("control_musica", {"accion": "anterior"})),
    (r"(?:para|quita|apaga) la musica",
     lambda m: Atajo("control_musica", {"accion": "parar"})),
    (r"(?:sube(?:me)?(?:lo)?(?: el)? volumen|subelo)" + _N, lambda m: Atajo("volumen", {"porcentaje": _num(m)})),
    (r"(?:baja(?:me)?(?:lo)?(?: el)? volumen|bajalo)" + _N, lambda m: Atajo("volumen", {"porcentaje": -_num(m)})),
    (r"silencia(?:lo)?(?: el (?:audio|sonido))?|mutea(?:lo)?|quita el sonido",
     lambda m: Atajo("silenciar")),
    (r"sube(?:me)?(?: el)? brillo" + _N, lambda m: Atajo("brillo", {"cambio": _num(m)})),
    (r"baja(?:me)?(?: el)? brillo" + _N, lambda m: Atajo("brillo", {"cambio": -_num(m)})),
    (r"que hora es", lambda m: Atajo("hora_fecha")),
    (r"bloquea(?: la pantalla| el (?:ordenador|pc)| la sesion)?(?:\s+que me voy.*)?", lambda m: Atajo("bloquear_pantalla")),
    (r"(?:haz(?:me)?|saca(?:me)?) una captura(?: de pantalla)?|saca un pantallazo", lambda m: Atajo("captura_pantalla")),
]
_COMPILADAS = [(re.compile(p), f) for p, f in _REGLAS]


def resolver(texto: str) -> Atajo | None:
    """Intenta resolver la orden como un atajo determinista directo sin invocar al LLM."""
    t = normalizar(texto)
    for patron, hacer in _COMPILADAS:
        m = patron.fullmatch(t)
        if m:
            return hacer(m)
    return None


def decir(atajo: Atajo, resultado: dict) -> str:
    """Devuelve el texto a hablar por TTS para el resultado del atajo.

    'Son las X' para hora_fecha; vacío (solo overlay) para música, volumen, brillo, etc.;
    'No he podido: ...' si el resultado no es exitoso (ok=False).
    """
    if not resultado.get("ok"):
        err = resultado.get("error", "ha ocurrido un error")
        return f"No he podido: {err}."
    if atajo.tool == "hora_fecha":
        resumen = resultado.get("resumen")
        if resumen:
            return resumen
        hora = resultado.get("hora", "")
        return f"Son las {hora}." if hora else "No tengo la hora."
    return ""
