# Handoff — Centro de Iluminación RGB

> **Para una sesión nueva:** este documento es autosuficiente. Léelo entero, luego lee
> `docs/CENTRO_ILUMINACION_RGB_PLAN.md`. Cuando Alberto diga *"empieza con las fases 4 y 5"*,
> haz la **Fase 4** (motor de flash) y la **Fase 5** (instalador + cierre) siguiendo las
> secciones detalladas de abajo. Antes de nada: `git fetch && git log --oneline -12` y
> comprueba que estás en la rama `feat/obsidian-vault-and-rgb-control`.

## Contexto en 30 segundos

Se ha sustituido el desplegable inline de ajustes de la base MCHOSE por un **panel único**
(`Centro de Iluminación`) en el shell Caelestia/Quickshell que controla la iluminación de
todos los periféricos. El panel es un overlay Wayland centrado, con 3 pestañas:
**Inicio** (color en reposo: seguir tema / fijo), **Dispositivos** (acordeón, una ficha por
dispositivo; la base MCHOSE lleva dentro los eventos de batería), **Notificaciones** (flash).
Fases 0-3 hechas y desplegadas. Faltan **4** (flash) y **5** (instalador).

- **Rama:** `feat/obsidian-vault-and-rgb-control` (en `origin`).
- **Plan de diseño:** `docs/CENTRO_ILUMINACION_RGB_PLAN.md`.
- **Mockup visual:** artifact `eee35834-5d30-42ef-bbd3-5431f332503c` (Claude Design, 3 pantallas).
- **Bóveda:** `vault/Rice LinuxRicing/Centro de Iluminación RGB.md` + `… Backlog - Efectos de iluminación.md`.

## Coordinación multi-agente (IMPORTANTE)

Alberto usa Claude **y Gemini** a la vez en este repo, misma identidad git. Reparto:
**Gemini = solo `vault/`**; **Claude = `rgb/`, `configs/quickshell/`, `widgets/`, `docs/`,
`install.sh`**. `git fetch` a menudo; commitea pronto (Gemini hace `git add -A` y puede
barrer tu working tree a medias).

## Estado: hecho y probado

| Fase | Contenido | Estado |
|---|---|---|
| 0 | `rgb-config.json` + `sync-rgb.py` config-aware | ✅ probado en hardware, sin regresión |
| 1 | Esqueleto del panel (overlay, 3 pestañas, animaciones) | ✅ renderiza; IPC abre/cierra |
| 2 | Las 3 pestañas con contenido real, enlazadas a la config | ✅ renderiza y refleja el estado real |
| 3 | El widget del ratón abre el panel; retirada la tarjeta inline | ✅ compila, sin errores QML |
| 4 | Motor de flash por notificación | ❌ **PENDIENTE** |
| 5 | `install.sh`, `scripts/sync-repo.sh`, docs | ❌ **PENDIENTE** |

**Verificado con capturas (`grim`).** Los clics NO se han podido verificar de forma
automatizada (ydotool necesitaba `ydotoold` con root). Pendiente de confirmar por Alberto o
con ydotool: que los chips guarden, que "Aplicar ahora" cambie los LEDs, que el clic en el
ratón abra el panel, que el acordeón colapse al clicar la cabecera.

## Mapa de archivos

### Python — `rgb/` → desplegado en `~/.config/caelestia/` y `~/.local/bin/`

- **`rgb/sync-rgb.py`** (MODIFICADO, desplegado en `~/.config/caelestia/sync-rgb.py`):
  - `load_rgb_config()` lee `~/.config/caelestia/rgb-config.json`; sin fichero → defaults =
    comportamiento antiguo.
  - `get_hex_color(config, cli_hex)` → `(hex, from_theme)`. Prioridad: cli_hex >
    `SCHEME_COLOURS` env > `config.source=="fixed"` → `fixed_color` > `scheme.json` primary >
    fallback. `from_theme=False` para fijo/CLI → se envía **sin** `enhance_color_for_leds`.
  - `parse_argv()`: `sync-rgb.py [hex] [--only a,b,c] [--skip-config]`.
  - `main()` filtra los hilos por `config["devices"]` ∩ `--only`.
- **`configs/caelestia/rgb-config.json`** (semilla, ya copiada a `~/.config/caelestia/`):
  ```json
  {
    "source": "theme",
    "fixed_color": "d8bde7",
    "devices": { "openrgb": true, "magichome": true, "mchose_base": true, "akko_keyboard": true, "spicetify": true },
    "devices_extra": { "openrgb": { "argb_zones": false } },
    "notification_flash": { "enabled": false, "mode": "accent", "pulses": 2, "devices": ["mchose_base", "akko_keyboard"] }
  }
  ```
