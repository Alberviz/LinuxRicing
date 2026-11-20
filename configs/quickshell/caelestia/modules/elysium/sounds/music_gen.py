#!/usr/bin/env python3
"""Música ambiente de Elysium: pieza original en bucle (Mi mayor, 74 BPM, ~1:44).

Espíritu: la calidez de un menú de consola (piano eléctrico suave, bajo redondo,
escobilla) con un toque espacial de fogata bajo las estrellas (cuerdas pulsadas
Karplus-Strong, pads lentos, destellos agudos con mucha reverb). Estéreo, 48 kHz.
El bucle es continuo: la cola de la reverb se pliega sobre el principio.

    python3 music_gen.py      -> ../music/elysium-ambient.ogg (necesita ffmpeg)
"""
import os, subprocess, wave

import numpy as np

SR = 48000
BPM = 74
BEAT = 60 / BPM
BAR = 4 * BEAT
rng = np.random.default_rng(11)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "music")


def hz(n):  # "E4" -> Hz
    names = "C C# D D# E F F# G G# A A# B".split()
    return 440 * 2 ** ((names.index(n[:-1]) - 9) / 12 + int(n[-1]) - 4)


# Progresión de 8 compases (x4 con variaciones = 32 compases)
PROG = [  # (bajo, voces del acorde)
    ("E2", ["E3", "G#3", "B3", "D#4", "F#4"]),   # Emaj9
    ("C#2", ["C#3", "E3", "G#3", "B3"]),          # C#m7
    ("A1", ["A2", "C#3", "E3", "G#3", "B3"]),     # Amaj9
    ("B1", ["B2", "D#3", "F#3", "G#3"]),          # B6
    ("G#1", ["G#2", "B2", "D#3", "F#3"]),         # G#m7
    ("C#2", ["C#3", "E3", "G#3", "B3", "D#4"]),   # C#m9
    ("A1", ["A2", "C#3", "E3", "F#3"]),           # A6
    ("B1", ["B2", "E3", "F#3", "A3"]),            # Bsus7
]
BARS = len(PROG) * 4
LEN = int(SR * BAR * BARS)
mixL = np.zeros(LEN + SR * 8)
mixR = np.zeros(LEN + SR * 8)


def put(sig, t, pan=0.0, gain=1.0):
    i = int(t * SR)
    n = min(len(sig), len(mixL) - i)
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    mixL[i:i + n] += sig[:n] * gain * l
    mixR[i:i + n] += sig[:n] * gain * r


def adsr(n, a, d, s, r_):
    t = np.arange(n) / SR
    e = np.where(t < a, t / a, s + (1 - s) * np.exp(-(t - a) / d))
    rel = int(r_ * SR)
    if rel < n:
        e[-rel:] *= np.linspace(1, 0, rel) ** 2
    return e


