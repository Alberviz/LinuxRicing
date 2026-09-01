# Laura — asistente de voz local

Estado: **v1** — atajo de teclado + voz + acciones básicas del sistema.
Diseño completo y decisiones en `vault/Backlog/Asistente de voz con IA local.md`.

Pipeline: atajo → grabar (corta sola con VAD) → faster-whisper (STT) →
Qwen3-4B por Ollama con *tool calling* → ejecutar acciones → Kokoro `ef_dora` +
efecto "jarvis" (TTS).

## Puesta en marcha

Requisitos ya instalados en la fase 0 (ver la nota del vault): Ollama + modelo
`qwen3:4b-instruct`, venv en `.venv` (Python 3.12) con faster-whisper, silero-vad,
kokoro, sounddevice, soundfile; `playerctl`, `wpctl`, `ffmpeg`, `xdg-open`.

1. **Arrancar el daemon** (deja la terminal abierta para ver el log):

   ```fish
   ~/LinuxRicing/assistant/.venv/bin/python ~/LinuxRicing/assistant/laurad.py
   ```

   O como servicio:

   ```fish
   # si vienes del nombre antiguo (aurora):
   systemctl --user disable --now aurora 2>/dev/null; rm -f ~/.config/systemd/user/aurora.service

   cp ~/LinuxRicing/assistant/laura.service ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now laura
   journalctl --user -u laura -f      # ver el log
   ```

2. **Atajo de teclado.** Añade esta línea a `~/.config/caelestia/hypr-user.lua`
   (fichero de overrides del usuario, sobrevive a las actualizaciones de Caelestia):

   ```lua
   hl.bind("SUPER + A", hl.dsp.exec_cmd("/home/alberviz/LinuxRicing/assistant/laura-toggle"))
   ```

   Recarga Hyprland (`hyprctl reload`) o cierra sesión y entra.

3. **Usar.** Pulsa `SUPER + A`, habla, calla. Laura transcribe, piensa,
   ejecuta y responde. Sale un `notify-send` en cada paso.

## Qué entiende (v1)

- «pon música» / «pausa» / «siguiente canción» / «quita la música»
- «sube el volumen» / «bájalo un 20 por ciento» / «silencia»
- «abre Google» / «busca la receta de tortilla» / «abre YouTube»
- «abre Spotify» / «abre la terminal» / «abre el navegador»
- «haz una captura» · «bloquea la pantalla»
- combinaciones: «quita la música y abre Google»
- cualquier pregunta normal → responde hablando, sin acción

## Configurar

Todo en `config.toml` (voz, efecto, modelo STT, prompt, apps que puede abrir,
tiempos de grabación). Reinicia el daemon tras cambiarlo.

## Pendiente (fases siguientes)

Wake word «Laura», integraciones externas vía n8n (calendario, tareas),
memoria persistente, overlay visual en Quickshell, *streaming* por frases,
*barge-in*, *fallback* online. Ver la nota del vault.
