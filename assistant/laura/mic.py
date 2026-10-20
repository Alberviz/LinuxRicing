"""Micrófono compartido: UN solo InputStream con distribuidor.

Wake word, `listen()` y barge-in se suscriben y reciben los mismos bloques de
512 muestras float32 a 16 kHz. El stream se abre con el primer suscriptor y se
cierra con el último (sin suscriptores no se retiene el micro). `inject()`
mete audio como si viniera del micro (pruebas y simulación)."""
from __future__ import annotations

import collections
import queue
import threading

import numpy as np

from .config import log

SR = 16000
CHUNK = 512  # silero-vad requiere exactamente 512 muestras a 16 kHz


class Mic:
    def __init__(self, use_device: bool = True) -> None:
        self._use_device = use_device
        self._lock = threading.Lock()
        self._subs: list[queue.Queue] = []
        self._stream = None
        self._recent: collections.deque = collections.deque(maxlen=int(1.5 * SR / CHUNK))

    # -- suscripción
    def subscribe(self) -> queue.Queue:
        q: queue.Queue = queue.Queue()
        with self._lock:
            self._subs.append(q)
            if self._stream is None and self._use_device:
                self._open()
        return q

    def unsubscribe(self, q: queue.Queue) -> None:
        with self._lock:
            if q in self._subs:
                self._subs.remove(q)
            if not self._subs:
                self._close()

    def _open(self) -> None:
        import sounddevice as sd
        self._stream = sd.InputStream(samplerate=SR, channels=1, dtype="float32",
                                      blocksize=CHUNK, callback=self._callback)
        self._stream.start()

    def _close(self) -> None:
        if self._stream is not None:
            try:
                self._stream.stop()
                self._stream.close()
            except Exception as e:  # noqa: BLE001
                log(f"mic: {e}")
            self._stream = None

    def _callback(self, indata, *_) -> None:
        self.inject(indata[:, 0].copy())

    # -- distribución
    def inject(self, chunk: np.ndarray) -> None:
        """Reparte un bloque (1-D float32) a todos los suscriptores."""
        self._recent.append(chunk)
        for q in list(self._subs):
            q.put(chunk)

    def recent(self, seconds: float) -> list[np.ndarray]:
        n = max(1, int(seconds * SR / CHUNK))
        return list(self._recent)[-n:]

    def clear_recent(self) -> None:
        self._recent.clear()


MIC = Mic()
