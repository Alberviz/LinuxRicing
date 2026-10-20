"""Kokoro: voz local en GPU (ef_dora / em_alex). Config: [tts.kokoro] voice."""
from __future__ import annotations

import numpy as np
import soundfile as sf

from ..config import log, resolve_device
from . import Engine, engine


@engine("kokoro")
class Kokoro(Engine):
    def __init__(self, cfg: dict) -> None:
        super().__init__(cfg)
        self.voice = cfg.get("voice", "ef_dora")
        self._pipe = None
        self._device = cfg.get("device", "auto")  # auto = como Whisper; cae a cpu si no cabe en VRAM

    def _load(self, device: str | None = None):
        if device is not None:
            self._device, self._pipe = device, None
        if self._pipe is None:
            log(f"cargando Kokoro ({self._dev()})…")
            from kokoro import KPipeline
            self._pipe = KPipeline(lang_code="e" if self.voice.startswith("e") else "a",
                                   device=self._dev())
        return self._pipe

    def _dev(self) -> str:
        return resolve_device() if self._device == "auto" else self._device

    def _run(self, text: str):
        parts = []
        for _, _, a in self._load()(text, voice=self.voice):
            parts.append(a.detach().cpu().numpy() if hasattr(a, "detach") else np.asarray(a))
        return np.concatenate(parts)

    def _run_safe(self, text: str):
        try:
            return self._run(text)
        except RuntimeError as e:
            if "out of memory" not in str(e).lower() or self._dev() == "cpu":
                raise
            log("Kokoro: sin VRAM libre, paso a CPU")
            self._load("cpu")
            return self._run(text)

    def warmup(self) -> None:
        self._run_safe("Hola.")

    def synth(self, text: str, out_wav: str) -> None:
        sf.write(out_wav, self._run_safe(text), 24000)
