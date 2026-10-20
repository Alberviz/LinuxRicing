"""Un solo dueño del audio de salida.

`OUT.hold()` es un lock compartido por Announcer, Speech y la confirmación de
escalada (que habla con `speak()`): nunca suenan dos voces a la vez. También
lleva el evento de interrupción (atajo o barge-in): corta lo que suena y el
ciclo pasa a escuchar en vez de cerrarse."""
from __future__ import annotations

import fcntl
import threading
from contextlib import contextmanager

from .config import DATA_DIR


class AnyEvent:
    """Se comporta como threading.Event de solo lectura: is_set() si lo está
    cualquiera de los eventos dados (None se ignora)."""

    def __init__(self, *events) -> None:
        self._events = [e for e in events if e is not None]

    def is_set(self) -> bool:
        return any(e.is_set() for e in self._events)


class AudioOut:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.interrupt_ev = threading.Event()
        self.barged = False  # la última interrupción vino de la voz de Alberto
        self._listeners: list = []  # callbacks (speaking: bool)

    def speaking(self) -> bool:
        return self._lock.locked()

    def on_change(self, fn) -> None:
        self._listeners.append(fn)

    def _notify(self, speaking: bool) -> None:
        for fn in self._listeners:
            try:
                fn(speaking)
            except Exception:  # noqa: BLE001
                pass

    def acquire(self) -> None:
        # lock de hilos + flock de fichero: también excluye a otros procesos
        # (p. ej. `laurad.py --text --speak` mientras el daemon da un aviso).
        self._lock.acquire()
        self._file = open(DATA_DIR / "audio.lock", "w")
        fcntl.flock(self._file, fcntl.LOCK_EX)
        self._notify(True)

    def release(self) -> None:
        self._notify(False)
        fcntl.flock(self._file, fcntl.LOCK_UN)
        self._file.close()
        self._lock.release()

    @contextmanager
    def hold(self):
        self.acquire()
        try:
            yield
        finally:
            self.release()

    def interrupt(self, barge: bool = False) -> None:
        self.barged = barge
        self.interrupt_ev.set()

    def clear_interrupt(self) -> None:
        self.interrupt_ev.clear()


OUT = AudioOut()
