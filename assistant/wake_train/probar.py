#!/usr/bin/env python
"""Score en directo del wake word: di «Laura despierta» y mira la barra.

Sirve para fijar `[wake] threshold` en config.toml: apunta el pico al decir la
frase y el máximo que alcanza hablando normal (o diciendo solo «Laura»).

    .venv/bin/python wake_train/probar.py [--modelo models/laura.onnx] [--umbral 0.8] [--patience 3]
"""
from __future__ import annotations

import argparse
import queue
import time
from pathlib import Path

import numpy as np
import sounddevice as sd

HERE = Path(__file__).resolve().parent.parent


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--modelo", default=str(HERE / "models/laura.onnx"))
    ap.add_argument("--umbral", type=float, default=0.8)
    ap.add_argument("--patience", type=int, default=3)
    args = ap.parse_args()
    from openwakeword.model import Model
    m = Model(wakeword_model_paths=[args.modelo])
    key = next(iter(m.models))
    q: queue.Queue = queue.Queue()
    print(f"Escuchando con «{key}» (Ctrl+C para salir)…\n")
    pico, t_pico, racha, ultimo = 0.0, 0.0, 0, 0.0
    with sd.InputStream(samplerate=16000, channels=1, dtype="int16", blocksize=1280,
                        callback=lambda d, *_: q.put(d[:, 0].copy())):
        try:
            while True:
                s = float(m.predict(q.get()).get(key, 0.0))
                now = time.monotonic()
                if s > pico or now - t_pico > 2:
                    pico, t_pico = s, now
                racha = racha + 1 if s >= args.umbral else 0
                bar = "█" * int(s * 40)
                mark = ""
                if racha >= args.patience and now - ultimo > 3:
                    mark, ultimo, racha = "  ◀ DISPARO (lo que haría Laura)", now, 0
                elif s >= args.umbral:
                    mark = f"  · {racha}/{args.patience}"
                print(f"\r{s:4.2f} |{bar:<40}| pico 2 s: {pico:4.2f}{mark}   ", end="", flush=True)
                if mark.startswith("  ◀"):
                    print()
        except KeyboardInterrupt:
            print()


if __name__ == "__main__":
    main()
