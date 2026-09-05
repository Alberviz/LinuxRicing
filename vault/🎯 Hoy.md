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
- **2026-09-05 · Claude** — Agujero negro Gargantua: eliminada la "X" del limbo — el disco ecuatorial y las bóvedas lensadas ya son **un solo cuerpo** (`solarfield.frag`, rama `feat/sistema-solar-v3`, commit `5fbc679`). `lensLUT0` se dibuja en todo su dominio con una única `discPlane()` (cara lejana + cuenco + arco superior = un campo geodésico continuo, C¹); `lensLUT1` al mismo brillo que el cuerpo para que la bóveda no flote aparte; fuera `crescentMask` y el "óvalo" derecho; `sampleFrontDisk` (cara cercana) confinado a `|u|<2.7` para no cruzar la bóveda descendente; espina de cruce ancha y rota (no una línea recta fija); umbral de centinela alto en las LUT (sin "rim" punteado). Sin regenerar LUT. Iterado en vivo con `grim` en el workspace 9.
- **2026-09-04 · Gemini** — Corrección e integración del visualizador de música en el agujero negro (`MusicHole.qml`): 6 variantes reactivas en GPU con `QtQuick.Shapes`, reubicación real del horizonte (`bhFx: 0.84, bhFy: 0.12, rFrac: 0.28` desatascando el hardcodeo en `defaultConfig`), reloj de animación a 60fps desacoplado y nuevo target IPC `solarSystem` (`setMusicVariant`, `nextMusicVariant`) para probar en vivo.
- **2026-09-03 · Gemini** — Ajustes finos: reposicionada etiqueta Música, nuevo color Gemini (m3tertiaryFixed), anti-colisión vertical de etiquetas espaciales y mitigada regresión de CPU en Variantes 2/3.
- **2026-09-03 · Gemini** — Sistema Solar v3 (Variante D): Migrada la órbita de los soles al shader `solarfield.frag` para movimiento independiente fluido, y reemplazado el pintado de `Canvas` por satélite por un `Repeater` de `ShaderEffectSource` cacheado, alcanzando 100+ cuerpos a < 48% de CPU.

*Los agentes añaden una línea por sesión, lo más reciente arriba.*

- **2026-09-03 · Claude** — Sistema solar **v3 — rendimiento resuelto + agujero negro con detalle** (rama `feat/sistema-solar-v3`, sin mergear). Alberto: «va muy petado, hazlo más fluido». **Medido en limpio: 15,1 % → 4,7 % de un núcleo** (objetivo del diseño ≤5 %). El `ShaderEffect` a pantalla completa clavaba ~10 % de más porque cada píxel de 1920×1080 corría el bucle de prominencias de los dos soles + el fbm de turbulencia del disco, contribuyeran o no. Fix: cortes tempranos por distancia en `sun()` (>3,4r), `blackHole()` (>4,6R) y `starfield()` (lente sólo cerca del agujero); fbm 4→3 octavas; tic del shader 20→10 fps; posiciones 2→1 fps. Se probó bajar la resolución del shader (`layer.textureSize` 0,62x) y **no compensó** — revertido (D-14). Luego, el agujero negro del shader que se veía plano («cometa salmón»): **bandeado concéntrico de dos frecuencias + gradiente de temperatura real (blanco-caliente → ámbar → rojo profundo) con las alfas medias/exteriores subidas + anillo de fotones casi blanco en el lado Doppler + halo lensado más marcado** (D-15). Ahora lee como disco de acreción. El horizonte negro se ve poco porque la composición D lo saca de cuadro — acercarlo es decisión de composición de Alberto. Commits `ba7a4fa` (perf), `4b23c35` (agujero), + docs. Gotcha nuevo en el traspaso: `qs -c caelestia -n -d` tiene que ir SOLO en su llamada de shell o el daemon muere al arrancar. **Traspaso actualizado: `docs/sistema-solar-v3-ESTADO-Y-SIGUIENTE.md`.**

