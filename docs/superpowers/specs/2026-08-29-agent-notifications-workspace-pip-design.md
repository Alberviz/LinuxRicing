# Notificaciones de agentes en el pip del workspace — diseño

**Fecha:** 2026-08-29
**Rama:** `feat/agent-notifications` (desde `main`)
**Estado:** diseño aprobado por Alberto, pendiente de plan de implementación
**Autor:** Claude (diseñador principal); brief de partida: `vault/PROMPT_CLAUDE_NOTIFICACIONES_AGENTES.md`

---

## Problema

Cuando un agente de IA (Claude, Gemini, Antigravity…) termina una tarea de fondo en un
terminal de Hyprland, el aviso actual no aporta valor:

- **Cero contexto:** "Claude ha terminado" — sin saber qué tarea, qué proyecto, ni en qué
  workspace/terminal está.
- **Fugacidad:** la notificación de Caelestia expira en segundos y desaparece; la información
  se pierde antes de poder actuar.
- **Sin vuelta atrás:** no hay forma de saltar al terminal del agente desde el aviso.

El intento anterior (commits `e0e63f1`…`005f535`, revertido en `e6569fc`) metió una
"píldora persistente" **dentro del cajón de notificaciones** de Caelestia y chocó de frente
con cuatro cosas de esa arquitectura:

1. **`BlobGroup` compartido** — el fondo oscuro de cada panel es una metabola SDF conectada
   con las vecinas; un elemento pequeño no puede tener ahí un rectángulo redondo limpio.
2. **`ClippingRectangle` por ítem** — recorta los delegados al ancho de la lista; una insignia
   encogida sale cortada.
3. **`notifications.bottom → sidebar.top`** (`Panels.qml`) — contenido persistente en ese hueco
   empuja la sidebar para siempre.
4. **`Notifs` quiere que los popups se vayan** — la lista es `popups.filter(n => !n.closed)`;
   persistir ahí va a contracorriente.

Quedó código muerto a medias: `AgentPills.qml` y un `DelegateChoice roleValue:"agents"` en
`Bar.qml` que **nunca se renderiza** (ningún entry de `Config.bar.entries` tiene id `"agents"`).

## Objetivo

Que el aviso de "agente terminado" sea **útil** y permita **volver al terminal del agente**,
apoyándose en sistemas que Caelestia **ya tiene** (barra, workspaces, popouts de barra) — sin
ventana flotante nueva y sin tocar el sistema de blobs.

Idea aprobada: **el propio pip del workspace donde vive el agente lleva el estado**, y al
hacer *hover* sale una tarjeta con el detalle. El clic ya lo resuelve Caelestia (cambia de
workspace).

### Fuera de alcance (v1)

- **Estado "en curso"** (aro que late mientras el agente trabaja). Requiere una señal de
  *inicio* en `agent-notify` y adoptar el wrapper `agent-notify run …` como forma de lanzar
  agentes. Se hará en una segunda pasada.
- **Badge con número saliéndose del pip** — el contenedor de workspaces va `clip:true`. El
  estado se expresa con color/brillo + un puntito interior; el recuento vive en la tarjeta.
- **Indicador para agentes en un workspace fuera del grupo mostrado** en la barra.
- **Persistencia entre reinicios del shell** de la lista de agentes (los `hints` tampoco
  persisten hoy).
- **Animación "la notificación vuela hasta el pip"** — se descartó por frágil (cruza la
  pantalla, coordina dos ventanas). El "traspaso" se lee: la notificación expira → el pip se
  enciende.
- Tratamiento especial por agente concreto (Gemini vs Claude): funciona genérico por nombre.

---

## Arquitectura

