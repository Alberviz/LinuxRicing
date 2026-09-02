#!/usr/bin/env python
"""Laura — daemon de asistente de voz local.

Carga los modelos una vez y se queda escuchando en un socket Unix. Cuando
`laura-toggle` le manda "activate" (atado a un atajo de Hyprland), hace UN ciclo:

    grabar (corta sola al detectar silencio) -> transcribir -> LLM con
    herramientas -> ejecutar acciones -> responder hablando

Arranque:  ~/LinuxRicing/assistant/.venv/bin/python laurad.py
"""
from __future__ import annotations

import json
import os
import queue
import socket
import subprocess
import sys
import threading
import time
import tomllib
import urllib.request
from pathlib import Path

import numpy as np
import sounddevice as sd
import soundfile as sf

import tools as tools_mod
from events import EventBus

HERE = Path(__file__).resolve().parent
CFG = tomllib.loads((HERE / "config.toml").read_text())

# Si se vuelve a poner STT/TTS en CPU (config.toml [stt] device = "cpu"), ocultar
# la GPU antes del primer `import torch` para que no abra un contexto CUDA de
# ~1 GB que no usaría: en la tarjeta de 6 GB esa VRAM le hace falta al LLM.
if CFG["stt"]["device"] == "cpu":
    os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

bus = EventBus(CFG["daemon"]["events_socket"])

SR = 16000
VAD_CHUNK = 512  # silero-vad requiere exactamente 512 muestras a 16 kHz

EFFECTS = {
    "dry": None,
    "jarvis": ("highpass=f=200,lowpass=f=3800,chorus=0.5:0.9:50:0.4:0.25:2,"
               "aecho=0.85:0.75:35:0.2,volume=2"),
    "subnautica": ("asetrate=24000*0.93,aresample=24000,aecho=0.8:0.9:55:0.35,"
                   "aecho=0.8:0.9:120:0.2,highpass=f=140,lowpass=f=7000,volume=2.2"),
    "robot": ("aeval='val(0)*(0.65+0.7*sin(2*PI*45*t))':c=same,"
              "highpass=f=300,lowpass=f=3200,volume=3"),
}


def log(*a):
    print("[laura]", *a, flush=True)


