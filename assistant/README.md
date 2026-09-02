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
tiempos de grabación, modo calidad, wake word). Reinicia el daemon tras cambiarlo.

## Activación por voz («Laura») — wake word

El daemon puede escuchar en segundo plano con un modelo diminuto (openWakeWord,
CPU, no transcribe nada) y arrancar el ciclo al oír «Laura», además del atajo.
Está **desactivado** hasta que haya un modelo entrenado.

Puesta en marcha:

1. `openwakeword` + `onnxruntime` ya están en el venv.
2. **Entrenar el modelo «Laura»** (cosa de Alberto). Los modelos de fábrica de openWakeWord son
   para otras palabras. El propio proyecto tiene un cuaderno de entrenamiento
   automático que genera cientos de muestras sintéticas con TTS
   (`piper-sample-generator`) y entrena un modelo pequeño:
   <https://github.com/dscripka/openWakeWord> → *Training new models* (el
   notebook de Colab `automatic_model_training.ipynb`; palabra objetivo:
   `laura`). Salida: `laura.onnx` (o `.tflite`).
3. Deja el modelo en `assistant/models/laura.onnx`.
4. En `config.toml`, `[wake] enabled = true`. Reinicia el daemon.
5. Ajusta `[wake] threshold` (sube a 0.6-0.7 si se dispara solo).

Mientras hay un ciclo activo el wake listener se pausa (no compite por el micro
ni se dispara con la voz de Laura). El atajo `SUPER+A` sigue funcionando igual.

## Pendiente (fases siguientes)

Integraciones externas vía n8n (calendario, tareas), memoria persistente,
*fallback* online. Ver la nota del vault.
