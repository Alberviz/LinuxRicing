"""Transcripción de voz a texto (faster-whisper)."""
from __future__ import annotations

import numpy as np
import soundfile as sf

from .audio import SR
from .config import CFG, log, resolve_device

log("cargando Whisper…")
_device = resolve_device()
from faster_whisper import WhisperModel  # noqa: E402

_stt = WhisperModel(CFG["stt"]["model"],
                    device=_device,
                    compute_type="int8" if _device == "cpu"
                    else "float16")


# Alucinaciones típicas de Whisper sobre silencio/ruido (es).
_STT_NOISE = {"música", "musica", "gracias", "subtítulos realizados por la comunidad de amara.org",
              "suscríbete", "suscribíos", "¡gracias!", "gracias por ver el video", "amara.org"}


def transcribe(audio: np.ndarray) -> str:
    if audio.size < SR * 0.3:
        return ""
    sf.write("/tmp/laura_in.wav", audio, SR)
    segments, _ = _stt.transcribe("/tmp/laura_in.wav",
                                  language=CFG["stt"]["language"],
                                  vad_filter=True)
    text = " ".join(s.text for s in segments).strip()
    if text.lower().strip(" .,!?¡¿") in _STT_NOISE or len(text.strip(" .,!?")) < 2:
        return ""
    return text
