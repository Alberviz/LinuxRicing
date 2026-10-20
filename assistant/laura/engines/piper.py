"""Piper: voz local offline en CPU. Config: [tts.piper] voice (modelo en ~/.local/share/piper/voices)."""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from . import Engine, EngineUnavailable, engine


@engine("piper")
class Piper(Engine):
    def synth(self, text: str, out_wav: str) -> None:
        voice = self.cfg.get("voice", "es_ES-davefx-medium")
        exe = shutil.which("piper-tts") or shutil.which("piper")
        if not exe:
            raise EngineUnavailable("no encuentro piper-tts")
        model = Path.home() / f".local/share/piper/voices/{voice}.onnx"
        if not model.exists():
            raise EngineUnavailable(f"falta el modelo {model}")
        p = subprocess.run([exe, "-m", str(model), "-f", out_wav], input=text.encode("utf-8"),
                           capture_output=True)
        if p.returncode != 0:
            raise RuntimeError(p.stderr.decode(errors="ignore")[-200:] or "piper falló")
