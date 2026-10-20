"""Modo texto de depuración: `laurad.py --text "frase" [--speak]`.

Ejecuta converse() con la frase (sin micro ni Whisper), con las herramientas
reales, imprime la respuesta y, con --speak, la reproduce."""
from __future__ import annotations

import sys


def run_text(text: str, speak_reply: bool = False) -> int:
    from .llm import Session, converse
    reply, actions, escalation = converse(Session(), text)
    if escalation is not None:
        print(f"[escalada Modo B] {escalation}")
    for a in actions:
        print(f"[acción] {a}")
    print(reply)
    if speak_reply and reply:
        from .tts import speak
        speak(reply)
    return 0


def main(argv: list[str]) -> int:
    import argparse
    ap = argparse.ArgumentParser(prog="laurad.py")
    ap.add_argument("--text", metavar="FRASE",
                    help="modo texto: procesa la frase sin micro y sale")
    ap.add_argument("--speak", action="store_true",
                    help="con --text, reproduce la respuesta por los altavoces")
    args = ap.parse_args(argv)
    if args.text is None:
        ap.error("--speak solo tiene sentido con --text")
    return run_text(args.text, args.speak)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