```
Terminal en WS N, ventana address 0x…
   │  el agente termina  (o:  `agent-notify run <cmd>`  captura inicio+fin)
   ▼
rgb/agent-notify  (Python, ya existe)
   ├─ captura:  hyprctl activewindow → address, ws, class, title
   │            git toplevel → nombre de proyecto
   │            duración / estado
   ├─ 1) qs -c caelestia ipc call agents notify <json>   → alimenta el servicio Agents
   └─ 2) notify-send  -a caelestia-agents  -h string:address:0x…  -h int:ws:N   → toast rico
             (si `qs ipc` falla, degrada a solo notify-send — ya está en try/except)

services/Agents.qml  (Singleton, ya cargado en ServiceLoader — pasa a ser la fuente de verdad)
   ├─ completedAgents: [{ id, name, task, dir, ws, address, time, seen }]
   ├─ resuelve address → workspace EN VIVO (Hypr.toplevels) por si mueves el terminal
   ├─ focus(address)         → Hypr focuswindow + dismissByAddress
   ├─ markSeen(id|ws)        → apaga el puntito (el brillo sigue)
   ├─ agentsForWs(n) / hasUnseenForWs(n)
   └─ auto-descarte: cuando ESA ventana o ESE workspace pasa a activo → dismiss

modules/notifications/Notification.qml   (ya enruta el clic)
   └─ onClicked: si hints.address → Agents.focus(address) + cierra el toast

modules/bar/components/workspaces/Workspace.qml   (+ capa de fondo estilo OccupiedBg)
   ├─ Agents.agentsForWs(ws).length > 0   → relleno de acento + brillo detrás del pip
   └─ Agents.hasUnseenForWs(ws)           → puntito interior en el pip

modules/bar/Bar.qml  ::checkPopout   (+ rama "workspaces")
   └─ hover sobre un pip con agente → popouts.currentName = "agents",
      popouts.currentCenter = centro del pip;  al abrir → Agents.markSeen(ws)

modules/bar/popouts/AgentsPopout.qml  (nuevo)  +  Popout { name: "agents" } en Content.qml
   └─ tarjeta(s) para el workspace en hover: 🤖 nombre · tarea · proyecto · "terminó hace Xm"
```

### Por qué esta vía no repite los errores del intento anterior

| Problema anterior | Cómo se evita ahora |
|---|---|
| `BlobGroup` compartido | No se dibuja ningún panel/fondo nuevo. El brillo del pip vive **dentro** del `StyledClippingRect` de `Workspaces.qml`, como `OccupiedBg`. |
| `ClippingRectangle` recorta | El estado es color + un dot interior; nada se sale del pip. |
| Empuje de la sidebar | No se toca el hueco `notifications`. El estado va en la barra, que ya es persistente. |
| "los popups se van" | El toast **sí** se va (comportamiento nativo, correcto). La persistencia vive en `Agents` + el pip, no en `Notifs`. |
| Popout que hay que inventar | Se reusa el sistema de popouts de barra (`checkPopout` + `Popout{}`), igual que `statusIcons`. |

---

## Componentes

### 1. `rgb/agent-notify` (Python, ya existe — cambios menores)

- Mantener `notify`, `run`, `test`, `clear`.
- El payload IPC ya incluye `id, name, status, address, ws, dir, duration, terminal`. Añadir
  `task` (texto corto de la tarea, si se pasa `--task`/`-t`; por defecto = `status`).
- `test` debe inyectar un agente en un **workspace real** (el activo) para poder verlo de verdad.
- Sin dependencias nuevas. La resolución `address → ws` en vivo se hace en QML, no aquí.

### 2. `services/Agents.qml` (Singleton, ya existe — se amplía)

Estructura de cada entrada de `completedAgents`:

```js
{ id: "agent-1724900000000",
  name: "Claude",
  task: "rgb: refactor de notificaciones",
  dir: "LinuxRicing",
  ws: 3,                 // workspace capturado al terminar
  address: "0x5578…",    // ventana del terminal
  time: <Date>,
  seen: false }           // false hasta el primer hover de su tarjeta
```

Funciones / propiedades:

- `notify(dataStr)` — parsea, deduplica por `address` (una entrada por terminal; una nueva
  finalización en el mismo terminal **reemplaza** y vuelve a poner `seen:false`).
- `liveWs(address)` — busca en `Hypr.toplevels` la ventana por address y devuelve su
  workspace actual; si no está, cae al `ws` capturado. Las vistas usan esto, no el `ws` crudo.