- Sin tocar (referencia para la Fase 4): `rgb/mchose-battery` (máquina de estados de la base;
  caché `~/.cache/mchose_battery.json` con `k7_was_charging`, `k7_was_low`),
  `rgb/mchose-lighting`, `rgb/mchose-config`, `rgb/magichome-control`.

### QML — servicios `configs/quickshell/caelestia/services/` (singletons)

- **`RgbConfig.qml`** — mirror de `rgb-config.json`. `source`, `fixedColour`, `devices`,
  `openrgbArgbZones`, `flashEnabled`, `flashMode`, `flashPulses`, `flashDevices`. Setters
  guardan (debounce 250 ms) y `apply()` re-lanza `sync-rgb.py` (debounce 500 ms). **La Fase 4
  usa `RgbConfig.flashEnabled/flashMode/flashPulses/flashDevices` y las lee sin abrir el panel.**
- **`MchoseConfig.qml`** — mirror de `mchose-config.json`; escribe vía el CLI `mchose-config`.

### QML — módulo `configs/quickshell/caelestia/modules/rgbcontrol/`

- **`RgbControl.qml`** — `Scope { LazyLoader{Variants{StyledWindow overlay}} IpcHandler CustomShortcut }`.
  `open()/openTab(i)/close()/toggle()`. `Binding` → `ShellState.rgbControl`. IPC target `"rgb"`.
  **La Fase 4 añade aquí, dentro del `Scope` (no del `LazyLoader`), el `Connections` a `Notifs`.**
- `Content.qml` — cabecera + barra de pestañas + `StackLayout` + footer "Aplicar ahora".
- `InicioView.qml`, `DispositivosView.qml`, `NotificacionesView.qml` — las 3 vistas.
- `DeviceCard.qml` — ficha expandible (cabecera clicable + cuerpo `clip` con altura animada).
- `ColourPicker.qml`, `Chip.qml`.

### QML — modificados

- `shell.qml` — `import "modules/rgbcontrol"` + `RgbControl {}`.
- `services/ShellState.qml` — `property QtObject rgbControl`.
- `modules/background/Background.qml` **+ gemelo byte-idéntico `widgets/Background.qml`** —
  quitada la tarjeta `mchoseSettingsCard`, `MchoseChip` y el estado/funciones `save*`;
  `DeviceItem` "K7 Ultra" → `onClicked: ShellState.rgbControl?.openTab(1)`; botón `tune` en el
  header del widget de tira LED. **Editar SIEMPRE las dos rutas idénticas** (`diff -q` vacío).

## Cambio de Gemini a tener en cuenta

El commit `1e335ae` (Gemini) **quitó** el `onClicked: ShellState.rgbControl?.openTab(1)` del
`DeviceItem` "K7 Ultra" y en su lugar añadió un botón `tune` en la **cabecera del widget de
Periféricos** que hace `ShellState.rgbControl?.open()`. Es decir: ahora el panel se abre
desde ese botón, no clicando el ratón. Alberto pidió originalmente que fuera el clic en el
ratón — **preguntarle** si quiere el clic en el ratón de vuelta (pueden coexistir).

## Bugs abiertos (feedback de Alberto, aún sin cerrar del todo)

1. **Acordeón** — reescrito `DeviceCard.qml`; el renderizado colapsado/expandido funciona
   (verificado con timer). **Falta confirmar que el CLIC en la cabecera togglea.** Si no:
   usar `TapHandler`, o hacer la cabecera un `StyledRect` con `StateLayer` como primer hijo
   (patrón `DeviceItem` de `Background.qml`, que sí funciona).
2. **Pestañas** — arregladas (`radius: height/2`, más contraste). Revisar que convence.
3. **Pase de diseño fino pendiente**: espaciado entre secciones, footer contextual (en
   Notificaciones "Aplicar ahora" sobra), `VerticalFadeFlickable` cuando desborda, hover/disabled.

## Desplegar y recargar

```bash
cd ~/LinuxRicing
cp -r configs/quickshell/caelestia/modules/rgbcontrol ~/.config/quickshell/caelestia/modules/
cp configs/quickshell/caelestia/services/{RgbConfig,MchoseConfig,ShellState}.qml ~/.config/quickshell/caelestia/services/
cp configs/quickshell/caelestia/shell.qml ~/.config/quickshell/caelestia/shell.qml
cp configs/quickshell/caelestia/modules/background/Background.qml ~/.config/quickshell/caelestia/modules/background/Background.qml
cp rgb/sync-rgb.py ~/.config/caelestia/sync-rgb.py
cp rgb/rgb-notify-flash ~/.local/bin/rgb-notify-flash 2>/dev/null; chmod +x ~/.local/bin/rgb-notify-flash 2>/dev/null
caelestia shell -k; sleep 1; setsid caelestia shell -d >/tmp/cae.log 2>&1 </dev/null & disown; sleep 4
grep -iE "error|warn" /tmp/cae.log | grep -viE "deprecat|QSG"
```

