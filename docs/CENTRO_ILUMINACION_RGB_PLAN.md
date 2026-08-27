# Plan — Centro de Iluminación RGB

Sustituir la tarjeta expansible inline de ajustes de la base MCHOSE (dentro del widget de
periféricos de `Background.qml`) por **un panel superpuesto único** que controle la
iluminación de **todos** los periféricos con luz, con selector de color, "seguir tema /
color fijo", interruptores por dispositivo y flash por notificación.

Contexto y estado actual del RGB: `docs/HARDWARE_PROTOCOLS.md`, `docs/RGB_HANDOVER_LINUX.md`
y la bóveda `vault/Rice LinuxRicing/`.

## Decisiones firmes

1. **Forma**: panel superpuesto centrado en capa Wayland (`WlrLayer.Overlay`), fondo
   oscurecido, cierra al clicar fuera. Patrón: `modules/areapicker/AreaPicker.qml`. No es
   una ventana flotante XDG.
2. **Estructura**: 3 pestañas — `Inicio` (estado en reposo) · `Dispositivos` (acordeón, una
   ficha por dispositivo con sus ajustes dentro) · `Notificaciones`. Plan B: una columna
   scrollable sin pestañas si algo se complica.
3. **Alcance**: global — base MCHOSE (anillo + logo), teclado Akko (retro + tira lateral),
   placa/RAM/ventiladores (OpenRGB), tira MagicHome. Interruptor "participa en la
   sincronización" por dispositivo. La ficha OpenRGB además elige `RGB estático` /
   `ARGB ola animada` para las zonas direccionables.
4. **Selector de color**: paleta de presets (colores del tema + fijos comunes) + campo hex
   editable con validación. Sin `Canvas` ni rueda.
5. **Reposo**: selector "seguir tema (Material You) / color fijo".
6. **Base MCHOSE**: se conservan "efecto al cargar" y "alerta de batería baja" + umbral
   dentro de su ficha en `Dispositivos` (son solo de la base, único dispositivo con
   batería). Siguen guardándose vía el CLI `mchose-config` (encadena
   `mchose-battery --trigger-lighting`).
7. **v1** incluye el motor "efecto temporal → restaurar" y el **flash al recibir
   notificación** (rojo / acento / complementario = tono +180° en HSV, N pulsos), con
   selección de qué dispositivos flashean.

## Arquitectura

### Módulo QML nuevo: `configs/quickshell/caelestia/modules/rgbcontrol/`

- **`RgbControl.qml`** — `Scope { LazyLoader { Variants(Screens.screens) { StyledWindow } } IpcHandler }`.
  - `WlrLayer.Overlay`, `WlrKeyboardFocus.OnDemand` (solo hace falta foco para el campo
    hex; `Exclusive` bloquearía el WM sin necesidad).
  - `Region` vacío + `mask` durante el cierre (patrón AreaPicker) para no atrapar clics.
  - Fondo oscurecido `Qt.alpha("black", 0.5)` con `MouseArea` que cierra; la tarjeta
    central no propaga. Entrada/salida con `scale` + `opacity` (`CAnim`).
  - `IpcHandler { target: "rgb"; function open()/close()/toggle() }`.
  - **Fuera del `LazyLoader`, en el `Scope`** (siempre vivo): el objeto de control expuesto
    en `ShellState`, un `FileView` de `rgb-config.json`, y el `Connections { target: Notifs }`
    del flash. Solo el contenido pesado es lazy.