- `agentsForWs(n)` → `completedAgents` cuyo `liveWs` == n.
- `hasUnseenForWs(n)` → alguno de los anteriores con `seen === false`.
- `markSeen(idOrWs)` — pone `seen:true` (dispara recomputo de bindings).
- `focus(address)` — igual que hoy: `Hypr.dispatch(focuswindow address:…)` + `dismissByAddress`.
- `dismiss(id)`, `dismissByAddress(addr)`, `clearAll()` — como hoy.
- `Connections { target: Hyprland }`:
  - `onActiveToplevelChanged` → `dismissByAddress(active.address)` (ya está).
  - `onFocusedWorkspaceChanged` (o equivalente) → `dismiss` de los agentes cuyo `liveWs` sea
    ahora el workspace activo **y** cuya ventana no exista ya (ventana cerrada). Si la ventana
    sigue viva, se descarta solo al enfocarla (evita limpiar por pasar de largo).
- Emite `count`, `agentAdded`, `agentRemoved` (ya está) para animaciones.

### 3. `modules/bar/components/workspaces/Workspace.qml` (+ fondo)

- Nueva propiedad derivada: `readonly property bool hasAgent: Agents.agentsForWs(ws).length > 0`
  y `readonly property bool agentUnseen: Agents.hasUnseenForWs(ws)`.
- **Brillo de fondo:** capa hermana estilo `OccupiedBg.qml` en `Workspaces.qml` (patrón ya
  probado: un `Repeater` de `StyledRect` posicionados sobre los pips que cumplen una condición)
  — un `AgentBg.qml` que pinta un halo en los pips con `hasAgent`. Color:
  `Colours.palette.m3primary` a baja opacidad + glow suave. Queda **dentro** del
  `StyledClippingRect` padre. (Alternativa descartada por más invasiva: un `StyledRect` dentro
  del `ColumnLayout` de cada `Workspace`.)
- **Puntito interior:** un `Rectangle` circular de ~4px anclado a una esquina interior del
  `indicator`, visible sólo si `agentUnseen`. Color `m3primary`. Nunca se sale del pip.
- Todo con `Behavior`/`Anim` de tokens para que aparezca/desaparezca suave.
- El texto del pip (`indicator.color`) puede virar a `m3onPrimaryContainer` cuando `hasAgent`
  para contraste sobre el halo.

### 4. `modules/bar/popouts/AgentsPopout.qml` (nuevo)

- Recibe `property int ws` (el workspace en hover) y lee `Agents.agentsForWs(ws)`.
- Renderiza una `Column` de tarjetas (una por agente; normalmente 1):
  - Cabecera: `smart_toy` + nombre del agente.
  - Meta: `task` · `dir` · "terminó hace Xm" (tiempo relativo, recalculado con un `Timer`).
  - Estado: chip "✔ Completado" (`m3primaryContainer`).
  - Pie: "clic en el workspace → saltas ahí".
- Estilo con `StyledRect` + tokens, coherente con los demás popouts (`Battery.qml`, etc.).
- Si `Agents.agentsForWs(ws)` queda vacío mientras está abierto → el popout se cierra solo
  (`popouts.hasCurrent = false`).

### 5. `modules/bar/popouts/Content.qml` (+ un `Popout`)

```qml
Popout {
    name: "agents"
    sourceComponent: AgentsPopout {
        ws: root.popouts.agentsWs   // nueva prop en PopoutState, seteada por checkPopout
    }
}
```

### 6. `modules/bar/popouts/PopoutState.qml` (+ una prop)

- `property int agentsWs: 0` — el workspace cuyo popout de agentes se muestra.

### 7. `modules/bar/Bar.qml` :: `checkPopout` (+ rama `workspaces`)

Tras las ramas de `statusIcons` / `tray` / `activeWindow`:

```qml
} else if (id === "workspaces") {
    const wsEntry = ch.item;                 // el Workspaces (StyledClippingRect)
    // localizar el hijo Workspace por posición vertical
    const wsItem = <Workspace bajo el cursor, usando el flag isWorkspace>;
    if (wsItem && Agents.agentsForWs(wsItem.ws).length > 0) {
        popouts.agentsWs = wsItem.ws;
        popouts.currentName = "agents";
        popouts.currentCenter = Qt.binding(() => wsItem.mapToItem(root, 0, wsItem.height / 2).y);
        popouts.hasCurrent = true;
        Agents.markSeen(wsItem.ws);
    } else {
        popouts.hasCurrent = false;
    }
}
```

