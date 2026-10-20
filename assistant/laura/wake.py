"""Escucha de palabra de activación (openWakeWord)."""
from __future__ import annotations

import os
import queue
import threading
import time

import numpy as np

from .config import CFG, HERE, log
from .mic import MIC

class WakeListener:
    """Escucha el micro compartido (MIC) con un modelo diminuto (openWakeWord)
    y dispara `on_wake` al oír la palabra clave. NO transcribe nada — el
    pipeline pesado (Whisper + LLM + TTS) solo arranca al detectar la palabra.
    Mientras hay un ciclo activo (`pause`) descarta el audio: no se auto-dispara
    con la voz de Laura. Ya no abre su propio stream: comparte el del distribuidor,
    así que pausar/reanudar no pelea por el micro."""

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
        self._t = threading.Thread(target=self._loop, daemon=True)

    def start(self) -> None:
        self._t.start()

    def pause(self) -> None:
        self._paused.set()

    def resume(self) -> None:
        self._oww.reset()
        self._paused.clear()

    def _loop(self) -> None:
        last = 0.0
        buf = np.zeros(0, "float32")
        q = MIC.subscribe()
        try:
            while not self._stop.is_set():
                try:
                    chunk = q.get(timeout=0.5)
                except queue.Empty:
                    continue
                if self._paused.is_set():
                    buf = buf[:0]
                    continue
                buf = np.concatenate([buf, chunk])
                while buf.size >= self.FRAME:
                    frame, buf = buf[:self.FRAME], buf[self.FRAME:]
                    pcm = (np.clip(frame, -1, 1) * 32767).astype("int16")
                    try:
                        score = self._oww.predict(pcm).get(self._key, 0.0)
                    except Exception as e:  # noqa: BLE001
                        log(f"wake listener: {e}")
                        time.sleep(1)
                        continue
                    now = time.monotonic()
                    if score >= self._threshold and now - last > self._cooldown:
                        last = now
                        log(f"wake «{self._key}» ({score:.2f})")
                        self._on_wake()
        finally:
            MIC.unsubscribe(q)


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
