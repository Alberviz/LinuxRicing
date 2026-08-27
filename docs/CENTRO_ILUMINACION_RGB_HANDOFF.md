# Handoff — Centro de Iluminación RGB

Estado del trabajo para poder **cerrar la conversación actual y retomar en una nueva sesión
sin perder contexto**. Léelo entero antes de tocar nada.

- **Rama:** `feat/obsidian-vault-and-rgb-control` (pusheada a `origin`).
- **Plan de diseño (fuente de la verdad):** `docs/CENTRO_ILUMINACION_RGB_PLAN.md`.
- **Mockup visual (Claude Design):** artifact `eee35834-5d30-42ef-bbd3-5431f332503c`
  (3 pantallas: Inicio · Dispositivos · Notificaciones). El diseño final debe parecerse a
  esto con los componentes reales de Caelestia.
- **Bóveda Obsidian:** `vault/Rice LinuxRicing/Centro de Iluminación RGB.md` y
  `vault/Rice LinuxRicing/Backlog - Efectos de iluminación.md`.

## Coordinación multi-agente (IMPORTANTE)

Alberto trabaja con Claude **y Gemini a la vez** en este repo, con la misma identidad git.
Reparto acordado: **Gemini = solo `vault/`**, **Claude = `rgb/`, `configs/quickshell/`,
`widgets/`, `docs/`, `install.sh`**. Antes de empezar: `git fetch && git log --oneline -10`
para ver qué se ha movido. Commitea pronto y a menudo (Gemini hace `git add -A` y puede
barrer tu working tree a medias).

## Qué está hecho y probado

Todo commiteado. Verificado en el shell en marcha con capturas (`grim`); los **clics** aún
no se han podido verificar de forma automatizada (ver "Cómo probar").

| Fase | Contenido | Estado |
|---|---|---|
| 0 | `rgb-config.json` + `sync-rgb.py` config-aware | ✅ probado (sin regresión en hardware) |
| 1 | Esqueleto del panel (overlay, 3 pestañas, animación abrir/cerrar) | ✅ renderiza, IPC abre/cierra |
| 2 | Las 3 pestañas con contenido real y enlazadas a la config | ✅ renderiza y refleja el estado real |
| 3 | El widget del ratón abre el panel; retirada la tarjeta inline | ✅ compila, sin errores |
| 4 | Motor de flash por notificación | ❌ pendiente |
| 5 | `install.sh`, docs, `scripts/sync-repo.sh` | ❌ pendiente |

### Archivos nuevos

**Python (`rgb/`, se despliegan a `~/.config/caelestia/` o `~/.local/bin/`):**
- `rgb/sync-rgb.py` — MODIFICADO. Lee `~/.config/caelestia/rgb-config.json`
  (`load_rgb_config`), prioridad de color en `get_hex_color(config, cli_hex)`, parser
  `parse_argv` (`[hex]`, `--only a,b,c`, `--skip-config`), filtra hilos por
  `devices`. Color fijo/CLI se envía sin realce de saturación. Sin config = comportamiento
  antiguo. Desplegado en `~/.config/caelestia/sync-rgb.py`.
- `configs/caelestia/rgb-config.json` — semilla del esquema nuevo. Ya copiado a
  `~/.config/caelestia/rgb-config.json`.

**QML — servicios (`configs/quickshell/caelestia/services/`, singletons auto-registrados):**
- `RgbConfig.qml` — mirror de `rgb-config.json`. Propiedades `source`, `fixedColour`,
  `devices` (objeto), `openrgbArgbZones`, `flash*`. Setters (`setSource`, `setFixedColour`,
  `setDevice`, …) que guardan (debounce 250 ms) y re-lanzan `sync-rgb.py` (debounce 500 ms).
  `apply()` fuerza el re-lanzamiento.
- `MchoseConfig.qml` — mirror de `mchose-config.json`. `setCharging/setLowBat/setThreshold`
  escriben vía el CLI `~/.local/bin/mchose-config` (que encadena
  `mchose-battery --trigger-lighting`). `previewCharging()` → `mchose-lighting`.