def epiano(f, dur, vel=1.0):
    """piano eléctrico tipo Rhodes: seno + parcial 2 con campana, trémolo suave"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t + 0.6 * np.exp(-t * 6) * np.sin(2 * np.pi * f * 2 * t))
    s += 0.18 * np.sin(2 * np.pi * f * 4.0 * t) * np.exp(-t * 9)
    s *= 1 + 0.12 * np.sin(2 * np.pi * 4.6 * t)
    return s * adsr(n, 0.006, 1.1, 0.0, 0.25) * vel


def pluck(f, dur, bright=0.5):
    """cuerda pulsada Karplus-Strong (vectorizada por periodos)"""
    n = int(dur * SR)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    # cuerpo más blando: ruido filtrado
    for _ in range(int(3 * (1 - bright)) + 1):
        buf = 0.5 * (buf + np.roll(buf, 1))
    out = np.zeros(n + p + 1)
    out[:p] = buf
    i = p
    decay = 0.996
    while i < n:
        j = min(i + p, n)
        prev = out[i - p:j - p + 1]
        out[i:j] = decay * 0.5 * (prev[:-1] + prev[1:]) if len(prev) > j - i else decay * prev[:j - i]
        i = j
    s = out[:n]
    return s * adsr(n, 0.002, 2.0, 0.0, 0.12)


def pad(freqs, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for f in freqs:
        for det in (-0.12, 0.0, 0.13):
            ph = rng.uniform(0, 2 * np.pi)
            s += np.sin(2 * np.pi * f * (1 + det / 100) * t + ph) + 0.25 * np.sin(2 * np.pi * 2 * f * (1 + det / 100) * t + ph)
    s /= len(freqs) * 3
    return s * adsr(n, dur * 0.35, 9, 1.0, dur * 0.35)


def bass(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 3)
    return s * adsr(n, 0.02, 0.9, 0.55, 0.2)


def brush(dur=0.18):
    n = int(dur * SR)
    x = rng.standard_normal(n)
    x = x - np.concatenate([[0], x[:-1]])  # aclarar (paso alto simple)
    return x * adsr(n, 0.004, 0.05, 0.0, 0.05) * 0.25


def star(f):
    n = int(2.5 * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 4)
    return s * adsr(n, 0.003, 0.7, 0.0, 0.4)


# ---------------- composición ----------------
for rep in range(4):
    for k, (b, ch) in enumerate(PROG):
        bar = rep * len(PROG) + k
        t0 = bar * BAR
        # pad de fondo (siempre)
        put(pad([hz(n) for n in ch[:4]], BAR * 1.15), t0, 0.0, 0.32)
        # bajo: desde la 2ª vuelta, redondas/blancas
        if rep >= 1:
            put(bass(hz(b), BEAT * 2.2), t0, 0, 0.42)
            put(bass(hz(b), BEAT * 1.8), t0 + BEAT * 2.5, 0, 0.32)
        # punteo de cuerda (fogata): corcheas en arpegio, desde el principio
        pattern = [0, 2, 1, 3, 2, 4 % len(ch), 1, 3]
        for i, idx in enumerate(pattern):
            f = hz(ch[idx % len(ch)]) * (2 if rep == 2 and i % 4 == 3 else 1)
            sw = 0.035 if i % 2 else 0  # un poco de swing
            put(pluck(f, 1.6, 0.35 + 0.1 * (i % 2)), t0 + i * BEAT / 2 + sw, -0.35 + 0.1 * (i % 3), 0.26 * (1.0 if i % 2 == 0 else 0.75))
        # piano eléctrico: acordes en 1 y en el «y» del 3 (vueltas 2 y 3)
        if rep in (1, 2):
            for tt, vel in ((0, 0.9), (2.5, 0.6)):
                for j, nn in enumerate(ch[1:]):
                    put(epiano(hz(nn), BEAT * 2.6, vel), t0 + tt * BEAT + j * 0.012, 0.3, 0.09)
        # melodía de campana (vuelta 3): notas largas de la escala
        if rep == 2:
            mel = ["B4", "G#4", "E5", "F#5", "D#5", "E5", "C#5", "B4"][k]
            put(epiano(hz(mel), BEAT * 3, 1.0), t0 + BEAT * 0.5, 0.15, 0.12)
            put(star(hz(mel) * 2), t0 + BEAT * 2.75, 0.5, 0.04)
        # escobilla: en los tiempos 2 y 4, desde la vuelta 2 (más floja en la 4)
        if rep in (1, 2, 3):
            for beat in (1, 3):
                put(brush(), t0 + beat * BEAT, 0.25, 0.5 if rep < 3 else 0.3)
            put(brush(0.08), t0 + 3.5 * BEAT, -0.2, 0.25)
        # destellos (estrellas) sueltos, siempre
        if rng.random() < 0.7:
            f = hz(rng.choice(["E5", "B5", "G#5", "F#5", "B4"]))
            put(star(f), t0 + rng.uniform(0, BAR), rng.uniform(-0.8, 0.8), 0.045)

# ---------------- reverb (convolución FFT) + bucle continuo ----------------
def reverb(x, secs=3.2, mix=0.32, seed=3):
    r = np.random.default_rng(seed)
    n = int(secs * SR)
    t = np.arange(n) / SR
    ir = r.standard_normal(n) * np.exp(-t * 6.9 / secs)
    ir[: int(0.012 * SR)] = 0  # pre-delay
    ir /= np.sqrt((ir ** 2).sum())
    m = len(x) + n
    nfft = 1 << (m - 1).bit_length()
    wet = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[:m]
    return np.concatenate([x, np.zeros(n)]) * (1 - mix) + wet * mix * 3.0


L = reverb(mixL, seed=3)
R = reverb(mixR, seed=4)
# plegar la cola sobre el principio para que el bucle no tenga corte
for ch in (L, R):
    tail = ch[LEN:].copy()
    ch[: len(tail)] += tail
L, R = L[:LEN], R[:LEN]
st = np.stack([L, R], 1)
st /= np.abs(st).max() / 0.6
# suave «cinta»: compresión ligera
st = np.tanh(st * 1.3) / np.tanh(1.3)

os.makedirs(OUT, exist_ok=True)
wav = os.path.join(OUT, "elysium-ambient.wav")
with wave.open(wav, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(st, -1, 1) * 32767).astype("<i2").tobytes())
ogg = os.path.join(OUT, "elysium-ambient.ogg")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
os.remove(wav)
print("ok:", ogg, "%.1f s" % (LEN / SR))