- **Gating:** de momento sin flag de config (Caelestia.Config es upstream y no podemos añadir
  `bar.popouts.workspaces`). Se activa siempre. Si más adelante se quiere apagar, se añade un
  shim en `GlobalConfig`/local.
- La localización del `Workspace` hijo se hace como `statusIcons` hace con sus iconos
  (`items.childAt(...)` / recorrer hijos con `isWorkspace === true` y comparar `y`).

### 8. `modules/notifications/Notification.qml` (ya hecho — verificar)

- `onClicked`: si `modelData.hints?.address` → `Agents.focus(String(addr))` + `close()`. **Ya
  está en el archivo tras el revert.** Solo verificar que sigue y que no rompe otros toasts.

### 9. Limpieza de deuda

- **Borrar** `modules/bar/components/AgentPills.qml`.
- **Borrar** el `DelegateChoice { roleValue: "agents" … }` de `Bar.qml` (código muerto).
- **Conservar** la lógica de dedup de `services/Notifs.qml` (evita el doble toast nativo de
  Antigravity/Claude + el de `caelestia-agents`) — sigue siendo relevante.
- **Conservar** `configs/hypr/hyprland/misc.lua` → `focus_on_activate = false` (evita el robo
  de foco de los agentes). La regla `suppressevent = "activate"` por terminal **no** se
  reintroduce (se revirtió a propósito; `focus_on_activate=false` ya cubre el caso).
- Revisar restos en `Content.qml` / `NotifData.qml` de los experimentos revertidos y quitar
  lo que no tenga uso (p. ej. propiedades `minimized`, `miniBadgeSize` si quedaron).

---

## Flujo de datos (ejemplo)

1. Claude termina una tarea en un kitty en el **WS 3**, ventana `0x5578ab`. Se lanzó con
   `agent-notify run -n Claude -t "rgb: refactor notif" -- claude …` (o dispara
   `agent-notify notify -n Claude -t "…"` al acabar).
2. `agent-notify` captura `address=0x5578ab, ws=3, dir=LinuxRicing, duration=2m14s`.
3. → `qs ipc call agents notify {…}` → `Agents.notify()` añade la entrada (`seen:false`).
4. → `notify-send -a caelestia-agents -h string:address:0x5578ab …` → toast arriba a la derecha:
   **🤖 Claude · LinuxRicing** / "rgb: refactor notif · 2m 14s · WS 3 · clic para enfocar".
5. `Workspace.qml` del WS 3 (en cada barra) recalcula: `hasAgent → true`, `agentUnseen → true`
   → halo de acento detrás del "3" + puntito interior.
6. **Camino A — clic en el toast:** `Agents.focus("0x5578ab")` → Hypr enfoca el kitty,
   `dismissByAddress` limpia la entrada → el halo del WS 3 se apaga.
7. **Camino B — el toast expira:** desaparece (nativo). La entrada en `Agents` sigue. El WS 3
   sigue con halo + puntito.
8. Alberto hace **hover** sobre el "3" en la barra → popout con la tarjeta de Claude;
   `markSeen(3)` → el puntito desaparece (el halo sigue).
9. Alberto hace **clic** en el "3" → Caelestia cambia al WS 3. `Agents` ve el workspace/ventana
   activos → si entra en la ventana del agente, `dismiss` → halo apagado. Fin.

---

## Errores y degradación

- **`qs ipc` no disponible** → `agent-notify` hace sólo `notify-send`; el toast es
  clicable-para-enfocar igualmente (usa el hint `address`), pero no hay pip persistente.
- **Sin `address` capturado** (fallback de `get_hyprland_window`) → la tarjeta se muestra igual;
  `focus` se salta; el clic en el pip cambia de workspace igual.
- **Terminal movido a otro workspace** → `Agents.liveWs(address)` sigue a la ventana; el halo
  se mueve al pip nuevo. Si la ventana se cierra → `Hypr.toplevels` ya no la tiene → la entrada
  se descarta en el siguiente recomputo / en `onFocusedWorkspaceChanged`.
- **Agente en un workspace fuera del grupo mostrado** → no hay pip visible; la entrada existe
  pero no se ve hasta cambiar de grupo. Aceptado en v1.
- **Multi-monitor** → el halo aparece en cada barra que muestre ese workspace; se respeta
  `perMonitorWorkspaces`. El toast lo gestiona Caelestia como cualquier notificación.
