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
import re
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


# ----------------------------------------------------------------- STT & CUDA setup
# faster-whisper (CTranslate2) en CUDA necesita cuDNN 9 y cuBLAS 12 de los wheels
# de pip, que no están en el linker path del sistema. Hay que precargarlas a mano.
#
# OJO: precargar TODO `nvidia/*/lib/*.so` arrastra también `libnvblas.so`, un
# interceptor de BLAS que, cargado con RTLD_GLOBAL y sin `nvblas.conf` ni BLAS de
# CPU de respaldo, tumba el proceso con SIGSEGV en la primera llamada BLAS (justo
# al empezar a escuchar). Por eso aquí se cargan SOLO cuBLAS y cuDNN, en ese
# orden (cuDNN depende de cuBLAS), y nada más.
if CFG["stt"]["device"] == "cuda":
    import ctypes
    import glob

    for _sub in ("cublas", "cudnn"):
        for _p in sorted(glob.glob(str(
                HERE / f".venv/lib/python*/site-packages/nvidia/{_sub}/lib/*.so*"))):
            if "nvblas" in _p:
                continue
            try:
                ctypes.CDLL(_p, mode=ctypes.RTLD_GLOBAL)
            except OSError:
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

# "Modo calidad": usa un modelo mayor (`llm.model_quality`, p. ej. qwen3:8b) para
# respuestas más elaboradas / código. Vacío en config = desactivado. Se alterna
# por voz («modo calidad» / «modo rápido»).
_quality = [False]
_MODE_ON = ("modo calidad", "modo potente", "modo experto", "mas potente", "más potente")
_MODE_OFF = ("modo rapido", "modo rápido", "modo normal", "modo ligero")


def _mode_switch(text: str) -> bool | None:
    """True = pasar a modo calidad, False = volver al rápido, None = no aplica."""
    if not CFG["llm"].get("model_quality"):
        return None
    t = text.lower()
    if any(k in t for k in _MODE_ON):
        return True
    if any(k in t for k in _MODE_OFF):
        return False
    return None


def _model_now() -> str:
    if _quality[0] and CFG["llm"].get("model_quality"):
        return CFG["llm"]["model_quality"]
    return CFG["llm"]["model"]


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


def _ollama_body(stream: bool) -> bytes:
    return json.dumps({
        "model": _model_now(),
        "messages": _messages,
        "tools": tools_mod.TOOLS,
        "stream": stream,
        "options": {"num_ctx": CFG["llm"].get("num_ctx", 4096)},
    }).encode()


def ollama_chat(messages: list[dict]) -> dict:
    req = urllib.request.Request(CFG["llm"]["url"], data=_ollama_body(False),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=CFG["llm"].get("timeout", 45)) as resp:
        return json.loads(resp.read())


# ---------------------------------------------------------- escalada a Gemini
# Todo lo que Laura no sabe/puede resolver ella misma se lo pide a Gemini
# (Antigravity, CLI `agy`) y devuelve la respuesta como si fuera suya. Dos
# modos, ver `[escalation]` en config.toml:
#   Modo A (auto)     -> _match_auto_case() + _handle_auto_escalation()
#   Modo B (confirma) -> tool `escalar_a_gemini` (tools.py) + converse()
#                        devuelve una `escalada` pendiente que gestiona
#                        _confirm_and_run_escalation().

