"""Síntesis de voz multi-motor (edge / piper / kokoro) y tubería de voz por frases."""
from __future__ import annotations

import queue
import subprocess
import threading
import time

from .audio import _play_with_amplitude
from .config import CFG, bus, log
from .engines import REGISTRY, Engine, EngineUnavailable
from .output import OUT, AnyEvent

EFFECTS = {
    "dry": None,
    "jarvis": ("highpass=f=200,lowpass=f=3800,chorus=0.5:0.9:50:0.4:0.25:2,"
               "aecho=0.85:0.75:35:0.2,volume=2"),
    "subnautica": ("asetrate=24000*0.93,aresample=24000,aecho=0.8:0.9:55:0.35,"
                   "aecho=0.8:0.9:120:0.2,highpass=f=140,lowpass=f=7000,volume=2.2"),
    "robot": ("aeval='val(0)*(0.65+0.7*sin(2*PI*45*t))':c=same,"
              "highpass=f=300,lowpass=f=3200,volume=3"),
}


# ------------------------------------------------------------ cadena de motores
# Los motores viven en laura/engines/ (un fichero por motor). La cadena es
# `[tts] engine` + `fallbacks`; si el principal es edge, kokoro entra el primero
# de los respaldos. Un motor que falla se aparca `_COOLDOWN` s para no pagar su
# timeout en cada frase.
_COOLDOWN = 120.0
_instances: dict[str, Engine] = {}
_down: dict[str, float] = {}
_lock = threading.Lock()


def chain() -> list[str]:
    t = CFG.get("tts", {})
    primary = t.get("engine", "kokoro")
    fb = list(t.get("fallbacks", ["piper"]))
    if primary == "edge" and "kokoro" not in fb:
        fb.insert(0, "kokoro")
    out = []
    for n in [primary, *fb]:
        if n not in out:
            out.append(n)
    return out


def _get(name: str) -> Engine:
    with _lock:
        if name not in _instances:
            cls = REGISTRY.get(name)
            if cls is None:
                raise EngineUnavailable(f"motor de voz desconocido: {name}")
            cfg = CFG.get("tts", {}).get(name, {})
            _instances[name] = cls(cfg if isinstance(cfg, dict) else {})
        return _instances[name]


def warmup() -> None:
    """Carga por adelantado el motor principal (el daemon lo llama al arrancar)."""
    for name in chain():
        try:
            _get(name).warmup()
            log(f"TTS listo: motor '{name}'")
            return
        except Exception as e:  # noqa: BLE001
            log(f"TTS: motor '{name}' no arranca ({e}); pruebo el siguiente")


def _synth_raw(text: str, raw: str) -> str:
    """Prueba los motores de la cadena hasta que uno escribe `raw`. Devuelve su nombre."""
    names = chain()
    now = time.monotonic()
    vivos = [n for n in names if _down.get(n, 0) <= now] or names
    ultimo: Exception | None = None
    for n in vivos:
        try:
            _get(n).synth(text, raw)
            return n
        except Exception as e:  # noqa: BLE001
            ultimo = e
            _down[n] = time.monotonic() + _COOLDOWN
            log(f"TTS: motor '{n}' falló ({str(e)[:120]}); siguiente")
    raise RuntimeError(f"ningún motor de voz funciona: {ultimo}")


def _synth_wav(text: str, tag: str) -> str:
    """Sintetiza `text` con la cadena de motores, aplica el efecto y devuelve la ruta del wav."""
    raw = f"/tmp/laura_{tag}_raw.wav"
    _synth_raw(text, raw)
    af = EFFECTS.get(CFG["tts"].get("effect", "dry"))
    if not af:
        return raw
    out = f"/tmp/laura_{tag}.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw,
                    "-af", af, out], check=True)
    return out


def speak(text: str, cancel: threading.Event | None = None) -> None:
    """Sintetiza y reproduce `text` de una vez, con el audio de salida en
    exclusiva (OUT) para no solaparse con otra voz."""
    stop = AnyEvent(cancel, OUT.interrupt_ev)
    if not text or stop.is_set():
        return
    wav = _synth_wav(text, "out")
    with OUT.hold():
        if not stop.is_set():
            _play_with_amplitude(wav, stop)


class Speech:
    """Tubería de voz por frases. Se le van dando frases (`feed`) según las
    genera el LLM; un hilo las sintetiza y otro las reproduce en orden, de modo
    que la primera frase suena mientras la segunda aún se está sintetizando.
    Emite `state=speaking` al arrancar el primer audio y `reply` acumulado
    frase a frase (subtítulos que crecen con la voz)."""

    def __init__(self, cancel: threading.Event | None, mode: str) -> None:
        self.cancel = AnyEvent(cancel, OUT.interrupt_ev)
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
        held = False  # el lock de salida se toma con el primer audio y se suelta al acabar
        try:
            while True:
                item = self._play_q.get()
                if item is None:
                    return
                if self._stopped():
                    continue
                wav, s = item
                if not held:
                    OUT.acquire()
                    held = True
                    if self._stopped():
                        continue
                if not self._spoken:
                    bus.emit(type="state", value="speaking", mode=self.mode)
                self._spoken.append(s)
                bus.emit(type="reply", value=" ".join(self._spoken))
                _play_with_amplitude(wav, self.cancel, reset=False)
        finally:
            if held:
                OUT.release()

    def finish(self) -> str:
        """Espera a que suene todo y devuelve lo que se ha hablado."""
        self._tts_q.put(None)
        self._t_tts.join()
        self._t_play.join()
        bus.emit(type="amplitude", value=0.0)
        return " ".join(self._spoken)

