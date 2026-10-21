#!/usr/bin/env python3
"""
Script de prueba de voces y efectos de IA (Castellano es-ES / Kokoro / Piper / Edge-TTS).
"""

import argparse
import asyncio
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PIPER_DIR = Path.home() / ".local/share/piper/voices"

# Efectos ffmpeg definidos en Laura
EFFECTS = {
    "jarvis": (
        "highpass=f=200,lowpass=f=3800,chorus=0.5:0.9:50:0.4:0.25:2,"
        "aecho=0.85:0.75:35:0.2,volume=2"
    ),
    "subnautica": (
        "asetrate=24000*0.93,aresample=24000,aecho=0.8:0.9:55:0.35,"
        "aecho=0.8:0.9:120:0.2,highpass=f=140,lowpass=f=7000,volume=2.2"
    ),
    "robot": (
        "aeval='val(0)*(0.65+0.7*sin(2*PI*45*t))':c=same,"
        "highpass=f=300,lowpass=f=3200,volume=3"
    ),
    "dry": None,
    "none": None,
}

VOICES_CATALOG = {
    "🇪🇸 Castellano Real (España es-ES) — Neural Cloud (Edge-TTS, Calidad Estudio)": [
        ("elvira", "es-ES-ElviraNeural", "Mujer (castellano España, muy natural y expresiva)"),
        ("alvaro", "es-ES-AlvaroNeural", "Hombre (castellano España, tono amigable/positivo)"),
        ("ximena", "es-ES-XimenaNeural", "Mujer (castellano España, tono juvenil/claro)"),
    ],
    "🇪🇸 Castellano Real (España es-ES) — Local Offline (Piper TTS)": [
        ("piper-dave", "es_ES-davefx-medium", "Hombre (castellano España estándar, local)"),
        ("piper-mujer", "es_ES-sharvard-medium (speaker 1)", "Mujer (castellano España, locutora 1)"),
        ("piper-hombre", "es_ES-sharvard-medium (speaker 0)", "Hombre (castellano España, locutor 0)"),
        ("piper-carl", "es_ES-carlfm-x_low", "Hombre (castellano España, ultra rápido)"),
    ],
    "🌎 Español Neutro / Latino — Local Offline (Kokoro-82M)": [
        ("dora", "ef_dora", "Mujer (voz actual de Laura, neutra con deje latino)"),
        ("alex", "em_alex", "Hombre (voz neutra latina)"),
        ("santa", "em_santa", "Santa Claus (profunda / navideña)"),
    ],
    "🇬🇧 / 🇺🇸 Inglés Popular (Kokoro-82M)": [
        ("heart", "af_heart", "Femenina US suave"),
        ("bella", "af_bella", "Femenina US expresiva"),
        ("emma", "bf_emma", "Femenina UK británica"),
        ("george", "bm_george", "Masculina UK británica"),
    ]
}


def play_audio(filepath: str):
    """Reproduce un archivo de audio usando paplay, mpv o aplay."""
    for player in ["paplay", "pw-play", "mpv", "aplay"]:
        if shutil.which(player):
            if player == "mpv":
                subprocess.run([player, "--no-video", filepath], check=False)
            else:
                subprocess.run([player, filepath], check=False)
            return
    print(f"[!] No se encontró reproductor de audio. Archivo en {filepath}")


def apply_effect_if_needed(raw_wav: str, output_wav: str, effect: str | None) -> bool:
    af = EFFECTS.get(effect) if effect else None
    if af:
        print(f"[*] Aplicando efecto '{effect}' con ffmpeg...")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", raw_wav, "-af", af, output_wav],
            check=True
        )
    else:
        shutil.copyfile(raw_wav, output_wav)
    return True


def test_edge_tts(text: str, voice: str, effect: str | None, output_wav: str) -> bool:
    try:
        import edge_tts
    except ImportError:
        print("[!] edge-tts no está instalado en el venv. Instálalo con: uv pip install edge-tts")
        return False

    print(f"[*] Sintetizando con Edge-TTS Neuronal (voz='{voice}')...")
    raw_mp3 = "/tmp/test_edge_raw.mp3"
    raw_wav = "/tmp/test_edge_raw.wav"

    async def _synth():
        communicate = edge_tts.Communicate(text, voice)
        await communicate.save(raw_mp3)

    try:
        asyncio.run(_synth())
    except Exception as e:
        print(f"[!] Error en Edge-TTS: {e}")
        return False

    # Convertir MP3 a WAV para procesar efectos uniformemente
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw_mp3, raw_wav], check=True)
    return apply_effect_if_needed(raw_wav, output_wav, effect)