def notify(title: str, body: str = ""):
    if CFG["daemon"].get("notify"):
        subprocess.Popen(["notify-send", "-a", "Laura", "-i",
                          "audio-input-microphone-symbolic", title, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# --------------------------------------------------------------------------- STT & CUDA setup
import ctypes
import glob
for _p in glob.glob(str(HERE / ".venv/lib/python*/site-packages/nvidia/*/lib/*.so*")):
    try:
        ctypes.CDLL(_p, mode=ctypes.RTLD_GLOBAL)
    except Exception:
        pass

log("cargando Whisper…")
from faster_whisper import WhisperModel
import torch

_device = CFG["stt"]["device"]
if _device == "cuda" and not torch.cuda.is_available():
    log("CUDA no disponible, usando CPU")
    _device = "cpu"

_stt = WhisperModel(CFG["stt"]["model"],
                    device=_device,
                    compute_type="int8" if _device == "cpu"
                    else "float16")

# --------------------------------------------------------------------------- VAD
from silero_vad import load_silero_vad, VADIterator

_vad_model = load_silero_vad()

# --------------------------------------------------------------------------- TTS
log("cargando Kokoro…")
from kokoro import KPipeline

_kokoro = KPipeline(lang_code="e", device=_device)

# ----------------------------------------------------------------------- estado
_messages = [{"role": "system", "content": CFG["llm"]["system_prompt"].strip()}]


def listen(max_seconds: float | None = None,
           cancel: threading.Event | None = None,
           start_grace: float | None = None) -> np.ndarray:
    """Graba desde el micro y corta cuando detecta silencio tras hablar.

    `max_seconds` acota la grabación total. `start_grace` (follow-up) cierra
    la escucha si la voz no ha empezado en esos segundos: así la conversación
    no se queda abierta esperando. `cancel` corta al instante (segundo
    SUPER+A)."""
    if max_seconds is None:
        max_seconds = CFG["audio"]["max_seconds"]
    vad = VADIterator(_vad_model, sampling_rate=SR,
                      min_silence_duration_ms=CFG["audio"]["silence_ms"])
    q: queue.Queue = queue.Queue()
    frames: list[np.ndarray] = []
    spoke = False

    gain = float(CFG["audio"].get("amp_gain", 12.0))
    with sd.InputStream(samplerate=SR, channels=1, dtype="float32",
                        blocksize=VAD_CHUNK,
                        callback=lambda indata, *_: q.put(indata.copy())):
        t0 = time.monotonic()
        while time.monotonic() - t0 < max_seconds:
            if cancel is not None and cancel.is_set():
                break
            if start_grace is not None and not spoke and time.monotonic() - t0 > start_grace:
                break
            try:
                chunk = q.get(timeout=0.2)
            except queue.Empty:
                continue
            frames.append(chunk)
            rms = float(np.sqrt(np.mean(chunk[:, 0] ** 2)))
            bus.emit(type="amplitude", value=min(1.0, rms * gain))
            event = vad(chunk[:, 0], return_seconds=True)
            if event:
                if "start" in event:
                    spoke = True
                elif "end" in event and spoke:
                    break
    vad.reset_states()
    # Sin arranque de voz detectado = no habló nadie (evita que Whisper
    # alucine palabras del silencio y la conversación no acabe nunca).
    if not spoke or not frames:
        return np.zeros(0, "float32")
    return np.concatenate(frames)[:, 0]


# Alucinaciones típicas de Whisper sobre silencio/ruido (es).
_STT_NOISE = {"música", "musica", "gracias", "subtítulos realizados por la comunidad de amara.org",
              "suscríbete", "suscribíos", "¡gracias!", "gracias por ver el video", "amara.org"}


def transcribe(audio: np.ndarray) -> str:
    if audio.size < SR * 0.3:
        return ""
    sf.write("/tmp/laura_in.wav", audio, SR)
    segments, _ = _stt.transcribe("/tmp/laura_in.wav",
                                  language=CFG["stt"]["language"],
                                  vad_filter=True)
    text = " ".join(s.text for s in segments).strip()
    if text.lower().strip(" .,!?¡¿") in _STT_NOISE or len(text.strip(" .,!?")) < 2:
        return ""
    return text


def ollama_chat(messages: list[dict]) -> dict:
    body = json.dumps({
        "model": CFG["llm"]["model"],
        "messages": messages,
        "tools": tools_mod.TOOLS,
        "stream": False,
        "options": {"num_ctx": CFG["llm"].get("num_ctx", 4096)},
    }).encode()
    req = urllib.request.Request(CFG["llm"]["url"], data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=CFG["llm"].get("timeout", 45)) as resp:
        return json.loads(resp.read())


def _trim_history() -> None:
    """Acota el historial: aunque el contexto de Ollama sea holgado
    (`llm.num_ctx` en config.toml), si `_messages` crece sin límite las
    respuestas se vuelven lentísimas y el modelo se despista. `history_msgs`
    manda sobre el contexto: es cuántos turnos de conversación recuerda Laura."""
    keep = CFG["llm"].get("history_msgs", 12)
    if len(_messages) <= keep + 1:
        return
    tail = _messages[-keep:]
    # No arrancar el tail con respuestas de herramienta huérfanas ni con un
    # assistant que referencia tool_calls ya recortados.
    while tail and (tail[0].get("role") == "tool"
                    or (tail[0].get("role") == "assistant" and tail[0].get("tool_calls"))):
        tail.pop(0)
    _messages[:] = [_messages[0], *tail]


def converse(user_text: str) -> tuple[str, list[dict]]:
    """Devuelve (respuesta, acciones) donde acciones = [{icon, text}, ...]."""
    _trim_history()
    _messages.append({"role": "user", "content": user_text})
    actions: list[dict] = []
    for _ in range(CFG["llm"]["max_tool_rounds"]):
        msg = ollama_chat(_messages)["message"]
        _messages.append(msg)
        calls = msg.get("tool_calls") or []
        if not calls:
            return (msg.get("content") or "").strip(), actions
        for call in calls:
            fn = call["function"]
            args = fn.get("arguments") or {}
            if isinstance(args, str):
                args = json.loads(args or "{}")
            result = tools_mod.run_tool(fn["name"], args, CFG.get("apps", {}))
            log(f"tool {fn['name']}({args}) -> {result}")
            if result.get("ok"):
                actions.append(tools_mod.accion_overlay(fn["name"], result))
            _messages.append({"role": "tool", "name": fn["name"],
                              "content": json.dumps(result, ensure_ascii=False)})
    return (_messages[-1].get("content") or "Hecho.").strip(), actions


def speak(text: str, cancel: threading.Event | None = None) -> None:
    if not text or (cancel is not None and cancel.is_set()):
        return
    parts = []
    for _, _, a in _kokoro(text, voice=CFG["tts"]["voice"]):
        parts.append(a.detach().cpu().numpy() if hasattr(a, "detach")
                     else np.asarray(a))
    sf.write("/tmp/laura_raw.wav", np.concatenate(parts), 24000)
    af = EFFECTS.get(CFG["tts"]["effect"])
    out = "/tmp/laura_raw.wav"
    if af:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i",
                        "/tmp/laura_raw.wav", "-af", af, "/tmp/laura_out.wav"],
                       check=True)
        out = "/tmp/laura_out.wav"
    _play_with_amplitude(out, cancel)


