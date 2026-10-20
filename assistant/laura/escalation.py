"""Escalada a Gemini (agy): Modo A (auto) y Modo B (confirmación)."""
from __future__ import annotations

import json
import os
import subprocess
import threading
import time
import urllib.request

from .audio import listen
from .config import CFG, bus, log, notify
from .llm import _messages
from .stt import transcribe
from .tts import speak

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

