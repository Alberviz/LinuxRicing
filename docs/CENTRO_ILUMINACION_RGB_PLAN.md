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
2. **Alcance**: global — base MCHOSE (anillo + logo), teclado Akko (retro + tira lateral),
   placa/RAM/ventiladores (OpenRGB), tira MagicHome. Interruptor on/off por dispositivo.
3. **Selector de color**: paleta de presets (colores del tema + fijos comunes) + campo hex
   editable con validación. Sin `Canvas` ni rueda.
4. **Reposo**: selector "seguir tema (Material You) / color fijo".
5. **Base MCHOSE**: se conservan "efecto al cargar" y "alerta de batería baja" + umbral
   (son solo de la base, único dispositivo con batería). Siguen guardándose vía el CLI
   `mchose-config` (encadena `mchose-battery --trigger-lighting`).
6. **v1** incluye el motor "efecto temporal → restaurar" y el **flash al recibir
   notificación** (rojo / acento / complementario = tono +180° en HSV, N pulsos).

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
- **`Content.qml`** — tarjeta modal (`StyledRect`, ancho ~560, alto por contenido,
  `VerticalFadeFlickable` si desborda). Secciones:
  - (a) Fuente: "Seguir tema" / "Color fijo" + `ColourPicker` visible si `fixed`.
  - (b) Dispositivos: `Repeater` de 4 → `DeviceToggleRow` (icono + label + `StyledSwitch`).
  - (c) Base MCHOSE: chips efecto de carga / alerta batería baja / umbral + botón "Probar".
  - (d) Flash notificación: `StyledSwitch` + chips modo (rojo/acento/complementario) +
    nº pulsos (1-5) + "Probar flash".
  - (e) Footer: "Aplicar ahora" + "Cerrar".
- **`ColourPicker.qml`** — `Flow` de swatches (6 del tema: `m3primary/secondary/tertiary/
  primaryContainer/error/surfaceTint` + ~7 fijos) + `StyledTextField` hex
  (`validate: /^#?[0-9a-fA-F]{6}$/`). Expone `selectedColor` (hex string).
- **`DeviceToggleRow.qml`**, **`Chip.qml`** (port de `MchoseChip`).

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
  "fixed_color": "#d8bde7",
  "devices": { "mchose_base": true, "akko_keyboard": true, "openrgb": true, "magichome": true },
  "notification_flash": { "enabled": false, "mode": "accent", "pulses": 2 }
}
```

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
- **Fase 2** — Contenido: `ColourPicker`, `DeviceToggleRow`, `Chip`; secciones (a)(b)(e) con
  `FileView` de `rgb-config.json`; luego sección (c) base vía CLI `mchose-config`.
  *Checkpoint*: cambiar fuente/color/toggles → JSON actualizado → "Aplicar ahora" cambia los
  LEDs correctos; paridad con la tarjeta inline.
- **Fase 3** — Migrar el widget: borrar tarjeta inline de las dos copias, `onClicked` →
  panel, botón "tune" en `DesktopLedStrip`.
  *Checkpoint*: `diff -q` vacío; `grep showMchoseSettings` vacío; clic en ratón abre panel.
- **Fase 4** — Flash: `rgb-notify-flash` + disparador QML + sección (d).
  *Checkpoint*: `notify-send` → flash + restauración; x5 seguidos = 1 flash; DND lo suprime;
  durante carga la base vuelve al efecto de carga.
- **Fase 5** — `install.sh`, `scripts/sync-repo.sh`, docs, checklist end-to-end completo.

## Verificación end-to-end

Recargar (`caelestia shell -k; sleep 0.5; caelestia shell -d`), abrir panel, color fijo
`#33cc88` → base + Akko + tira cambian; apagar OpenRGB → placa/RAM no cambian; cambiar tema
con `source:"fixed"` → LEDs no cambian, con `source:"theme"` → sí; `notify-send` → flash
complementario 2 pulsos y restaura; acoplar ratón → efecto de carga; mover
`rgb-config.json` fuera → comportamiento idéntico al actual.
