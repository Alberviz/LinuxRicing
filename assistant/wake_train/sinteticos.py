#!/usr/bin/env python
"""Genera muestras sintéticas para entrenar el wake word «Laura despierta».

Positivos: «Laura despierta» (y variantes) con todas las voces Piper en español
y voces Kokoro mezcladas al azar (timbres infinitos), con velocidad variable.
Negativos: «Laura» sola o con otra palabra, «despierta» sola, frases normales y parecidas («Aurora», «ahora»,
«Lara», «Clara»…), con las mismas voces.

Salida: WAV 16 kHz mono en ~/.local/share/laura/wake/{pos,neg}/sint_*.wav

    .venv/bin/python wake_train/sinteticos.py [--pos 1500] [--neg 2500]
"""
from __future__ import annotations

import argparse
import json
import random
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

DATA = Path.home() / ".local/share/laura/wake"
PIPER_DIR = Path.home() / ".local/share/piper/voices"
SR = 16000

POS_TXT = ["Laura despierta", "Laura, despierta.", "¡Laura, despierta!", "Laura despierta.",
           "Laura… despierta.", "Oye, Laura, despierta.", "Venga Laura, despierta.",
           "¿Laura? Despierta.", "Laura, despiértate.", "Laura despierta ya."]

# «Laura» sin «despierta» (Laura es también el nombre de la novia de Alberto) y
# «despierta» sin «Laura»: negativos duros, el modelo debe exigir las dos juntas.
CASI = [
    "Laura", "Laura.", "¡Laura!", "¿Laura?", "Oye Laura.", "Laura, ven.", "Laura, mira esto.",
    "Laura, ¿qué tal?", "Laura, espera.", "Laura, ¿dónde estás?", "Hola Laura.", "Laura, cariño.",
    "Laura, despacio.", "Laura, después.", "Laura, desde luego.", "Laura, dispara.",
    "Laura, ¿estás despierta?", "Laura está despierta.", "Laura se despierta tarde.",
    "Despierta.", "¡Despierta!", "Despierta ya.", "Venga, despierta.", "Aurora, despierta.",
    "Clara, despierta.", "Lara despierta.", "Maura, despierta.", "Paula, despierta.",
    "Despierta, que es tarde.", "La hora despierta.", "Ahora despierta.",
]

CONFUSABLES = [
    "Aurora", "ahora", "la hora", "Lara", "Clara", "aura", "laurel", "Mauro", "Maura",
    "lora", "la ruta", "dura", "oscura", "Lucía", "Laia", "Paula", "Raúl", "Laureano",
    "Lorena", "la lluvia", "la radio", "ya era hora", "Lourdes", "lavadora", "ahora mismo",
    "Oye Aurora", "Aurora, mira esto", "la aurora boreal", "es la hora", "a la hora",
    "Laurita no", "Paula, ven", "Clara, oye", "Nora", "Dora", "Flora", "loro", "aula",
    "Claudia", "pausa", "causa", "auto", "lauda", "nada", "Sara", "Lola", "Laila",
]

SUJ = ["Mañana", "Esta tarde", "Luego", "Ahora", "El lunes", "Después de comer", "Esta noche"]
VERB = ["tengo que", "quiero", "voy a", "me toca", "debería", "no puedo", "prefiero"]
OBJ = ["terminar el trabajo de la universidad", "ir al gimnasio", "llamar a mi madre",
       "comprar pan y leche", "revisar el correo", "ver una película", "arreglar el portátil",
       "estudiar para el examen", "salir a correr", "preparar la cena", "limpiar la habitación",
       "mirar el calendario", "pagar la factura de la luz", "escribir el informe",
       "jugar un rato", "configurar el servidor", "subir los cambios al repositorio"]
SUELTAS = [
    "¿Qué tiempo hace hoy?", "Pon un temporizador de diez minutos.", "Abre el navegador.",
    "Baja el volumen un poco.", "¿Cuántas tareas tengo pendientes?", "Pásame la sal, por favor.",
    "No sé qué hacer esta noche.", "El código no compila otra vez.", "¿Has visto mis llaves?",
    "Me encanta esta canción.", "Vamos a ver qué pasa.", "Esto va muy lento.",
    "Hay que reiniciar el ordenador.", "¿Dónde dejé el cargador?", "Buenos días a todos.",
    "La reunión es a las cinco.", "Qué hambre tengo.", "¿Me ayudas con esto?",
    "Ya está, lo he arreglado.", "Espera un momento.", "Sí, claro, perfecto.", "No, gracias.",
    "Venga, vamos.", "¿Qué hora es?", "Pon música relajante.", "Apaga las luces del salón.",
    "Mañana llueve seguro.", "El partido empieza a las nueve.", "Hoy estoy cansadísimo.",
    "Mira este error en la terminal.", "Abre Spotify.", "¿Qué hay en la tele?",
]


def frases_neg(n: int, rng: random.Random) -> list[str]:
    out = []
    for _ in range(n):
        r = rng.random()
        if r < 0.40:
            out.append(rng.choice(CASI))
        elif r < 0.55:
            out.append(rng.choice(CONFUSABLES) + rng.choice([".", "", "!", "?"]))
        elif r < 0.65:
            out.append(f"{rng.choice(SUJ)} {rng.choice(VERB)} {rng.choice(OBJ)}.")
        else:
            out.append(rng.choice(SUELTAS))
    return out


