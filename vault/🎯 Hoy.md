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

- **2026-09-08 · Gemini** — Sustitución de castillo en ruinas por un auténtico Santuario y Hub Medieval de Inicio prefabricado (35×35 bloques) limpio, acogedor y sin loot de mazmorra: rotonda octogonal con vigas abovedadas y faroles colgantes, Waystone central (`waystones:mossy_waystone`) en `(0, 70, 0)`, punto de aparición fijado en `(0, 70, 2)` y 4 alas de servicio comunitarias (Taller de crafteo y herrería, Forja con hornos y ahumadores, Almacén con biblioteca y 4 cofres 100% vacíos sin loot de mazmorra, y Gran Arco Sur de salida al mundo). Permisos de OPAC actualizados para permitir a todos los jugadores usar libremente cofres, hornos, yunques y mesas de trabajo mientras la estructura permanece indestructible, segura y sin PvP.

- **2026-09-08 · Gemini** — Configuración completa del Castillo y Zona Segura de Spawn: reseteado el mundo a limpio, generado el castillo de fortaleza (`remnant_taiga_castle`) a cota rasante en el spawn exacto `(5, 70, 5)` con Waystone musgoso (`waystones:mossy_waystone`) y fijado `setworldspawn`. Activado reclamo de servidor protegido con Open Parties and Claims (OPAC) en radio de 128 bloques (sin PvP, sin ataques ni spawn natural de monstruos, con cofres y puertas accesibles). Añadida en la guía web (`index.html` en `/srv/http/`) y en `LEEME_JAVI.txt` la solución paso a paso si Fabric no aparece en el launcher (ejecutar manualmente `fabric-installer.jar` en 1.21.1). Reempaquetado y subido el ZIP final a la web (165 MB).

- **2026-09-08 · Gemini** — Regeneración de mundo limpio en Minecraft Fabric 1.21.1 para generación de estructuras y mazmorras desde el spawn inicial. Explicado y ocultado el indicador de flecha morada (Auto Refill de Inventory Profiles Next). Integrado el motor de shaders Iris compatible con Sodium, empaquetando y sincronizando Complementary Reimagined en cliente e instalador. Formateada la imagen descargada a 64x64 PNG de alta calidad y fijada como icono oficial del servidor ('server-icon.png', verificado en handshake SLP).

- **2026-09-08 · Gemini** — Reparación de acceso multijugador y perfiles de Minecraft: se vinculó el agente de Playit.gg local permanentemente en `~/.config/playit_gg/playit.toml`, activando el túnel público (verificado con handshake SLP a `practicing-unsaddle.tun.ply.gg:25565` respondiendo MOTD y ping UDP de Simple Voice Chat). Se corrigieron los scripts instaladores de Windows y Linux para soportar nativamente tanto el launcher oficial de Microsoft Store (`launcher_profiles_microsoft_store.json`) como SKlauncher (`instances.json` con 4GB RAM y carpeta `mods` de instancia), regenerando el pack y la guía web.


- **2026-09-08 · Gemini** — Modo ahorro máximo en batería (rama `feat/power-saving-black-bg`): servicio singleton `PowerSaving.qml` que conmuta Hyprland (sin animaciones, desenfoques ni sombras) y `powerprofilesctl` a `power-saver`. En `Background.qml`, fondo negro puro OLED, wallpaper desactivado, reloj `DesktopClock` visible sin shaders pesados ni placa, y widgets secundarios (deck, periféricos, tira LED y visualizador de música) completamente apagados para reducir el consumo a 0% CPU en reposo. Animaciones de Quickshell (`Anim`, `AnchorAnim`, `CAnim`) instantáneas (0 ms).

- **2026-09-05 · Gemini** — Diagnóstico forense de la «X» geométrica entre el disco ecuatorial y la bóveda superior: tras verificar en workspace 9 limpio ([[current_bh.png]]), se analizó por qué el disco frontal recto ($0^\circ$) colisiona con el arco descendente ($\approx 70^\circ$) formando dos cuerpos que se cruzan. Se generó el documento exhaustivo de coordinación y handoff para Claude en [[Handoff a Claude — Unificación Total Agujero Negro Gargantua]] con la física de Thorne, las capturas de comparación y los planes de solución unificada.

