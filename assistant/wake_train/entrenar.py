#!/usr/bin/env python
"""Entrena el modelo openWakeWord de «Laura despierta» y lo exporta a models/laura.onnx.

Arquitectura (la de openWakeWord): audio 16 kHz → melspectrograma → embeddings de
Google speech_embedding (congelados, los trae openwakeword) → clasificador pequeño
nuestro sobre las últimas 16 ventanas (16×96, ≈2 s de contexto) → probabilidad.

Datos (~/.local/share/laura/wake/):
  pos/  sint_*.wav (TTS) y alb_*.wav (tu voz) — «Laura despierta»
  neg/  todo lo demás: «Laura» sola, frases, ambiente, grabaciones largas
  oww/validation_set_features.npy — ~11 h de habla/ruido variados (falsos positivos/hora)

Aumento: reverberación sintética, filtros de micro, ruido de fondo (tu ambiente,
ruido coloreado, murmullo de otras frases) y volumen. Además, cada positivo se usa
también CORTADO antes de «despierta» como negativo (para no saltar con «Laura…»).

    .venv/bin/python wake_train/entrenar.py [--epocas 40]
"""
from __future__ import annotations

import argparse
import random
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from scipy.signal import butter, fftconvolve, sosfilt

HERE = Path(__file__).resolve().parent.parent
DATA = Path.home() / ".local/share/laura/wake"
OUT = HERE / "models" / "laura.onnx"
SR = 16000
CLIP = 2 * SR          # 2,0 s → exactamente 16 embeddings
NFR = 16


def load(p: Path) -> np.ndarray:
    a, sr = sf.read(p, dtype="float32", always_2d=True)
    a = a.mean(1)
    assert sr == SR, p
    return a


def habla(a: np.ndarray) -> tuple[int, int]:
    """Inicio y fin aproximados de la voz (energía por bloques de 20 ms)."""
    b = 320
    n = len(a) // b
    if n == 0:
        return 0, len(a)
    e = np.sqrt((a[: n * b].reshape(n, b) ** 2).mean(1))
    thr = max(e.max() * 0.08, np.percentile(e, 20) * 3, 1e-4)
    idx = np.where(e > thr)[0]
    if idx.size == 0:
        return 0, len(a)
    return idx[0] * b, min(len(a), (idx[-1] + 1) * b)


# ---------------------------------------------------------------- aumento
class Aug:
    def __init__(self, rng: np.random.Generator, ruidos: list[np.ndarray],
                 murmullo: list[np.ndarray]) -> None:
        self.rng, self.ruidos, self.murmullo = rng, ruidos, murmullo

    def ruido(self, n: int) -> np.ndarray:
        r = self.rng.random()
        if r < 0.45 and self.ruidos:
            src = self.ruidos[self.rng.integers(len(self.ruidos))]
            if len(src) > n:
                i = self.rng.integers(len(src) - n)
                return src[i:i + n].copy()
        if r < 0.7 and self.murmullo:
            out = np.zeros(n, "float32")
            for _ in range(self.rng.integers(1, 4)):
                m = self.murmullo[self.rng.integers(len(self.murmullo))][:n]
                i = self.rng.integers(0, n - len(m) + 1)
                out[i:i + len(m)] += m * self.rng.uniform(0.3, 1.0)
            return out
        # ruido coloreado (blanco/rosa/marrón)
        w = self.rng.standard_normal(n).astype("float32")
        f = np.fft.rfftfreq(n, 1 / SR)
        f[0] = f[1]
        W = np.fft.rfft(w) / f ** (self.rng.choice([0, 0.5, 1.0]))
        return np.fft.irfft(W, n).astype("float32")

    def __call__(self, a: np.ndarray, fondo: bool = True) -> np.ndarray:
        rng = self.rng
        if rng.random() < 0.5:  # reverberación sintética
            rt60 = rng.uniform(0.15, 0.8)
            t = np.arange(int(SR * min(rt60, 0.5))) / SR
            rir = rng.standard_normal(t.size) * np.exp(-6.9 * t / rt60)
            rir[0] = 1.0 / rng.uniform(0.3, 1.0)
            a = fftconvolve(a, rir / np.abs(rir).sum() * 4)[: len(a)].astype("float32")
        if rng.random() < 0.35:  # micro: paso banda
            lo, hi = rng.uniform(60, 300), rng.uniform(3000, 7600)
            a = sosfilt(butter(4, [lo, hi], "bandpass", fs=SR, output="sos"), a).astype("float32")
        pk = np.abs(a).max() + 1e-6
        a = a / pk * rng.uniform(0.05, 0.9)
        if fondo and rng.random() < 0.8:
            nz = self.ruido(len(a))
            snr = rng.uniform(3, 30)
            ps = (a ** 2).mean() + 1e-9
            pn = (nz ** 2).mean() + 1e-9
            a = a + nz * np.sqrt(ps / pn / 10 ** (snr / 10))
        return np.clip(a, -1, 1).astype("float32")


