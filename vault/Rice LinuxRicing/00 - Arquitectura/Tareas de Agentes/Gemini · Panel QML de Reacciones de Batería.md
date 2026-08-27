---
tags: [tarea-agente, gemini, qml, rgb, bateria]
para: Gemini
de: Claude
creado: 2026-08-27
estado: pendiente
---

# Gemini · Panel QML «Reacciones de batería» (Fase 2)

> **Eres el agente `QML-panel`.** Este documento es tu única fuente de instrucciones.
> Léelo entero antes de tocar nada. No tienes contexto previo de esta sesión.

## 0. Contexto en una frase

Claude ha construido y probado el **motor backend** `rgb/battery-lighting` (un daemon
que enruta eventos de batería → efectos de luz, configurable con reglas en
`~/.config/caelestia/battery-lighting.json`). Falta la **UI**: un panel nuevo en el
Centro de Iluminación de Quickshell para crear y editar esas reglas. **Ese panel es
tu trabajo.**

## 1. Lee primero (en este orden)

1. `/home/alberviz/LinuxRicing/CLAUDE.md` — flujo de ramas, coordinación multi-agente, copias idénticas.
2. `docs/superpowers/specs/2026-08-27-battery-lighting-engine-design.md` — el diseño del sistema. Secciones **§2 (esquema de config)**, **§3 (efectos por destino)**, **§6 (UI)**.
3. `docs/superpowers/plans/2026-08-27-battery-lighting-engine.md` — **Tasks 16, 17, 18** (tu alcance exacto, con estructura de archivos y patrones). Ignora Tasks 1-15 y 19.
4. **Diseño visual** (mockups del panel, hechos en Material You de Caelestia): `https://claude.ai/code/artifact/b0cb4839-378d-4233-aa5c-bb60f2ec95cc` — 3 artboards (panel, editor de acción, diálogo añadir regla). Replica esa estructura y estética.
5. Ejemplos de estilo de la casa (Caelestia QML) que DEBES seguir:
   - `configs/quickshell/caelestia/modules/rgbcontrol/AkkoCard.qml` (ChipGroup, SectionLabel, Divider, StyledSwitch, StyledSlider)
   - `configs/quickshell/caelestia/modules/rgbcontrol/DispositivosView.qml` (DeviceCard, ChipRow)
   - `configs/quickshell/caelestia/modules/rgbcontrol/NotificacionesView.qml` (Card, CheckRow — aquí va tu sección nueva)
   - `configs/quickshell/caelestia/modules/rgbcontrol/Chip.qml`, `KeyboardPreview.qml`, `DeviceCard.qml`
   - `configs/quickshell/caelestia/services/MchoseConfig.qml` y `RgbConfig.qml` (patrón de singleton — ya lo cumple el que hizo Claude)

## 2. Rama y aislamiento

- El trabajo del motor está en la rama **`feat/battery-lighting-engine`**, en el worktree `/home/alberviz/LinuxRicing/.worktrees/battery-lighting-engine`.
- **Crea tu propio worktree** desde el HEAD de esa rama para no chocar con nadie:
  ```
  cd /home/alberviz/LinuxRicing
  git worktree add .worktrees/qml-battery-panel -b feat/battery-panel-ui feat/battery-lighting-engine
  cd .worktrees/qml-battery-panel
  ```
  (hay otro agente en `.worktrees/fix-theme-and-rgb-sync` — no lo toques.)
- Trabaja SOLO en `configs/quickshell/caelestia/modules/rgbcontrol/` y `configs/quickshell/caelestia/services/` (salvo lo que se indica).
- **NO toques** `rgb/`, `widgets/`, `docs/`, ni `configs/quickshell/caelestia/services/BatteryLightingConfig.qml` (ese lo hizo Claude y es el contrato — solo lo consumes).
- Commits pequeños, uno por componente. Mensajes de commit terminan con:
  `Co-Authored-By: Gemini <noreply@google.com>` (o tu identidad habitual).
- Textos de usuario en **español con tildes**.

## 3. El contrato: API de `BatteryLightingConfig` (singleton, YA existe)

`configs/quickshell/caelestia/services/BatteryLightingConfig.qml` — es `pragma Singleton`,
Quickshell lo expone solo por estar en `services/`. Impórtalo con `import qs.services`
y úsalo como `BatteryLightingConfig`. **No lo modifiques. Codifica contra esta API:**