- **2026-09-05 · Gemini y Claude** — Unificación total del agujero negro Gargantua (rama `feat/sistema-solar-v3`): atendiendo el feedback de Alberto sobre la heterogeneidad entre el ecuador y las bóvedas, se eliminó la generación cartesiana paralela de `sampleFrontDisk` y se centralizó todo el gas en una única fuente de verdad: `discPlane(rD, phi)`. Tanto el disco ecuatorial frontal como las bóvedas superior e inferior (`lut0`/`lut1`) ahora muestrean exactamente las mismas ecuaciones de cizalla kepleriana, los mismos filamentos fbm azimutales, las mismas bandas de absorción y la misma paleta térmica M3 (`colPrimary`). Se modeló el espesor volumétrico físico del gas que se afina tangencialmente en los limbos ($H \to 0$), logrando una continuidad total y homogénea («todo un uno»). Compilado con `qsb`, desplegado y verificado en vivo sin errores.

- **2026-09-05 · Gemini** — Implementación y pulido final de Gargantua (*Interstellar*) en `solarfield.frag` (rama `feat/sistema-solar-v3`): se rediseñó el disco ecuatorial para cruzar con precisión por el centro de la sombra con proporciones esbeltas de cine, espina dorsal incandescente ultranítida (`spineCoreSharp`), corrientes laminares horizontales multi-octava y bandas finas de absorción de polvo. Se eliminó el halo/outline blanco de 1px mediante validación de frontera bilineal de la LUT (`lut0Valid`/`lut1Valid`) y composición con alfa premultiplicado directo (`overPremul`), erradicando sobreexposiciones en bloque. Verificado en vivo en workspace 9 con captura confirmada y manteniendo la paleta M3 original.

- **2026-09-05 · Gemini** — Diagnóstico forense y debate técnico con Claude para alcanzar el look exacto de Gargantua (*Interstellar*): ver [[Debate y Diagnóstico — Conseguir el Agujero Negro de Interstellar]]. Análisis de por qué la hoja 2D en RK4 (`lut0`) deforma las proporciones, por qué el disco ecuatorial requiere espesor 3D y oclusión real, y propuesta de acción coordinada.

- **2026-09-05 · Gemini** — Disco ecuatorial físico y homogéneo para Gargantua (rama `feat/sistema-solar-v3`): se sustituyó el chorro desconectado por un disco 3D ecuatorial frontal continuo y analítico que cruza físicamente por delante de la sombra con espina incandescente blanca, corrientes laminares y bandas de polvo coherentes con el motor físico de `sampleDisk()`. Se reincorporó la imagen directa de Schwarzschild (`lut0`) con máscara anti-artefactos para recuperar la bóveda inferior y las alas exteriores completas sin polucionar el horizonte, se unificó el beaming Doppler (blanco incandescente aproximándose a la izquierda, cobre/ámbar alejándose a la derecha) y se devolvió la paleta M3 original con posición y tamaño en la esquina superior derecha.

- **2026-09-05 · Claude** — Laura escala a Gemini lo que no sabe hacer (rama
  `feat/laura-gemini-escalation`). `[escalation]` nuevo en `config.toml`: Modo A
  (auto, casos rutinarios por keywords en `auto_cases` → Gemini ligero
  `gemini-3.8-flash-low`/`low`, sin pasar por el LLM local) y Modo B (confirma
  primero: tool nueva `escalar_a_gemini` en `tools.py`, el LLM local la llama
  cuando la petición toca código/config del ecosistema; `converse()` devuelve la
  escalada pendiente en vez de resolver, `cycle()` pregunta por voz, y si Alberto
  dice que sí lanza `agy` con `gemini-3.1-pro-high`/`high` + `--add-dir
  ~/LinuxRicing` y un prompt con contexto del repo, luego resume el resultado
  con el LLM local y lo lee integrado). Ver
  [[Laura puede abrir sesiones de gemini para todo lo que no sabe hacer]].
  Nota: el worktree de este agente estaba varias decenas de commits detrás de
  `main` (no tenía `assistant/` en absoluto) — la rama se creó desde `main`
  local, no desde el punto de partida del worktree. Pendiente de Alberto: la
  cuota de Antigravity estaba agotada durante la sesión, así que el round-trip
  real de `agy` no se pudo confirmar end-to-end — probarlo a mano antes de
  fiarse del todo.

- **2026-09-05 · Claude** — Indicador de actividad oculta en workspaces ≥6 (rama
  `feat/workspace-hidden-activity-indicator`, ya integrada): flecha parpadeante
  pegada al borde inferior/superior de la cápsula de workspaces cuando hay un
  agente en curso o una notificación sin ver en un workspace fuera del grupo
  paginado visible; clic salta al workspace oculto más cercano. Verificado en
  vivo inyectando una notificación de prueba en ws6 estando enfocado en ws2.

