"""Daemon: ciclo de conversación, socket de control y arranque."""
from __future__ import annotations

import json
import os
import queue
import re
import socket
import threading
import time

from .audio import listen, load_vad
from .bargein import BargeIn
from .config import CFG, bus, log, notify
from . import avisos
from .escalation import (_confirm_and_run_escalation, _handle_auto_escalation,
                         _match_auto_case, voice_yes_no)
from . import jobs as jobs_mod
from .jobs import JobManager, reap_orphans
from .llm import Session, _mode_switch, converse
from .stt import transcribe
from .output import OUT, AnyEvent
from .tts import Speech, speak, warmup as tts_warmup
from .wake import WakeListener, _make_wake

_FAREWELL = ("adios", "adiós", "hasta luego", "hasta pronto", "hasta la vista",
             "nada mas", "nada más", "eso es todo", "eso es to", "chao", "chau",
             "ciao", "ya esta", "ya está", "buenas noches", "gracias nada")


def _is_farewell(text: str) -> bool:
    t = text.lower().strip(" .,!?¡¿")
    return any(k in t for k in _FAREWELL)


_STOP_DEFAULT = ["para", "calla", "cállate", "silencio", "basta"]


def _norm_stop(t: str) -> str:
    """Minúsculas, sin puntuación y sin el nombre «Laura»: «Para, Laura» -> «para»."""
    words = re.findall(r"[\wáéíóúüñ]+", t.lower())
    return " ".join(w for w in words if w != "laura")


def _is_stop(text: str) -> bool:
    """¿Es una frase de corte exacta («para», «calla», «para, Laura»)? Configurable en
    `[audio] stop_phrases`. Es coincidencia EXACTA: «para qué sirve…» no corta."""
    frases = CFG["audio"].get("stop_phrases", _STOP_DEFAULT)
    return _norm_stop(text) in {_norm_stop(f) for f in frases}


