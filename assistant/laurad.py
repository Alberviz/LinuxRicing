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
             cancel: threading.Event | None = None) -> tuple[str, list[dict]]:
    """Devuelve (respuesta, acciones) donde acciones = [{icon, text}, ...].

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
            return content.strip(), actions
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
                reply, actions = converse(
                    text, speech.feed if speech else None, cancel)
                # El LLM ya ha terminado de generar; el audio puede seguir
                # sonando. Publicar aquí lo demás, no tras la voz.
                log(f"laura: {reply}  · acciones: {actions}")
                notify("Laura", reply)
                bus.emit(type="result", actions=actions)
            finally:
                spoken = speech.finish() if speech else ""
            if cancel.is_set():
                break
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