def _run_agy(prompt: str, model: str, effort: str, timeout: float,
             add_dir: str | None = None,
             cancel: threading.Event | None = None) -> dict:
    """Lanza `agy -p <prompt> --model ... --effort ...` y devuelve
    {"ok": True, "texto": ...} o {"ok": False, "error": ...}. No lanza
    excepciones: cualquier fallo (binario ausente, timeout, cancelado, exit
    code != 0) se traduce a un resultado con ok=False para que quien llama
    pueda decírselo a Alberto en voz."""
    ecfg = CFG.get("escalation", {})
    agy_bin = os.path.expanduser(ecfg.get("agy_bin", "agy"))
    cmd = [agy_bin, "-p", prompt, "--model", model, "--effort", effort,
           "--dangerously-skip-permissions"]
    if add_dir:
        cmd += ["--add-dir", os.path.expanduser(add_dir)]
    log(f"agy: {model}/{effort} -> {prompt[:80]!r}…")
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
    except FileNotFoundError:
        return {"ok": False, "error": f"no encuentro el binario '{agy_bin}' (¿está en el PATH?)"}
    t0 = time.monotonic()
    while proc.poll() is None:
        if cancel is not None and cancel.is_set():
            proc.terminate()
            return {"ok": False, "error": "cancelado"}
        if time.monotonic() - t0 > timeout:
            proc.terminate()
            return {"ok": False, "error": f"Gemini no respondió en {timeout:.0f} s"}
        time.sleep(0.2)
    out, err = proc.communicate()
    if proc.returncode != 0:
        return {"ok": False, "error": (err or out or "agy falló").strip()[:400]}
    out = out.strip()
    if not out:
        return {"ok": False, "error": "Gemini no devolvió nada"}
    return {"ok": True, "texto": out}


def _match_auto_case(text: str) -> dict | None:
    """Modo A: ¿el texto encaja con algún caso rutinario pre-programado en
    `[escalation] auto_cases` de config.toml? Si sí, se manda a Gemini sin
    pasar por el LLM local ni pedir confirmación."""
    ecfg = CFG.get("escalation", {})
    if not ecfg.get("enabled", True):
        return None
    t = text.lower()
    for case in ecfg.get("auto_cases", []):
        for kw in case.get("keywords", []):
            if kw.lower() in t:
                return case
    return None


def _handle_auto_escalation(text: str, case: dict, mode: str,
                            cancel: threading.Event) -> None:
    """Modo A: manda `text` tal cual a un Gemini ligero y habla la respuesta."""
    ecfg = CFG.get("escalation", {})
    log(f"Modo A ({case.get('nombre')}) -> Gemini ligero")
    bus.emit(type="state", value="thinking", mode=mode)
    prompt = ("Responde de forma breve y directa, en español, en una o dos "
              "frases pensadas para leerse en voz alta (nada de markdown, "
              "listas ni emojis):\n\n" + text)
    result = _run_agy(prompt,
                      model=ecfg.get("model_auto", "gemini-3.8-flash-low"),
                      effort=ecfg.get("effort_auto", "low"),
                      timeout=ecfg.get("timeout_auto", 25),
                      cancel=cancel)
    if cancel.is_set():
        return
    if result.get("ok"):
        reply = result["texto"].strip()
    else:
        reply = f"No he podido consultarlo con Gemini: {result.get('error', 'error desconocido')}"
    _messages.append({"role": "user", "content": text})
    _messages.append({"role": "assistant", "content": reply})
    log(f"laura (gemini auto): {reply}")
    notify("Laura", reply)
    bus.emit(type="reply", value=reply)
    bus.emit(type="state", value="speaking", mode=mode)
    speak(reply, cancel)


_GEMINI_BRIEF = """Eres un agente de código (Gemini, vía Antigravity) invocado por Laura, el
asistente de voz local de Alberto, para una tarea que Laura no puede resolver
por sí misma.

Contexto del repositorio:
- Repo: ~/LinuxRicing — dotfiles y "rice" de escritorio Linux (Hyprland +
  Quickshell/Caelestia, tema matugen, control RGB, este mismo asistente de
  voz en assistant/).
- Lee CLAUDE.md (y GEMINI.md) en la raíz del repo: ahí están las convenciones
  del proyecto (flujo de ramas, qué carpetas toca cada agente, backlog vivo
  en vault/, obligación de reiniciar el shell de Quickshell tras tocar UI).
- Si el cambio es sustancial, créate una rama dedicada para el trabajo (no
  hace falta pedir permiso); si es un arreglo mínimo, ir directo a la rama
  activa está bien.
- No reinicies tú el shell de Quickshell ni hagas instalaciones de sistema:
  eso lo hace Alberto a mano.

Petición original de Alberto (transcrita de su voz, tal cual):
"{peticion}"

Por qué Laura no puede resolver esto ella misma:
{motivo}

Instrucciones:
1. Interpreta la petición y haz el cambio necesario en el repo de verdad (no
   te limites a proponerlo).
2. Sé conciso y ve al grano.
3. Termina con un párrafo corto (2-3 frases) resumiendo qué has hecho y qué
   archivos has tocado — Laura se lo va a leer a Alberto en voz alta, así que
   nada de markdown, listas ni bloques de código en ese resumen final.
"""


