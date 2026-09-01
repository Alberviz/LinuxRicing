---
tipo: plan
proyecto: "[[Asistente de voz con IA local]]"
estado: en-curso
creado: 2026-09-01
actualizado: 2026-09-01
tags:
  - laura
  - aurora
  - plan
---

# Laura — asistente de voz local (estado, arquitectura y plan)

> Antes se llamaba **Aurora**. El rename a **Laura** está hecho en el código
> (`assistant/` + módulo de Quickshell); falta en el vault (Gemini) y en la
> reinstalación del servicio (Alberto). Rama: `feat/aurora-voice-assistant`.

## Qué es y qué funciona (v1)

Asistente de voz **100 % local**. Pipeline probado de extremo a extremo:

```
atajo (SUPER+A) → grabar (VAD corta sola) → faster-whisper (STT) →
Qwen3-4B por Ollama con tool-calling → ejecutar acciones →
Kokoro (voz ef_dora + efecto "jarvis") → hablar
```

Feedback: `notify-send` en cada paso **+** un overlay de Quickshell que reacciona
al estado y a la voz (en rediseño, ver abajo).

## Arquitectura

Todo en la rama, `estado: funcional`.

### Daemon — `assistant/`

| Archivo | Qué hace |
|---|---|
| `laurad.py` | Servicio `laura.service` (systemd `--user`). Carga los modelos una vez. Socket de control `$XDG_RUNTIME_DIR/laura.sock` (recibe `activate:centro` / `activate:barra`). El ciclo corre en un **hilo worker**; el hilo principal sigue aceptando conexiones. |
| `events.py` | `EventBus`: servidor socket Unix `laura-events.sock`, **multi-lector**, JSON por líneas. Reemite el último `state` a cada cliente nuevo. Hilo de **heartbeat** que emite `{"type":"ping"}` cada 5 s. |
| `tools.py` | 8 herramientas: `control_musica`, `volumen`, `silenciar`, `abrir_web`, `abrir_app`, `captura_pantalla`, `bloquear_pantalla`, `copiar_al_portapapeles` (wl-copy). Cada una devuelve `{ok, resumen, …}`. `TOOL_ICONS` (Material Symbols) + `accion_overlay()` → `{icon, text}` para las píldoras. |
| `config.toml` | Todo lo tuneable: voz, efecto, modelo STT, `system_prompt`, apps, tiempos, `max_turns`, `timeout` de Ollama, `history_msgs`, `amp_gain`, `followup_seconds`. |
| `laura-toggle` | Cliente que manda `activate:<modo>` al socket de control. Para el atajo de Hyprland. |
| `README.md` | Puesta en marcha + migración del servicio aurora→laura. |

### Bus de eventos (lo que consume el overlay)

```json
{"type":"state","value":"idle|listening|thinking|speaking","mode":"centro|barra"}
{"type":"amplitude","value":0.0-1.0}      // ~30 Hz al grabar; envolvente del wav al hablar
{"type":"transcript","value":"lo que dijo Alberto"}
{"type":"reply","value":"la respuesta completa de Laura"}
{"type":"result","actions":[{"icon":"volume_up","text":"Subir volumen"}, …]}
{"type":"ping"}                            // latido cada 5 s (para detectar caída)
```

### Overlay — `configs/quickshell/caelestia/modules/assistant/`

(Sincronizar SIEMPRE a `~/.config/quickshell/caelestia/` y reiniciar el shell.)

| Archivo | Estado |
|---|---|
| `Laura.qml` | **Singleton/servicio.** Lee el bus por `Socket` y expone `state`, `mode`, `amplitude` (suavizada), `transcript`, `reply`, `actions` + colores del tema (`accent`, `accentAlt`, `surface`, `onSurface`). **Se queda.** |
| `Assistant.qml` | Entrada del módulo, registrada en `shell.qml`. **Se queda.** |
| `Orb.qml`, `OrbWindow.qml`, `BarWindow.qml` | Las ventanas del overlay viejo (orbe + cordón). **Se borran en el rediseño.** |

### Lógica del ciclo (`cycle(mode, cancel)`)

- **`barra`**: un input → respuesta → se recoge.
- **`centro`**: conversación multi-turno. Tras responder, escucha un follow-up con
  `start_grace` (4 s). **Se cierra** si: Alberto se despide (`_is_farewell`:
  «adiós», «hasta luego», «nada más»…), **repite el atajo** (pone el evento
  `cancel`), calla 4 s, o llega a `max_turns` (6).
- `cancel` (threading.Event) se comprueba en `listen()`, `speak()` y
  `_play_with_amplitude()` → corta al instante.
- Historial podado a system + últimos 12 mensajes (Ollama corre con contexto 4096).

## Diseño del overlay — DECIDIDO

**Un solo modo** (se acaba la separación centro/barra). El overlay es **mínimo**:
lo vistoso pasa en el **fondo del escritorio** (orbe de música / sistema que
orbita — plan del otro agente). El overlay solo señala el estado de Laura.

**Estilo elegido (Alberto, 2026-09-01):**

> **El borde inferior de la pantalla se ilumina**, como una barra de luz, con
> **subtítulos**: una línea con lo que dice Alberto (`transcript`) y luego la
> **respuesta completa** de Laura (`reply`).