def cycle(session: Session, jobs: JobManager, mode: str = "centro",
          cancel: threading.Event | None = None, first_text: str | None = None) -> None:
    """Un ciclo de asistente.

    `first_text` (depuración, comando `ask`): primera frase ya dada, sin micro.

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
    espera_larga = False  # la última respuesta acabó en pregunta: dar más margen para contestar
    turn_cancel = AnyEvent(cancel, OUT.interrupt_ev)  # corta voz y LLM (atajo o barge-in)
    # Si se arranca el ciclo sobre una voz (aviso) que se está cortando, esperar a que calle.
    t_wait = time.monotonic()
    while OUT.speaking() and time.monotonic() - t_wait < 2:
        time.sleep(0.05)
    try:
        while not cancel.is_set():
            pre = 0.9 if OUT.barged else 0.0  # tras un barge-in, recuperar sus primeras palabras
            OUT.barged = False
            OUT.clear_interrupt()
            if first_text is not None:
                text, first_text = first_text, None
            else:
                bus.emit(type="state", value="listening", mode=mode)
                if first and not pre:
                    audio = listen(cancel=cancel)
                else:
                    audio = listen(max_seconds=CFG["audio"]["max_seconds"],
                                   cancel=cancel,
                                   start_grace=None if first else (grace * 2 if espera_larga else grace),
                                   preroll=pre)
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
            if _is_stop(text):
                log("frase de corte: cierro el modo centro")
                break
            notify("Tú", text)
            bus.emit(type="transcript", value=text)
            bye = _is_farewell(text)

            # Modo A: casos rutinarios pre-programados (config.toml
            # [escalation].auto_cases) van directos a un Gemini ligero, sin
            # pasar por el LLM local ni pedir confirmación.
            auto_case = _match_auto_case(text)
            if auto_case is not None:
                _handle_auto_escalation(session, text, auto_case, mode, turn_cancel)
                turns += 1
                if mode != "centro" or bye or turns >= max_turns:
                    break
                continue

            sw = _mode_switch(text)
            if sw is not None:
                session.quality = sw
                r = ("Modo calidad activado." if sw
                     else "Vuelvo al modo rápido.")
                log(f"laura: {r}  (modelo -> {session.model_now()})")
                notify("Laura", r)
                bus.emit(type="reply", value=r)
                bus.emit(type="state", value="speaking", mode=mode)
                speak(r, cancel)
                turns += 1
                if mode != "centro" or turns >= max_turns:
                    break
                continue

            speech = Speech(turn_cancel, mode) if CFG["llm"].get("stream", True) else None
            lanzados0 = jobs.launched
            try:
                reply, actions, escalation = converse(
                    session, text, speech.feed if speech else None, turn_cancel)
                # El LLM ya ha terminado de generar; el audio puede seguir
                # sonando. Publicar aquí lo demás, no tras la voz.
                if escalation is None:
                    log(f"laura: {reply}  · acciones: {actions}")
                    notify("Laura", reply)
                    bus.emit(type="result", actions=actions)
                else:
                    log(f"laura: pide escalar (Modo B) -> {escalation}")
            finally:
                spoken = speech.finish() if speech else ""
            if cancel.is_set():
                break
            if OUT.interrupt_ev.is_set():
                continue  # interrumpida (atajo o barge-in): a escuchar de nuevo

            # Modo B: el LLM local ha pedido escalar. Confirmar con Alberto
            # antes de lanzar nada (lo gestiona esta función aparte, incluye
            # su propio turno de escucha para el sí/no).
            if escalation is not None:
                lanzo = _confirm_and_run_escalation(session, jobs, escalation, mode, cancel)
                turns += 1
                if lanzo or mode != "centro" or turns >= max_turns:
                    break  # trabajo lanzado en segundo plano: el orbe toma el relevo
                continue

            # Sin streaming, o si el streaming no llegó a decir nada, se
            # reproduce la respuesta entera de una vez.
            if reply and not spoken.strip():
                bus.emit(type="reply", value=reply)
                bus.emit(type="state", value="speaking", mode=mode)
                speak(reply, cancel)
            turns += 1
            if jobs.launched > lanzados0:
                log("trabajo en segundo plano lanzado: cierro el ciclo")
                break
            espera_larga = reply.rstrip().endswith("?")
            if mode != "centro" or bye or turns >= max_turns:
                break
    finally:
        OUT.clear_interrupt()
        bus.emit(type="state", value="idle", mode=mode)


class Announcer:
    """Cola de avisos hablados (temporizadores, recordatorios, trabajos que
    terminan). Habla aunque no haya ciclo activo; si hay uno en curso, espera
    a que acabe. `busy()` dice si hay un ciclo en marcha."""

    def __init__(self, busy, before=None, after=None, on_barge=None) -> None:
        self._busy = busy
        self._on_barge = on_barge
        self._before = before
        self._after = after
        self._q: queue.Queue = queue.Queue()
        threading.Thread(target=self._loop, daemon=True).start()

    def say(self, text: str, idle_only: bool = False) -> None:
        """Encola una frase. `idle_only`: si hay un ciclo en marcha cuando le toca, se descarta
        (los avisos de trabajos terminados no interrumpen ni se acumulan)."""
        self._q.put((text, idle_only))

    def _loop(self) -> None:
        while True:
            text, idle_only = self._q.get()
            if idle_only and self._busy():
                continue
            while self._busy():
                time.sleep(0.5)
            barged = False
            try:
                if self._before:
                    self._before()
                OUT.clear_interrupt()
                bus.emit(type="reply", value=text)
                bus.emit(type="state", value="speaking", mode="centro")
                speak(text)
                barged = OUT.interrupt_ev.is_set() and OUT.barged
            except Exception as e:  # noqa: BLE001
                log(f"error al anunciar: {e}")
            finally:
                bus.emit(type="amplitude", value=0.0)
                bus.emit(type="state", value="idle", mode="centro")
                if self._after:
                    self._after()
            if barged and self._on_barge and not self._busy():
                self._on_barge()  # Alberto habló encima del aviso: a escuchar


def main() -> None:
    load_vad()
    tts_warmup()
    BargeIn().install()
    n = reap_orphans()
    if n:
        log(f"{n} trabajo(s) huérfano(s) marcados como fallidos")
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
    session = Session()

    def busy() -> bool:
        return worker is not None and worker.is_alive()

    announcer = Announcer(busy,
                          before=lambda: wake.pause() if wake is not None else None,
                          after=lambda: wake.resume() if wake is not None else None,
                          on_barge=lambda: fire("centro"))
    confirm_q: queue.Queue = queue.Queue()
    jobs = JobManager(announcer.say, on_confirm=confirm_q.put)
    jobs_mod.set_manager(jobs)

    def confirmer() -> None:
        """Un trabajo en marcha (p. ej. Aurora) necesita un sí/no: cuando Laura esté libre
        lo pregunta por voz. Si lo contestan antes desde la tarjeta, no pregunta."""
        nonlocal worker
        while True:
            meta = confirm_q.get()
            while busy():
                time.sleep(0.5)
            ev = jobs.answered_event(meta["id"])
            if ev is None or ev.is_set():
                continue
            cancel.clear()

            def task(m=meta):
                try:
                    voice_yes_no(m["id"], m["pregunta"], "centro", cancel, jobs)
                except Exception as e:  # noqa: BLE001
                    log(f"pregunta de confirmación: {e}")
                finally:
                    bus.emit(type="state", value="idle", mode="centro")

            worker = threading.Thread(target=task, daemon=True)
            worker.start()
            worker.join()

    threading.Thread(target=confirmer, daemon=True).start()

    def on_aviso(a: dict) -> None:
        etiqueta = a["texto"]
        if a["tipo"] == "temporizador":
            frase = (f"Temporizador de {etiqueta} terminado."
                     if etiqueta and etiqueta != "temporizador" else "El temporizador ha terminado.")
        else:
            frase = f"Recordatorio: {etiqueta}"
        notify("Laura", frase)
        bus.emit(type="aviso", value=frase, tipo=a["tipo"], id=a["id"])
        announcer.say(frase)

    avisos.Scheduler(on_aviso).start()

    def run(mode: str, first_text: str | None = None) -> None:
        if wake is not None:
            wake.pause()
        try:
            cycle(session, jobs, mode, cancel, first_text)
        except Exception as e:  # noqa: BLE001
            log(f"error en el ciclo: {e}")
            notify("Laura", f"error: {e}")
            bus.emit(type="state", value="idle", mode=mode)
        finally:
            if wake is not None:
                wake.resume()

    def fire(mode: str, first_text: str | None = None) -> None:
        """Arranca un ciclo (o lo cierra si ya hay uno). Lo usan el atajo y la
        palabra de activación."""
        nonlocal worker
        if worker is not None and worker.is_alive():
            if OUT.speaking():
                log("atajo con Laura hablando: corto la voz y escucho")
                OUT.interrupt()
                return
            log("disparo repetido, cierro el ciclo")
            cancel.set()
            return
        if OUT.speaking():  # aviso hablando: callarlo y pasar a escuchar
            OUT.interrupt()
        cancel.clear()
        worker = threading.Thread(target=run, args=(mode, first_text), daemon=True)
        worker.start()

    wake = _make_wake(on_wake=lambda: fire("centro"))
    if wake is not None:
        wake.start()

    def control(data: str) -> dict | None:
        """Comandos del socket de control (una línea). Devuelve la respuesta JSON, o None
        para `activate` (sin respuesta). Contrato: docs/laura-v2/PLAN-ORBE.md."""
        cmd, _, arg = data.partition(" ")
        arg = arg.strip()
        if cmd.startswith("activate"):
            mode = data.split(":", 1)[1].strip() if ":" in data else "centro"
            fire(mode if mode in ("centro", "barra") else "centro")
            return None
        if cmd == "ask":  # depuración: una frase como si la hubiera dicho Alberto (ciclo completo, sin micro)
            if busy():
                return {"ok": False, "error": "hay un ciclo en curso"}
            fire("centro", first_text=arg)
            return {"ok": True}
        if cmd == "jobs":
            return {"jobs": [jobs_mod.to_event(m) for m in jobs_mod.list_jobs(500, horas=24)]}
        if cmd == "job-cancel":
            return jobs.cancel(arg)
        if cmd == "job-confirm":
            jid, _, ans = arg.partition(" ")
            if ans.strip() not in ("yes", "no"):
                return {"ok": False, "error": "uso: job-confirm <id> yes|no"}
            return jobs.confirm(jid, ans.strip() == "yes")
        if cmd == "job-read":
            return jobs.read(arg)
        if cmd == "job-follow":
            m = jobs_mod.get_job(arg)
            if not m:
                return {"ok": False, "error": "no existe ese trabajo"}
            raw = jobs_mod.JOBS_DIR / f"{arg}.md"
            detalle = raw.read_text()[:1500] if raw.exists() else ""
            session.add("user", (f"Contexto: {m['destino']} trabajó en «{m['titulo']}» (estado {m['estado']}). "
                                 f"Resumen: {m.get('resumen', '')}\nDetalle:\n{detalle}\n"
                                 "Alberto quiere seguir hablando de esto."))
            session.add("assistant", "Entendido, tengo el contexto de ese trabajo. ¿Qué quieres hacer con él?")
            jobs.read(arg)
            fire("centro")
            return {"ok": True}
        return {"ok": False, "error": f"comando desconocido: {cmd}"}

    try:
        while True:
            conn, _ = srv.accept()
            with conn:
                conn.settimeout(2)
                try:
                    data = b""
                    while b"\n" not in data and len(data) < 8192:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                    line = data.decode(errors="ignore").strip().splitlines()[0] if data.strip() else ""
                    resp = control(line) if line else None
                    if resp is not None:
                        conn.sendall((json.dumps(resp, ensure_ascii=False) + "\n").encode())
                except Exception as e:  # noqa: BLE001
                    log(f"control: {e}")
    except KeyboardInterrupt:
        pass
    finally:
        srv.close()
        if os.path.exists(sock_path):
            os.unlink(sock_path)
        bus.close()


if __name__ == "__main__":
    main()