def _build_gemini_prompt(peticion: str, motivo: str) -> str:
    return _GEMINI_BRIEF.format(
        peticion=peticion,
        motivo=motivo or "Laura ha juzgado que esto se sale de lo que sabe o "
                         "puede hacer ella misma.")


_YES = ("si", "sí", "vale", "adelante", "hazlo", "dale", "venga", "claro", "correcto")
_NO = ("no", "nanay", "para nada", "olvidalo", "olvídalo", "mejor no", "nada")


def _is_affirmative(text: str) -> bool:
    t = text.lower().strip(" .,!?¡¿")
    words = t.split()
    if not words:
        return False
    if words[0] in _NO:
        return False
    return any(w in words for w in _YES)


def _summarize_for_voice(texto: str) -> str:
    """Resume la respuesta completa de Gemini en 1-2 frases orales usando el
    LLM local, para que Laura la devuelva "como si fuera suya". Si el resumen
    falla (Ollama caído, etc.), cae a un recorte crudo del texto."""
    try:
        msgs = [
            {"role": "system", "content": CFG["llm"]["system_prompt"].strip()},
            {"role": "user", "content": (
                "Le pedí ayuda a Gemini para algo que yo no podía resolver "
                "sola y esto es lo que ha hecho, con todo detalle:\n\n"
                + texto[:6000] +
                "\n\nResúmelo para Alberto en una o dos frases orales, en "
                "español, sin markdown ni listas, como si tú misma lo "
                "hubieras hecho.")},
        ]
        req = urllib.request.Request(
            CFG["llm"]["url"],
            data=json.dumps({"model": CFG["llm"]["model"], "messages": msgs,
                             "stream": False,
                             "options": {"num_ctx": CFG["llm"].get("num_ctx", 4096)}}).encode(),
            headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=CFG["llm"].get("timeout", 45)) as resp:
            msg = json.loads(resp.read())["message"]
        resumen = (msg.get("content") or "").strip()
        if resumen:
            return resumen
    except Exception as e:  # noqa: BLE001
        log(f"resumen de Gemini falló: {e}")
    primera = next((ln.strip() for ln in texto.strip().splitlines() if ln.strip()), "hecho.")
    return f"Gemini ha terminado: {primera[:200]}"


