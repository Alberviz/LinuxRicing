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
- **2026-09-08 · Claude** — Recuperado el botón "Cargar al 100%" del popout de batería (se había perdido: nunca estuvo en git) y añadido uno para apagar el fondo del espacio a mano. El control de batería Lenovo (`~/.local/bin/lenovo-battery-control` + regla udev + `.desktop`) ahora está versionado en `widgets/`, `configs/udev/`, `configs/applications/` y lo despliega `install.sh`. `SolarSystemModel.enabled` se persiste en `~/.config/caelestia/desktop-state.json` e IPC `solarSystem toggle`; en OFF el `SolarSystemLayer` descarga el `SolarSystem` (igual que en ahorro) pero sin tocar CPU ni Hyprland. Todo en `feat/sistema-solar-v3` (`3431731`, `d817916`). Pendiente: redesplegar + instalar la regla udev con sudo.
- **2026-09-08 · Claude** — Diagnóstico "se fue el agujero negro": no fue git, fue despliegue. La rama `refactor/background-modularize` **nunca** tuvo el sistema solar (vive sólo en `feat/sistema-solar-v3`); el agente de Gemini implementó el modo ahorro (`adbcd91`) sobre esa rama y al desplegar sobrescribió el `Background.qml` desplegado —el del sistema solar— por el modularizado sin `SolarSystemLayer`, dejando `~/.config/quickshell/caelestia/solarsystem/` huérfano. Nada perdido. Reintegrado el modo ahorro sobre `feat/sistema-solar-v3` (commit `600f238`): `PowerSaving.qml` + gates; en ahorro el `SolarSystemLayer` **descarga** el `SolarSystem` entero vía `Loader.active` (shader + Canvas + FrameAnimation), queda sólo la ventana negra. Pendiente: redesplegar desde esta rama.
- **2026-09-05 · Claude** — Agujero negro Gargantua: eliminada la "X" del limbo — el disco ecuatorial y las bóvedas lensadas ya son **un solo cuerpo** (`solarfield.frag`, rama `feat/sistema-solar-v3`, commit `5fbc679`). `lensLUT0` se dibuja en todo su dominio con una única `discPlane()` (cara lejana + cuenco + arco superior = un campo geodésico continuo, C¹); `lensLUT1` al mismo brillo que el cuerpo para que la bóveda no flote aparte; fuera `crescentMask` y el "óvalo" derecho; `sampleFrontDisk` (cara cercana) confinado a `|u|<2.7` para no cruzar la bóveda descendente; espina de cruce ancha y rota (no una línea recta fija); umbral de centinela alto en las LUT (sin "rim" punteado). Sin regenerar LUT. Iterado en vivo con `grim` en el workspace 9.
- **2026-09-04 · Gemini** — Corrección e integración del visualizador de música en el agujero negro (`MusicHole.qml`): 6 variantes reactivas en GPU con `QtQuick.Shapes`, reubicación real del horizonte (`bhFx: 0.84, bhFy: 0.12, rFrac: 0.28` desatascando el hardcodeo en `defaultConfig`), reloj de animación a 60fps desacoplado y nuevo target IPC `solarSystem` (`setMusicVariant`, `nextMusicVariant`) para probar en vivo.
- **2026-09-03 · Gemini** — Ajustes finos: reposicionada etiqueta Música, nuevo color Gemini (m3tertiaryFixed), anti-colisión vertical de etiquetas espaciales y mitigada regresión de CPU en Variantes 2/3.
- **2026-09-03 · Gemini** — Sistema Solar v3 (Variante D): Migrada la órbita de los soles al shader `solarfield.frag` para movimiento independiente fluido, y reemplazado el pintado de `Canvas` por satélite por un `Repeater` de `ShaderEffectSource` cacheado, alcanzando 100+ cuerpos a < 48% de CPU.

