---
tipo: plan
proyecto: "[[Asistente de voz con IA local]]"
estado: listo-para-ejecutar
creado: 2026-09-01
tags:
  - aurora
  - plan
---

# Aurora — plan de implementación del overlay (fase 6)

Plan de traspaso para una sesión limpia. Las **decisiones ya están tomadas**
(diseño incluido); esto es solo ejecución.

## Contexto imprescindible

- **Diseño y decisiones completas:** [[Asistente de voz con IA local]] (§2.5 para el
  overlay, §1 para VRAM, §2.3 para la voz).
- **Mockups del overlay:** canvas de Claude Design en
  `assistant/design/aurora-overlay.html` — publicado. Dos modos decididos:
  - **Modo centro — orbe líquido.** Círculo grande centrado en pantalla. Esfera con
    brillo/degradado (accent rosa + lavanda del theming) que ondula y respira.
    Estados: reposo (orbe pequeño, respira lento) · escuchando (crece y ondula con la
    voz) · pensando (halo que gira) · hablando (anillos que emanan) + bocadillo de
    respuesta breve.
  - **Modo barra — "punto con cordón".** La barra de Caelestia es **vertical, a la
    izquierda**. En reposo, Aurora es un **punto** anclado a la barra. Al activarla el
    punto **se despega en un cordón fino que nunca se corta** y hace de gota que se
    deforma con la voz. Pensando: se calma, un aro gira alrededor. Resultado: la gota
    se deshace hacia abajo en un **tallo con una pastilla (icono + texto corto) por
    acción**; al terminar todo se recoge en el punto.
- **Rama de trabajo:** `feat/aurora-voice-assistant` (ya existe, con la v1 + los
  mockups commiteados). Seguir en ella; mergear a `main` al final.
- **Reparto de trabajo:** Alberto hace instalaciones, config y pruebas; el agente
  programa. Marcado abajo con **[A]** / **[Ag]**.

## Estado actual (v1, ya en la rama)

`assistant/` contiene un daemon funcional:

- `aurorad.py` — servicio systemd `--user` (`aurora.service`, instalado y activo).
  Escucha en `$XDG_RUNTIME_DIR/aurora.sock`; al recibir `"activate"` hace un ciclo:
  grabar (VAD) → faster-whisper (`small`, CPU) → Qwen3-4B por Ollama con *tool
  calling* → ejecutar acciones → Kokoro `ef_dora` + efecto "jarvis" (TTS).
  **Feedback actual = solo `notify-send`** en cada paso.
- `tools.py` — 7 herramientas locales (música, volumen, silenciar, abrir web/app,
  captura, bloquear).
- `config.toml` — voz, efecto, modelo STT, prompt, apps, tiempos.
- `aurora-toggle` — cliente que manda `"activate"` al socket (para el atajo).
- El bucle completo **ya funciona** de extremo a extremo (probado a mano).

Lo que **falta** para el overlay: el daemon no publica su estado ni la amplitud; no
hay módulo de Quickshell; solo hay un disparador (no distingue modo centro/barra).

## Trabajo, en orden

### 1 · Daemon: capa de eventos — [Ag]

En `aurorad.py`, además de `notify-send`, publicar eventos JSON por líneas en un
socket/FIFO propio (p. ej. `$XDG_RUNTIME_DIR/aurora-events.sock`, servidor que admite
varios lectores; o un FIFO). Eventos:

```json
{"type":"state","value":"idle|listening|thinking|speaking","mode":"centro|barra"}
{"type":"amplitude","value":0.0-1.0}          // ~30-60 Hz mientras graba y mientras habla
{"type":"result","actions":[{"icon":"volume","text":"Volumen al 60 %"}, ...]}
{"type":"transcript","value":"lo que dijo Alberto"}   // opcional, para el bocadillo
```

- `amplitude` mientras graba = RMS del bloque de `sounddevice` (ya se tiene el stream
  en `listen()`).
- `amplitude` mientras habla = RMS del wav de Kokoro por ventanas, reproducido en
  sincronía con `paplay` (o exponer el nivel del sink por PipeWire; lo más simple:
  precalcular la envolvente del wav y emitirla temporizada).
- `mode` viene del disparador (ver paso 2).
- Los `actions` salen del bucle de tool-calling: mapear cada `tool_call` ejecutado a
  `{icon, text}` corto (hay que añadir esa traducción; `tools.py` puede devolver un
  campo `resumen`).

### 2 · Dos disparadores — [Ag] + [A]