- **`Content.qml`** — tarjeta modal (`StyledRect`, ancho ~560, alto por contenido).
  Cabecera + **barra de 3 pestañas** (`Inicio` · `Dispositivos` · `Notificaciones`) +
  `StackLayout` con una vista por pestaña. Cada vista con `VerticalFadeFlickable` si
  desborda. (Plan B si algo se complica: una sola columna scrollable, sin pestañas.)
  - **`InicioView.qml`** — "Estado en reposo" (el color base cuando no hay ningún evento):
    segmentado "Seguir el tema" / "Color fijo" + `ColourPicker` visible si `fixed`.
    Footer "Aplicar ahora".
  - **`DispositivosView.qml`** — acordeón de fichas de dispositivo (`Repeater` sobre el
    modelo de 4). Cada ficha: cabecera con icono/nombre/estado + chevron; al expandir,
    sus ajustes:
    - **Base MCHOSE 8K**: "Participa en la sincronización" (`StyledSwitch`); brillo
      (`StyledSlider`, *pendiente de protocolo*); y **todos los "Eventos de batería"** —
      chips "al cargar" (tema/batería/firmware/ola), "alerta batería baja"
      (roja/ola/ninguna/fija), umbral (`StyledSlider`), botón "Probar". Se guardan vía el
      CLI `mchose-config` (como hoy).
    - **Teclado Akko 5075B**: solo "Participa en la sincronización" por ahora.
    - **Placa · RAM · ventiladores (OpenRGB)**: "Participa en la sincronización" +
      **modo de las zonas direccionables**: `RGB · color estático` / `ARGB · ola animada`.
      "ARGB" engancha el daemon `argb-wave.py` (rama `feature/argb-wave`) sobre `Aura
      Addressable 1/2`; la RAM y `Aura Mainboard` van siempre en estático (bus SMBus).
      Nueva clave de config `devices_extra.openrgb.argb_zones: bool`.
    - **Tira LED MagicHome**: "Participa en la sincronización" + encendido/apagado
      (absorbe la acción del widget `DesktopLedStrip`).
  - **`NotificacionesView.qml`** — `StyledSwitch` "Flash al recibir notificación" + chips
    de color (rojo/acento/complementario) + nº pulsos (1-5) + **lista de casillas "qué
    dispositivos flashean"** (base, teclado, tira; placa/RAM deshabilitada por el bus) +
    botón "Probar flash".
- **`ColourPicker.qml`** — `Flow` de swatches (6 del tema: `m3primary/secondary/tertiary/
  primaryContainer/error/surfaceTint` + ~7 fijos) + `StyledTextField` hex
  (`validate: /^#?[0-9a-fA-F]{6}$/`). Expone `selectedColor` (hex string).
- **`DeviceCard.qml`** (acordeón), **`Chip.qml`** (port de `MchoseChip`).

### Apertura del panel

- Desde el widget (mismo proceso): `ShellState.qml` gana `property QtObject rgbControl`;
  `RgbControl.qml` hace el `Binding`. El `DeviceItem` "K7 Ultra" cambia su `onClicked` a
  `ShellState.rgbControl?.toggle()`.
- CLI / bind de Hypr: `caelestia shell ipc call rgb toggle`.
- `shell.qml`: `import "modules/rgbcontrol"` + `RgbControl {}` bajo `ShellRoot`.

### Config nueva: `~/.config/caelestia/rgb-config.json` (semilla en `configs/caelestia/rgb-config.json`)

```json
{
  "source": "theme",
  "fixed_color": "d8bde7",
  "devices": { "openrgb": true, "magichome": true, "mchose_base": true, "akko_keyboard": true, "spicetify": true },
  "devices_extra": { "openrgb": { "argb_zones": false } },
  "notification_flash": {
    "enabled": false,
    "mode": "accent",
    "pulses": 2,
    "devices": ["mchose_base", "akko_keyboard"]
  }
}
```

- `devices_extra.openrgb.argb_zones` — `true` deja las zonas `Aura Addressable 1/2` al
  daemon `argb-wave.py` (ola animada); `false` = color estático de un disparo como todo
  lo demás.
- `notification_flash.devices` — subconjunto de dispositivos rápidos que parpadean.
  `openrgb` nunca entra aquí (bus SMBus).

**Separado de `mchose-config.json`** a propósito: `mchose-battery` (proceso aparte, systemd
+ eventos de carga) solo lee `mchose-config.json`; `sync-rgb.py` solo lee `rgb-config.json`.
El panel edita los dos, cada backend lee el suyo. Sin `rgb-config.json` → comportamiento
actual intacto.

### Cambios en `rgb/sync-rgb.py` (y copia `~/.config/caelestia/sync-rgb.py`)

- `load_rgb_config()`; sin fichero → defaults = comportamiento actual.
- Prioridad de color: argumento posicional > env `SCHEME_COLOURS` > `source=fixed` →
  `fixed_color` > `scheme.json` primary > fallback.
- Parser trivial de `sys.argv` (mantener estilo "sin argparse"): `sync-rgb.py [hex]`,
  `--only a,b,c`, `--skip-config`.
