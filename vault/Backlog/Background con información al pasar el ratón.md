---
fileClass: Backlog
tipo: tarea
estado: pendiente
prioridad: 5
area: escritorio
origen: Alberto
esfuerzo: L
creado: 2026-09-05
tags:
  - backlog
---

# Background con información al pasar el ratón

Nueva versión del fondo de escritorio (`configs/quickshell/caelestia/modules/background/`)
en la que **pasar el ratón por encima de un elemento revela información** sobre él (en
vez de, o además de, requerir clic).

## Decisión de alcance de esta sesión: solo planificación, sin implementar

Revisado el módulo (`Background.qml` + `Desktop*`, `Deck*`, `DeviceItem`, `TaskRow`,
`Visualiser.qml`, etc.): **ningún componente usa hoy `HoverHandler` ni
`hoverEnabled`** — la interacción actual es 100% por clic (`onClicked` en
`DeckFocusCard`, `DesktopLedStrip`, `DesktopPeripherals`, `DesktopMedia`, `TaskRow`,
`DeviceItem`...). Esto es, por tanto, una decisión de **diseño visual desde cero**, no
un añadido incremental sobre algo ya existente.

Se deja **solo planeada** (arquitectura + puntos de enganche) en vez de implementada,
por tres motivos:
1. Es la **prioridad más baja** de las 6 tareas de esta sesión (ver reparto en
   [[🎯 Hoy]] / bitácora del 2026-09-05).
2. Al no existir ningún patrón de hover previo, es una **decisión visual real** (qué
   aparece, dónde, con qué transición, qué tan intrusivo es) — encaja con la
   preferencia ya conocida de Alberto de **ver maquetas/variantes antes de que un
   agente decida por su cuenta el aspecto** de algo así, no en encajarlo a ciegas
   durante una sesión autónoma sin él delante.
3. En esta misma sesión hay **otro agente editando en vivo** archivos de
   `background/` (T5, click del planeta de configuración → panel de LEDs), en su
   propio worktree — añadir aquí una implementación real subiría el riesgo de
   solapamiento al integrar, para una tarea que el propio Alberto marcó como
   "el alcance lo decides tú, puede quedarse en planificación".

## Arquitectura propuesta (para cuando se implemente)

- **Overlay de información desacoplado del elemento**, no tooltip nativo de Qt: un
  único componente `HoverInfoPanel.qml` en `background/`, instanciado una vez en
  `Background.qml`, que se posiciona y rellena mediante un modelo compartido
  (`hoverTarget: { title, subtitle, details, anchorItem }`) en vez de que cada
  `Desktop*`/`Deck*` dibuje su propio popup — así el estilo (blur, borde, animación de
  entrada) se mantiene consistente en todos los elementos con una sola implementación.
- Cada componente hovereable expone un `HoverHandler` que, en `onHoveredChanged`,
  escribe en ese modelo compartido (vía una señal o un singleton tipo `ShellState`) en
  vez de gestionar su propio overlay — mismo patrón desacoplado que ya usa
  `ShellState.rgbControl` para el panel de LEDs.
- **Debounce de entrada** (~150-200 ms) antes de mostrar el panel, para que pasar el
  ratón de refilón no dispare parpadeos de información; salida más rápida o instantánea.
- Candidatos naturales a llevar información en hover, según lo que ya existe: satélites
  del sistema solar (agente/tarea/workspace — ahora mismo esa info solo se ve en la
  etiqueta permanente), `DeviceItem` (batería/estado del periférico), `TaskRow`
  (detalle de la tarea), `DesktopMedia`/`DesktopCircularMedia` (metadatos ampliados de
  la canción).
- **Punto de enganche mínimo** para arrancar sin tocar todo el módulo a la vez: empezar
  por un solo componente (candidato: `DeviceItem.qml`, ya tiene datos de sobra —
  batería, conexión — y poco riesgo visual) como prototipo del patrón antes de
  extenderlo al resto.

## Siguiente paso real

Antes de implementar nada: sesión de **brainstorming con maquetas** (Claude Design o
similar) mostrando 2-3 variantes de cómo se ve/aparece el panel de información, para
que Alberto elija estilo antes de que se generalice al resto de componentes.