- **2026-09-27 · Gemini** — Modo Ahorro Extremo de batería y refresco 60Hz (rama `feat/extreme-battery-saving`): 1) Resuelto el fallo de cambio de refresco (Hyprland Lua requiere `hyprctl eval` en vez del clásico `keyword`), conmutando automáticamente la pantalla de 144Hz a 60Hz en batería y restaurando a 144Hz en corriente; 2) Desactivado autoinicio de Mailspring (ahorrando >500MB de RAM y ciclos GPU de Electron); 3) Creado `/usr/local/bin/caelestia-power-root` y `widgets/caelestia-power-tweaks` (`~/.local/bin/caelestia-power-tweaks`) que desactivan Intel Turbo Boost (`no_turbo=1`), activan WiFi Power Save, Audio Power Save y suspenden la dGPU NVIDIA (`suspended` / 0W); 4) Parada de daemons de fondo en batería (`argb-wave`, `laura`, `minecraft-telegram-bot` y OpenRGB/LEDs apagados); 5) Solucionado problema de desconexiones periódicas de Bluetooth: desactivado el autosuspend agresivo USB del adaptador Intel AX201 (`options btusb enable_autosuspend=0`, udev rule y `power/control="on"`), evitado que reloads de Hyprland apaguen la radio, y blindado el apagado de Bluetooth para no ejecutarse si hay periféricos conectados (ratón MCHOSE K7 Ultra); 6) Integrado y orquestado reactivamente en `PowerSaving.qml`, sincronizado a `~/.config/quickshell/caelestia/` y verificado en vivo.

- **2026-09-24 · Gemini** — Desactivación de Laura en batería / modo ahorro: 1) En `assistant/laura.service`, añadida la directiva `ConditionACPower=true` para omitir completamente el arranque del servicio al iniciar el sistema con batería (0 RAM, 0 VRAM y 0 W consumidos al encender desenchufado); 2) En `PowerSaving.qml`, parada reactiva automática del servicio `laura.service` al desconectar la corriente o entrar en perfil `power-saver`, y reanudación limpia al reconectar a corriente AC; 3) En `assistant/laura-toggle`, detección de estado de batería/ahorro y notificación descriptiva («Laura en reposo») al pulsar Super+A si el asistente está apagado por ahorro; 4) Verificado ciclo completo, liberación de ~1.5 GB de memoria y recargado Caelestia Shell.

- **2026-09-14 · Gemini** — Reconciliación de la rama `feat/wifi-panel-fixes` con PRs upstream #1869 y #1881 de `caelestia-dots/shell`: 1) En `NetworkConnection.qml`, eliminada la bifurcación `hasSavedProfile` para pasar siempre por `connectToNetworkWithPasswordCheck`, permitiendo que nmcli pruebe primero el perfil guardado y solo pida contraseña si falta o falla (PR #1869); 2) En `Nmcli.qml`, añadidas `listWifiProfiles`, `deleteProbeLeftovers` y `probeCleanupTimer` para purgar automáticamente perfiles temporales/fantasma creados tras sondeos fallidos sin secretos (PR #1881), y eliminadas funciones obsoletas (`createConnectionWithPassword`, `connectionParamBssid`); 3) En `NexusState.qml`, método `openPasswordPage` idempotente contra múltiples llamadas concurrentes de `needsPassword` y limpieza de `pendingNetwork` en `ConnectPasswordPage.qml` al cerrarse; 4) Simplificado el `onClicked` de `NetworkList.qml` a una única ruta unificada. Verificado y recargado Quickshell limpiamente.

