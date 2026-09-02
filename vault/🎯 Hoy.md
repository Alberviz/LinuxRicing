---
tags:
  - home
  - backlog
actualizado: 2026-09-01
---

# 🎯 Hoy · ¿Qué hago?

## 💡 Ideas — banco sin desarrollar

Tu base de datos de ideas en bruto. **Para elegir una:** edita su fila en la tabla y cambia **Estado** de `idea` a `pendiente`. Con eso se promociona y baja a la sección de abajo con contexto. Para añadir idea nueva, crea una nota en `Backlog/` con `estado: idea` (o dile a un agente «apunta la idea …»).

![[Backlog.base#💡 Ideas]]

---

## 🎯 Pendiente (por prioridad)

Lo que ya has elegido y está listo para hacerse. Usa el **selector de estado** en cada fila para cambiar entre Pendiente → En curso → Terminado.

![[Backlog.base#🎯 Hoy]]

## 🔨 En curso ahora mismo

Lo que se está haciendo en este momento.

![[Backlog.base#🔨 En curso]]

## ✅ Terminado

Lo que ya está hecho.

![[Backlog.base#✅ Hechas]]

---

## 📓 Bitácora de sesiones

*Los agentes añaden una línea por sesión, lo más reciente arriba.*

- **2026-09-02 · Claude** — Sistema solar **v1.5** (rama `feat/sistema-solar-v1`). Maqueta de rediseño: [artifact 6935dde1](https://claude.ai/code/artifact/6935dde1-72c3-4ba1-8c87-c907f7ba8561) — propone devolver la música a sol dominante, bajar «config» a planeta, separar los dos soles por forma y no solo color, y meter los tres periféricos + tres zonas LED. **Cambio de dispositivo M8 → K7 Ultra** integrado (anillo de la base = cuerpo LED; batería del ratón = planeta). Código: adaptadores reales de batería (`mchose-battery --json`) y LED (`RgbConfig`), cuerpos de periférico dinámicos (solo si conectados), 5 bugs de la v1 corregidos (`anyActivity` ya para el Timer en reposo; fuera `ledOn:1.0`; hex fijo del agujero negro → paleta; `reduceMotion` atable; pausa con GameMode). **Aparte — bug gordo:** el shell arrancaba a **~100 % CPU** por un `FrameAnimation { running: true }` incondicional en `DesktopCircularMedia` (repinta un Canvas 448px a 60fps para siempre); gateado a música+visible → **~5 %**. `SolarSystemLayer` cableada al shell y verificada (carga limpia, 5 % en reposo). **Pendiente de Alberto:** mirar la maqueta y decir si la música vuelve a sol o se queda agujero negro; la v2 (interacción) necesita iteración en vivo.

- **2026-09-02 · Gemini** — TTS de Laura actualizado: integrado soporte multi-motor (Edge-TTS, Piper y Kokoro) en `laurad.py` con auto-detección según `config.toml`. Laura configurada con la voz en castellano de España `es-ES-ElviraNeural` + efecto `jarvis` por ffmpeg. Creada la utilidad `assistant/test-voice` para previsualizar voces y efectos (Santa, Elvira, Álvaro, Dave, etc.). `laura.service` reiniciado y operativo.

- **2026-09-02 · Claude** — Resuelto el emparejamiento Bluetooth del ratón MCHOSE K7 Ultra. Diagnóstico en vivo sobre la máquina (btmon no llegó a hacer falta): ningún bond existía nunca, las MACs "rotatorias" eran `AddressType=static` regeneradas por el firmware Telink al fallar el bonding, y el journal de `bluetoothd` mostraba **ATT 0x0E** en todas las características HOGP tras un GATT limpio → BlueZ no escalaba a SMP. Causa raíz: `ControllerMode = dual` en `main.conf`; con `= le` (LE puro) el pairing cierra, se distribuyen 2 LTK y se crean los nodos uhid. Registrado en la Base de Datos de Errores y marcada como `resuelto` la nota *Diagnóstico y Handoff Bluetooth*.

- **2026-09-02 · Claude** — Análisis del asistente para el portátil (i5-12600HX / RTX 4050 6 GB / 24 GB) y consolidación de ramas. Arreglado el segfault de `laurad.py` al escuchar: el preload de CUDA de `93740b0` cargaba `libnvblas.so` con RTLD_GLOBAL y tumbaba el proceso en la primera llamada BLAS; acotado a solo cuBLAS + cuDNN. `llm.num_ctx` configurable (antes fijo a 4096), a 6144 por presupuesto de VRAM. Mergeados a `main`: overlay nuevo de Laura (`feat/laura-overlay-redesign`), arreglos del portátil y el `ProjectDialog` de Gemini. `~/.config` resincronizado (fuera `Orb`/`OrbWindow`/`BarWindow`). Además, plan de mejora de Laura del portátil: **voz por frases** (fase 3, `converse()` en streaming + clase `Speech` de 2 hilos, `[llm] stream`); **tools nuevas** (`leer_portapapeles`, `pegar_texto` con ydotool, `leer_pantalla` grim+tesseract, `ventanas_abiertas` hyprctl); **modo calidad** por voz (`llm.model_quality`, a `qwen2.5:7b-instruct`); **wake word** (fase 5, clase `WakeListener` con openWakeWord, `[wake]` en config, se pausa durante el ciclo). Medido: STT 0,6 s, primera palabra a ~1 s, ~1,5 s percibido. OCR acotado a la ventana activa (~2,5 s). Todo en `main`. Pendiente de Alberto: `ollama pull qwen2.5:7b-instruct`; usuario al grupo `input` + módulo `uinput` para que `pegar_texto` teclee (ydotoold no abre `/dev/uinput`); entrenar `models/laura.onnx` para el wake word; decir en qué app el OCR salió difuso.

- **2026-09-02 · Gemini** — Rendimiento, layout, Laura CUDA y selector de pantallas: eliminadas instancias duplicadas de Quickshell y optimizado Laura en CUDA (Whisper/Kokoro en RTX 4050). Implementado el módulo nativo de Caelestia `ProjectDialog` (`Super + P`) con tarjetas interactivas Material Design 3, atajos numéricos 1-4, animación de entrada/salida y llamadas a la API Lua de Hyprland (`hyprctl eval`) para control en caliente de monitores a 144Hz y apagado de panel integrado.

- **2026-09-01 · Claude** — Brainstorming + arranque del **sistema solar binario** del
  escritorio (sustituirá los widgets). Plan por versiones en `docs/sistema-solar-binario.md`
  + maqueta `artifact 0cf6374a`. Mergeado `feat/aurora-voice-assistant` → `main`; ramas
  `feat/sistema-solar` (paraguas) + `feat/sistema-solar-v1` (worktree dedicado). v1 WIP
  commiteado (7d88b47): motor puro config-driven `Sim.js` + `SolarSystem.qml` +
  `SolarSystemModel` (adaptadores cava/agentes/tareas) + capa `SolarSystemLayer`. Carga
  limpia. Falta cerrar la disposición con Alberto y adaptadores de batería/LED. Además:
  fix del recorte del anillo orbital de música (`Background.qml`, lienzo 448px).

- **2026-09-01 · Claude** — Overlay de **Laura** rehecho (rama
  `feat/laura-overlay-redesign`): un solo modo, `LauraOverlay.qml` = borde
  inferior de la pantalla iluminado (altura + intensidad siguen el estado:
  amplitud del micro al escuchar, envolvente del TTS al hablar, deriva de tono
  al pensar) + píldora translúcida de subtítulos (transcript + respuesta
  completa). Borrados `Orb`/`OrbWindow`/`BarWindow`; `laura-toggle` sin
  argumento. Shell recargado sin errores. Coordinado con la sesión del
  [[Sistema solar binario del escritorio]] (fondo): reparto de archivos, merge
  de `feat/aurora-voice-assistant` a `main`, backlog + roadmap del sistema
  solar. Pendiente de Alberto: reinstalar el servicio como `laura`, atajo.
- **2026-09-01 · Claude** — Aurora → **Laura**: rename hecho en el código
  (`assistant/` completo + módulo Quickshell; sockets `laura-events.sock`;
  `laurad.py`, `laura.service`, `laura-toggle`). Daemon: conversación
  multi-turno en modo centro (cierra por «adiós» / repetir atajo / silencio /
  6 turnos), ciclo en hilo worker con evento `cancel`, evento `reply` con la
  respuesta completa, guardas anti-alucinación de Whisper, herramienta
  `copiar_al_portapapeles`. Overlay: arreglada la reconexión del `Socket` de
  Quickshell (Loader + heartbeat `ping`). **Pivote de diseño:** overlay
  minimalista, lo vistoso va al fondo del escritorio; elegido **borde inferior
  iluminado + subtítulos** (lo que dice Alberto + respuesta completa). Estado
  y trampas en [[Aurora — plan del overlay]]. Pendiente: reinstalar el
  servicio, atajo de Hyprland, rehacer el overlay con el estilo nuevo.
- **2026-09-01 · Claude** — [[Asistente de voz con IA local]] «Aurora»: investigación
  completa (LLM/STT/TTS/acciones/wake word/n8n, precios, rendimiento) + **v1 construida**
  en rama `feat/aurora-voice-assistant` (`assistant/`): daemon que hace atajo → VAD →
  Whisper → Qwen3-4B con tool-calling → acciones → Kokoro `ef_dora` + efecto jarvis.
  Servicio systemd `--user` activo. Diseño del overlay decidido con mockups (Claude
  Design): **modo centro = orbe líquido**, **modo barra = punto con cordón**. Plan de
  implementación del overlay listo para sesión limpia en [[Aurora — plan del overlay]].
  Whisper va en CPU (GPU peta con el LLM cargado); daemon ocupa ~3 GB de RAM.
- **2026-09-01 · Claude** — Flujo de dos niveles en esta página: nuevo estado `idea` +
  vista «💡 Ideas» arriba (base de datos de ideas); promocionar = cambiar `estado` a
  `pendiente` en la tabla. Fix del widget del teclado Akko por cable (transporte real,
  sin batería inventada). Investigado el falso positivo del *running pulse* de agentes.
- **2026-08-29 · Claude** — Sistema de Backlog del vault: carpeta `Backlog/`, `Backlog.base`
  con 7 vistas y esta página. Semilla con el trabajo reciente + el Roadmap accionable.
- **2026-08-29 · Claude** — Convergido a `main` (`9b8d78f`): running-pulse v2 + sonidos de
  notificaciones + backlog del vault. Shell reiniciado y verificado, sonidos activos.
- **2026-08-29 · Claude** — Sonidos de notificaciones de agentes: sonido al iniciar /
  completar / fallar, 4 paletas (`system` + 3 de Kenney CC0), CLI `agent-notify sound-set`.
  Paleta activa: `kenney-glass`.
- **2026-08-29 · Claude** — *Running pulse* v2 del pip: aro palpitante mientras el agente
  trabaja + halo neón solo en el contorno; reproducibilidad de los hooks de Claude Code
  en `install.sh`.
- **2026-08-29 · Claude** — Fix: el teclado Akko reporta transporte USB al cargar por
  cable; fix de la bandera de carga atascada en 2.4 GHz.
- **2026-08-29 · Claude** — Auto-intercepción de las notificaciones nativas de Antigravity
  y Claude hacia el pipeline enriquecido de agentes.
- **2026-08-27 · Gemini + Claude** — Notificaciones de agentes en el pip del workspace
  (v1): CLI `agent-notify`, toasts enriquecidos, halo de acento, tarjeta popout.

---

### Fijar esta nota como pantalla de inicio

Para que Obsidian la abra al arrancar: **Ajustes → Plugins de la comunidad → Explorar →
«Homepage»** (instalar y activar) → en sus opciones, *Homepage* = `🎯 Hoy`. Mientras
tanto está en **Marcadores** (barra lateral).