### Propiedades (solo lectura para ti)
- `rules: var` — lista de `{ id, source, trigger, threshold|null, actions: [{ target, zone|null, effect }] }`
- `criticalThreshold: int`
- `loaded: bool` — falso hasta que el fichero se ha leído; muestra un estado de carga si quieres
- `sources: [{ key, label, icon }]` — `akko_keyboard` / `mchose_mouse` / `v9_headset`
- `triggers: [{ key, label }]` — `charging` (Al cargar) / `low` (Batería baja) / `critical` (Batería crítica)
- `targets: [{ key, label, icon, hasZones }]` — `mchose_base` / `akko_keyboard` (hasZones=true) / `magichome` / `openrgb`
- `zones: [{ key, label }]` — `keys` / `sidestrip` / `both`

### Métodos
- `effectsFor(target, zone) -> [{ key, label }]` — la lista de efectos válidos para ese destino (y zona, si es el teclado). ÚSALO para poblar los chips de efecto.
- `sourceLabel(key)`, `triggerLabel(key)`, `targetLabel(key)`, `targetHasZones(key) -> bool` — helpers de etiqueta.
- `addRule(source, trigger)` — crea una regla vacía (sin acciones). `threshold` arranca en 20 si `trigger === "low"`.
- `removeRule(id)`
- `setRuleThreshold(id, n)` — clampa a 5..40 en pasos de 5.
- `addAction(ruleId, target, zone, effect)` — `zone` puede ser `null`/`""` para destinos sin zonas.
- `updateAction(ruleId, index, patch)` — `patch` es un objeto parcial, p.ej. `{ effect: "red_static" }` o `{ target: "magichome" }`. Reajusta `zone`/`effect` automáticamente si cambias `target`/`zone`.
- `removeAction(ruleId, index)`
- `probe(ruleId)` — dispara los efectos de esa regla ahora mismo (botón «Probar»).

Cada mutación **guarda sola** (debounce 250 ms) y dispara `battery-lighting --tick`. No
tienes que llamar a `save()` ni escribir el JSON. No hay botón «Aplicar» para esta sección.

## 4. Qué construir (3 componentes + ediciones)

### 4a. `modules/rgbcontrol/BatteryActionRow.qml` (NUEVO)
Editor de UNA acción. Props: `required property string ruleId`, `required property int index`,
`required property var action` (`{ target, zone, effect }`).
- Fila de chips **Destino** (de `BatteryLightingConfig.targets`) → `updateAction(ruleId, index, { target: key })`.
- Fila de chips **Zona** (`Teclas / Tira lateral / Ambas`) — **visible solo si** `action.target === "akko_keyboard"` → `updateAction(ruleId, index, { zone: key })`.
- Fila de chips **Efecto** — `BatteryLightingConfig.effectsFor(action.target, action.zone)` → `updateAction(ruleId, index, { effect: key })`. Los efectos `red*` usan el color de error (mira `ChipGroup { danger: true }` en `AkkoCard.qml`).
- Botón ✕ → `removeAction(ruleId, index)`.
- Si `action.target === "akko_keyboard"`: incrusta `KeyboardPreview { mode: ...; sidestripMode: ... }` con este mapa efecto→propiedad:

| efecto (motor), zona `keys` | `KeyboardPreview.mode` |
|---|---|
| `theme` | `theme` |
| `battery_meter` | `fill` |
| `breathing_battery` | `breathing` |
| `stream` | `stream` |
| `red_breathing` / `red_static` / `none` | igual |

| efecto (motor), zona `sidestrip` | `KeyboardPreview.sidestripMode` |
|---|---|
| `stream_battery` | `stream_battery` |
| `solid_theme` | `solid` |
| `breathing` | `solid` (temporal — ver 4d) |
| `red_breathing` / `red_static` / `none` | igual |

### 4b. `modules/rgbcontrol/BatteryRuleCard.qml` (NUEVO)
Tarjeta de UNA regla, plegable (patrón de `DeviceCard.qml` si te sirve, o una `StyledRect`
propia). Prop: `required property var rule`.
- Cabecera: icono según `rule.source` (`BatteryLightingConfig.sources`), texto
  `${sourceLabel(rule.source)} · ${triggerLabel(rule.trigger)}` + (si `low`/`critical`) `≤ N %`,
  resumen corto de acciones, botón borrar (`removeRule(rule.id)`), chevron plegar.
- Cuerpo desplegado:
  - Si `rule.trigger === "low"`: `StyledSlider` de umbral 5–40 paso 5, misma fórmula que
    `AkkoCard.qml` líneas ~212-219, → `setRuleThreshold(rule.id, v)`. Etiqueta
    `qsTr("Umbral de aviso: ≤ %1 %").arg(rule.threshold)`.
  - `Repeater { model: rule.actions; BatteryActionRow { ruleId: rule.id; index: modelData.index?; action: modelData } }`
    (usa `required property int index` en el delegado del Repeater).
  - Botón «+ Añadir acción» → `addAction(rule.id, "mchose_base", null, "red_breathing")` (un default sensato).
  - Botón «Probar» (icono `bolt` o `play_arrow`) → `probe(rule.id)`.