- **2026-09-14 · Gemini** — Arreglo de perfiles WiFi rotos/secretless y resolución de perfiles con sufijos automáticos (rama `feat/wifi-panel-fixes`, basado en issue #1934 de caelestia-dots/shell): 1) Mapeo de SSID a nombre real de conexión (`savedSsidToName`) en `Nmcli.qml` y función `savedProfileNameFor()` para resolver nombres como "SSID 1" en `forgetNetwork` y activación; 2) En `NetworkConnection.qml`, activación de perfiles guardados directamente con `Nmcli.activateConnection` ("nmcli connection up") en vez de crear perfiles duplicados; 3) Detección de fallos por falta de secretos en `activateConnection` y `CommandProcess`, eliminando el perfil roto y abriendo el diálogo de contraseña para recuperar la red atascada. Verificado con recarga de shell sin errores.

- **2026-09-14 · Gemini** — Arreglo integral del subsistema de conexión WiFi en Caelestia (rama `feat/wifi-panel-fixes`): implementadas las 4 tareas del diagnóstico. 1) En el Popout rápido de la barra, persistencia de `passwordNetwork` en `PopoutState` para no perder la referencia de la red al cambiar el Loader a la vista `wirelesspassword`. 2) Sustituido el campo artesanal de puntos (`charList` + `passwordContainer`) en `WirelessPassword.qml` por `StyledTextField` con `echoMode: TextInput.Password` y `Layout.fillWidth`, eliminando el desbordamiento visual en claves largas. 3) En el backend `Nmcli.qml`, sustituido el pinning forzado a BSSID y `wpa-psk` por `nmcli device wifi connect` estándar que autonegocia WPA2/WPA3, ampliado el timeout a 13s y corregido el callback vacío en éxito. 4) En el Centro de Control Nexus, creada la subpágina `ConnectPasswordPage.qml` (registrada en `PageCompRegistry.qml`) y conectado `NetworkList.qml` para abrir el diálogo de contraseña en redes no guardadas; en `AddNetworkPage.qml`, corregido el anclaje `anchors.fill: parent` del campo de contraseña, desactivado el modo oculto por defecto (`checked: false`) y retirado el borrado prematuro del perfil.

- **2026-09-10 · Claude** — Botón "Server mode" en *Quick Toggles* de Caelestia (rama `feat/modo-servidor-consola`): un escalón por encima del `PowerSaving.qml` automático — cierra el entorno gráfico entero (`systemctl isolate multi-user.target`) para dejar el portátil en consola pura durando lo máximo en batería con el servidor de Minecraft abierto. Confirmación por **mantener pulsado ~1 s** (componente `HoldToggle` con anillo `CircularProgress` que se rellena; un toque suelto no hace nada) → `services/ServerMode.qml` (singleton + `IpcHandler`) lanza `caelestia-server-mode on` por ruta absoluta (Quickshell no tiene `~/.local/bin` en el PATH): perfil `power-saver`, para servicios cosméticos (`openrgb`, `argb-wave`, `battery-lighting`, `laura`, `mchose-audio-cleanup`, `ydotool`, `appimagelauncherd`) y procesos sueltos (`sync-rgb.py`, `mchose-battery`, `magichome-control`, `desktop-deck-helper`, `gtasks`), `rfkill block bluetooth`, LEDs a negro. Las ops privilegiadas van por `caelestia-server-mode-root` (helper de 4 verbos fijos, NOPASSWD acotado en `/etc/sudoers.d/`). No se tocan `minecraft-server.service`, el bot (ambos bajo `user@1000` con linger), `playitd` ni el WiFi. Vuelta: `volver-escritorio`. Diseño en `docs/plans/2026-09-10-modo-servidor-consola.md`.

- **2026-09-09 · Gemini** — Arreglo del botón de fondo negro y limitación del fondo a 60 fps (rama `feat/sistema-solar-v3`): se corrigió `SolarSystemModel.qml` exponiendo `toggle()` en el singleton raíz para que el botón del popout de batería funcione al instante. Para erradicar los tirones en monitores de 144 Hz en GPU integrada, se implementó un limitador de cadencia (`targetFps: 60`, configurable por IPC y persistido en `desktop-state.json`) en `SolarSystem.qml` con acumulador de tiempo real, reduciendo un 58% la carga del shader en la iGPU Intel y espaciando el recálculo orbital a 30 fps. Se optimizó además `Agents.qml` para evitar mutar `root.sessions` si los datos no cambian, anulando las tormentas de invalidación reactiva que ocurrían cada 15 s.

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
