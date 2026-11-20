#!/usr/bin/env python
"""Graba la voz de Alberto para entrenar el wake word «Laura despierta».

1. Positivos: 40 tomas de ~2 s. Di «Laura despierta» cuando veas ● GRABANDO (varía:
   normal, flojito, desde lejos, con prisa, con pausa entre las dos palabras…).
2. Casi: 20 tomas diciendo SOLO «Laura» o «Laura, ven/mira…» o «despierta» suelta
   (negativos duros: tu novia se llama Laura, solo vale la frase entera).
3. Negativos: 90 s hablando normal SIN decir la frase (lee algo, cuenta tu día,
   di «Aurora», «ahora», «la hora»…).
4. Ambiente: 45 s en silencio (ruido de tu cuarto, ventilador, teclado si quieres).

    .venv/bin/python wake_train/grabar.py [--tomas 40] [--solo pos|casi|neg|amb]
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

import numpy as np
import sounddevice as sd
import soundfile as sf

DATA = Path.home() / ".local/share/laura/wake"
SR = 16000
CONSEJOS = ["normal", "flojito", "más alto", "rápido", "lento", "con pausa: «Laura… despierta»",
            "«oye Laura, despierta»", "girando la cabeza / desde más lejos", "cansado", "con energía"]
CASI = ["«Laura»", "«Laura, ven»", "«oye Laura»", "«despierta»", "«Laura, mira esto»",
        "«¿Laura?»", "«Laura, ¿estás despierta?»", "«venga, despierta»", "«Laura, espera»",
        "«Aurora, despierta»"]


def rec(seg: float) -> np.ndarray:
    a = sd.rec(int(seg * SR), samplerate=SR, channels=1, dtype="float32")
    sd.wait()
    return a[:, 0]


def nivel(a: np.ndarray) -> str:
    db = 20 * np.log10(np.abs(a).max() + 1e-9)
    return f"pico {db:5.1f} dBFS" + ("  ⚠ muy bajo" if db < -30 else "") + (
        "  ⚠ satura" if db > -0.5 else "")


def siguiente(d: Path, pref: str) -> int:
    return len(list(d.glob(f"{pref}_*.wav")))


def tomas(n: int, carpeta: str, pref: str, titulo: str, guion: list[str]) -> None:
    d = DATA / carpeta
    d.mkdir(parents=True, exist_ok=True)
    i0 = siguiente(d, pref)
    print(f"\n== {titulo}: {n} tomas ==\nEn cada toma: Enter → sale ● GRABANDO (2,5 s) → habla."
          "\nEscribe «r» + Enter para repetir la toma anterior.")
    k = 0
    while k < n:
        orden = input(f"\n[{k + 1}/{n}] di: {guion[k % len(guion)]}   (Enter para grabar) ")
        if orden.strip().lower() == "r" and k > 0:
            k -= 1
            print(f"  repitiendo la toma {k + 1}: {guion[k % len(guion)]}")
        time.sleep(0.2)
        print("  ● GRABANDO", flush=True)
        a = rec(2.5)
        print("  ■ ok ", nivel(a))
        sf.write(d / f"{pref}_{i0 + k:04d}.wav", a, SR)
        k += 1


def largo(nombre: str, seg: int, instr: str) -> None:
    d = DATA / "neg"
    d.mkdir(parents=True, exist_ok=True)
    print(f"\n== {nombre.upper()}: {seg} s ==\n{instr}")
    input("Pulsa Enter para empezar…")
    print("  ● GRABANDO", flush=True)
    a = rec(seg)
    print("  ", nivel(a))
    sf.write(d / f"alb_{nombre}_{siguiente(d, f'alb_{nombre}'):02d}.wav", a, SR)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tomas", type=int, default=40)
    ap.add_argument("--solo", choices=["pos", "casi", "neg", "amb"])
    args = ap.parse_args()
    print("Micro:", sd.query_devices(kind="input")["name"])
    if args.solo in (None, "pos"):
        tomas(args.tomas, "pos", "alb", "POSITIVOS «Laura despierta»",
              [f"«Laura despierta» ({c})" for c in CONSEJOS])
    if args.solo in (None, "casi"):
        tomas(args.tomas // 2, "neg", "alb_casi", "CASI (sin la frase entera)", CASI)
    if args.solo in (None, "neg"):
        largo("habla", 90, "Habla normal SIN decir «Laura despierta»: lee algo, cuenta tu día, "
              "di también «Aurora», «ahora», «la hora», «Lara», «Clara»…")
    if args.solo in (None, "amb"):
        largo("ambiente", 45, "Silencio (o tu ruido normal: ventilador, teclado…).")
    print(f"\nListo. Datos en {DATA}")


if __name__ == "__main__":
    main()