Estados de la luz del borde inferior:
- **reposo** — apagado.
- **escucha** — brillo estable, intensidad sigue `amplitude`.
- **piensa** — la luz deriva / se mueve (deriva de tono o un punto que recorre el borde).
- **habla** — palpita al ritmo de la envolvente del TTS.

Mockup con las 5 direcciones que se barajaron (elegida la **B · Borde inferior**):
Artifact de Claude — <https://claude.ai/code/artifact/65142660-67cf-4c38-84a0-968a0e4509a0>

Implementación esperada: `WlrLayershell` a pantalla completa, transparente,
click-through (`mask: Region {}`), en `WlrLayer.Overlay`. La luz = gradientes
(sin shader). Colores desde `Colours.palette` de Caelestia. Los subtítulos =
una píldora translúcida centrada abajo con `StyledText` (que muestre `reply`
completo, hasta ~8 líneas; mientras piensa, `transcript` atenuado).

## Trampas conocidas (leer antes de tocar nada)

1. **El `Socket` de Quickshell NO reconecta tras un error.** Reasignar
   `connected` no basta. Solución aplicada: el `Socket` vive en un `Loader`;
   un `Timer` (`linkWatch`, 9 s) lo **recrea** si no llega ninguna línea. El
   daemon manda `ping` cada 5 s como señal de vida. Mantener este patrón.
2. **Whisper alucina voz del silencio/ruido** («Música», «Gracias»,
   «¡Suscríbete!», «Subtítulos… amara.org»). Mitigado: `listen()` devuelve
   vacío si silero no detecta arranque de voz + `vad_filter=True` + lista
   `_STT_NOISE`. **Aún coge audio real de vídeos/podcasts cerca del micro** →
   pendiente cancelación de eco / push-to-talk.
3. **El daemon se reinicia solo al cambiar un archivo** (Alberto tiene un
   watcher). ~6 s recargando modelos. Hace el testeo rápido incómodo.
4. **`Tokens` / `Config` de Caelestia necesitan contexto de pantalla.**
   Accederlos dentro de `contentItem` (hijos de la ventana), no en la raíz de
   la ventana, o dan warning «accessed without a screen set» y valores malos.
5. **`MaterialShape`** viene de `import M3Shapes` (formas expresivas M3:
   `SoftBurst`, `Cookie9Sided`, `Flower`, `Puffy`, `Sunny`, `Oval`…). Morphea
   sola al cambiar `shape` (via `animationDuration`). Es el mismo componente
   que el `LoadingIndicator` de Caelestia. (Menos relevante ya con el borde
   inferior, pero útil.)
6. **Singletons de módulo** se importan `import qs.modules.assistant`.
   Ventanas por pantalla: `Variants { model: Screens.screens; Scope { required
   property ShellScreen modelData; … } }`.
7. **`mask: Region {}`** (vacío) en un `PanelWindow`/`StyledWindow` = click-through total.
8. **Archivos gemelos:** `configs/quickshell/caelestia/` ⇔
   `~/.config/quickshell/caelestia/` (`cp` + `diff -rq`). Reinicio del shell
   obligatorio tras tocar UI (`caelestia shell -k … ; caelestia shell -d`).
9. **Whisper en CPU** (`device = "cpu"`): en GPU peta junto a Ollama y
   recalienta la gráfica.

## Pendiente de Alberto (instalaciones/config)

1. Reinstalar el servicio:
   ```bash
   systemctl --user disable --now aurora; rm -f ~/.config/systemd/user/aurora.service
   cp ~/LinuxRicing/assistant/laura.service ~/.config/systemd/user/
   systemctl --user daemon-reload && systemctl --user enable --now laura
   ```
2. En `~/.config/caelestia/hypr-user.lua`: cambiar `aurora-toggle` →
   `laura-toggle` en las dos líneas del atajo. `hyprctl reload`.

## Pendiente de trabajo (agentes)

- **Rehacer el overlay** con el estilo decidido (borde inferior + subtítulos):
  una sola ventana unificada, borrar `Orb.qml` / `OrbWindow.qml` /
  `BarWindow.qml`, terminar el rename en esos archivos nuevos. `laura-toggle`
  puede dejar de aceptar argumento (o mantener `centro` por compatibilidad).
- **Vault:** renombrar Aurora → Laura en las notas (Gemini). Backlog:
  [[Renombrar el asistente de voz de Aurora a Laura]].
- **Cancelación de eco / push-to-talk** para que el modo conversación no coja
  audio de vídeos.
- Fases siguientes (ver [[Asistente de voz con IA local]]): wake word «Laura»,
  n8n (calendario/tareas), memoria persistente, streaming por frases, fallback
  online, carga perezosa de modelos.

## Reparto con el otro agente

- **Este trabajo (overlay + daemon):** `assistant/`, `configs/quickshell/…/assistant/`.
- **El otro agente (fondo vistoso):** `widgets/Background.qml` /
  `configs/quickshell/…/background/` — el orbe de música y el «sistema solar»
  de agentes que orbita. Su plan hay que leerlo antes de rehacer el overlay
  (comparten el borde inferior de la pantalla).
