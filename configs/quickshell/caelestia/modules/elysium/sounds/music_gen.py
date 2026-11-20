#!/usr/bin/env python3
"""Ambiente espacial de Elysium: el «sonido de nave en el espacio» de las películas.

Nada de instrumentos ni ritmo: capas de zumbido y ruido que respiran muy despacio.
    - zumbido de la nave: fundamental grave (E1 ≈ 41 Hz) + armónicos con batidos lentos
    - rumor sub: ruido marrón por debajo de ~90 Hz que crece y se retira
    - aire de cabina: ruido suave filtrado (~150-700 Hz) con un barrido muy lento
    - dron tonal: quintas y octavas graves (E/B) que aparecen y desaparecen en 30-60 s
    - resonancias lejanas: «gemidos» metálicos graves (bandas estrechas 180-420 Hz) muy espaciados
    - reverb larga
Todo se sintetiza en el dominio de la frecuencia sobre la duración EXACTA del bucle y con
LFOs de un número entero de ciclos: el bucle es circular y no tiene costura.

    python3 music_gen.py      -> ../music/elysium-ambient.ogg (necesita ffmpeg)
"""
import os, subprocess, wave

import numpy as np

SR = 48000
DUR = 192.0                     # s (bucle)
N = int(SR * DUR)
t = np.arange(N) / SR
rng = np.random.default_rng(23)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "music")
F = np.fft.rfftfreq(N, 1 / SR)


def lfo(cycles, phase=0.0):
    """LFO de 0..1 con un número entero de ciclos en el bucle (circular)"""
    return 0.5 + 0.5 * np.sin(2 * np.pi * cycles * t / DUR + phase)


def shaped_noise(gain_fn, seed):
    """ruido circular con una curva de ganancia por frecuencia"""
    r = np.random.default_rng(seed)
    spec = (r.standard_normal(len(F)) + 1j * r.standard_normal(len(F))) * gain_fn(F)
    spec[0] = 0
    x = np.fft.irfft(spec, N)
    return x / (np.abs(x).max() + 1e-12)


def tone(f, phase=0.0):
    # frecuencia ajustada para que haga ciclos enteros en el bucle (sin salto)
    f = round(f * DUR) / DUR
    return np.sin(2 * np.pi * f * t + phase)


def band(lo, hi, slope=2.0):
    def g(f):
        g = np.ones_like(f)
        g *= 1 / (1 + (lo / np.maximum(f, 1)) ** (2 * slope))
        g *= 1 / (1 + (f / hi) ** (2 * slope))
        return g
    return g


E1, B1, E2, B2, E3 = 41.2, 61.7, 82.4, 123.5, 164.8

layers = []

# 1) zumbido de la nave: E1 + armónicos, con pares desafinados (batido lento)
hum = np.zeros(N)
for k, amp in ((1, 1.0), (2, 0.55), (3, 0.28), (4, 0.16), (6, 0.07)):
    f = E1 * k
    hum += amp * (tone(f) + tone(f + 0.07 * k, 1.3)) * 0.5
hum *= 0.75 + 0.25 * lfo(5, 0.4)
layers.append((hum / np.abs(hum).max(), 0.34, 0.0))

# 2) rumor sub (ruido marrón < 90 Hz), crece y se retira
sub = shaped_noise(lambda f: band(18, 90, 2)(f) / np.maximum(f, 18) * 30, 1)
sub *= 0.45 + 0.55 * lfo(3, 2.0)
layers.append((sub, 0.42, 0.0))

# 3) aire de cabina: dos versiones del mismo ruido (más oscura y más abierta) cruzándose
air_dark = shaped_noise(band(120, 380, 1.5), 2)
air_open = shaped_noise(band(180, 750, 1.5), 3)
x = lfo(2, 1.1)
air = air_dark * (1 - x) + air_open * x
air *= 0.6 + 0.4 * lfo(7, 0.2)
layers.append((air, 0.10, 0.0))

# 4) dron tonal: E2, B2, E3 que aparecen y desaparecen muy despacio, cada uno a su ritmo
drone = np.zeros(N)
for f, cyc, ph, amp in ((E2, 3, 0.0, 0.9), (B2, 4, 1.7, 0.7), (E3, 5, 3.1, 0.45), (B1, 2, 4.2, 0.6)):
    # timbre suave: fundamental + 2º armónico, con un vibrato lentísimo
    vib = 0.15 * np.sin(2 * np.pi * 1 * t / DUR * 9)
    ph_acc = 2 * np.pi * np.cumsum(f + vib) / SR
    ph_acc -= np.linspace(0, ph_acc[-1] - round(ph_acc[-1] / (2 * np.pi)) * 2 * np.pi, N)  # cerrar el ciclo
    s = np.sin(ph_acc + ph) + 0.3 * np.sin(2 * ph_acc + ph)
    drone += amp * s * lfo(cyc, ph) ** 2.2
layers.append((drone / np.abs(drone).max(), 0.20, 0.0))

# 5) resonancias lejanas: bandas estrechas graves que se hinchan muy de vez en cuando
groan = np.zeros(N)
for i, (fc, when) in enumerate(((210, 0.12), (330, 0.37), (180, 0.58), (260, 0.81), (410, 0.93))):
    nb = shaped_noise(lambda f, fc=fc: np.exp(-((f - fc) / (fc * 0.012)) ** 2), 10 + i)
    center = when * DUR
    d = np.minimum(np.abs(t - center), DUR - np.abs(t - center))  # distancia circular
    env = np.exp(-(d / 5.5) ** 2)
    groan += nb * env
layers.append((groan / (np.abs(groan).max() + 1e-9), 0.13, 0.0))

mono = sum(sig * g for sig, g, _ in layers)

# Estéreo amplio: cada lado con un retardo y un ruido de aire distinto
L = mono + 0.04 * shaped_noise(band(150, 600, 1.5), 40) * (0.5 + 0.5 * lfo(3, 0))
R = np.roll(mono, int(0.017 * SR)) + 0.04 * shaped_noise(band(150, 600, 1.5), 41) * (0.5 + 0.5 * lfo(3, 2))


def reverb_circular(x, secs=6.0, mix=0.45, seed=5):
    """reverb por convolución CIRCULAR (la cola vuelve al principio del bucle)"""
    r = np.random.default_rng(seed)
    n = int(secs * SR)
    tt = np.arange(n) / SR
    ir = r.standard_normal(n) * np.exp(-tt * 6.9 / secs)
    ir = np.fft.irfft(np.fft.rfft(ir) * band(30, 2500, 1.0)(np.fft.rfftfreq(n, 1 / SR)), n)  # reverb oscura
    ir /= np.sqrt((ir ** 2).sum())
    irp = np.zeros(N)
    irp[:n] = ir
    wet = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irp), N)
    return x * (1 - mix) + wet * mix * 2.5


L, R = reverb_circular(L, seed=5), reverb_circular(R, seed=6)
st = np.stack([L, R], 1)
st /= np.abs(st).max() / 0.55

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
print("ok:", ogg, "%.0f s" % DUR)
