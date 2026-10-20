"""Escucha de palabra de activación (openWakeWord)."""
from __future__ import annotations

import os
import threading
import time

import sounddevice as sd

from .audio import SR
from .config import CFG, HERE, log

class WakeListener:
    """Escucha el micro en segundo plano con un modelo diminuto (openWakeWord)
    y dispara `on_wake` al oír la palabra clave. NO transcribe nada — el
    pipeline pesado (Whisper + LLM + Kokoro) solo arranca al detectar la
    palabra. Se pausa mientras hay un ciclo activo (no competir por el micro
    ni auto-dispararse con la voz de Laura)."""

    FRAME = 1280  # 80 ms a 16 kHz — tamaño que espera openWakeWord

    def __init__(self, model_path: str, threshold: float, cooldown: float,
                 on_wake) -> None:
        from openwakeword.model import Model
        kw = {} if model_path.endswith(".onnx") else {"inference_framework": "tflite"}
        self._oww = Model(wakeword_model_paths=[model_path], **kw)
        self._key = next(iter(self._oww.models))
        self._threshold = threshold
        self._cooldown = cooldown
        self._on_wake = on_wake
        self._paused = threading.Event()
        self._stop = threading.Event()
        self._idle = threading.Event()  # el micro está libre (stream cerrado)
        self._idle.set()
        self._t = threading.Thread(target=self._loop, daemon=True)

    def start(self) -> None:
        self._t.start()

    def pause(self) -> None:
        """Suelta el micro y no vuelve hasta resume(). Bloquea hasta que el
        stream de captura esté realmente cerrado (el ciclo lo necesita)."""
        self._paused.set()
        self._idle.wait(timeout=1.0)

    def resume(self) -> None:
        self._oww.reset()
        self._paused.clear()

    def _loop(self) -> None:
        last = 0.0
        while not self._stop.is_set():
            if self._paused.is_set():
                time.sleep(0.1)
                continue
            try:
                self._idle.clear()
                with sd.InputStream(samplerate=SR, channels=1, dtype="int16",
                                    blocksize=self.FRAME) as stream:
                    while not self._stop.is_set() and not self._paused.is_set():
                        data, _ = stream.read(self.FRAME)
                        score = self._oww.predict(data[:, 0]).get(self._key, 0.0)
                        now = time.monotonic()
                        if score >= self._threshold and now - last > self._cooldown:
                            last = now
                            log(f"wake «{self._key}» ({score:.2f})")
                            self._on_wake()
            except Exception as e:  # noqa: BLE001
                log(f"wake listener: {e}")
                time.sleep(1)
            finally:
                self._idle.set()


def _make_wake(on_wake) -> WakeListener | None:
    wcfg = CFG.get("wake", {})
    if not wcfg.get("enabled") or not wcfg.get("model"):
        return None
    mp = os.path.expanduser(wcfg["model"])
    if not os.path.isabs(mp):
        mp = str(HERE / mp)
    if not os.path.exists(mp):
        log(f"wake word: no encuentro el modelo {mp} — solo atajo")
        return None
    try:
        w = WakeListener(mp, float(wcfg.get("threshold", 0.5)),
                         float(wcfg.get("cooldown", 3.0)), on_wake)
        log(f"wake word activo: {mp}")
        return w
    except Exception as e:  # noqa: BLE001
        log(f"wake word desactivado ({e}) — solo atajo")
        return None