## Probar

- Capturas: `grim /tmp/shot.png`.
- IPC: `qs -c caelestia ipc call rgb openTab 1` (0/1/2), `... rgb close`, `qs -c caelestia ipc show`.
- Estado = ficheros: editar `~/.config/caelestia/{rgb-config,mchose-config}.json`, recargar, capturar.
- Clics (ydotool): en terminal aparte `sudo ydotoold -p /run/user/1000/.ydotool_socket -o 1000:1000`;
  luego `export YDOTOOL_SOCKET=/run/user/1000/.ydotool_socket`; `ydotool mousemove -a X Y`;
  `ydotool click 0xC0`.
- Flash (Fase 4): `notify-send "prueba" "hola"` con `RgbConfig.flashEnabled=true` en la config.

---

# FASE 4 — Motor de flash por notificación

**Objetivo:** al llegar una notificación (con el flash activado en la pestaña Notificaciones),
los dispositivos seleccionados dan N pulsos de color y vuelven al estado anterior.

## 4.1 — `rgb/rgb-notify-flash` (Python, cero dependencias)

Crear el archivo, `chmod +x`, y también copiarlo a `~/.local/bin/rgb-notify-flash`.

Interfaz: `rgb-notify-flash [--mode red|accent|complementary] [--pulses N] [--test]`.
Si no se pasan flags, leer todo de `~/.config/caelestia/rgb-config.json`
(`notification_flash.{mode,pulses,devices}`).

Comportamiento:

1. **Lock** con `fcntl.flock(LOCK_EX|LOCK_NB)` sobre `~/.cache/rgb_flash.lock`. Si ya hay un
   flash en curso → salir en silencio (evita solapamiento con ráfagas de notificaciones).
2. **Resolver el color del flash:**
   - `red` → `(255, 0, 0)`.
   - `accent` → primary del tema. Leer `~/.local/state/caelestia/scheme.json` →
     `colours.primary` (copiar el helper `get_theme_primary_rgb` de `rgb/mchose-battery`).
   - `complementary` → color **efectivo actual** → HSV → `h = (h + 0.5) % 1.0` → RGB.
     "Color efectivo": si `rgb-config.source == "fixed"` → `fixed_color`; si no → primary del
     tema. Usar `colorsys.rgb_to_hsv` / `hsv_to_rgb`.
3. **Qué dispositivos parpadean:** intersección de `notification_flash.devices` con los que
   estén `true` en `devices`. **NUNCA `openrgb`** (bus SMBus lento). `magichome` solo si
   `pulses <= 2` (latencia Wi-Fi). Base y teclado siempre que estén en la lista.
4. **Pulso (repetir `pulses` veces):**
   - enviar color-flash a: base MCHOSE (target `0x06` estático — misma construcción de
     payload que `sync_mchose_base` en `sync-rgb.py`), Akko (opcodes `0x07`+`0x08` estáticos —
     misma que `sync_akko_keyboard`), MagicHome (`magichome-control --color`).
   - `time.sleep(0.18)`
   - enviar negro/apagado a los mismos.
   - `time.sleep(0.18)`
5. **Restaurar** al terminar:
   - Lanzar `python3 ~/.config/caelestia/sync-rgb.py` (deja el estado estable de
     `rgb-config.json`).
   - **Excepción base MCHOSE:** leer `~/.cache/mchose_battery.json`. Si `k7_was_charging` es
     `true` → NO dejar que sync-rgb ponga la base estática; en su lugar
     `os.system("~/.local/bin/mchose-battery --trigger-lighting")`. Si `k7_was_low` es
     `true` → re-aplicar la alerta de batería baja (`mchose-lighting` según
     `low_battery_effect` de `mchose-config.json`, o dejar que `mchose-battery` lo haga).
6. **`--test`**: ignora todo lo demás y hace un flash de 2 pulsos con el modo actual.

Reutilizar código: copiar de `rgb/sync-rgb.py` las funciones `HIDIOCSFEATURE`, el glob de
hidraw para `3151:4015` (Akko) y `3837:1001` (base), y la construcción de payloads. El
proyecto ya duplica helpers entre scripts — es el estilo, no hagas imports cruzados.

## 4.2 — Disparador en QML

En **`RgbControl.qml`**, dentro del `Scope` (NO dentro del `LazyLoader`, para que funcione
aunque el panel no se haya abierto nunca):