- Filtrar hilos por `devices` ∩ `--only`. `spicetify` siempre salvo exclusión explícita.
- `enhance_color_for_leds` **solo** cuando el color viene del tema; color fijo / CLI se
  envía sin realce (el panel lo advierte).
- Retrocompat: todas las llamadas actuales sin args siguen valiendo.

### Motor de flash: `rgb/rgb-notify-flash` (Python, cero deps) + disparador QML

- Disparador en el `Scope` de `RgbControl.qml`: `Connections { target: Notifs }` →
  detectar item nuevo por `id`, ignorar si `Notifs.dnd`, filtrar `appName` propias
  (`"MCHOSE Battery"`), debounce `Timer` 400 ms → `execDetached(["rgb-notify-flash", ...])`.
- `rgb-notify-flash --mode {red|accent|complementary} --pulses N [--test]`:
  - `flock` en `~/.cache/rgb_flash.lock` — si hay flash en curso, salir.
  - Color: `red`=`#FF0000`; `accent`=primary de `scheme.json`; `complementary`=color actual
    efectivo (`fixed_color` o primary) → HSV → `h=(h+0.5)%1` → RGB.
  - Dispositivos: **base MCHOSE + Akko + MagicHome. NUNCA OpenRGB** (bus SMBus). Respeta los
    toggles `devices.*`. MagicHome solo si `pulses <= 2` (latencia Wi-Fi).
  - Pulso: color-flash (base target 0x06 estático + Akko opcodes 0x07/0x08) → `sleep 0.18`
    → apagado/previo → `sleep 0.18`.
  - Restauración: re-lanzar `sync-rgb.py` (deja el estado estable de `rgb-config.json`).
    Excepción: si `~/.cache/mchose_battery.json` tiene `k7_was_charging` → restaurar la base
    con `mchose-battery --trigger-lighting`; si `k7_was_low` → re-aplicar alerta.

### Helper de config

- `rgb-config.json`: el panel lo escribe directo con `FileView.setText`. CLI opcional
  `rgb/rgb-config` (`get|set|show`) para scripting/binds.
- `mchose-config.json`: seguir usando el CLI `mchose-config` existente (no duplicar en QML).

### Migración del widget (`Background.qml` ×2 — editar idénticos)

`widgets/Background.qml` y `configs/quickshell/caelestia/modules/background/Background.qml`
son byte-idénticos; toda edición va a las dos rutas en el mismo commit y se verifica con
`diff -q` (sin salida).

- Borrar estado (`showMchoseSettings`, `chargingEffect`, `lowBatEffect`, `lowBatThreshold`,
  `configReadProc`, `configSaveProc`, `saveCharging/saveLowBat/saveThreshold/previewEffect`).
- Borrar `StyledRect { id: mchoseSettingsCard ... }` y `component MchoseChip`.
- `onClicked` del ratón → `ShellState.rgbControl?.toggle()` (mantener `isClickable`).
  Comprobar `import qs.services`.
- `DesktopLedStrip`: se mantiene en v1; añadir un `IconButton` "tune" en su cabecera →
  `ShellState.rgbControl?.open()`. Absorberlo del todo queda para v2.

### `install.sh`

- Copiar a `~/.local/bin/` (con `chmod +x`): `mchose-config`, `mchose-lighting`,
  `rgb-notify-flash`, `rgb-config`.
- Semilla sin sobrescribir:
  `[ -f ~/.config/caelestia/rgb-config.json ] || cp configs/caelestia/rgb-config.json ...`.
- El módulo QML y `shell.qml` ya se despliegan con el `cp -ru` de la sección Caelestia.

### Sincronización de copias

- `widgets/Background.qml` ⇔ `configs/.../modules/background/Background.qml`: idénticos,
  `diff -q` en cada commit. (Opcional: `scripts/sync-repo.sh` + hook pre-commit.)
- `rgb/*` ⇔ `~/.local/bin/*`: la fuente es el repo; ampliar `install.sh` elimina la
  divergencia manual actual.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Bus SMBus/I2C (OpenRGB placa+RAM): pulsos rápidos cuelgan el bus | OpenRGB excluido del flash SIEMPRE; preview del panel con `--only` sin openrgb; `sleep ≥150 ms` entre escrituras HID |