def _confirm_and_run_escalation(escalation: dict, mode: str,
                                cancel: threading.Event) -> None:
    """Modo B: pregunta a Alberto si quiere escalar, y si dice que sí, lanza
    `agy` con un prompt bien formado y le lee el resultado."""
    peticion = escalation.get("peticion", "")
    motivo = escalation.get("motivo", "")
    log(f"Modo B pendiente: {peticion!r} ({motivo!r})")

    pregunta = "Esto se me escapa. ¿Quieres que se lo mande a Gemini para que lo resuelva?"
    notify("Laura", pregunta)
    bus.emit(type="reply", value=pregunta)
    bus.emit(type="state", value="speaking", mode=mode)
    speak(pregunta, cancel)
    if cancel.is_set():
        return

    bus.emit(type="state", value="listening", mode=mode)
    grace = CFG["audio"].get("followup_seconds", 4)
    audio = listen(max_seconds=CFG["audio"]["max_seconds"], cancel=cancel,
                   start_grace=grace)
    if cancel.is_set():
        return
    bus.emit(type="state", value="thinking", mode=mode)
    respuesta = transcribe(audio)
    bus.emit(type="transcript", value=respuesta or "(sin respuesta)")

    if not respuesta or not _is_affirmative(respuesta):
        r = "Vale, no hago nada."
        log(f"laura: {r}")
        notify("Laura", r)
        bus.emit(type="reply", value=r)
        bus.emit(type="state", value="speaking", mode=mode)
        speak(r, cancel)
        _messages.append({"role": "assistant", "content": r})
        return

    r = "Vale, se lo mando a Gemini. Dame un momento."
    notify("Laura", r)
    bus.emit(type="reply", value=r)
    bus.emit(type="state", value="speaking", mode=mode)
    speak(r, cancel)
    if cancel.is_set():
        return

    ecfg = CFG.get("escalation", {})
    prompt = _build_gemini_prompt(peticion, motivo)
    bus.emit(type="state", value="thinking", mode=mode)
    result = _run_agy(prompt,
                      model=ecfg.get("model_confirm", "gemini-3.1-pro-high"),
                      effort=ecfg.get("effort_confirm", "medium"),
                      timeout=ecfg.get("timeout_confirm", 180),
                      add_dir=ecfg.get("add_dir") or None,
                      cancel=cancel)
    if cancel.is_set():
        return

    if not result.get("ok"):
        final = f"No he podido completar el encargo con Gemini: {result.get('error', 'error desconocido')}"
    else:
        final = _summarize_for_voice(result["texto"])
    _messages.append({"role": "assistant", "content": final})
    log(f"laura (gemini): {final}")
    notify("Laura", final)
    bus.emit(type="reply", value=final)
    bus.emit(type="state", value="speaking", mode=mode)
    speak(final, cancel)


# Fin de frase: puntuación terminal seguida de un espacio (para no cortar en el
# punto de "3.5"), o un salto de línea. Trocea la respuesta según se genera para
# mandar cada frase ya a la voz sin esperar al resto.
_SENT_END = re.compile(r"[.!?…]+[\"'’”)\]]*(?=\s)|\n")


def _drain_sentences(buf: str) -> tuple[list[str], str]:
    """Extrae de `buf` las frases ya completas; devuelve (frases, resto)."""
    out: list[str] = []
    while (m := _SENT_END.search(buf)):
        cut = m.end()
        frag = buf[:cut].strip()
        if frag:
            out.append(frag)
        buf = buf[cut:].lstrip()
    return out, buf


def _ollama_stream(cancel: threading.Event | None):
    """Itera la respuesta de Ollama token a token (líneas JSON)."""
    req = urllib.request.Request(CFG["llm"]["url"], data=_ollama_body(True),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=CFG["llm"].get("timeout", 45)) as resp:
        for raw in resp:
            if cancel is not None and cancel.is_set():
                return
            raw = raw.strip()
            if raw:
                yield json.loads(raw)


def _stream_round(on_sentence, cancel: threading.Event | None) -> tuple[str, list]:
    """Una ronda del LLM en streaming. Devuelve (texto completo, tool_calls).
    Mientras no aparezcan tool_calls, cada frase terminada se manda a `on_sentence`
    (para que la voz empiece ya). Si es una ronda de herramientas, no habla."""
    parts: list[str] = []
    calls: list = []
    buf = ""
    for chunk in _ollama_stream(cancel):
        m = chunk.get("message") or {}
        if m.get("tool_calls"):
            calls += m["tool_calls"]
        piece = m.get("content") or ""
        if piece:
            parts.append(piece)
            if on_sentence is not None and not calls:
                buf += piece
                sents, buf = _drain_sentences(buf)
                for s in sents:
                    on_sentence(s)
        if chunk.get("done"):
            break
    if on_sentence is not None and not calls and buf.strip():
        on_sentence(buf.strip())
    return "".join(parts), calls


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