- **[Ag]** `aurora-toggle` acepta un argumento: `aurora-toggle centro` /
  `aurora-toggle barra` (por defecto `centro`). Manda `activate:centro` /
  `activate:barra` al socket de control. `aurorad.py` guarda el modo del ciclo en
  curso y lo mete en los eventos `state`.
- **[A]** Dos atajos en `~/.config/caelestia/hypr-user.lua`:
  ```lua
  hl.bind("SUPER + A",        hl.dsp.exec_cmd("/home/alberviz/LinuxRicing/assistant/aurora-toggle centro"))
  hl.bind("SUPER + SHIFT + A", hl.dsp.exec_cmd("/home/alberviz/LinuxRicing/assistant/aurora-toggle barra"))
  ```

### 3 · Módulo Quickshell `modules/assistant/` — [Ag]

Vive en `configs/quickshell/caelestia/modules/assistant/` (y sincronizar a
`~/.config/quickshell/caelestia/` — ver `CLAUDE.md`, reinicio obligatorio del shell).

- **`Aurora.qml` (singleton/servicio)** — abre un `Socket`/`Process` que lee el socket
  de eventos del daemon y expone propiedades reactivas: `state`, `amplitude`,
  `actions`, `transcript`, `mode`. Colores desde el singleton `Colours` de Caelestia
  (theming dinámico — usar `Colours.palette.m3primary` / `m3tertiary` o equivalente).
- **`OrbWindow.qml`** — `WlrLayershell` a pantalla completa, `exclusiveZone: -1`,
  transparente, *click-through* (`WlrLayershell.keyboardFocus: None`, sin capturar
  ratón salvo si algún día hay interacción). Visible cuando
  `Aurora.mode === "centro" && Aurora.state !== "idle"`. El orbe:
  **empezar sin shader** — capas de `Rectangle`/`Canvas` con `RadialGradient`,
  `border-radius` animado (wobble) y `SequentialAnimation`/`Behavior` por estado,
  escalando con `Aurora.amplitude`. Bocadillo de respuesta = `StyledText` en una
  píldora translúcida debajo. Dejar el orbe en un componente aparte (`Orb.qml`) para
  poder cambiarlo por un `ShaderEffect` GLSL más adelante sin tocar el resto.
- **`BarWindow.qml`** — `WlrLayershell` anclado al **borde izquierdo**
  (`anchors: { left: true; top: true; bottom: true }`), estrecho (~120-200 px),
  transparente, *click-through*. **No tocar el módulo `bar` de Caelestia** — esto va
  como capa por encima de su borde. Dibuja: el punto ancla (a la altura vertical que
  se decida, p. ej. centrado), el cordón (un `Shape`/`Path` que se estira), la gota
  (`Rectangle` con `radius` animado / `Shape` que se deforma con `amplitude`), el aro
  de "pensando", y en "resultado" el tallo + una pastilla por cada `Aurora.actions[i]`
  (icono Material Symbols + `StyledText`). Auto-ocultar ~3 s tras el resultado.
- **Registrar el módulo** donde Caelestia carga los suyos (revisar `shell.qml` /
  `Variants` / el loader de módulos) para que ambas ventanas existan siempre y se
  muestren por binding.

### 4 · Integración y verificación — [A]

1. **[Ag]** sincronizar los archivos QML a `~/.config/quickshell/caelestia/` y
   verificar que los pares gemelos queden idénticos (`diff -q`).
2. **[A]** reiniciar el shell:
   ```bash
   caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
   ```
   comprobar `INFO: Configuration Loaded` sin errores.
3. **[A]** añadir los dos atajos, `hyprctl reload`, y probar:
   - `SUPER+A` → orbe centrado que escucha/piensa/habla y reacciona a la voz.
   - `SUPER+SHIFT+A` → punto en la barra que se estira, gota reactiva, y al terminar
     cuelga las pastillas de acción.

## Decisiones técnicas ya tomadas (no re-debatir)

- **Orbe sin shader primero**; el `ShaderEffect` GLSL es una mejora posterior aislada
  en `Orb.qml`.
- **Modo barra = layershell propio anclado al borde**, NO modificar el módulo `bar`
  de Caelestia.
- **IPC = socket Unix con JSON por líneas** (sin dependencias). El de control
  (`aurora.sock`) y el de eventos (`aurora-events.sock`) separados.
- **Whisper en CPU** (en GPU peta junto al LLM — ver §1 de la nota).
- **Colores desde `Colours` de Caelestia**, nunca hardcodeados.

## Después de esto

Fase 4 (más acciones + n8n + memoria), fase 5 (wake word "Aurora"), fase 7 (fallback
online, carga perezosa de modelos para bajar los ~3 GB de RAM, sonidos). Ver
[[Asistente de voz con IA local]] §4.
