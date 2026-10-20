#!/usr/bin/env python
"""Laura — daemon de asistente de voz local.

Carga los modelos una vez y se queda escuchando en un socket Unix. Cuando
`laura-toggle` le manda "activate" (atado a un atajo de Hyprland), hace UN ciclo:

    grabar (corta sola al detectar silencio) -> transcribir -> LLM con
    herramientas -> ejecutar acciones -> responder hablando

Arranque:  ~/LinuxRicing/assistant/.venv/bin/python laurad.py
Depuración sin micro:  laurad.py --text "qué hora es" [--speak]

La lógica vive en el paquete `laura/` (config, audio, stt, llm, escalation,
tts, wake, daemon, textmode).
"""
import sys

if __name__ == "__main__":
    if len(sys.argv) > 1:
        from laura.textmode import main as text_main
        sys.exit(text_main(sys.argv[1:]))
    from laura.daemon import main
    main()