### 4c. `modules/rgbcontrol/NotificacionesView.qml` (EDITAR)
Añade una sección nueva tras la `Card` de «Dispositivos que flashean»:
- Título `qsTr("Reacciones de batería")` (estilo `title.small`, color `m3primary`), con
  subtítulo `qsTr("la batería de un dispositivo acciona luces")`.
- `Repeater { model: BatteryLightingConfig.rules; BatteryRuleCard { rule: modelData } }`.
- Botón «+ Añadir regla» (outlined, como el de `DispositivosView`). Al pulsar, un
  diálogo mínimo (puede ser un `Popup`/`StyledRect` inline que se expande, no hace falta
  ventana): elegir **dispositivo** (`BatteryLightingConfig.sources`, muestra el nivel si
  lo sabes — puedes leer `~/.cache/mchose_battery.json` con un `FileView`, opcional) +
  **disparador** (`BatteryLightingConfig.triggers`) → `BatteryLightingConfig.addRule(source, trigger)`.
- Quita del bloque «Más adelante» la línea que dice *«Aviso de batería baja propio de cada dispositivo…»* (ya está hecho).

### 4d. `modules/rgbcontrol/KeyboardPreview.qml` (EDITAR — cambio de ~4 líneas)
Su `sidestripMode` hoy solo distingue `solid`/`red_static`/`stream_battery`/`none`. Añade
un caso `breathing` (pulso suave con el color de acento) junto a la línea ~145. Cambio mínimo.

### 4e. `modules/rgbcontrol/AkkoCard.qml` (EDITAR — quitar cosas)
Elimina TODA la sección de batería: `property bool showLow`, el `KeyboardPreview` de
evento, el selector «Al cargar / Batería baja», el master toggle «Reaccionar a la
batería», los dos `ZoneTitle`+`ChipGroup` de carga/baja, el `ColumnLayout` del umbral, y
la nota de estado del final. Quita `import` y usos de `AkkoConfig`. La tarjeta queda con
icono/nombre/subtítulo y una nota: *«El color del teclado sigue el tema global. Sus
reacciones de batería están en Notificaciones → Reacciones de batería.»*

### 4f. `modules/rgbcontrol/DispositivosView.qml` (EDITAR — quitar cosas)
En la `DeviceCard` de la Base MCHOSE, elimina el bloque «Eventos de batería» entero (los
dos `ChipRow`, el slider de umbral, el botón «Probar»). Quita `import`/usos de
`MchoseConfig`. Añade la misma nota de reenvío a Notificaciones.

### 4g. Borrar singletons superados
```
git rm configs/quickshell/caelestia/services/AkkoConfig.qml
git rm configs/quickshell/caelestia/services/MchoseConfig.qml
```
Después: `grep -rn "AkkoConfig\|MchoseConfig" configs/quickshell/` → **sin resultados**.
(Nota: `MchoseConfig.qml` apuntaba a `~/.local/bin/mchose-config`, que ya se borró en el
backend — por eso hay que quitarlo.)

## 5. Verificación (lo que puedas)

- `qmllint configs/quickshell/caelestia/modules/rgbcontrol/*.qml configs/quickshell/caelestia/services/*.qml` → sin errores nuevos.
- `grep -rn "AkkoConfig\|MchoseConfig" configs/quickshell/` → vacío.
- Si puedes recargar el shell: `caelestia shell -k && sleep 1 && caelestia shell -d`, luego
  `caelestia shell ipc call rgb openTab 2` (abre Notificaciones) y revisa el log:
  `journalctl --user -t quickshell -n 60 --no-pager | grep -iE "battery|rule|Config"`.
  **La verificación visual final (que el panel se ve bien y las reglas se guardan) la hace Alberto.**

## 6. Cuando termines

Escribe un informe en `vault/Rice LinuxRicing/00 - Arquitectura/Tareas de Agentes/Gemini · Panel QML — INFORME.md` con:
- Qué archivos creaste/editaste/borraste y sus commits.
- Salida de `qmllint` y del `grep` de verificación.
- Cualquier duda sobre la API de `BatteryLightingConfig` o desviación que hayas tenido que hacer.
- Qué queda por verificar visualmente.
- Deja la rama `feat/battery-panel-ui` lista (NO la mergees — lo hace Claude tras revisar).

Avisa a Alberto de que has terminado. Él le dirá a Claude que revise e integre.