def to16k(a: np.ndarray, sr: int) -> np.ndarray:
    if a.ndim > 1:
        a = a.mean(1)
    if sr != SR:
        from math import gcd
        g = gcd(sr, SR)
        a = resample_poly(a, SR // g, sr // g)
    return a.astype("float32")


def trim(a: np.ndarray, thr: float = 0.01) -> np.ndarray:
    idx = np.where(np.abs(a) > thr * max(np.abs(a).max(), 1e-6) * 10)[0]
    if idx.size == 0:
        return a
    return a[max(0, idx[0] - 800): idx[-1] + 800]


# ---------- Piper
def piper_voices() -> list[tuple[Path, int]]:
    out = []
    for onnx in sorted(PIPER_DIR.glob("es_*.onnx")):
        n = json.loads(onnx.with_suffix(".onnx.json").read_text()).get("num_speakers", 1)
        out += [(onnx, s) for s in range(n)]
    return out


def piper(text: str, model: Path, spk: int, rng: random.Random) -> np.ndarray:
    sr = json.loads(model.with_suffix(".onnx.json").read_text())["audio"]["sample_rate"]
    with tempfile.NamedTemporaryFile(suffix=".wav") as f:
        subprocess.run(["piper-tts", "-m", str(model), "-s", str(spk), "-f", f.name,
                        "--length_scale", f"{rng.uniform(0.75, 1.35):.2f}",
                        "--noise_scale", f"{rng.uniform(0.4, 0.9):.2f}",
                        "--noise_w", f"{rng.uniform(0.5, 1.0):.2f}"],
                       input=text.encode(), capture_output=True, check=True, timeout=30)
        a, _ = sf.read(f.name, dtype="float32")
    return to16k(a, sr)


# ---------- Kokoro
KOKORO_VOICES = ["ef_dora", "em_alex", "em_santa", "if_sara", "im_nicola", "pf_dora",
                 "pm_alex", "pm_santa", "ff_siwis", "af_heart", "af_bella", "af_nicole",
                 "af_sarah", "am_adam", "am_michael", "bf_emma", "bf_isabella", "bm_george",
                 "bm_lewis", "hf_alpha", "hm_omega"]


class Kok:
    def __init__(self) -> None:
        import torch
        from huggingface_hub import hf_hub_download
        from kokoro import KPipeline
        self.torch = torch
        self.pipe = KPipeline(lang_code="e", repo_id="hexgrad/Kokoro-82M",
                              device="cuda" if torch.cuda.is_available() else "cpu")
        self.voices = {}
        for v in KOKORO_VOICES:
            try:
                p = hf_hub_download("hexgrad/Kokoro-82M", f"voices/{v}.pt")
                self.voices[v] = torch.load(p, weights_only=True)
            except Exception as e:  # noqa: BLE001
                print("sin voz", v, e)
        self.es = [v for v in self.voices if v[0] in "e"]

    def __call__(self, text: str, rng: random.Random) -> np.ndarray:
        # mezcla: una voz española como base (acento) + otra cualquiera (timbre)
        a = self.voices[rng.choice(self.es)]
        b = self.voices[rng.choice(list(self.voices))]
        w = rng.uniform(0.4, 1.0)
        voice = w * a + (1 - w) * b
        parts = [x.detach().cpu().numpy() if hasattr(x, "detach") else np.asarray(x)
                 for _, _, x in self.pipe(text, voice=voice, speed=rng.uniform(0.8, 1.3))]
        return to16k(np.concatenate(parts), 24000)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pos", type=int, default=1500)
    ap.add_argument("--neg", type=int, default=2500)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    for d in ("pos", "neg"):
        (DATA / d).mkdir(parents=True, exist_ok=True)

    pv = piper_voices()
    kok = Kok()
    print(f"piper: {len(pv)} hablantes · kokoro: {len(kok.voices)} voces", flush=True)

    jobs = [("pos", rng.choice(POS_TXT)) for _ in range(args.pos)]
    jobs += [("neg", t) for t in frases_neg(args.neg, rng)]
    rng.shuffle(jobs)
    from tqdm import tqdm
    n = {"pos": len(list((DATA / "pos").glob("sint_*.wav"))),
         "neg": len(list((DATA / "neg").glob("sint_*.wav")))}
    for kind, text in tqdm(jobs, mininterval=10):
        try:
            if rng.random() < 0.35:
                m, s = rng.choice(pv)
                a = piper(text, m, s, rng)
            else:
                a = kok(text, rng)
        except Exception as e:  # noqa: BLE001
            print("fallo", text, e, flush=True)
            continue
        a = trim(a)
        a = a / (np.abs(a).max() + 1e-6) * rng.uniform(0.3, 0.9)
        sf.write(DATA / kind / f"sint_{n[kind]:05d}.wav", a, SR)
        n[kind] += 1
    print("hecho", n)


if __name__ == "__main__":
    main()