def converse(user_text: str, on_sentence=None,
             cancel: threading.Event | None = None
             ) -> tuple[str, list[dict], dict | None]:
    """Devuelve (respuesta, acciones, escalada) donde acciones = [{icon, text},
    ...] y `escalada` es None salvo que el LLM haya llamado a la herramienta
    `escalar_a_gemini` (Modo B): entonces es {"peticion":..., "motivo":...} y
    `cycle()` se encarga de confirmar con Alberto antes de lanzar nada — no se
    sigue el bucle de tools con normalidad en esa ronda.

    Si `on_sentence` no es None, la respuesta final se genera en streaming y
    cada frase terminada se le pasa según se produce (voz por frases)."""
    _trim_history()
    _messages.append({"role": "user", "content": user_text})
    actions: list[dict] = []
    for _ in range(CFG["llm"]["max_tool_rounds"]):
        if on_sentence is not None:
            content, calls = _stream_round(on_sentence, cancel)
            _messages.append({"role": "assistant", "content": content,
                              **({"tool_calls": calls} if calls else {})})
        else:
            msg = ollama_chat(_messages)["message"]
            _messages.append(msg)
            content, calls = msg.get("content") or "", msg.get("tool_calls") or []
        if not calls:
            return content.strip(), actions, None
        for call in calls:
            fn = call["function"]
            args = fn.get("arguments") or {}
            if isinstance(args, str):
                args = json.loads(args or "{}")
            result = tools_mod.run_tool(fn["name"], args, CFG.get("apps", {}))
            log(f"tool {fn['name']}({args}) -> {result}")
            _messages.append({"role": "tool", "name": fn["name"],
                              "content": json.dumps(result, ensure_ascii=False)})
            if fn["name"] == "escalar_a_gemini":
                return "", actions, {
                    "peticion": args.get("peticion") or user_text,
                    "motivo": args.get("motivo", ""),
                }
            if result.get("ok"):
                actions.append(tools_mod.accion_overlay(fn["name"], result))
    return (_messages[-1].get("content") or "Hecho.").strip(), actions, None


def _synth_wav(text: str, tag: str) -> str:
    """Sintetiza `text` con Kokoro, aplica el efecto y devuelve la ruta del wav."""
    parts = []
    for _, _, a in _kokoro(text, voice=CFG["tts"]["voice"]):
        parts.append(a.detach().cpu().numpy() if hasattr(a, "detach")
                     else np.asarray(a))
    raw = f"/tmp/laura_{tag}_raw.wav"
    sf.write(raw, np.concatenate(parts), 24000)
    af = EFFECTS.get(CFG["tts"]["effect"])
    if not af:
        return raw
    out = f"/tmp/laura_{tag}.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw,
                    "-af", af, out], check=True)
    return out


def speak(text: str, cancel: threading.Event | None = None) -> None:
    """Sintetiza y reproduce `text` de una vez (camino sin streaming)."""
    if not text or (cancel is not None and cancel.is_set()):
        return
    _play_with_amplitude(_synth_wav(text, "out"), cancel)


class Speech:
    """Tubería de voz por frases. Se le van dando frases (`feed`) según las
    genera el LLM; un hilo las sintetiza y otro las reproduce en orden, de modo
    que la primera frase suena mientras la segunda aún se está sintetizando.
    Emite `state=speaking` al arrancar el primer audio y `reply` acumulado
    frase a frase (subtítulos que crecen con la voz)."""

    def __init__(self, cancel: threading.Event | None, mode: str) -> None:
        self.cancel = cancel
        self.mode = mode
        self._tts_q: queue.Queue = queue.Queue()
        self._play_q: queue.Queue = queue.Queue()
        self._spoken: list[str] = []
        self._n = 0
        self._t_tts = threading.Thread(target=self._tts_loop, daemon=True)
        self._t_play = threading.Thread(target=self._play_loop, daemon=True)
        self._t_tts.start()
        self._t_play.start()

    def _stopped(self) -> bool:
        return self.cancel is not None and self.cancel.is_set()

    def feed(self, sentence: str) -> None:
        s = sentence.strip()
        if s and not self._stopped():
            self._tts_q.put(s)

    def _tts_loop(self) -> None:
        while True:
            s = self._tts_q.get()
            if s is None:
                self._play_q.put(None)
                return
            if self._stopped():
                continue
            self._n += 1
            try:
                wav = _synth_wav(s, f"s{self._n}")
            except Exception as e:  # noqa: BLE001
                log(f"error sintetizando «{s[:40]}…»: {e}")
                continue
            self._play_q.put((wav, s))

    def _play_loop(self) -> None:
        while True:
            item = self._play_q.get()
            if item is None:
                return
            if self._stopped():
                continue
            wav, s = item
            if not self._spoken:
                bus.emit(type="state", value="speaking", mode=self.mode)
            self._spoken.append(s)
            bus.emit(type="reply", value=" ".join(self._spoken))
            _play_with_amplitude(wav, self.cancel, reset=False)

    def finish(self) -> str:
        """Espera a que suene todo y devuelve lo que se ha hablado."""
        self._tts_q.put(None)
        self._t_tts.join()
        self._t_play.join()
        bus.emit(type="amplitude", value=0.0)
        return " ".join(self._spoken)