```qml
import qs.services   // ya importado

// ... dentro del Scope:

property string lastFlashedId: ""

Connections {
    target: Notifs

    function onListChanged(): void {
        if (!RgbConfig.flashEnabled)
            return;
        const n = Notifs.list[0];
        if (!n || String(n.notificationId) === scope.lastFlashedId)
            return;
        scope.lastFlashedId = String(n.notificationId);
        if (Notifs.dnd)
            return;
        // ignora las notificaciones del propio sistema de batería / RGB
        const app = (n.appName || "").toLowerCase();
        if (app.includes("mchose") || app.includes("battery") || app.includes("iluminaci"))
            return;
        flashDebounce.restart();
    }
}

Timer {
    id: flashDebounce
    interval: 400
    onTriggered: Quickshell.execDetached([
        Quickshell.env("HOME") + "/.local/bin/rgb-notify-flash",
        "--mode", RgbConfig.flashMode,
        "--pulses", String(RgbConfig.flashPulses)
    ])
}
```

Verificar el nombre exacto de la señal de `Notifs` (`onListChanged` / o conectar a
`NotificationServer.onNotification` si hiciera falta; `Notifs.list` se **prepende** al llegar
una notificación, así que `list[0]` es la más nueva).

## 4.3 — Botón "Probar flash" en `NotificacionesView.qml`

Añadir bajo el spinbox de pulsos un botón (mismo estilo que "Probar" de `DispositivosView`)
que haga `Quickshell.execDetached([".../rgb-notify-flash", "--test"])`.

## 4.4 — Verificación Fase 4

1. `rgb-notify-flash --mode red --pulses 3` en terminal → la base y el teclado parpadean 3
   veces en rojo y vuelven al color del tema.
2. `--mode complementary` → calcula el tono opuesto del color efectivo.
3. Lanzar `rgb-notify-flash` 5 veces seguidas → solo un flash (lock).
4. En el shell con `flashEnabled=true`: `notify-send "x" "y"` → flash. Con DND activo → nada.
5. Acoplar el ratón a la base (que quede cargando), `notify-send` → tras el flash la base
   vuelve al **efecto de carga**, no a estático (excepción `k7_was_charging`).
6. Sin OpenRGB tocado nunca (revisar que la placa/RAM no parpadean).

---

# FASE 5 — Instalador y cierre

## 5.1 — `install.sh`

En la sección `# 6. Instalar RGB Hardware Control` (`if [ "$SELECTED_RGB" = true ]`), añadir:

```bash
for tool in mchose-config mchose-lighting rgb-notify-flash; do
    if [ -f "$BASE_DIR/rgb/$tool" ]; then
        cp -u "$BASE_DIR/rgb/$tool" "$HOME/.local/bin/$tool"
        chmod +x "$HOME/.local/bin/$tool"
    fi
done
# semilla de config sin sobrescribir la del usuario
if [ ! -f "$HOME/.config/caelestia/rgb-config.json" ] && [ -f "$BASE_DIR/configs/caelestia/rgb-config.json" ]; then
    cp "$BASE_DIR/configs/caelestia/rgb-config.json" "$HOME/.config/caelestia/rgb-config.json"
fi
```

El módulo QML `modules/rgbcontrol/` y `shell.qml` ya los despliega el `cp -ru` de la sección
Caelestia; `services/RgbConfig.qml` y `MchoseConfig.qml` también. Verificarlo.

## 5.2 — `scripts/sync-repo.sh` (nuevo)

Script que:
- copia `widgets/Background.qml` → `configs/quickshell/caelestia/modules/background/Background.qml`
  (o al revés; definir cuál es el master — sugerido: editar ambos siempre y que el script
  solo **verifique** con `diff -q` y falle si difieren).
- opcionalmente un hook `.git/hooks/pre-commit` que aborte si las parejas difieren
  (`widgets/Background.qml` ⇔ el de `modules/background/`, `configs/caelestia/cli.json` ⇔
  `configs/cli.json`).

## 5.3 — Docs

- `hardware/` / `README.md`: mencionar el panel y el esquema `rgb-config.json`.
- `docs/CENTRO_ILUMINACION_RGB_PLAN.md`: marcar fases 4-5 como hechas.
- Nota de la bóveda (`vault/Rice LinuxRicing/Centro de Iluminación RGB.md`): actualizar el
  Registro. (Pero coordina — `vault/` es de Gemini; añade, no reescribas.)

## 5.4 — Cierre

- Recargar el shell y correr el checklist de verificación de
  `docs/CENTRO_ILUMINACION_RGB_PLAN.md` §"Verificación end-to-end".
- Pase de diseño final comparando con el mockup.
- `superpowers:finishing-a-development-branch` para integrar (merge a `main` cuando Alberto dé el OK).

---

## Backlog (futuras versiones)

En `vault/Rice LinuxRicing/Backlog - Efectos de iluminación.md`: reacciones de batería por
dispositivo, brillo por dispositivo, color propio por dispositivo, OpenRGB por zonas,
perfiles/escenas, apagado maestro, color de flash por app, nivel de urgencia, indicador DND.