def test_piper(text: str, model_name: str, speaker: int | None, effect: str | None, output_wav: str) -> bool:
    if not shutil.which("piper-tts") and not shutil.which("piper"):
        print("[!] Error: no se encontró 'piper-tts' ni 'piper' en el sistema.")
        return False

    bin_name = "piper-tts" if shutil.which("piper-tts") else "piper"
    model_file = PIPER_DIR / f"{model_name}.onnx"
    if not model_file.exists():
        print(f"[!] Error: modelo Piper no encontrado en {model_file}")
        return False

    raw_wav = "/tmp/test_piper_raw.wav"
    cmd = [bin_name, "-m", str(model_file), "-f", raw_wav]
    if speaker is not None:
        cmd.extend(["-s", str(speaker)])

    print(f"[*] Sintetizando con Piper Local ({model_name}, locutor={speaker or 0})...")
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    p.communicate(input=text.encode("utf-8"))
    if p.returncode != 0:
        print("[!] Error al ejecutar Piper TTS.")
        return False

    return apply_effect_if_needed(raw_wav, output_wav, effect)


def test_kokoro(text: str, voice: str, effect: str | None, device: str, output_wav: str) -> bool:
    try:
        import numpy as np
        import soundfile as sf
        import torch
        from kokoro import KPipeline
    except ImportError as e:
        print(f"[!] Error de importación Kokoro: {e}")
        return False

    if device == "cuda" and not torch.cuda.is_available():
        print("[*] CUDA no disponible para PyTorch, usando CPU...")
        device = "cpu"

    lang_code = "e" if voice.startswith("e") else ("b" if voice.startswith("b") else "a")
    print(f"[*] Sintetizando con Kokoro-82M (lang='{lang_code}', voice='{voice}', device='{device}')...")
    pipeline = KPipeline(lang_code=lang_code, device=device)
    generator = pipeline(text, voice=voice)
    parts = []
    for _, _, audio in generator:
        if hasattr(audio, "detach"):
            parts.append(audio.detach().cpu().numpy())
        else:
            parts.append(np.asarray(audio))

    if not parts:
        print("[!] No se generó audio con Kokoro.")
        return False

    raw_wav = "/tmp/test_kokoro_raw.wav"
    sf.write(raw_wav, np.concatenate(parts), 24000)
    return apply_effect_if_needed(raw_wav, output_wav, effect)