def colocar(voz: np.ndarray, fin: int, n: int = CLIP) -> np.ndarray:
    """Pone `voz` dentro de un clip de n muestras terminando en la muestra `fin`."""
    out = np.zeros(n, "float32")
    i = fin - len(voz)
    s0, d0 = max(0, i), max(0, -i)
    m = min(n, fin) - s0
    if m > 0:
        out[s0:s0 + m] = voz[d0:d0 + m]
    return out


# ---------------------------------------------------------------- datos
def construir(rng: np.random.Generator, pyr: random.Random):
    pos_files = sorted((DATA / "pos").glob("*.wav"))
    neg_files = sorted((DATA / "neg").glob("*.wav"))
    alb_pos = [p for p in pos_files if p.name.startswith("alb_")]
    sint_pos = [p for p in pos_files if not p.name.startswith("alb_")]
    largos = [p for p in neg_files if p.name.startswith(("alb_habla", "alb_ambiente"))]
    cortos = [p for p in neg_files if p not in largos]
    print(f"pos: {len(sint_pos)} sint + {len(alb_pos)} tuyas · neg: {len(cortos)} cortos + "
          f"{len(largos)} largos")

    ruidos = [load(p) for p in largos if "ambiente" in p.name]
    murm = [load(p) * 0.5 for p in pyr.sample(cortos, min(300, len(cortos)))]
    aug = Aug(rng, ruidos, murm)

    # validación: tus últimas 8 tomas + 8 % de las sintéticas (no se entrenan)
    pyr.shuffle(sint_pos)
    nv = max(1, int(0.08 * len(sint_pos)))
    val_pos = sint_pos[:nv] + alb_pos[-8:]
    tr_pos = [(p, 4) for p in sint_pos[nv:]] + [(p, 30) for p in alb_pos[:-8]]

    X, Y = [], []

    def voz_de(p: Path) -> np.ndarray:
        a = load(p)
        s, e = habla(a)
        return a[max(0, s - 1600): min(len(a), e + 800)]

    for p, k in tr_pos:
        v = voz_de(p)
        for _ in range(k):
            fin = CLIP - int(rng.uniform(0.0, 0.3) * SR)
            X.append(aug(colocar(v, fin)))
            Y.append(1)
        # cortado: solo se ve el principio («Laura de…») → negativo
        for _ in range(max(1, k // 3)):
            fin = CLIP + int(rng.uniform(0.45, 0.9) * SR)
            X.append(aug(colocar(v, fin)))
            Y.append(0)

    for p in cortos:
        v = voz_de(p)
        k = 6 if "casi" in p.name else (3 if "solo_laura" in p.name else 2)
        for _ in range(k):
            fin = CLIP - int(rng.uniform(-0.6, 0.6) * SR)
            X.append(aug(colocar(v, fin)))
            Y.append(0)

    for p in largos:
        a = load(p)
        for i in range(0, len(a) - CLIP, SR // 4):
            X.append(aug(a[i:i + CLIP].copy(), fondo=False))
            Y.append(0)

    for _ in range(1500):  # silencio/ruido puro
        X.append(aug.ruido(CLIP) * rng.uniform(0.001, 0.3))
        Y.append(0)

    Xv = []
    for p in val_pos:
        v = voz_de(p)
        Xv.append(aug(colocar(v, CLIP - int(0.1 * SR))))
    return np.stack(X), np.array(Y, "float32"), np.stack(Xv)


def embed(F, X: np.ndarray) -> np.ndarray:
    pcm = (np.clip(X, -1, 1) * 32767).astype("int16")
    E = F.embed_clips(pcm, batch_size=256, ncpu=8)
    return E[:, -NFR:, :].astype("float32")


# ---------------------------------------------------------------- modelo
class Net(torch.nn.Module):
    def __init__(self, h: int = 128) -> None:
        super().__init__()
        self.f = torch.nn.Sequential(
            torch.nn.Flatten(), torch.nn.Linear(NFR * 96, h), torch.nn.LayerNorm(h),
            torch.nn.ReLU(), torch.nn.Dropout(0.3), torch.nn.Linear(h, h),
            torch.nn.LayerNorm(h), torch.nn.ReLU(), torch.nn.Linear(h, 1), torch.nn.Sigmoid())

    def forward(self, x):
        return self.f(x)


def ventanas(fe: np.ndarray) -> np.ndarray:
    """Features continuas (N, 96) → vista (M, 16, 96) sin copiar memoria."""
    return np.lib.stride_tricks.sliding_window_view(fe, (NFR, fe.shape[1]))[:, 0]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--epocas", type=int, default=40)
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("--oww", type=int, default=150000, help="ventanas de oww como negativos")
    ap.add_argument("--wneg", type=float, default=30.0, help="peso máximo de los negativos")
    ap.add_argument("--wpos", type=float, default=1.0, help="peso de los positivos")
    ap.add_argument("--rehacer", action="store_true", help="ignora la caché de embeddings")
    args = ap.parse_args()
    rng, pyr = np.random.default_rng(args.seed), random.Random(args.seed)
    torch.manual_seed(args.seed)

    from openwakeword.utils import AudioFeatures
    F = AudioFeatures(ncpu=8)
    cache = DATA / f"cache_seed{args.seed}.npz"
    if cache.exists() and not args.rehacer:
        c = np.load(cache)
        E, Y, Ev = c["E"], c["Y"], c["Ev"]
        print(f"embeddings de la caché {cache.name} (--rehacer para recalcular)")
    else:
        X, Y, Xv = construir(rng, pyr)
        print(f"clips: {len(X)} ({int(Y.sum())} positivos) · embebiendo…", flush=True)
        E, Ev = embed(F, X), embed(F, Xv)
        del X
        np.savez(cache, E=E, Y=Y, Ev=Ev)

    vf = DATA / "oww" / "validation_set_features.npy"
    fp_feats = None
    if vf.exists():
        raw = np.load(vf)
        fp_feats = raw if raw.ndim == 3 else ventanas(raw)
        horas = (len(raw) if raw.ndim == 2 else len(raw) * NFR) * 0.08 / 3600
        # una parte de esas 11 h también como negativos de entrenamiento
        cut = len(fp_feats) // 2
        extra = fp_feats[np.sort(rng.choice(cut, min(cut, args.oww), replace=False))].copy()
        fp_feats, horas = fp_feats[cut:], horas / 2
        E = np.concatenate([E, extra])
        Y = np.concatenate([Y, np.zeros(len(extra), "float32")])
        print(f"+{len(extra)} ventanas de oww como negativos; {horas:.1f} h para medir")

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    net = Net().to(dev)
    opt = torch.optim.AdamW(net.parameters(), lr=1e-3, weight_decay=1e-3)
    Et, Yt = torch.tensor(E), torch.tensor(Y)
    npos = Y.sum()
    for ep in range(args.epocas):
        net.train()
        perm = torch.randperm(len(Et))
        # el peso de los negativos crece con las épocas (castiga cada vez más los falsos)
        wneg = 1 + (args.wneg - 1) * ep / max(1, args.epocas - 1)
        tot = 0.0
        for i in range(0, len(perm), 512):
            b = perm[i:i + 512]
            x, y = Et[b].to(dev), Yt[b].to(dev)
            p = net(x).squeeze(1).clamp(1e-6, 1 - 1e-6)
            w = torch.where(y > 0.5, torch.full_like(y, args.wpos * 20), torch.full_like(y, wneg))
            loss = (torch.nn.functional.binary_cross_entropy(p, y, reduction="none") * w).mean()
            opt.zero_grad()
            loss.backward()
            opt.step()
            tot += loss.item() * len(b)
        if ep % 5 == 4 or ep == args.epocas - 1:
            print(f"época {ep + 1}: pérdida {tot / len(Et):.4f}", flush=True)

    net.eval().cpu()
    with torch.no_grad():
        sv = net(torch.tensor(Ev)).squeeze(1).numpy()
        sfp = None if fp_feats is None else np.concatenate([
            net(torch.from_numpy(np.ascontiguousarray(fp_feats[i:i + 4096]))).squeeze(1).numpy()
            for i in range(0, len(fp_feats), 4096)])
        print("\nValidación (frases no vistas):")
        for thr in (0.3, 0.5, 0.7, 0.9):
            linea = f"  umbral {thr}: detecta {100 * (sv >= thr).mean():.0f} %"
            if sfp is not None:
                # disparos = flancos de subida (un disparo dura varias ventanas seguidas)
                d = np.diff((sfp >= thr).astype(int))
                linea += f" · falsos {int((d == 1).sum()) / horas:.2f}/h"
            print(linea)

    OUT.parent.mkdir(exist_ok=True)
    torch.onnx.export(net, torch.zeros(1, NFR, 96), str(OUT), input_names=["input"],
                      output_names=["output"], dynamic_axes={"input": {0: "b"}, "output": {0: "b"}},
                      opset_version=13, dynamo=False)
    print(f"\nModelo: {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
