# Sistema solar binario — plan de desarrollo

> Maqueta visual e interactiva del plan (recomendado abrirla):
> https://claude.ai/code/artifact/0cf6374a-85f0-4f6a-8003-3aae212b33b1
>
> **Iteración v1.5 (2026-09-02)** — rediseño de disposición + cambio de ratón +
> preview de la v2: https://claude.ai/code/artifact/6935dde1-72c3-4ba1-8c87-c907f7ba8561

## Cambio de dispositivo: MCHOSE M8 → K7 Ultra (2026-09-02)

El ratón pasó a ser el **MCHOSE K7 Ultra con Base 8K**. La base es a la vez
receptor RF y un **anillo LED direccionable por firmware** (`rgb-config` →
`mchose_base`). Para el sistema solar eso significa:

- **«La tira LED» ya no es una:** son tres cuerpos LED — MagicHome, la tira
  lateral del Akko y el **anillo de la base del K7 Ultra** — orbitando el sol de
  configuración.
- **Batería del ratón:** telemetría real por `mchose-battery --json` (cmd `0x06`).
  Al acoplarse a la base, `charging = true` → el planeta ratón podría contraer su
  órbita hacia el sol («en casa»).
- El **LED del cuerpo** del ratón (distinto de la base) sigue sin caracterizar
  (`target 0x06` vs `0x07`); hasta que se resuelva, no aparece (principio 5).

Fuente canónica del protocolo: `hardware/mchose-k7-ultra/`.

## Qué es

La columna de widgets del escritorio (Periféricos, Mis tareas, Iluminación
Ambiente) se retira y se sustituye por un **sistema estelar binario** en la capa
del fondo:

- **Sol música** — dominante, siempre visible, movido por `Audio.cava` +
  now-playing. Séquito cercano (órbita **tipo-S**): tira LED, los tres
  periféricos (auriculares, ratón, teclado) y, en la v3, clima y ambiente.
- **Sol Laura** — siempre en el cielo pero **tenue y girando lento** mientras no
  se interacciona; se aviva y acelera al hablarle o al abrir un terminal.
  Séquito cercano (tipo-S): los **astros-terminal**, uno por sesión de Claude /
  Antigravity, con estado real de `Agents.qml`.
- **Circumbinario (tipo-P)** — gira alrededor de los dos soles: el **cinturón de
  tareas** (recuento del backlog).

El color de cada cuerpo sale de la paleta del wallpaper (`Colours.palette.m3*`):
cada cuerpo referencia un **rol** (primario/secundario/terciario…), nunca un hex
fijo, así que cambiar de fondo re-colorea todo el sistema.

## Principios

1. **Glanceable → hover → clic.** En reposo el cuerpo ya dice su estado con
   color, brillo y tamaño. El hover añade el número exacto. El clic actúa.
2. **Calmo por defecto.** Un cuerpo inactivo se oscurece y su órbita se
   ralentiza. La atención se gana con brillo y velocidad.
3. **Congelar al acercarse.** Al entrar el puntero en la región del sistema, las
   órbitas frenan y las etiquetas se despliegan; al salir, se reanuda.
4. **Los widgets se quedan hasta que haya confianza.** La columna izquierda es la
   fuente de verdad durante v1 y v2. Solo se retira en la v3.
5. **Cero telemetría inventada.** Un cuerpo sin señal real o se omite o es
   decorativo (y se documenta). Nunca un número de batería falso.

## Reproducibilidad fuera de Caelestia

- **Nivel 1 (cualquier config de Quickshell): sí.** El módulo no toca
  `Colours.palette` ni `mchose-battery` directamente — van detrás de adaptadores
  y una paleta inyectada como propiedad.
- **Nivel 2 (el núcleo re-portable): `SolarSim`.** La simulación pura (cuerpos +
  tiempo → posiciones y parámetros visuales) vive en un archivo sin dependencias
  de Quickshell.
- **Nivel 3 (eww/AGS/waybar como código compartido): no.** Se porta el concepto y
  el `SolarSim`, no el módulo.

## Versiones

| Ver | Título | Dificultad | Objetivo |
|-----|--------|-----------|----------|
| **v1** | Estrella binaria de solo lectura | 5/10 | El sistema existe en el escritorio, movido por señales reales baratas. Sin interacción. Widgets intactos. |
| **v1.5** | Disposición completa + cambio de ratón | 3/10 | ✅ 2026-09-02. Adaptadores reales de batería (3 periféricos) y LED (3 zonas); cuerpos del K7 Ultra; 5 bugs de la v1 corregidos; `SolarSystemLayer` cableada al shell. Disposición música-sol-vs-agujero-negro **pendiente de Alberto** (ver artifact 6935dde1). |
| **v2** | Interacción: hover, clic, congelar | 5/10 | Panel de detalle al pasar el ratón; clic para encender la LED / abrir tareas / enfocar un terminal (`Agents.focus`). Entrada real en la capa Background. |
| **v3** | El gran refactor: fuera los widgets | 4/10 · punto de no retorno | Ni un widget salvo el reloj. El dashboard conmutable se elimina y se reconvierte en el sistema a pantalla completa. |
| **v4** | Astros-terminal con vida propia | 6/10 | Sub-lunas = subagentes; anillo = actividad del turno; conjunción / eclipses por git. |
| **v5** | Momentos y pulido | 4/10 · opcional | Modo conjunción de Laura, cometa de build, modo "sábado". |