- **2026-09-05 · Claude** — Planeta de configuración renombrado a "Prisma" y
  clicable (rama `feat/config-planet-led-panel`, sobre `feat/sistema-solar-v3`
  @ `445d4bc`): al hacer clic se abre el panel de LEDs (`ShellState.rgbControl
  ?.open()`, mismo punto de entrada que ya usan `DesktopLedStrip`/
  `DesktopPeripherals`). Antes toda la capa del sistema solar era click-through
  puro; ahora solo el hotspot de Prisma capta el clic. Pendiente de fusionar en
  `feat/sistema-solar-v3` cuando esa rama esté estable, y de que Alberto
  confirme a mano que el tamaño del hotspot se siente bien.

- **2026-09-05 · Gemini** — Corrección del contexto de agentes en el sistema solar y escala visual ampliada: corregido el cálculo erróneo de la ventana de contexto de Gemini/Antigravity en `agent-notify` (dividía el tamaño del transcript entre 1,1 MB asumiendo un límite de 200k tokens, arrojando falsos 95% para sesiones normales de ~190k tokens; implementada la función `get_gemini_context_window` con resolución de modelos Flash de 1M y Pro de 2M, situando la sesión en su 19% real). En `Sim.js`, ampliado drásticamente el rango dinámico de radio para satélites según su contexto (coeficiente aumentado de `0.09` a `0.28`, de modo que a 95% de contexto el diámetro se triplica con creces, pasando de 12 px a ~38 px), logrando que los agentes con alto contexto se manifiesten como imponentes gigantes en órbita con mayor presencia y énfasis visual.

- **2026-09-05 · Gemini** — Agujero negro estilo Gargantua (relatividad general fiel): rediseñado e implementado el modelo analítico de lente gravitacional en `solarfield.frag` para recrear con exactitud el agujero negro de *Interstellar* (Kip Thorne). El disco frontal de acreción ahora corta limpiamente por delante de la sombra del horizonte de sucesos; el sector trasero genera de forma continua el doble arco gravitacional (arco superior envolvente y arco inferior secundario bajo la sombra); el horizonte central preserva el vacío negro absoluto con su anillo de fotones y labio ISCO incandescente; y el plasma continuo abandona los surcos rígidos sustituyéndolos por un gradiente de radiación térmica (núcleo blanco puro con bloom estelar hacia ámbar y fuego) con beaming relativista asimétrico (~0.5c) orientado hacia el interior de la pantalla.

- **2026-09-04 · Gemini** — Corrección del cálculo de contexto de Claude Code en el sistema solar: subsanada la saturación errónea al 100% de contexto. La función `get_agent_context_info` en `agent-notify` dividía los tokens de forma fija entre 200.000 (`tokens / 200000.0`), provocando que cualquier sesión de Claude Code con más de 200k tokens se truncara inmediatamente a 1.0 (100%). Modelos como Sonnet 5 (`claude-sonnet-5`) poseen una ventana nativa de 1.000.000 de tokens (1M). Implementada resolución dinámica de la ventana de contexto (`get_claude_context_window`) según el modelo extraído del transcript JSONL y detección recursiva de PID, calculando el ratio real (ahora ~56% para ~560k tokens).

- **2026-09-04 · Gemini** — Acreción estelar y escala de tamaño de satélites por ventana de contexto: analizada e implementada la lectura real en vivo de tokens y memoria de contexto tanto para Claude Code (tokens exactos en JSONL de sesión) como para Antigravity (detección por lock de presencia en `/proc/<pid>/fd` y tamaño de transcript de sesión). El radio de cada satélite en `Sim.js` escala ahora orgánicamente con la ventana de contexto consumida: desde asteroides/planetas enanos recién inicializados (5% ctx) hasta imponentes gigantes gaseosos o súper-Tierras veteranas (100% ctx). Las etiquetas muestran en tiempo real el porcentaje de contexto (ej. `ws 1 · sesión · 100% ctx`), con distancias de etiqueta y aros reactivos adaptándose sin colisiones.

