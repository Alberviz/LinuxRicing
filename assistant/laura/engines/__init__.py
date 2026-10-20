"""Motores de voz (TTS) enchufables.

Añadir un motor nuevo = UN fichero en este paquete con una clase decorada con
`@engine("nombre")`. Se descubre solo al importar el paquete.

    from . import Engine, engine

    @engine("miMotor")
    class MiMotor(Engine):
        def synth(self, text: str, out_wav: str) -> None:
            ...  # escribe un WAV en out_wav; lanza EngineUnavailable si no puede

Cada motor lee su configuración de `[tts.<nombre>]` en config.toml (dict `self.cfg`).
Si lanza una excepción, `laura.tts` prueba el siguiente de la cadena
(`[tts] engine` + `fallbacks`) y lo aparca unos minutos."""
from __future__ import annotations

import importlib
import pkgutil

from ..config import log


class EngineUnavailable(RuntimeError):
    """El motor no puede funcionar ahora (falta un paquete, un servidor caído…)."""


class Engine:
    name = "?"

    def __init__(self, cfg: dict) -> None:
        self.cfg = cfg

    def warmup(self) -> None:
        """Carga modelos por adelantado (el daemon lo llama al arrancar)."""

    def synth(self, text: str, out_wav: str) -> None:
        raise NotImplementedError


REGISTRY: dict[str, type[Engine]] = {}


def engine(name: str):
    def deco(cls):
        cls.name = name
        REGISTRY[name] = cls
        return cls
    return deco


def _discover() -> None:
    for m in pkgutil.iter_modules(__path__):
        try:
            importlib.import_module(f"{__name__}.{m.name}")
        except Exception as e:  # noqa: BLE001
            log(f"motor de voz «{m.name}» no disponible: {e}")


_discover()