### Adiciones opcionales (sin versión asignada)

- **Planeta del homelab** — un cuerpo que informa del estado de la Raspberry Pi
  (servicios arriba/abajo, carga). Requiere un heartbeat de la Pi. Opcional.
- ~~Planeta de Windows~~ — descartado.

## Arquitectura

- **`SolarSim`** — simulación pura, sin dependencias de Quickshell. Dado
  `{ id, kind, host, orbit, phase, activity, alert }` + tiempo → posiciones y
  parámetros visuales. `host` = música / laura / circumbinario.
- **`SolarSystem.qml`** — la vista: `Canvas` (FBO) o `ShaderEffect`, entrada,
  tema. Depende solo del núcleo de Quickshell + paleta inyectada.
- **`SolarSystemService.qml`** (singleton) — el modelo de datos. Expone
  `property var bodies`; cada adaptador actualiza su trozo.
- **`adapters/`** — `MusicAdapter`, `BatteryAdapter`, `AgentsAdapter`,
  `TasksAdapter`, `LedAdapter`, `WeatherAdapter`. Pasar de v1 a v4 solo añade
  adaptadores.

### Estado de los adaptadores tras la v1.5

Todos viven todavía dentro de `SolarSystemModel.qml` (no en archivos separados);
factorizarlos a `adapters/` es limpieza pendiente, no bloqueante.

| Adaptador | Fuente | Señales |
|-----------|--------|---------|
| Música | `Audio.cava` + `Players` | `music` (0..1), `musicPlaying` |
| Agentes | `Agents.qml` | ancla `laura` viva; un cuerpo por terminal (`term:<id>`) |
| Tareas | `grep estado: pendiente` en `vault/Backlog` cada 60 s | `tasks` (0..1) |
| Batería | `rgb/mchose-battery --json` cada 30 s | `batt:<headset\|mouse\|keyboard>`, `battLow:*`; cuerpo dinámico solo si conectado |
| LED | `RgbConfig.devices` | `led:<magichome\|akko\|base>` (1 si la zona la gestiona el sync de tema) |

Los cuerpos de periférico son **dinámicos**: `_deviceBodies()` solo emite los
conectados. Un periférico sin señal real no se pinta (principio 5).

## v2 — plan de implementación (rama `feat/sistema-solar-v2`)

La v2 **necesita iteración en vivo con Alberto** (tamaño de las hit-areas, tacto
del frenado, que el clic haga lo correcto). No se implementa a ciegas. El camino:

1. **Región de input, no toda la pantalla.** `SolarSystem.qml` expone el
   bounding-box del layout (`layout.bounds`). `SolarSystemLayer` pone
   `mask: Region { item: … }` solo sobre esa caja + margen. Fuera de ahí, la capa
   sigue siendo click-through. Un flag `SolarSystemModel.interactive` (por
   defecto **false**) activa todo esto — un fallo nunca atrapa el puntero.
2. **Congelar al acercarse.** `HoverHandler` sobre la región → `hovered`. En
   `Sim.js`, un factor `freeze` 0..1 multiplica todas las velocidades orbitales
   (a ~0.15 cuando `hovered`), con un `Behavior` de 400 ms. Al salir, se reanuda.
   Mientras `hovered`, el `Timer` sube a `fastRate` aunque no haya música (hay
   que repintar el frenado).
3. **Cuerpo más cercano al puntero → panel.** El sim ya calcula posiciones; el
   más cercano dentro de un radio gana. Panel QML (`Item` + `StyledRect`) anclado
   a su posición, con el detalle del adaptador correspondiente (batería exacta y
   modo; lista de tareas; color/efecto de la LED; `task`/`dir`/workspace del
   astro-terminal).
4. **Clic → acción.** `TapHandler` por cuerpo: LED → `mchose-lighting` /
   `magichome-control` + abrir selector; tareas → abrir `🎯 Hoy.md`; sol música →
   `Players.active.togglePlaying()`; astro-terminal → `Agents.focus(address)`
   (ya existe). Recorrido por teclado como extra.

Se cierra cuando Alberto usa el sistema una semana para ver batería, enfocar un
terminal y encender la LED sin echar de menos los widgets.

## Ramas

- `feat/aurora-voice-assistant` → **`main`** (hecho).
- **`feat/sistema-solar`** — rama paraguas.
- **`feat/sistema-solar-v1`**, `-v2`, … — una sub-rama por versión, se mergea de
  vuelta a la paraguas al cerrar.

## Coordinación

El overlay de voz de Laura (rama `feat/aurora-voice-assistant`, ahora en `main`)
lo lleva otro agente: `WlrLayer.Overlay` a pantalla completa con una barra de luz
en el **borde inferior** (~130px) + píldora de subtítulos, visible solo mientras
Laura está activa. El sistema solar (capa `Background`, debajo) **deja libre la
franja inferior** (~200px) para no pisarse. A largo plazo la barra de luz de
Laura y el "Sol Laura que emerge desde abajo" son el mismo gesto y pueden
unificarse.

## Pruebas

Las hace Alberto en vivo al cerrar cada versión. Sin tests automáticos.
