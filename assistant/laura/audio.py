"""Captura de micro con VAD y reproducción de audio con envolvente de amplitud."""
from __future__ import annotations

import queue
import subprocess
import threading
import time

import numpy as np
import soundfile as sf

from .config import CFG, bus

from .mic import CHUNK as VAD_CHUNK, MIC, SR  # noqa: E402

_vad_model = None


def load_vad():
    """Carga silero-vad (una vez). El daemon la llama al arrancar."""
    global _vad_model
    if _vad_model is None:
        from silero_vad import load_silero_vad
        _vad_model = load_silero_vad()
    return _vad_model


def listen(max_seconds: float | None = None,
           cancel: threading.Event | None = None,
           start_grace: float | None = None,
           preroll: float = 0.0) -> np.ndarray:
    """Graba desde el micro compartido y corta cuando detecta silencio tras hablar.

    `max_seconds` acota la grabación total. `start_grace` (follow-up) cierra
    la escucha si la voz no ha empezado en esos segundos: así la conversación
    no se queda abierta esperando. `cancel` corta al instante (segundo
    SUPER+A). `preroll` (s) antepone el audio reciente del micro: tras un
    barge-in recupera las primeras palabras con las que Alberto interrumpió."""
    if max_seconds is None:
        max_seconds = CFG["audio"]["max_seconds"]
    from silero_vad import VADIterator
    load_vad()
    vad = VADIterator(_vad_model, sampling_rate=SR,
                      min_silence_duration_ms=CFG["audio"]["silence_ms"])
    frames: list[np.ndarray] = []
    spoke = False
    gain = float(CFG["audio"].get("amp_gain", 12.0))

    q = MIC.subscribe()
    try:
        pending = MIC.recent(preroll) if preroll > 0 else []
        t0 = time.monotonic()
        while time.monotonic() - t0 < max_seconds:
            if cancel is not None and cancel.is_set():
                break
            if start_grace is not None and not spoke and time.monotonic() - t0 > start_grace:
                break
            if pending:
                chunk = pending.pop(0)
            else:
                try:
                    chunk = q.get(timeout=0.2)
                except queue.Empty:
                    continue
            frames.append(chunk)
            rms = float(np.sqrt(np.mean(chunk ** 2)))
            bus.emit(type="amplitude", value=min(1.0, rms * gain))
            event = vad(chunk, return_seconds=True)
            if event:
                if "start" in event:
                    spoke = True
                elif "end" in event and spoke:
                    break
    finally:
        MIC.unsubscribe(q)
    vad.reset_states()
    # Sin arranque de voz detectado = no habló nadie (evita que Whisper
    # alucine palabras del silencio y la conversación no acabe nunca).
    if not spoke or not frames:
        return np.zeros(0, "float32")
    return np.concatenate(frames)


def _play_with_amplitude(wav_path: str, cancel: threading.Event | None = None,
                         hz: float = 25.0, reset: bool = True) -> None:
    """Reproduce el wav y emite su envolvente RMS por ventanas, en sincronía."""
    data, sr = sf.read(wav_path, dtype="float32")
    if data.ndim > 1:
        data = data.mean(axis=1)
    win = max(1, int(sr / hz))
    env = np.array([np.sqrt(np.mean(data[i:i + win] ** 2))
                    for i in range(0, len(data), win) if data[i:i + win].size])
    if env.size == 0:
        proc = subprocess.Popen(["paplay", wav_path])
        proc.wait()
        return
    env = np.nan_to_num(env)
    peak = float(env.max()) or 1.0
    env = np.minimum(1.0, env / peak)
    step = win / sr
    proc = subprocess.Popen(["paplay", wav_path])
    t0 = time.monotonic()
    for i, v in enumerate(env):
        if cancel is not None and cancel.is_set():
            proc.terminate()
            break
        bus.emit(type="amplitude", value=float(v))
        target = t0 + (i + 1) * step
        time.sleep(max(0.0, target - time.monotonic()))
    proc.wait()
    if reset:
        bus.emit(type="amplitude", value=0.0)