- **2026-09-03 · Claude** — Sistema solar **v3 (variante D) — diseño visual implementado**. Iterado en harness HTML con capturas headless hasta superar la calidad de la maqueta (`docs/sistema-solar-v3-mockup/harness-v3.html` + `v3-harness-{reposo,activo}.png`): agujero negro con todas las capas (§4.1: horizonte, anillo de fotones con Doppler, disco relleno multi-banda con gradiente de temperatura + turbulencia + beaming, lente sobre el horizonte, estrellas lensadas, jet), dos soles granulados (Laura primario con prominencias, Config secundario calmo), satélites de agentes/dispositivos, cinturón circumbinario. Portado a QML: `Sim.js` (motor de la composición D + bounding-box para interacción futura), `SolarSystem.qml` (Canvas estático cacheado + Canvas dinámico dimensionado a la caja del contenido, tic por Timer gateado a 3 fps en reposo), `SolarSystemModel.qml` (config v3, dispositivos→Config, agentes→Laura, LED fuera del dibujo, flag `showWallpaper`), `SolarSystemLayer.qml` (es EL fondo: `WlrLayer.Background` negro opaco), `Background.qml` (wallpaper apagado tras flag, widgets comentados, reloj a `Bottom`), `shell.qml`. Desplegado, **carga limpia** (`Configuration Loaded`, sin warnings QML nuevos), **1 instancia**. Hubo un bloqueo largo: el compositor perdió la asociación monitor↔GPU tras un hotplug de monitor externo (`grim` colgaba, ningún `Canvas` del shell pintaba; aislado con `qs -p` → el código descartado como causa). **Alberto reenchufó el equipo y se recuperó.** Con eso se perfiló la CPU: el agujero repintándose entero cada tic costaba ~22 % de shell con un agente en curso → **refactor a 3 Canvas** (estático / agujero a 1 de cada 3 tics / binario), cada uno a su caja; `fastRate` de música a ~7 fps (no 30 — el visualizador en tiempo real es posterior); `onValuesChanged/onConfigChanged` coalescidos. Coste final sobre la línea base del shell: **+~0.4 % reposo, +~4 % con agente, +~5 % música**. **Verificado en el escritorio real** (`docs/sistema-solar-v3-mockup/real-escritorio.png`), idéntico al harness. Después Alberto pidió: (1) que el movimiento no se pare nunca y sea imperceptible por frame → animar siempre + períodos x2-3 (`d0b5d44`); (2) **modo Laura activa** (D-12) — al hablarle a Laura todo se congela y oscurece y Laura brilla latiendo con la voz, cableado (`b81e5b5`); (3) **fondo entero a shader GLSL en GPU** (D-13) — `SolarField` + `solarfield.frag`, integrado (`e055cfd`, `954c08e`). El shader renderiza en el escritorio real (`real-shader-fondo.png`), composición correcta, soles bien. **Pendiente:** sigue lento (el ShaderEffect a pantalla completa cuesta ~+5-8 % en esta máquina multi-GPU) y el agujero negro del shader perdió detalle vs la versión Canvas. Alberto reinicia el equipo y abre sesión limpia. **Traspaso: `docs/sistema-solar-v3-ESTADO-Y-SIGUIENTE.md`.** Decisiones D-8..D-13 en spec §8 + nota del vault. Rama `feat/sistema-solar-v3` sin mergear.

- **2026-09-03 · Claude** — Sistema solar **v3**: brainstorming de composición cerrado. Alberto adelantó la v3 (escritorio vacío salvo el reloj, a pantalla completa, fondo negro). Elegida la **variante D** ([artifact 6935dde1 → ahora 0951108d](https://claude.ai/code/artifact/0951108d-14ed-46df-8a48-9264b32df0ab)): agujero negro «música» masivo y detallado en la esquina superior derecha saliéndose de cuadro, disco de acreción en diagonal; binario **Laura↔Configuración anclado** abajo-izquierda (Laura primario, agentes orbitan Laura; Config secundario, dispositivos conectados orbitan Config); cinturón de tareas circumbinario. Movimiento lento (sistema informativo). Descartada la deriva del binario alrededor del agujero (los blancos de info/clic deben estar donde el usuario los espera). Guardada la **visión B** como reserva en el vault. Preparada la rama `feat/sistema-solar-v3` (desde `refactor/background-modularize`) con los archivos y el traspaso completo: `docs/sistema-solar-v3-DISENO.md` (spec de composición + render + rendimiento) y `docs/sistema-solar-v3-PROMPT.md` (prompt para sesión limpia). **La implementación del diseño se hace en sesión nueva.** Aparte: confirmado que el fix de CPU de la v1.5 (`DesktopCircularMedia`) aguanta — shell a ~8 %, una sola instancia.

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
