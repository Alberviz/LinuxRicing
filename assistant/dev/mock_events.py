#!/usr/bin/env python3
"""Servidor simulado de los dos sockets de Laura, para probar el orbe y el cajón
sin el daemon real.

    LAURA_EVENTS_SOCK=/tmp/x/ev.sock LAURA_CTRL_SOCK=/tmp/x/ctrl.sock \
        python3 assistant/dev/mock_events.py [--scene] [--cmd-fifo RUTA]

Lanza el shell con las MISMAS variables para que Quickshell se conecte aquí.

- Bus de eventos: una línea JSON por evento (ping cada 5 s).
- Control: `jobs`, `job-cancel <id>`, `job-confirm <id> yes|no`, `job-read <id>`,
  `job-follow <id>`; una línea JSON de respuesta.
- Órdenes manuales por stdin o por --cmd-fifo (una por línea):
    aviso <id> <baja|normal|alta> <resumen...>   (aviso del vigia, origen laura)
    state <idle|listening|thinking|speaking> | transcript <txt> | reply <txt> | amp <0..1> [s]
    start <id> <destino> <titulo...>      waiting <id>
    confirm <id> <pregunta...>            done <id> <resumen...>
    failed <id> <resumen...>              scene   (started->waiting->confirm->done + un failed)
    seed                                  (trabajos viejos ya terminados, sin leer)
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import threading
import time

EV = os.environ.get("LAURA_EVENTS_SOCK") or os.path.expandvars("$XDG_RUNTIME_DIR/laura-events.sock-mock")
CTRL = os.environ.get("LAURA_CTRL_SOCK") or os.path.expandvars("$XDG_RUNTIME_DIR/laura.sock-mock")

jobs: dict[str, dict] = {}
clients: list[socket.socket] = []
lock = threading.Lock()


def emit(ev: dict) -> None:
    data = (json.dumps(ev, ensure_ascii=False) + "\n").encode()
    with lock:
        for c in list(clients):
            try:
                c.sendall(data)
            except OSError:
                clients.remove(c)


def job_event(j: dict) -> dict:
    ev = {"type": "job", **j}
    return ev


def set_job(jid: str, value: str, **kw) -> dict:
    j = jobs.setdefault(jid, {"id": jid, "destino": "laura", "titulo": jid, "resumen": "", "pregunta": "",
                               "nota": "", "fuentes": [], "inicio": time.time(), "fin": None, "leido": False,
                               "origen": "alberto", "tipo": "trabajo", "prioridad": "normal"})
    j["value"] = value
    j.update(kw)
    if value in ("done", "failed", "cancelled"):
        j["fin"] = time.time()
    emit(job_event(j))
    return j


def accept_loop(path: str, handler) -> None:
    if os.path.exists(path):
        os.unlink(path)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path)
    srv.listen(8)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handler, args=(c,), daemon=True).start()


def ev_client(c: socket.socket) -> None:
    with lock:
        clients.append(c)
    try:
        c.sendall(b'{"type":"state","value":"idle","mode":"centro"}\n')
        while True:
            time.sleep(5)
            c.sendall(b'{"type":"ping"}\n')
    except OSError:
        pass
    finally:
        with lock:
            if c in clients:
                clients.remove(c)


def ctrl_client(c: socket.socket) -> None:
    try:
        line = c.makefile("r").readline().strip()
        parts = line.split()
        out: dict = {"ok": True}
        if parts[:1] == ["jobs"]:
            out = {"jobs": [job_event(j) for j in jobs.values() if time.time() - (j["fin"] or j["inicio"]) < 86400]}
        elif parts[:1] == ["job-cancel"] and len(parts) > 1 and parts[1] in jobs:
            set_job(parts[1], "cancelled")
        elif parts[:1] == ["job-confirm"] and len(parts) > 2 and parts[1] in jobs:
            if parts[2] == "yes":
                set_job(parts[1], "started")
                threading.Timer(2.5, lambda: set_job(parts[1], "done", resumen="Hecho tras tu confirmación.")).start()
            else:
                set_job(parts[1], "cancelled", resumen="Rechazado. No se ha tocado nada.")
        elif parts[:1] == ["job-read"] and len(parts) > 1 and parts[1] in jobs:
            jobs[parts[1]]["leido"] = True
            emit(job_event(jobs[parts[1]]))
        elif parts[:1] == ["job-dismiss"] and len(parts) > 1:
            jobs.pop(parts[1], None)
        elif parts[:1] == ["ui"]:
            print("ui", line[3:], flush=True)
        elif parts[:1] == ["vigia-now"]:
            print("vigia-now", flush=True)
            threading.Timer(1.0, lambda: command("aviso v%d normal Hay un correo nuevo del profesor de Algebra" % int(time.time() % 1000))).start()
        elif parts[:1] == ["job-follow"]:
            print("follow", parts[1:], flush=True)
        c.sendall((json.dumps(out, ensure_ascii=False) + "\n").encode())
    except OSError:
        pass
    finally:
        c.close()


def scene() -> None:
    def run():
        set_job("j1", "started", destino="laura", titulo="Cámaras térmicas para la Raspberry")
        time.sleep(3)
        set_job("j2", "started", destino="gemini", titulo="Ordenar las ideas del Roadmap por esfuerzo")
        time.sleep(2)
        set_job("j1", "waiting", destino="gemini")
        time.sleep(3)
        set_job("j3", "started", destino="claude", titulo="Refactor de mchose-battery")
        time.sleep(1)
        set_job("j3", "confirm", pregunta="Voy a editar rgb/mchose-battery y widgets/mchose-battery. ¿Adelante?")
        time.sleep(4)
        set_job("j1", "done", destino="laura", resumen="Ya está: 3 opciones. Encaja la MLX90640.",
                nota=os.path.expanduser("~/LinuxRicing/vault/Laura/2026-10-20 1200 cámaras térmicas.md"),
                fuentes=[{"titulo": "adafruit.com", "url": "https://adafruit.com"}, {"titulo": "flir.com", "url": "https://flir.com"}])
        time.sleep(3)
        set_job("j4", "started", destino="aurora", titulo="Estado del Pi-hole")
        time.sleep(2)
        set_job("j4", "failed", resumen="Aurora no contesta: la Raspberry no responde.", nota="")
    threading.Thread(target=run, daemon=True).start()


def seed() -> None:
    now = time.time()
    for i, (d, t) in enumerate([("gemini", "Revisión del backlog"), ("aurora", "Temperatura de la Raspberry")]):
        jobs[f"s{i}"] = {"id": f"s{i}", "value": "done", "destino": d, "titulo": t, "resumen": "Resumen de ejemplo. Dos frases.",
                         "pregunta": "", "nota": "/home/x/LinuxRicing/vault/Laura/ejemplo.md", "fuentes": [],
                         "inicio": now - 600 - i * 60, "fin": now - 560 - i * 60, "leido": True}


def command(line: str) -> None:
    p = line.strip().split(maxsplit=3)
    if not p:
        return
    c = p[0]
    rest = lambda n: " ".join(p[n:]) if len(p) > n else ""
    if c == "start":
        set_job(p[1], "started", destino=p[2], titulo=rest(3))
    elif c == "waiting":
        set_job(p[1], "waiting")
    elif c == "confirm":
        set_job(p[1], "confirm", pregunta=" ".join(line.split()[2:]))
    elif c in ("done", "failed"):
        set_job(p[1], c, resumen=" ".join(line.split()[2:]),
                nota=os.path.expanduser(f"~/LinuxRicing/vault/Laura/2026-10-20 {p[1]}.md"),
                fuentes=[{"titulo": "ejemplo.org", "url": "https://example.org"}] if c == "done" else [])
    elif c == "aviso":  # aviso <id> <baja|normal|alta> <resumen...>
        set_job(p[1], "done", origen="laura", tipo="aviso", prioridad=p[2], destino="laura",
                titulo="Aviso del vigia", resumen=" ".join(line.split()[3:]),
                fuentes=[{"titulo": "Abrir en Gmail", "url": "https://mail.google.com"}])
    elif c == "state":      # state <idle|listening|thinking|speaking>
        emit({"type": "state", "value": p[1], "mode": "centro"})
    elif c == "transcript":
        emit({"type": "transcript", "value": " ".join(line.split()[1:])})
    elif c == "reply":
        emit({"type": "reply", "value": " ".join(line.split()[1:])})
    elif c == "amp":        # amp <0..1> [segundos]: voz sintetica a ~20 Hz
        v = float(p[1]); dur = float(p[2]) if len(p) > 2 else 3.0
        def _amp():
            import math
            t0 = time.time()
            while time.time() - t0 < dur:
                emit({"type": "amplitude", "value": max(0.0, min(1.0, v * (0.5 + 0.5 * math.sin((time.time() - t0) * 9)))) })
                time.sleep(0.05)
            emit({"type": "amplitude", "value": 0})
        threading.Thread(target=_amp, daemon=True).start()
    elif c == "scene":
        scene()
    elif c == "seed":
        seed()
    elif c == "quit":
        os._exit(0)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", action="store_true", help="reproduce la escena al arrancar")
    ap.add_argument("--cmd-fifo", help="FIFO de órdenes")
    a = ap.parse_args()
    threading.Thread(target=accept_loop, args=(EV, ev_client), daemon=True).start()
    threading.Thread(target=accept_loop, args=(CTRL, ctrl_client), daemon=True).start()
    print(f"mock: eventos={EV} control={CTRL}", flush=True)
    if a.scene:
        time.sleep(1)
        scene()
    src = open(a.cmd_fifo) if a.cmd_fifo else sys.stdin
    while True:
        line = src.readline()
        if not line:
            if a.cmd_fifo:
                src = open(a.cmd_fifo)
                continue
            time.sleep(3600)
            continue
        command(line)


if __name__ == "__main__":
    main()