| Keyboard focus del overlay | `WlrKeyboardFocus.OnDemand`; `Region` vacío + `mask` al cerrar |
| Doble `Background.qml` | Editar ambas rutas en el mismo commit + `diff -q` en verificación |
| Divergencia target 0x06 / 0x02 / 0x07 | Flash y restauración usan **target 0x06 estático** (igual que `sync_mchose_base`) |
| `LazyLoader` no cargado al llamar desde el widget | Objeto de control + `FileView` + `Connections` viven en el `Scope`, no en el `LazyLoader` |
| Bucle de flash por notificación propia | Filtrar por `id` visto + `appName` propias + `dnd` |
| `enhance_color_for_leds` altera el hex fijo elegido | Color fijo / CLI sin realce; el panel lo advierte |

## Orden de implementación (con checkpoints)

- **Fase 0** — `rgb-config.json` semilla + refactor `sync-rgb.py` (config, parser argv,
  `--only`, `--skip-config`, prioridad de color, filtrado de hilos).
  *Checkpoint*: sin args = comportamiento actual; `sync-rgb.py '#ff0000' --only mchose_base`
  solo cambia la base; `source:"fixed"` respetado.
- **Fase 1** — Esqueleto del módulo: `RgbControl.qml` (Scope + LazyLoader + dim + IpcHandler
  + objeto en `ShellState`) con `Content.qml` placeholder; `shell.qml` + `ShellState.qml`.
  *Checkpoint*: `caelestia shell ipc call rgb open` muestra el modal; clic fuera cierra.
- **Fase 2** — Contenido: `ColourPicker`, `DeviceCard`, `Chip`; pestaña `Inicio` +
  `Dispositivos` (acordeón) con `FileView` de `rgb-config.json`; ficha de la base vía CLI
  `mchose-config`; ficha OpenRGB con el toggle ARGB.
  *Checkpoint*: cambiar fuente/color/toggles/modo ARGB → JSON actualizado → "Aplicar ahora"
  cambia los LEDs correctos; paridad con la tarjeta inline.
- **Fase 3** — Migrar el widget: borrar tarjeta inline de las dos copias, `onClicked` →
  panel, botón "tune" en `DesktopLedStrip`.
  *Checkpoint*: `diff -q` vacío; `grep showMchoseSettings` vacío; clic en ratón abre panel.
- **Fase 4** — Flash: `rgb-notify-flash` + disparador QML + pestaña `Notificaciones` (con la
  lista de casillas de qué dispositivos flashean).
  *Checkpoint*: `notify-send` → flash + restauración; x5 seguidos = 1 flash; DND lo suprime;
  durante carga la base vuelve al efecto de carga.
- **Fase 5** — `install.sh`, `scripts/sync-repo.sh`, docs, checklist end-to-end completo.

## Visión futura (otra versión — al backlog de la bóveda)

- **Reacciones de batería por dispositivo.** Hoy "Eventos de batería" solo existe para la
  base (reacciona a la batería del ratón). Generalizarlo: cada dispositivo inalámbrico con
  luz define su propio efecto al cargar / de batería baja / umbral, en su ficha. El teclado
  Akko cambia de color con SU batería (requiere antes su batería real — hoy es un stub); los
  cascos V9 Pro no tienen luz, quedan fuera.
- **Brillo por dispositivo** (base, teclado, tira) — requiere exponer brillo/velocidad en
  los protocolos de teclado y tira.
- **Color fijo propio por dispositivo** que ignora el color global de reposo.
- **OpenRGB por zonas** (placa vs RAM vs cada cabecero de ventiladores por separado).
- **Notificaciones más ricas**: color por app, nivel de urgencia (`critical`/`normal`/`low`),
  indicador de "No molestar".
- **Perfiles / escenas** ("Trabajo", "Cine", "Noche") con atajo, y un **apagado maestro**.

## Verificación end-to-end

Recargar (`caelestia shell -k; sleep 0.5; caelestia shell -d`), abrir panel, color fijo
`#33cc88` → base + Akko + tira cambian; apagar OpenRGB → placa/RAM no cambian; cambiar tema
con `source:"fixed"` → LEDs no cambian, con `source:"theme"` → sí; `notify-send` → flash
complementario 2 pulsos y restaura; acoplar ratón → efecto de carga; mover
`rgb-config.json` fuera → comportamiento idéntico al actual.
