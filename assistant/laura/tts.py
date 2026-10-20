"""Síntesis de voz multi-motor (edge / piper / kokoro) y tubería de voz por frases."""
from __future__ import annotations

import queue
import subprocess
import threading
from pathlib import Path

import numpy as np
import soundfile as sf

from .audio import _play_with_amplitude
from .config import CFG, bus, log, resolve_device

EFFECTS = {
    "dry": None,
    "jarvis": ("highpass=f=200,lowpass=f=3800,chorus=0.5:0.9:50:0.4:0.25:2,"
               "aecho=0.85:0.75:35:0.2,volume=2"),
    "subnautica": ("asetrate=24000*0.93,aresample=24000,aecho=0.8:0.9:55:0.35,"
                   "aecho=0.8:0.9:120:0.2,highpass=f=140,lowpass=f=7000,volume=2.2"),
    "robot": ("aeval='val(0)*(0.65+0.7*sin(2*PI*45*t))':c=same,"
              "highpass=f=300,lowpass=f=3200,volume=3"),
}


# --------------------------------------------------------------------------- TTS
_tts_engine = CFG.get("tts", {}).get("engine", "auto")
_tts_voice = CFG.get("tts", {}).get("voice", "es-ES-ElviraNeural")

if _tts_engine == "auto":
    if _tts_voice.startswith("es-ES-") or _tts_voice.startswith("es-"):
        _tts_engine = "edge"
    elif _tts_voice.startswith("es_ES-"):
        _tts_engine = "piper"
    else:
        _tts_engine = "kokoro"

_kokoro = None
if _tts_engine == "kokoro":
    log("cargando Kokoro…")
    from kokoro import KPipeline
    _kokoro = KPipeline(lang_code="e" if _tts_voice.startswith("e") else "a", device=resolve_device())
else:
    log(f"TTS configurado en motor '{_tts_engine}' (voz: {_tts_voice})")


def _synth_wav(text: str, tag: str) -> str:
    """Sintetiza `text` según el motor configurado, aplica el efecto y devuelve la ruta del wav."""
    raw = f"/tmp/laura_{tag}_raw.wav"
    engine = _tts_engine
    voice = CFG["tts"]["voice"]

    if engine == "edge":
        import asyncio
        import edge_tts

        raw_mp3 = f"/tmp/laura_{tag}_raw.mp3"

        async def _run():
            communicate = edge_tts.Communicate(text, voice)
            await communicate.save(raw_mp3)

        asyncio.run(_run())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw_mp3, raw], check=True)
    elif engine == "piper":
        import shutil
        piper_bin = "piper-tts" if shutil.which("piper-tts") else "piper"
        model_path = Path.home() / f".local/share/piper/voices/{voice}.onnx"
        p = subprocess.Popen([piper_bin, "-m", str(model_path), "-f", raw], stdin=subprocess.PIPE)
        p.communicate(input=text.encode("utf-8"))
    else:
        global _kokoro
        if _kokoro is None:
            from kokoro import KPipeline
            _kokoro = KPipeline(lang_code="e" if voice.startswith("e") else "a", device=resolve_device())
        parts = []
        for _, _, a in _kokoro(text, voice=voice):
            parts.append(a.detach().cpu().numpy() if hasattr(a, "detach") else np.asarray(a))
        sf.write(raw, np.concatenate(parts), 24000)

    af = EFFECTS.get(CFG["tts"]["effect"])
    if not af:
        return raw
    out = f"/tmp/laura_{tag}.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw,
                    "-af", af, out], check=True)
    return out


def speak(text: str, cancel: threading.Event | None = None) -> None:
    """Sintetiza y reproduce `text` de una vez (camino sin streaming)."""
    if not text or (cancel is not None and cancel.is_set()):
        return
    _play_with_amplitude(_synth_wav(text, "out"), cancel)


class Speech:
    """Tubería de voz por frases. Se le van dando frases (`feed`) según las
    genera el LLM; un hilo las sintetiza y otro las reproduce en orden, de modo
    que la primera frase suena mientras la segunda aún se está sintetizando.
    Emite `state=speaking` al arrancar el primer audio y `reply` acumulado
    frase a frase (subtítulos que crecen con la voz)."""

    def __init__(self, cancel: threading.Event | None, mode: str) -> None:
        self.cancel = cancel
        self.mode = mode
        self._tts_q: queue.Queue = queue.Queue()
        self._play_q: queue.Queue = queue.Queue()
        self._spoken: list[str] = []
        self._n = 0
        self._t_tts = threading.Thread(target=self._tts_loop, daemon=True)
        self._t_play = threading.Thread(target=self._play_loop, daemon=True)
        self._t_tts.start()
        self._t_play.start()

    def _stopped(self) -> bool:
        return self.cancel is not None and self.cancel.is_set()

    def feed(self, sentence: str) -> None:
        s = sentence.strip()
        if s and not self._stopped():
            self._tts_q.put(s)

    def _tts_loop(self) -> None:
        while True:
            s = self._tts_q.get()
            if s is None:
                self._play_q.put(None)
                return
            if self._stopped():
                continue
            self._n += 1
            try:
                wav = _synth_wav(s, f"s{self._n}")
            except Exception as e:  # noqa: BLE001
                log(f"error sintetizando «{s[:40]}…»: {e}")
                continue
            self._play_q.put((wav, s))

    def _play_loop(self) -> None:
        while True:
            item = self._play_q.get()
            if item is None:
                return
            if self._stopped():
                continue
            wav, s = item
            if not self._spoken:
                bus.emit(type="state", value="speaking", mode=self.mode)
            self._spoken.append(s)
            bus.emit(type="reply", value=" ".join(self._spoken))
            _play_with_amplitude(wav, self.cancel, reset=False)

    def finish(self) -> str:
        """Espera a que suene todo y devuelve lo que se ha hablado."""
        self._tts_q.put(None)
        self._t_tts.join()
        self._t_play.join()
        bus.emit(type="amplitude", value=0.0)
        return " ".join(self._spoken)

