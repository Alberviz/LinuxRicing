"""Stubs documentados de motores de voz propia que necesitan paquetes no instalados.

Para activarlos: instala el paquete, implementa `synth()` (escribir un WAV en
`out_wav`) y pon el nombre en `[tts] engine`. Mientras tanto lanzan
EngineUnavailable y `laura.tts` pasa al siguiente motor de la cadena.

- pocket:    PocketTTS (Kyutai). `pip install pocket-tts`; clonación con
             `[tts.pocket] ref_audio`. Alternativa sin paquete: servirlo aparte
             y usar el motor `http`.
- omnivoice: OmniVoice servido localmente. Lo normal es usar el motor `http`
             apuntando a su servidor; este stub existe por si se quiere
             integrar en proceso.
"""
from __future__ import annotations

from . import Engine, EngineUnavailable, engine


@engine("pocket")
class Pocket(Engine):
    def synth(self, text: str, out_wav: str) -> None:
        raise EngineUnavailable("PocketTTS no instalado (pip install pocket-tts) o usa el motor «http»")


@engine("omnivoice")
class OmniVoice(Engine):
    def synth(self, text: str, out_wav: str) -> None:
        raise EngineUnavailable("OmniVoice no integrado en proceso: sírvelo aparte y usa el motor «http»")
