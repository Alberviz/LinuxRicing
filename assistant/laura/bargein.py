"""Barge-in por voz: mientras Laura habla, escucha el micro con el VAD y, si
detecta voz sostenida, corta la reproducción (OUT.interrupt) para pasar a escuchar.

Config en `[audio]`:
    barge_in = "auriculares"  # true | false | "auriculares": solo con auriculares.
                              # Por altavoces/tele (HDMI) Laura se oye a sí misma
                              # (no hay cancelación de eco) y se cortaba sola; ahí
                              # se corta con botón (Home mantenido, atajo de Laura).
    barge_in_threshold = 0.6  # probabilidad de voz (silero, 0..1) por bloque
    barge_in_ms = 300         # voz sostenida necesaria

Comparte el micro con wake y listen vía MIC (un solo InputStream)."""
from __future__ import annotations

import json
import subprocess
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
        return CFG["audio"].get("barge_in", False) not in (False, "false", "no")

    @staticmethod
    def output_is_headphones() -> bool:
        """¿La salida por defecto son auriculares? Bluetooth/USB = sí (cascos);
        HDMI = no (tele); tarjeta interna = según el puerto activo (jack o altavoz)."""
        try:
            sink = subprocess.run(["pactl", "get-default-sink"], capture_output=True, text=True, timeout=2).stdout.strip()
            if "hdmi" in sink:
                return False
            if sink.startswith("bluez") or ".usb-" in sink:
                return True
            sinks = json.loads(subprocess.run(["pactl", "-f", "json", "list", "sinks"], capture_output=True, text=True, timeout=2).stdout)
            info = next((x for x in sinks if x.get("name") == sink), {})
            port = (info.get("active_port") or "").lower()
            ff = info.get("properties", {}).get("device.form_factor", "")
            return "headphone" in port or "headset" in port or ff in ("headphone", "headset")
        except Exception:  # noqa: BLE001
            return False  # ante la duda, no: mejor no cortarse sola

    def _allowed(self) -> bool:
        mode = CFG["audio"].get("barge_in", False)
        return mode is True or mode == "true" or self.output_is_headphones()

    def install(self) -> None:
        """Se engancha al audio de salida: vigila solo mientras Laura habla."""
        if self.enabled():
            OUT.on_change(self._on_speaking)

    def _on_speaking(self, speaking: bool) -> None:
        if speaking and not self._allowed():
            log("barge-in: salida por altavoces/tele, solo se corta con botón")
            return
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
        thr = float(CFG["audio"].get("barge_in_threshold", 0.55))
        need = max(1, int(float(CFG["audio"].get("barge_in_ms", 220)) * SR / 1000 / CHUNK))
        run = 0
        q = MIC.subscribe()
        try:
            while not self._stop.is_set():
                try:
                    chunk = q.get(timeout=0.1)
                except Exception:  # noqa: BLE001
                    continue
                p = float(model(torch.from_numpy(np.ascontiguousarray(chunk)), SR).item())
                run = run + 1 if p >= thr else max(0, run - 1)
                if run >= need:
                    log(f"barge-in: voz detectada (p={p:.2f}, run={run}), corto la reproducción")
                    OUT.interrupt(barge=True)
                    return
        finally:
            MIC.unsubscribe(q)
            try:
                model.reset_states()
            except Exception:  # noqa: BLE001
                pass
