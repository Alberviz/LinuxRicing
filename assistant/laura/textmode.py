"""Modo texto de depuración: `laurad.py --text "frase" [--speak] [--confirm yes|no]`.

Ejecuta converse() con la frase (sin micro ni Whisper), con las herramientas
reales, imprime la respuesta y, con --speak, la reproduce. Si la frase lanza
trabajos en segundo plano (investigar, Aurora, escaladas) espera a que terminen e
imprime su estado final; las confirmaciones (sí/no) se contestan solas con
`--confirm` (por defecto `no`: nunca se hace un cambio sin pedirlo)."""
from __future__ import annotations

import sys


def run_text(text: str, speak_reply: bool = False, confirm: str = "no") -> int:
    from . import jobs as jobs_mod
    from .llm import Session, converse

    import time
    t0 = time.time()
    jm = jobs_mod.JobManager(lambda t, **k: print(f"[voz] {t}"))
    jm.on_confirm = lambda m: (print(f"[confirm] {m['pregunta']}  -> respondo «{confirm}»"),
                               jm.confirm(m["id"], confirm == "yes"))
    jobs_mod.set_manager(jm)

    reply, actions, escalation = converse(Session(), text)
    if escalation is not None:
        print(f"[escalada Modo B] {escalation}")
        pregunta = (f"¿Se lo mando a {escalation['destino']}? {escalation['peticion']}")
        es_cmd = escalation["destino"] == "comando"
        jid = jm.start("laura" if es_cmd else escalation["destino"], escalation["peticion"],
                       escalation.get("motivo", ""), pregunta=pregunta, ask_voice=False,
                       kind="comando" if es_cmd else "agent")
        print(f"[confirm] {pregunta}  -> respondo «{confirm}»")
        jm.confirm(jid, confirm == "yes")
    for a in actions:
        print(f"[acción] {a}")
    print(reply)
    if speak_reply and reply:
        from .tts import speak
        speak(reply)
    jm.wait_all()
    for m in jobs_mod.list_jobs(20):
        if m["inicio"] >= t0 - 1:
            print(f"[job {m['id']}] {m['destino']} {m['estado']}: {m['resumen'][:200]}")
            if m["nota"]:
                print(f"  nota: {m['nota']}")
    return 0


def main(argv: list[str]) -> int:
    import argparse
    ap = argparse.ArgumentParser(prog="laurad.py")
    ap.add_argument("--text", metavar="FRASE",
                    help="modo texto: procesa la frase sin micro y sale")
    ap.add_argument("--speak", action="store_true",
                    help="con --text, reproduce la respuesta por los altavoces")
    ap.add_argument("--confirm", choices=["yes", "no"], default="no",
                    help="con --text, respuesta automática a las confirmaciones (por defecto no)")
    args = ap.parse_args(argv)
    if args.text is None:
        ap.error("--speak y --confirm solo tienen sentido con --text")
    return run_text(args.text, args.speak, args.confirm)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