- **DND / pantalla completa** → `Notifs.shouldShowPopup()` suprime el toast; la entrada en
  `Agents` y el halo del pip **sí** ocurren (no son intrusivos).
- **Reinicio del shell** → `completedAgents` es en memoria; se pierde. Aceptado en v1.
- **Varias finalizaciones en el mismo terminal** → una sola entrada (dedup por address), la
  última gana, `seen` vuelve a `false`.
- **Varios agentes en el mismo workspace** (distintos terminales) → varias entradas; la
  tarjeta las lista todas; el halo se mantiene hasta que se descartan todas.

---

## Pruebas

**Python (`rgb/tests/`):**

- `agent-notify`: parseo de flags top-level y de subcomandos (`notify`, `run`, `test`, `clear`).
- Captura de ventana: con `hyprctl` simulado devuelve `address/ws/class`; sin él, fallback a
  `os.getppid()` / ws 1 sin lanzar excepción.
- Forma del payload IPC (claves obligatorias, `task` por defecto = `status`).
- `run`: propaga el código de salida del comando envuelto; formatea la duración (`Xm Ys` / `Ys`).

**QML / manual (checklist en el plan):**

- `caelestia shell -d` → `INFO: Configuration Loaded` sin errores de sintaxis/propiedades.
- `agent-notify test` inyecta un agente en el WS activo → aparece halo + puntito en ese pip.
- Hover → sale la tarjeta con los datos correctos; el puntito desaparece, el halo sigue.
- Clic en el pip → cambia de workspace; al entrar en la ventana test, el halo se apaga.
- `agent-notify clear` → limpia todos los halos.
- Con DND activo: no sale toast pero sí el halo.
- Segundo monitor: el halo se ve en su barra.

---

## Archivos

**Nuevos**
- `configs/quickshell/caelestia/modules/bar/popouts/AgentsPopout.qml`
- `configs/quickshell/caelestia/modules/bar/components/workspaces/AgentBg.qml`
- `docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md` (este)
- `rgb/tests/test_agent_notify.py`

**Modificados**
- `rgb/agent-notify` — `--task`, `test` en workspace real, `task` en el payload
- `configs/quickshell/caelestia/services/Agents.qml` — `task`, `seen`, `liveWs`, `agentsForWs`,
  `hasUnseenForWs`, `markSeen`, auto-descarte por workspace
- `configs/quickshell/caelestia/modules/bar/components/workspaces/Workspace.qml` — halo + puntito
- `configs/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml` — instanciar
  la capa `AgentBg` junto a `OccupiedBg`
- `configs/quickshell/caelestia/modules/bar/Bar.qml` — rama `workspaces` en `checkPopout`;
  **borrar** el `DelegateChoice "agents"`
- `configs/quickshell/caelestia/modules/bar/popouts/Content.qml` — `Popout { name: "agents" }`
- `configs/quickshell/caelestia/modules/bar/popouts/PopoutState.qml` — `property int agentsWs`
- `configs/quickshell/caelestia/modules/notifications/Notification.qml` — verificar el
  `onClicked` → `Agents.focus`; quitar restos de `minimized` si los hay
- `configs/quickshell/caelestia/modules/notifications/Content.qml` /
  `services/NotifData.qml` — quitar restos de los experimentos revertidos si quedan
- `install.sh` — desplegar `agent-notify` si no lo hace ya

**Borrados**
- `configs/quickshell/caelestia/modules/bar/components/AgentPills.qml`

**Sincronizar tras editar UI** (CLAUDE.md): copiar a `~/.config/quickshell/caelestia/`,
verificar pares gemelos con `diff -q`, reiniciar el shell con
`caelestia shell -k … ; caelestia shell -d` y comprobar `INFO: Configuration Loaded`.

---

## Preguntas resueltas

- **Marcador:** halo en el pip del workspace (no píldora dedicada, no badge externo).
- **Momento de completado:** se mantiene el toast nativo rico arriba a la derecha; al expirar,
  el pip queda encendido (sin animación de "vuelo").
- **"En curso":** fuera de v1.
- **Puntito interior de "novedad":** sí, hasta el primer hover de la tarjeta.
- **Acceso:** clic en el pip (nativo de Caelestia) + hover para el detalle.