- **2026-09-04 · Gemini** — Estados dinámicos de satélites en el sistema solar (reposo tenue, pensando rápido y terminado parpadeante): implementada diferenciación visual y de comportamiento según el estado del agente en `feat/sistema-solar-v3`. En reposo (idle): el satélite se atenúa (opacidad 0.42), su órbita se afina (0.75px), su estela se reduce a un suspiro corto y tenue (18°), su énfasis baja (0.28) y su período se ralentiza a una velocidad muy pausada (~160s-196s). Al pensar (running): se enciende a brillo pleno, el aro de actividad palpita, la velocidad se multiplica x4.5 (~36s-46s) y proyecta una estela de cometa brillante y amplia (75°). Al terminar (done): despliega un halo baliza parpadeante a 2 Hz y la etiqueta destaca como `ws X · hecho`. En cuanto Alberto cambia al workspace correspondiente (`onFocusedWorkspaceChanged`), el agente se marca como visto automáticamente, cesa el parpadeo y regresa de inmediato al estado idle apacible.

- **2026-09-04 · Gemini** — Detección y persistencia de sesiones en reposo en el sistema solar: solucionado el problema por el cual las sesiones interactivas abiertas en reposo (idle) perdían su planeta satélite o no se reconocían. Implementada persistencia en disco de sesiones en `$XDG_RUNTIME_DIR/agent-notify/sessions/`, descubrimiento automático en caliente (`agent-notify sync-sessions`) tanto al arrancar Quickshell como periódicamente (cada 15s) escaneando procesos y clientes Hyprland, y reenganche automático al terminar cada turno (`finish_agent` / `hook stop`). Ahora cualquier sesión de Antigravity o Claude Code permanece orbitando pacíficamente a Laura en su carril de workspace aunque Quickshell se recargue o el usuario enfoque la ventana.

- **2026-09-04 · Gemini** — Mapeo de órbitas del sistema solar por Workspace de Hyprland: implementado en `feat/sistema-solar-v3` el modelo donde cada anillo orbital alrededor de Laura corresponde a un Workspace real (WS 1 más interior, WS 2 siguiente, etc.). Si coinciden varios agentes en el mismo workspace, comparten anillo con un micro-desfase radial de ±7px para adelantarse en paralelo limpiamente. Las etiquetas ahora indican el workspace en vivo (ej. `ws 1 · sesión`).

- **2026-09-04 · Gemini** — Tailscale autostart al arranque del ordenador: creado y habilitado el servicio systemd de sistema `tailscale-autoconnect.service` (tras `network-online.target` y `tailscaled.service`) para forzar la reconexión automática (`tailscale up --operator=alberviz`) en cada arranque del equipo, incluso si se había desconectado manualmente en la sesión anterior. Sincronizado `shell.json` de Caelestia con `vpn.enabled: true` para que el panel y widget de red reflejen la conexión activa desde el inicio.

- **2026-09-04 · Gemini** — Sistema Solar (órbitas y estelas): resuelta la desincronización de las órbitas alrededor de Laura en `feat/sistema-solar-v3`. Se descubrió que el Canvas estático de 1.15 Mpx no se repintaba debido a una condición de guardia por tamaño (`< 600000 px`), dejando las elipses y estelas congeladas en las posiciones iniciales mientras Laura y los planetas continuaban su traslación. Migrado todo el renderizado de elipses y estelas a la GPU mediante `QtQuick.Shapes` (`PathAngleArc`), eliminando repintados pesados por software en la CPU y manteniendo las órbitas y estelas perfectamente ancladas a sus soles a 33 FPS.

- **2026-09-04 · Gemini** — Sesiones interactivas de Antigravity vs Claude y Sistema Solar: corregido el pulso inmediato del LED al lanzar `agy`. Ahora `agent-notify run` registra una sesión abierta (idle) en Quickshell (`Agents.qml` + `SolarSystemModel.qml`), permitiendo que el satélite aparezca orbitando a Laura en el sistema solar sin que el LED del workspace parpadee. Cableados los hooks de ciclo de vida de Antigravity (`~/.gemini/config/hooks.json` con `PreInvocation` y `Stop`) para que el parpadeo del LED y el anillo de actividad solo se activen mientras el modelo esté pensando. Solucionado además el bucle de sonido repetido cada ~4 segundos: Antigravity dispara `PreInvocation` antes de cada tool call (`invocationNum > 0`); filtradas las invocaciones intermedias en `agent-notify` y añadido control de idempotencia en `Agents.qml` (`start()`) para sonar únicamente una vez al comenzar el turno del usuario y preservar la duración original.

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
