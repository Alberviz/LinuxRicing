"""Barge-in por voz: mientras Laura habla, escucha el micro con el VAD y, si
detecta voz sostenida, corta la reproducción (OUT.interrupt) para pasar a escuchar.

Config en `[audio]`:
    barge_in = false          # desactivado por defecto: sin auriculares el eco
                              # de los altavoces puede dispararlo
    barge_in_threshold = 0.6  # probabilidad de voz (silero, 0..1) por bloque
    barge_in_ms = 300         # voz sostenida necesaria

Comparte el micro con wake y listen vía MIC (un solo InputStream)."""
from __future__ import annotations

import threading

import numpy as np

from .config import CFG, log
from .mic import CHUNK, MIC, SR
from .output import OUT


class BargeIn:
    def __init__(self) -> None:
        self._stop = threading.Event()
        self._t: threading.Thread | None = None
        self._model = None

    @staticmethod
    def enabled() -> bool:
        return bool(CFG["audio"].get("barge_in", False))

    def install(self) -> None:
        """Se engancha al audio de salida: vigila solo mientras Laura habla."""
        if self.enabled():
            OUT.on_change(self._on_speaking)

    def _on_speaking(self, speaking: bool) -> None:
        if speaking:
            self._stop.clear()
            self._t = threading.Thread(target=self._watch, daemon=True)
            self._t.start()
        else:
            self._stop.set()

    def _watch(self) -> None:
        import torch
        if self._model is None:  # instancia propia: el VAD es con estado
            from silero_vad import load_silero_vad
            self._model = load_silero_vad()
        model = self._model
        thr = float(CFG["audio"].get("barge_in_threshold", 0.6))
        need = max(1, int(float(CFG["audio"].get("barge_in_ms", 300)) * SR / 1000 / CHUNK))
        run = 0
        q = MIC.subscribe()
        try:
            while not self._stop.is_set():
                try:
                    chunk = q.get(timeout=0.2)
                except Exception:  # noqa: BLE001
                    continue
                p = float(model(torch.from_numpy(np.ascontiguousarray(chunk)), SR).item())
                run = run + 1 if p >= thr else 0
                if run >= need:
                    log("barge-in: voz sostenida, corto la reproducción")
                    OUT.interrupt(barge=True)
                    return
        finally:
            MIC.unsubscribe(q)
            try:
                model.reset_states()
            except Exception:  # noqa: BLE001
                pass