def _play_with_amplitude(wav_path: str, cancel: threading.Event | None = None,
                         hz: float = 25.0, reset: bool = True) -> None:
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
    if reset:
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

            # Modo A: casos rutinarios pre-programados (config.toml
            # [escalation].auto_cases) van directos a un Gemini ligero, sin
            # pasar por el LLM local ni pedir confirmación.
            auto_case = _match_auto_case(text)
            if auto_case is not None:
                _handle_auto_escalation(text, auto_case, mode, cancel)
                turns += 1
                if mode != "centro" or bye or turns >= max_turns:
                    break
                continue

            sw = _mode_switch(text)
            if sw is not None:
                _quality[0] = sw
                r = ("Modo calidad activado." if sw
                     else "Vuelvo al modo rápido.")
                log(f"laura: {r}  (modelo -> {_model_now()})")
                notify("Laura", r)
                bus.emit(type="reply", value=r)
                bus.emit(type="state", value="speaking", mode=mode)
                speak(r, cancel)
                turns += 1
                if mode != "centro" or turns >= max_turns:
                    break
                continue

            speech = Speech(cancel, mode) if CFG["llm"].get("stream", True) else None
            try:
                reply, actions, escalation = converse(
                    text, speech.feed if speech else None, cancel)
                # El LLM ya ha terminado de generar; el audio puede seguir
                # sonando. Publicar aquí lo demás, no tras la voz.
                if escalation is None:
                    log(f"laura: {reply}  · acciones: {actions}")
                    notify("Laura", reply)
                    bus.emit(type="result", actions=actions)
                else:
                    log(f"laura: pide escalar a Gemini (Modo B) -> {escalation}")
            finally:
                spoken = speech.finish() if speech else ""
            if cancel.is_set():
                break

            # Modo B: el LLM local ha pedido escalar. Confirmar con Alberto
            # antes de lanzar nada (lo gestiona esta función aparte, incluye
            # su propio turno de escucha para el sí/no).
            if escalation is not None:
                _confirm_and_run_escalation(escalation, mode, cancel)
                turns += 1
                if mode != "centro" or turns >= max_turns:
                    break
                continue

            # Sin streaming, o si el streaming no llegó a decir nada, se
            # reproduce la respuesta entera de una vez.
            if reply and not spoken.strip():
                bus.emit(type="reply", value=reply)
                bus.emit(type="state", value="speaking", mode=mode)
                speak(reply, cancel)
            turns += 1
            if mode != "centro" or bye or turns >= max_turns:
                break
    finally:
        bus.emit(type="state", value="idle", mode=mode)