**QML — módulo del panel (`configs/quickshell/caelestia/modules/rgbcontrol/`):**
- `RgbControl.qml` — raíz. `Scope { LazyLoader { Variants { StyledWindow(overlay) } } IpcHandler CustomShortcut }`.
  Funciones `open()/openTab(i)/close()/toggle()`. `Binding` a `ShellState.rgbControl`.
  IPC target `"rgb"`. Shortcut `caelestia:rgbControl`.
- `Content.qml` — tarjeta modal: cabecera + barra de 3 pestañas + `StackLayout` de vistas +
  footer "Aplicar ahora". `property int tab`.
- `InicioView.qml` — estado en reposo: segmentado tema/fijo (`Chip`) + `ColourPicker`.
- `DispositivosView.qml` — acordeón de 4 `DeviceCard`. La base MCHOSE tiene dentro los
  eventos de batería (chips de `MchoseConfig`). OpenRGB tiene el toggle RGB/ARGB.
- `NotificacionesView.qml` — flash on/off + color + `StyledSpinBox` de pulsos + casillas
  "qué dispositivos flashean" + tarjeta "Más adelante".
- `DeviceCard.qml` — ficha expandible (cabecera clicable + cuerpo con `clip` y altura
  animada). `default property alias content` → el cuerpo.
- `ColourPicker.qml` — swatches del tema + fijos + `StyledTextField` hex validado.
- `Chip.qml` — píldora seleccionable (port de `MchoseChip`).

### Archivos modificados

- `configs/quickshell/caelestia/shell.qml` — `import "modules/rgbcontrol"` + `RgbControl {}`.
- `configs/quickshell/caelestia/services/ShellState.qml` — `property QtObject rgbControl`.
- `configs/quickshell/caelestia/modules/background/Background.qml` **y su gemelo byte-idéntico**
  `widgets/Background.qml` — quitada la tarjeta inline `mchoseSettingsCard`, el componente
  `MchoseChip`, y el estado/Process/funciones `save*`. El `DeviceItem` "K7 Ultra" hace
  `onClicked: ShellState.rgbControl?.openTab(1)`. Botón `tune` añadido al header del widget
  de tira LED. **Mantener las dos copias idénticas** (`diff -q` debe salir vacío).

## Bugs / cosas a medias (feedback de Alberto, 2026-08-27)

1. **Acordeón no colapsaba** — `DeviceCard.qml` reescrito (cabecera = `StateLayer` sobre un
   `Item`, cuerpo = `Item` con `clip` + `height` animada). *El renderizado colapsado/expandido
   sí funciona* (verificado con un timer). **Falta verificar que el CLIC en la cabecera
   togglea** — necesita ydotool (ver abajo). Si el clic no llega: probar `TapHandler` en la
   cabecera, o hacer la cabecera un `StyledRect` con el `StateLayer` como primer hijo (patrón
   `DeviceItem` de `Background.qml`, que funciona).
2. **Pestañas sin marco redondeado** — arreglado en `Content.qml` (`radius: height/2`,
   contenedor `m3surfaceContainerLowest` alpha, píldora activa `m3secondaryContainer`).
   Revisar visualmente que convence.
3. **"Va raro" en general** — falta el pase de diseño fino: espaciado entre secciones,
   jerarquía tipográfica, footer contextual por pestaña (en Notificaciones "Aplicar ahora"
   sobra), `VerticalFadeFlickable` cuando el contenido desborda la pantalla (Dispositivos con
   varias fichas abiertas), estados hover/disabled.
4. **Sin verificar en absoluto**: que los chips guarden de verdad, que "Aplicar ahora" cambie
   los LEDs, que el clic en el ratón abra el panel, que el switch por dispositivo funcione.

## Cómo desplegar y recargar

```bash
cd ~/LinuxRicing
# QML
cp -r configs/quickshell/caelestia/modules/rgbcontrol ~/.config/quickshell/caelestia/modules/
cp configs/quickshell/caelestia/services/{RgbConfig,MchoseConfig,ShellState}.qml ~/.config/quickshell/caelestia/services/
cp configs/quickshell/caelestia/shell.qml ~/.config/quickshell/caelestia/shell.qml
cp configs/quickshell/caelestia/modules/background/Background.qml ~/.config/quickshell/caelestia/modules/background/Background.qml
# Python
cp rgb/sync-rgb.py ~/.config/caelestia/sync-rgb.py
# recargar
caelestia shell -k; sleep 1; setsid caelestia shell -d >/tmp/cae.log 2>&1 </dev/null & disown; sleep 4
grep -iE "error|warn" /tmp/cae.log | grep -viE "deprecat|QSG"
```