def main():
    parser = argparse.ArgumentParser(description="Prueba de voces de IA (Castellano / Latino / Inglés)")
    parser.add_argument("text", nargs="?", default=None, help="Texto a sintetizar")
    parser.add_argument("-e", "--effect", choices=list(EFFECTS.keys()), default=None, help="Efecto de audio ffmpeg")
    parser.add_argument("-o", "--output", default="/tmp/test_voice.wav", help="Archivo de audio resultante")
    parser.add_argument("--no-play", action="store_true", help="No reproducir el audio tras generarlo")
    parser.add_argument("--list-voices", action="store_true", help="Mostrar todas las voces disponibles")

    # 🇪🇸 Voces en Castellano (España)
    parser.add_argument("--elvira", action="store_true", help="[Castellano Neural] Voz femenina Elvira (España)")
    parser.add_argument("--alvaro", action="store_true", help="[Castellano Neural] Voz masculina Alvaro (España)")
    parser.add_argument("--ximena", action="store_true", help="[Castellano Neural] Voz femenina Ximena (España)")
    parser.add_argument("--piper-dave", action="store_true", help="[Castellano Local] Piper davefx (Hombre, España)")
    parser.add_argument("--piper-mujer", action="store_true", help="[Castellano Local] Piper sharvard (Mujer, España)")
    parser.add_argument("--piper-hombre", action="store_true", help="[Castellano Local] Piper sharvard (Hombre, España)")
    parser.add_argument("--piper-carl", action="store_true", help="[Castellano Local] Piper carlfm (Hombre, España)")

    # 🌎 Voces Kokoro (Latino / Neutro / Especiales)
    parser.add_argument("--dora", action="store_true", help="[Kokoro Local] Voz Laura (ef_dora, neutra)")
    parser.add_argument("--alex", action="store_true", help="[Kokoro Local] Voz masculina (em_alex)")
    parser.add_argument("--santa", action="store_true", help="[Kokoro Local] Voz Santa Claus (em_santa)")

    # Custom
    parser.add_argument("--voice", "-v", default=None, help="Nombre de voz personalizada")
    parser.add_argument("--engine", choices=["kokoro", "piper", "edge"], default=None, help="Motor TTS")
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cuda", help="Dispositivo para Kokoro")

    args = parser.parse_args()

    if args.list_voices:
        print("================================================================")
        print("          CATÁLOGO DE VOCES DISPONIBLES EN EL SISTEMA          ")
        print("================================================================")
        for cat, voices in VOICES_CATALOG.items():
            print(f"\n{cat}")
            print("-" * len(cat))
            for flag, name, desc in voices:
                print(f"  --{flag:<14} -> [{name:<24}] : {desc}")
        print("\nEfectos disponibles (-e): jarvis, subnautica, robot, dry")
        print("================================================================")
        return

    # Selección de motor y voz
    engine = args.engine
    voice_name = args.voice
    speaker = None

    if args.elvira:
        engine, voice_name = "edge", "es-ES-ElviraNeural"
    elif args.alvaro:
        engine, voice_name = "edge", "es-ES-AlvaroNeural"
    elif args.ximena:
        engine, voice_name = "edge", "es-ES-XimenaNeural"
    elif args.piper_dave:
        engine, voice_name = "piper", "es_ES-davefx-medium"
    elif args.piper_mujer:
        engine, voice_name, speaker = "piper", "es_ES-sharvard-medium", 1
    elif args.piper_hombre:
        engine, voice_name, speaker = "piper", "es_ES-sharvard-medium", 0
    elif args.piper_carl:
        engine, voice_name = "piper", "es_ES-carlfm-x_low"
    elif args.dora:
        engine, voice_name = "kokoro", "ef_dora"
    elif args.alex:
        engine, voice_name = "kokoro", "em_alex"
    elif args.santa:
        engine, voice_name = "kokoro", "em_santa"

    # Default si no se especificó nada: Elvira (Castellano España)
    if not engine:
        if voice_name:
            if voice_name.startswith("es-ES-") or voice_name.startswith("es-"):
                engine = "edge"
            elif voice_name.startswith("es_ES-"):
                engine = "piper"
            else:
                engine = "kokoro"
        else:
            # Si no pasa nada, probamos la castellana Elvira
            engine, voice_name = "edge", "es-ES-ElviraNeural"

    if not voice_name:
        if engine == "edge":
            voice_name = "es-ES-ElviraNeural"
        elif engine == "piper":
            voice_name = "es_ES-davefx-medium"
        else:
            voice_name = "ef_dora"

    # Texto de prueba predeterminado
    if not args.text:
        if "santa" in voice_name.lower():
            args.text = "¡Ho ho ho! ¡Feliz Navidad, Alberto! Un saludo desde el polo norte."
        elif engine == "edge":
            args.text = f"Hola Alberto, esta es una prueba con la voz neuronal en castellano de España, {voice_name.split('-')[2].replace('Neural', '')}."
        elif engine == "piper":
            args.text = "Hola Alberto, esta es una prueba de síntesis local en castellano de España con Piper."
        else:
            args.text = f"Hola Alberto, probando la voz {voice_name}."

    print(f"=== Prueba de Voz ({engine.upper()}) ===")
    print(f"[*] Texto: \"{args.text}\"")

    if engine == "edge":
        ok = test_edge_tts(args.text, voice_name, args.effect, args.output)
    elif engine == "piper":
        ok = test_piper(args.text, voice_name, speaker, args.effect, args.output)
    elif engine == "kokoro":
        ok = test_kokoro(args.text, voice_name, args.effect, args.device, args.output)
    else:
        print(f"[!] Motor desconocido: {engine}")
        return

    if ok:
        print(f"[✓] Audio generado con éxito en: {args.output}")
        if not args.no_play:
            print("[*] Reproduciendo audio...")
            play_audio(args.output)


if __name__ == "__main__":
    main()
