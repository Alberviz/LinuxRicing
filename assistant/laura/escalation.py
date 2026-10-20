"""Escalada a Gemini/Claude. Modo A (auto, Gemini ligero, respaldo) y Modo B
(confirmación por voz y trabajo en segundo plano)."""
from __future__ import annotations

import threading

from .audio import listen
from .config import CFG, bus, log, notify
from .jobs import NOMBRES, JobManager, run_agy
from .llm import Session
from .output import AnyEvent
from .stt import transcribe
from .tts import speak


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


def _handle_auto_escalation(session: Session, text: str, case: dict, mode: str,
                            cancel: threading.Event) -> None:
    """Modo A: manda `text` tal cual a un Gemini ligero y habla la respuesta."""
    ecfg = CFG.get("escalation", {})
    log(f"Modo A ({case.get('nombre')}) -> Gemini ligero")
    bus.emit(type="state", value="thinking", mode=mode)
    prompt = ("Responde de forma breve y directa, en español, en una o dos "
              "frases pensadas para leerse en voz alta (nada de markdown, "
              "listas ni emojis):\n\n" + text)
    result = run_agy(prompt,
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
    session.add("user", text)
    session.add("assistant", reply)
    log(f"laura (gemini auto): {reply}")
    notify("Laura", reply)
    bus.emit(type="reply", value=reply)
    bus.emit(type="state", value="speaking", mode=mode)
    speak(reply, cancel)


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


def _say(text: str, mode: str, cancel: threading.Event) -> None:
    notify("Laura", text)
    bus.emit(type="reply", value=text)
    bus.emit(type="state", value="speaking", mode=mode)
    speak(text, cancel)


def voice_yes_no(job_id: str, pregunta: str, mode: str, cancel: threading.Event,
                 jobs: JobManager) -> bool | None:
    """Pregunta por voz y espera la respuesta, o que llegue antes desde la tarjeta
    (`job-confirm`). Resuelve el trabajo con el sí/no. Devuelve True/False, o None si
    no hubo respuesta (el trabajo queda pendiente en `confirm`, visible en el orbe)."""
    ev = jobs.answered_event(job_id)
    _say(pregunta, mode, cancel)
    if cancel.is_set() or (ev is not None and ev.is_set()):
        return None
    bus.emit(type="state", value="listening", mode=mode)
    grace = CFG["audio"].get("followup_seconds", 4)
    audio = listen(max_seconds=CFG["audio"]["max_seconds"], cancel=AnyEvent(cancel, ev),
                   start_grace=grace)
    if cancel.is_set() or (ev is not None and ev.is_set()):
        return None
    bus.emit(type="state", value="thinking", mode=mode)
    respuesta = transcribe(audio)
    bus.emit(type="transcript", value=respuesta or "(sin respuesta)")
    if not respuesta:
        return None
    si = _is_affirmative(respuesta)
    jobs.confirm(job_id, si)
    return si


def _confirm_and_run_escalation(session: Session, jobs: JobManager, escalation: dict,
                                mode: str, cancel: threading.Event) -> bool:
    """Devuelve True si el trabajo se lanzó (sí). Modo B: crea el trabajo en estado `confirm` (visible en el orbe, respondible desde
    la tarjeta) y pregunta por voz a quién se manda y qué. Voz o tarjeta, lo que llegue
    antes. Tras el sí, el trabajo corre en segundo plano y el ciclo sigue libre."""
    destino = escalation.get("destino", "gemini")
    nombre = NOMBRES.get(destino, destino)
    peticion = escalation.get("peticion", "")
    motivo = escalation.get("motivo", "")
    log(f"Modo B pendiente ({destino}): {peticion!r} ({motivo!r})")

    resumen = peticion.strip().rstrip(".")
    if len(resumen) > 160:
        resumen = resumen[:157].rstrip() + "…"
    pregunta = f"Esto se me escapa. ¿Se lo mando a {nombre}? Sería: {resumen}."
    jid = jobs.start(destino, peticion, motivo, pregunta=pregunta, ask_voice=False,
                     titulo=f"{nombre}: {peticion}")
    r = voice_yes_no(jid, pregunta, mode, cancel, jobs)
    if cancel.is_set():
        jobs.cancel(jid)
        return False
    if r is None:
        ev = jobs.answered_event(jid)
        if ev is not None and ev.is_set():
            return True  # contestado desde la tarjeta: sigue en el orbe
        _say("Lo dejo pendiente en el panel.", mode, cancel)
        session.add("assistant", "Dejé pendiente la confirmación en el panel.")
        return True
    msg = (f"Vale, lo he lanzado con {nombre}. Te aviso cuando termine." if r
           else "Vale, no hago nada.")
    session.add("assistant", msg)
    log(f"laura: {msg} (job {jid})")
    _say(msg, mode, cancel)
    return bool(r)
