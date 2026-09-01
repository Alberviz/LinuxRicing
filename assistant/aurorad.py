#!/usr/bin/env python
"""Aurora — daemon de asistente de voz local.

Carga los modelos una vez y se queda escuchando en un socket Unix. Cuando
`aurora-toggle` le manda "activate" (atado a un atajo de Hyprland), hace UN ciclo:

    grabar (corta sola al detectar silencio) -> transcribir -> LLM con
    herramientas -> ejecutar acciones -> responder hablando

Arranque:  ~/LinuxRicing/assistant/.venv/bin/python aurorad.py
"""
from __future__ import annotations

import json
import os
import queue
import socket
import subprocess
import sys
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
    print("[aurora]", *a, flush=True)


def notify(title: str, body: str = ""):
    if CFG["daemon"].get("notify"):
        subprocess.Popen(["notify-send", "-a", "Aurora", "-i",
                          "audio-input-microphone-symbolic", title, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# --------------------------------------------------------------------------- STT
log("cargando Whisper…")
from faster_whisper import WhisperModel

_stt = WhisperModel(CFG["stt"]["model"],
                    device=CFG["stt"]["device"],
                    compute_type="int8" if CFG["stt"]["device"] == "cpu"
                    else "int8_float16")

# --------------------------------------------------------------------------- VAD
from silero_vad import load_silero_vad, VADIterator

_vad_model = load_silero_vad()

# --------------------------------------------------------------------------- TTS
log("cargando Kokoro…")
from kokoro import KPipeline

_kokoro = KPipeline(lang_code="e")

# ----------------------------------------------------------------------- estado
_messages = [{"role": "system", "content": CFG["llm"]["system_prompt"].strip()}]


def listen() -> np.ndarray:
    """Graba desde el micro y corta cuando detecta silencio tras hablar."""
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
        while time.monotonic() - t0 < CFG["audio"]["max_seconds"]:
            chunk = q.get()
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
    return np.concatenate(frames)[:, 0] if frames else np.zeros(0, "float32")


def transcribe(audio: np.ndarray) -> str:
    if audio.size < SR * 0.3:
        return ""
    sf.write("/tmp/aurora_in.wav", audio, SR)
    segments, _ = _stt.transcribe("/tmp/aurora_in.wav",
                                  language=CFG["stt"]["language"])
    return " ".join(s.text for s in segments).strip()


def ollama_chat(messages: list[dict]) -> dict:
    body = json.dumps({
        "model": CFG["llm"]["model"],
        "messages": messages,
        "tools": tools_mod.TOOLS,
        "stream": False,
    }).encode()
    req = urllib.request.Request(CFG["llm"]["url"], data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=CFG["llm"].get("timeout", 45)) as resp:
        return json.loads(resp.read())


def _trim_history() -> None:
    """Acota el historial: Ollama corre con contexto pequeño (-c 4096) y si
    `_messages` crece sin límite las respuestas se vuelven lentísimas o cuelgan."""
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


def speak(text: str) -> None:
    if not text:
        return
    parts = []
    for _, _, a in _kokoro(text, voice=CFG["tts"]["voice"]):
        parts.append(a.detach().cpu().numpy() if hasattr(a, "detach")
                     else np.asarray(a))
    sf.write("/tmp/aurora_raw.wav", np.concatenate(parts), 24000)
    af = EFFECTS.get(CFG["tts"]["effect"])
    out = "/tmp/aurora_raw.wav"
    if af:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i",
                        "/tmp/aurora_raw.wav", "-af", af, "/tmp/aurora_out.wav"],
                       check=True)
        out = "/tmp/aurora_out.wav"
    _play_with_amplitude(out)


def _play_with_amplitude(wav_path: str, hz: float = 25.0) -> None:
    """Reproduce el wav y emite su envolvente RMS por ventanas, en sincronía."""
    data, sr = sf.read(wav_path, dtype="float32")
    if data.ndim > 1:
        data = data.mean(axis=1)
    win = max(1, int(sr / hz))
    env = np.array([np.sqrt(np.mean(data[i:i + win] ** 2))
                    for i in range(0, len(data), win)])
    peak = float(env.max()) or 1.0
    env = np.minimum(1.0, env / peak)
    step = win / sr
    proc = subprocess.Popen(["paplay", wav_path])
    t0 = time.monotonic()
    for i, v in enumerate(env):
        bus.emit(type="amplitude", value=float(v))
        target = t0 + (i + 1) * step
        time.sleep(max(0.0, target - time.monotonic()))
    proc.wait()
    bus.emit(type="amplitude", value=0.0)


def cycle(mode: str = "centro") -> None:
    log(f"escuchando… (modo {mode})")
    notify("Aurora te escucha…")
    bus.emit(type="state", value="listening", mode=mode)
    audio = listen()
    bus.emit(type="state", value="thinking", mode=mode)
    text = transcribe(audio)
    if not text:
        log("(nada que transcribir)")
        notify("Aurora", "no te he oído")
        bus.emit(type="state", value="idle", mode=mode)
        return
    log(f"tú: {text}")
    notify("Tú", text)
    bus.emit(type="transcript", value=text)
    reply, actions = converse(text)
    log(f"aurora: {reply}  · acciones: {actions}")
    notify("Aurora", reply)
    bus.emit(type="result", actions=actions)
    bus.emit(type="state", value="speaking", mode=mode)
    speak(reply)
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
    busy = False
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
            if busy:
                log("ocupado, ignoro")
                continue
            busy = True
            try:
                cycle(mode)
            except Exception as e:  # noqa: BLE001
                log(f"error en el ciclo: {e}")
                notify("Aurora", f"error: {e}")
                bus.emit(type="state", value="idle", mode=mode)
            finally:
                busy = False
    except KeyboardInterrupt:
        pass
    finally:
        srv.close()
        if os.path.exists(sock_path):
            os.unlink(sock_path)
        bus.close()


if __name__ == "__main__":
    main()
