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

## Activación por voz («Laura despierta») — wake word

El daemon escucha en segundo plano con un modelo diminuto (openWakeWord, CPU, no
transcribe nada) y arranca el ciclo al oír **«Laura despierta»**, además del atajo.
No basta con «Laura» sola (es también el nombre de la novia de Alberto): el modelo
se entrena con «Laura», «Laura, ven…» y «despierta» suelta como negativos.

Modelo: `models/laura.onnx`, entrenado en local con `wake_train/` (datos en
`~/.local/share/laura/wake/`, fuera del repo):

1. `sinteticos.py` — miles de clips TTS (voces Piper en español + mezclas de voces
   Kokoro) de la frase y de negativos parecidos.
2. `grabar.py` — tu voz: tomas de la frase, tomas «casi», habla normal y ambiente
   (Enter por toma; `r` repite).
3. `entrenar.py` — aumento (reverberación, filtros, ruido), embeddings congelados de
   openWakeWord, clasificador pequeño → ONNX. Mide detección y falsos/hora con
   ~5 h de `validation_set_features.npy` de openWakeWord. `--rehacer` recalcula la caché.
4. `probar.py` — score en directo con la misma lógica que el daemon.

En `config.toml` → `[wake]`: `enabled`, `threshold` (0.8) y `patience` (3 ventanas
de 80 ms seguidas sobre el umbral; los falsos suelen ser picos sueltos). Examen
inicial: ~88 % de tus tomas no vistas, ~0,2 falsos/h. Si salta solo, sube
`patience` a 4; si no te oye, bájalo a 2 o graba más tomas y reentrena.

Wake, `listen()` y el barge-in comparten **un único InputStream** (`laura/mic.py`,
distribuidor con suscriptores): no compiten por el micro. Mientras hay un ciclo
activo el wake listener descarta el audio (no se dispara con la voz de Laura).
El atajo `SUPER+A` sigue funcionando igual.

## Voz (TTS), audio y barge-in

- **Motores** en `laura/engines/` (un fichero por motor, registro con `@engine`):
  `kokoro` (local, GPU; cae a CPU si no hay VRAM), `piper` (local, CPU), `edge`
  (nube), `http` (POST a una URL que devuelve un WAV: VoiceStudio :3900, OmniVoice,
  PocketTTS servidos aparte, con `ref_audio`/`ref_text` para clonar), y stubs
  `pocket`/`omnivoice`. Cadena: `[tts] engine` + `fallbacks`.
- **Voz propia con VoiceStudio** (motor `voicestudio`, MCP Streamable HTTP, solo `requests`;
  probado únicamente contra un servidor simulado: `python tests/mock_voicestudio.py`). Para activarlo:
  1. Instala y arranca VoiceStudio (backend en `http://127.0.0.1:3900`).
  2. Crea la voz por MCP con `design_voice` (descripción) o `clone_voice` (audio de referencia)
     y copia el `profile_id` que devuelve.
  3. En `config.toml`: `[tts.voicestudio] profile_id = "…"` y
     `[tts] engine = "voicestudio"`, `fallbacks = ["kokoro", "piper"]`. Si VoiceStudio no
     responde, el motor se aparca 2 min y entra kokoro.
- **Un solo dueño del audio**: `laura/output.py` (lock de hilos + flock de fichero);
  avisos, respuestas y confirmaciones nunca se solapan, ni siquiera entre procesos.
  Pulsar el atajo mientras Laura habla corta la voz y pasa a escuchar.
- **Barge-in** (`[audio] barge_in`, off por defecto: sin auriculares el eco puede
  dispararlo): voz sostenida (`barge_in_ms`, `barge_in_threshold`) corta la voz.
- **Frases de corte** (`[audio] stop_phrases`): «para», «calla»… cierran el modo centro.

## Pendiente (fases siguientes)

Integraciones externas vía n8n (calendario, tareas), memoria persistente,
*fallback* online. Ver la nota del vault.
