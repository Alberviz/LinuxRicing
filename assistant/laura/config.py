"""Configuración, log, notificaciones y bus de eventos compartidos."""
from __future__ import annotations

import os
import subprocess
import tomllib
from pathlib import Path

from .events import EventBus

HERE = Path(__file__).resolve().parent.parent  # assistant/
CFG = tomllib.loads((HERE / "config.toml").read_text())

# Si se vuelve a poner STT/TTS en CPU (config.toml [stt] device = "cpu"), ocultar
# la GPU antes del primer `import torch` para que no abra un contexto CUDA de
# ~1 GB que no usaría: en la tarjeta de 6 GB esa VRAM le hace falta al LLM.
if CFG["stt"]["device"] == "cpu":
    os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

DATA_DIR = Path(os.environ.get("LAURA_DATA", Path.home() / ".local/share/laura"))
DATA_DIR.mkdir(parents=True, exist_ok=True)

bus = EventBus(CFG["daemon"]["events_socket"])


def log(*a):
    print("[laura]", *a, flush=True)


def notify(title: str, body: str = ""):
    if CFG["daemon"].get("notify"):
        subprocess.Popen(["notify-send", "-a", "Laura", "-i",
                          "audio-input-microphone-symbolic", title, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)



_device_cache: str | None = None


def resolve_device() -> str:
    """Precarga cuBLAS/cuDNN (si procede), importa torch y devuelve 'cuda' o 'cpu'."""
    global _device_cache
    if _device_cache is not None:
        return _device_cache
    # ----------------------------------------------------------------- STT & CUDA setup
    # faster-whisper (CTranslate2) en CUDA necesita cuDNN 9 y cuBLAS 12 de los wheels
    # de pip, que no están en el linker path del sistema. Hay que precargarlas a mano.
    #
    # OJO: precargar TODO `nvidia/*/lib/*.so` arrastra también `libnvblas.so`, un
    # interceptor de BLAS que, cargado con RTLD_GLOBAL y sin `nvblas.conf` ni BLAS de
    # CPU de respaldo, tumba el proceso con SIGSEGV en la primera llamada BLAS (justo
    # al empezar a escuchar). Por eso aquí se cargan SOLO cuBLAS y cuDNN, en ese
    # orden (cuDNN depende de cuBLAS), y nada más.
    if CFG["stt"]["device"] == "cuda":
        import ctypes
        import glob

        for _sub in ("cublas", "cudnn"):
            for _p in sorted(glob.glob(str(
                    HERE / f".venv/lib/python*/site-packages/nvidia/{_sub}/lib/*.so*"))):
                if "nvblas" in _p:
                    continue
                try:
                    ctypes.CDLL(_p, mode=ctypes.RTLD_GLOBAL)
                except OSError:
                    pass

    import torch

    dev = CFG["stt"]["device"]
    if dev == "cuda" and not torch.cuda.is_available():
        log("CUDA no disponible, usando CPU")
        dev = "cpu"
    _device_cache = dev
    return dev
