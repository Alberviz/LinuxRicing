"""Daemon: ciclo de conversación, socket de control y arranque."""
from __future__ import annotations

import os
import socket
import threading

from .audio import listen, load_vad
from .config import CFG, bus, log, notify
from .escalation import (_confirm_and_run_escalation, _handle_auto_escalation,
                         _match_auto_case)
from .llm import _mode_switch, _model_now, _quality, converse
from .stt import transcribe
from .tts import Speech, speak
from .wake import WakeListener, _make_wake

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


def main() -> None:
    load_vad()
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