class WakeListener:
    """Escucha el micro en segundo plano con un modelo diminuto (openWakeWord)
    y dispara `on_wake` al oír la palabra clave. NO transcribe nada — el
    pipeline pesado (Whisper + LLM + Kokoro) solo arranca al detectar la
    palabra. Se pausa mientras hay un ciclo activo (no competir por el micro
    ni auto-dispararse con la voz de Laura)."""

    FRAME = 1280  # 80 ms a 16 kHz — tamaño que espera openWakeWord

    def __init__(self, model_path: str, threshold: float, cooldown: float,
                 on_wake) -> None:
        from openwakeword.model import Model
        kw = {} if model_path.endswith(".onnx") else {"inference_framework": "tflite"}
        self._oww = Model(wakeword_model_paths=[model_path], **kw)
        self._key = next(iter(self._oww.models))
        self._threshold = threshold
        self._cooldown = cooldown
        self._on_wake = on_wake
        self._paused = threading.Event()
        self._stop = threading.Event()
        self._idle = threading.Event()  # el micro está libre (stream cerrado)
        self._idle.set()
        self._t = threading.Thread(target=self._loop, daemon=True)

    def start(self) -> None:
        self._t.start()

    def pause(self) -> None:
        """Suelta el micro y no vuelve hasta resume(). Bloquea hasta que el
        stream de captura esté realmente cerrado (el ciclo lo necesita)."""
        self._paused.set()
        self._idle.wait(timeout=1.0)

    def resume(self) -> None:
        self._oww.reset()
        self._paused.clear()

    def _loop(self) -> None:
        last = 0.0
        while not self._stop.is_set():
            if self._paused.is_set():
                time.sleep(0.1)
                continue
            try:
                self._idle.clear()
                with sd.InputStream(samplerate=SR, channels=1, dtype="int16",
                                    blocksize=self.FRAME) as stream:
                    while not self._stop.is_set() and not self._paused.is_set():
                        data, _ = stream.read(self.FRAME)
                        score = self._oww.predict(data[:, 0]).get(self._key, 0.0)
                        now = time.monotonic()
                        if score >= self._threshold and now - last > self._cooldown:
                            last = now
                            log(f"wake «{self._key}» ({score:.2f})")
                            self._on_wake()
            except Exception as e:  # noqa: BLE001
                log(f"wake listener: {e}")
                time.sleep(1)
            finally:
                self._idle.set()


def _make_wake(on_wake) -> WakeListener | None:
    wcfg = CFG.get("wake", {})
    if not wcfg.get("enabled") or not wcfg.get("model"):
        return None
    mp = os.path.expanduser(wcfg["model"])
    if not os.path.isabs(mp):
        mp = str(HERE / mp)
    if not os.path.exists(mp):
        log(f"wake word: no encuentro el modelo {mp} — solo atajo")
        return None
    try:
        w = WakeListener(mp, float(wcfg.get("threshold", 0.5)),
                         float(wcfg.get("cooldown", 3.0)), on_wake)
        log(f"wake word activo: {mp}")
        return w
    except Exception as e:  # noqa: BLE001
        log(f"wake word desactivado ({e}) — solo atajo")
        return None


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
    wake: WakeListener | None = None

    def run(mode: str) -> None:
        if wake is not None:
            wake.pause()
        try:
            cycle(mode, cancel)
        except Exception as e:  # noqa: BLE001
            log(f"error en el ciclo: {e}")
            notify("Laura", f"error: {e}")
            bus.emit(type="state", value="idle", mode=mode)
        finally:
            if wake is not None:
                wake.resume()

    def fire(mode: str) -> None:
        """Arranca un ciclo (o lo cierra si ya hay uno). Lo usan el atajo y la
        palabra de activación."""
        nonlocal worker
        if worker is not None and worker.is_alive():
            log("disparo repetido, cierro el ciclo")
            cancel.set()
            return
        cancel.clear()
        worker = threading.Thread(target=run, args=(mode,), daemon=True)
        worker.start()

    wake = _make_wake(on_wake=lambda: fire("centro"))
    if wake is not None:
        wake.start()

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
            fire(mode)
    except KeyboardInterrupt:
        pass
    finally:
        srv.close()
        if os.path.exists(sock_path):
            os.unlink(sock_path)
        bus.close()


if __name__ == "__main__":
    main()