def _play_with_amplitude(wav_path: str, cancel: threading.Event | None = None,
                         hz: float = 25.0) -> None:
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
    bus.emit(type="amplitude", value=0.0)


_FAREWELL = ("adios", "adiós", "hasta luego", "hasta pronto", "hasta la vista",
             "nada mas", "nada más", "eso es todo", "eso es to", "chao", "chau",
             "ciao", "ya esta", "ya está", "buenas noches", "gracias nada")


def _is_farewell(text: str) -> bool:
    t = text.lower().strip(" .,!?¡¿")
    return any(k in t for k in _FAREWELL)


def cycle(mode: str = "centro", cancel: threading.Event | None = None) -> None:
    """Un ciclo de asistente.

    - modo `barra`: un solo input -> respuesta -> se cierra.
    - modo `centro`: conversación. Tras responder, vuelve a escuchar un
      follow-up; se cierra si Alberto no dice nada en `followup_seconds`, si
      se despide («adiós», «hasta luego»…) o si vuelve a pulsar el atajo.
    """
    if cancel is None:
        cancel = threading.Event()
    log(f"escuchando… (modo {mode})")
    notify("Laura te escucha…")
    grace = CFG["audio"].get("followup_seconds", 4)
    max_turns = CFG["llm"].get("max_turns", 6)
    first = True
    turns = 0
    try:
        while not cancel.is_set():
            bus.emit(type="state", value="listening", mode=mode)
            if first:
                audio = listen(cancel=cancel)
            else:
                audio = listen(max_seconds=CFG["audio"]["max_seconds"],
                               cancel=cancel, start_grace=grace)
            if cancel.is_set():
                break
            bus.emit(type="state", value="thinking", mode=mode)
            text = transcribe(audio)
            if not text:
                if first:
                    log("(nada que transcribir)")
                    notify("Laura", "no te he oído")
                break
            if cancel.is_set():
                break
            first = False
            log(f"tú: {text}")
            notify("Tú", text)
            bus.emit(type="transcript", value=text)
            bye = _is_farewell(text)
            reply, actions = converse(text)
            log(f"laura: {reply}  · acciones: {actions}")
            notify("Laura", reply)
            bus.emit(type="reply", value=reply)
            bus.emit(type="result", actions=actions)
            bus.emit(type="state", value="speaking", mode=mode)
            speak(reply, cancel)
            turns += 1
            if mode != "centro" or bye or turns >= max_turns:
                break
    finally:
        bus.emit(type="state", value="idle", mode=mode)


def main() -> None:
    sock_path = os.path.expandvars(CFG["daemon"]["socket"])
    if os.path.exists(sock_path):
        os.unlink(sock_path)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(sock_path)
    srv.listen(4)
    bus.start()
    bus.emit(type="state", value="idle", mode="centro")
    log(f"listo. control: {sock_path}  ·  eventos: {bus.path}")

    cancel = threading.Event()
    worker: threading.Thread | None = None

    def run(mode: str) -> None:
        try:
            cycle(mode, cancel)
        except Exception as e:  # noqa: BLE001
            log(f"error en el ciclo: {e}")
            notify("Laura", f"error: {e}")
            bus.emit(type="state", value="idle", mode=mode)

    try:
        while True:
            conn, _ = srv.accept()
            with conn:
                data = conn.recv(64).decode(errors="ignore").strip()
            if not data.startswith("activate"):
                continue
            mode = data.split(":", 1)[1].strip() if ":" in data else "centro"
            if mode not in ("centro", "barra"):
                mode = "centro"
            if worker is not None and worker.is_alive():
                # Segundo atajo mientras hay un ciclo -> cerrar.
                log("atajo repetido, cierro el ciclo")
                cancel.set()
                continue
            cancel.clear()
            worker = threading.Thread(target=run, args=(mode,), daemon=True)
            worker.start()
    except KeyboardInterrupt:
        pass
    finally:
        srv.close()
        if os.path.exists(sock_path):
            os.unlink(sock_path)
        bus.close()


if __name__ == "__main__":
    main()