## Cómo probar

- **Capturas:** `grim /tmp/shot.png` y leerla.
- **Abrir/cerrar/pestañas por IPC:** `qs -c caelestia ipc call rgb openTab 1` (0=Inicio,
  1=Dispositivos, 2=Notificaciones), `... rgb close`, `... rgb toggle`.
- **Ver targets IPC:** `qs -c caelestia ipc show`.
- **Estado del panel = ficheros JSON:** editar `~/.config/caelestia/rgb-config.json` y
  `~/.config/caelestia/mchose-config.json`, recargar, capturar.
- **Clics automatizados (ydotool):** el demonio necesita root una vez. En una terminal
  aparte: `sudo ydotoold -p /run/user/1000/.ydotool_socket -o 1000:1000` (dejar corriendo).
  Luego: `export YDOTOOL_SOCKET=/run/user/1000/.ydotool_socket`;
  `ydotool mousemove -a <x> <y>`; `ydotool click 0xC0` (clic izquierdo). Coordenadas: leer de
  la captura (el panel está centrado en pantalla).
- **Regresión de `sync-rgb.py`:** `python3 rgb/sync-rgb.py` sin args = comportamiento
  anterior (ver `/tmp/sync-rgb.log`). `python3 rgb/sync-rgb.py '#00ff00' --only mchose_base`
  solo la base.

## Lo que queda

### Pase de diseño (prioridad de Alberto)
Comparar cada pestaña con el mockup y ajustar hasta que convenza. Verificar con ydotool que
todo lo clicable responde. Añadir scroll (`components/containers/VerticalFadeFlickable`)
cuando el contenido desborde.

### Fase 4 — Motor de flash (ver `docs/CENTRO_ILUMINACION_RGB_PLAN.md` §4)
- `rgb/rgb-notify-flash` (Python, cero deps): `--mode {red|accent|complementary} --pulses N
  [--test]`. `flock` en `~/.cache/rgb_flash.lock`. Complementario = HSV hue+180 del color
  efectivo (fijo o primary). Dispositivos: base MCHOSE + Akko + (MagicHome si pulses≤2).
  **Nunca OpenRGB** (bus SMBus). Restauración: re-lanzar `sync-rgb.py`; excepción si
  `~/.cache/mchose_battery.json` tiene `k7_was_charging`/`k7_was_low`.
- En `RgbControl.qml` (en el `Scope`, no en el `LazyLoader`): `Connections { target: Notifs }`
  → detectar item nuevo por `id`, ignorar si `Notifs.dnd`, filtrar `appName` propias, debounce
  `Timer` → `Quickshell.execDetached(["rgb-notify-flash", ...])`. Solo si
  `RgbConfig.flashEnabled`.
- Botón "Probar flash" en `NotificacionesView.qml` → `rgb-notify-flash --test`.

### Fase 5 — Instalador y cierre
- `install.sh`: copiar `mchose-config`, `mchose-lighting`, `rgb-notify-flash` a
  `~/.local/bin/`; semilla `rgb-config.json` sin sobrescribir. (Hoy solo copia `sync-rgb.py`,
  `mchose-battery`, `magichome-control`.)
- `scripts/sync-repo.sh` + hook pre-commit opcional para `diff -q` de las parejas
  (`widgets/Background.qml` ⇔ `configs/.../background/Background.qml`).
- Actualizar `docs/HARDWARE_PROTOCOLS.md` / `README.md` / la nota de la bóveda.

### Backlog (futuras versiones) — en la bóveda
Reacciones de batería por dispositivo, brillo por dispositivo, color propio por dispositivo,
OpenRGB por zonas, perfiles/escenas, apagado maestro, color de flash por app, etc.
Ver `vault/Rice LinuxRicing/Backlog - Efectos de iluminación.md`.
