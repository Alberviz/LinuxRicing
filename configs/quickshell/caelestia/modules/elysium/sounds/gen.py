#!/usr/bin/env python3
"""Genera los efectos de sonido de Elysium (WAV 48 kHz, mono, 16 bit) en esta carpeta.

Timbre común: campana de cristal (seno + parciales inarmónicos suaves que decaen más
rápido), ataque de 3-6 ms sin clics, cola con un eco corto y un poco de aire. Todo
en una escala de Mi mayor para que los sonidos encajen entre sí.

    python3 gen.py
"""
import os, wave

import numpy as np

SR = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
N = lambda name: 440.0 * 2 ** ((("C C# D D# E F F# G G# A A# B".split().index(name[:-1])) - 9) / 12 + int(name[-1]) - 4)


def env(n, a=0.004, d=0.4):
    t = np.arange(n) / SR
    e = np.minimum(1, t / a) * np.exp(-t / d)
    e[-int(SR * 0.004):] *= np.linspace(1, 0, int(SR * 0.004))  # cola sin clic
    return e


def bell(freq, dur, decay=0.35, bright=0.35):
    n = int(SR * dur)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * freq * t)
    for ratio, amp, dk in ((2.0, 0.35 * bright, 0.5), (2.76, 0.25 * bright, 0.3), (5.4, 0.12 * bright, 0.15)):
        s += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / (decay * dk))
    return s * env(n, 0.004, decay)


def mix(dur, *parts):
    out = np.zeros(int(SR * dur))
    for start, sig in parts:
        i = int(SR * start)
        out[i:i + len(sig)] += sig[:len(out) - i]
    return out


def echo(s, delay=0.09, fb=0.28, n=3):
    out = s.copy()
    d = int(SR * delay)
    for k in range(1, n + 1):
        out[d * k:] += s[:len(s) - d * k] * fb ** k
    return out


def air(dur, lo, hi, amp=0.15):
    """ruido filtrado que barre de lo a hi Hz (un «whoosh»)"""
    n = int(SR * dur)
    x = np.random.default_rng(7).standard_normal(n)
    f = np.geomspace(lo, hi, n)
    y, s1, s2 = np.zeros(n), 0.0, 0.0
    for i in range(n):  # paso banda de 2 polos con frecuencia variable
        a = 2 * np.pi * f[i] / SR
        s1 += a * (x[i] - s1 - 0.6 * s2)
        s2 += a * s1
        y[i] = s1
    t = np.linspace(0, 1, n)
    return y / (np.abs(y).max() + 1e-9) * amp * np.sin(np.pi * t) ** 1.5


def pad(freqs, dur, attack=0.5):
    n = int(SR * dur)
    t = np.arange(n) / SR
    s = sum(np.sin(2 * np.pi * f * t + 0.3 * np.sin(2 * np.pi * 0.7 * t)) * (0.9 ** i) for i, f in enumerate(freqs))
    e = np.minimum(1, t / attack) * np.minimum(1, (dur - t) / (dur * 0.5))
    return s * np.clip(e, 0, 1) / len(freqs)


def save(name, s, peak=0.42):
    s = s / (np.abs(s).max() + 1e-9) * peak
    f = int(SR * 0.01)
    s[-f:] *= np.linspace(1, 0, f) ** 2  # fundido final: sin clic
    data = (np.clip(s, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(HERE, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


save("move", bell(N("B6"), 0.07, decay=0.025, bright=0.15), peak=0.16)
save("select", echo(mix(0.45, (0, bell(N("E5"), 0.3, 0.18)), (0.06, bell(N("B5"), 0.38, 0.22)))), peak=0.36)
save("back", mix(0.32, (0, bell(N("B5"), 0.2, 0.12, 0.2)), (0.055, bell(N("E5"), 0.26, 0.14, 0.2))), peak=0.28)
save("dialog", echo(bell(N("G#5"), 0.25, 0.1, 0.25), 0.07, 0.2, 2), peak=0.26)
save("toggle_on", mix(0.22, (0, bell(N("E5"), 0.12, 0.06, 0.2)), (0.05, bell(N("G#5"), 0.16, 0.08, 0.2))), peak=0.26)
save("toggle_off", mix(0.22, (0, bell(N("G#5"), 0.12, 0.06, 0.2)), (0.05, bell(N("E5"), 0.16, 0.08, 0.2))), peak=0.24)
save("prompt", echo(mix(0.9, (0, bell(N("E6"), 0.6, 0.35)), (0.16, bell(N("B5"), 0.7, 0.4)))), peak=0.34)
save("error", mix(0.45, (0, bell(N("C#4"), 0.3, 0.12, 0.6)), (0.12, bell(N("C4"), 0.32, 0.14, 0.6))), peak=0.32)
save("success", echo(mix(1.4, *[(i * 0.085, bell(N(n), 1.0 - i * 0.1, 0.45)) for i, n in enumerate(["E5", "G#5", "B5", "E6"])])), peak=0.36)
save("open", echo(mix(2.0, (0, pad([N("E3"), N("B3"), N("E4"), N("G#4")], 1.9, 0.7) * 0.8),
                     (0.15, air(1.2, 300, 5000, 0.5)), (0.75, bell(N("B5"), 1.1, 0.5)), (0.9, bell(N("E6"), 1.0, 0.5)))), peak=0.38)
save("close", mix(1.2, (0, pad([N("G#4"), N("E4"), N("B3")], 1.1, 0.05) * 0.7), (0, air(0.9, 4000, 300, 0.4)),
                  (0.05, bell(N("E5"), 0.8, 0.35, 0.2))), peak=0.3)
save("launch", echo(mix(2.4, (0, air(1.3, 200, 9000, 0.9)), (0.55, pad([N("E3"), N("E4"), N("B4"), N("G#5")], 1.8, 0.4)),
                       (0.9, bell(N("E6"), 1.3, 0.6)), (1.0, bell(N("B6"), 1.2, 0.5, 0.2)))), peak=0.4)
print("ok:", sorted(f for f in os.listdir(HERE) if f.endswith(".wav")))
