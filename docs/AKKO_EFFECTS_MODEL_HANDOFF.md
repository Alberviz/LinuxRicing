# Modelo unificado de efectos por dispositivo — handoff

**Rama:** `feat/akko-effects-model` (worktree `.worktrees/akko-effects`)
**Estado:** en implementación
**Objetivo:** una sola lista de efectos por dispositivo RGB, mostrada igual en la
ficha del dispositivo (pestaña *Dispositivos*) y en las reglas de batería
(pestaña *Notificaciones*). Empezamos por el teclado Akko; la base MCHOSE usa el
mismo modelo con su propio descriptor.

## El objeto "efecto"

```json
{
  "animation": "wave",
  "colour": { "source": "battery", "hex": "d8bde7" },
  "speed": 3,
  "direction": "down"
}
```

- **animation**: nombre de la animación de firmware (ver descriptor por dispositivo).
- **colour.source**: `theme` | `fixed` | `battery`.
  - `theme` = color primario de Matugen (con boost de saturación para LED).
  - `fixed` = `colour.hex`.
  - `battery` = rojo→ámbar→verde según nivel. En una regla de batería el nivel es
    el del disparador; en la ficha del dispositivo es el último nivel conocido de
    la caché (`mchose_battery.json`).
  - Algunas animaciones ignoran el color (Neón = arcoíris del firmware).
- **speed**: 1 (lento) .. 5 (rápido). Se traduce a `byte[2]`.
- **direction**: `right` | `left` | `down` | `up`. Solo la aplican las animaciones
  del set `directional` del descriptor (por ahora solo `wave` en el Akko).

## Descriptor de capacidades por dispositivo

`configs/quickshell/caelestia/services/DeviceEffects.qml` (singleton) y su gemelo
en Python `rgb/_device_effects.py`... **no** — el proyecto duplica helpers a
propósito. El descriptor vive en dos sitios que hay que mantener en sync:

- QML: `DeviceEffects.qml` singleton (para la UI).
- Python: tabla `DEVICE_EFFECTS` en `rgb/battery-lighting` y espejo en
  `rgb/sync-rgb.py` (para construir el paquete).

```
akko_keyboard:
  zones: [keys, sidestrip]          # dos zonas físicas independientes
  animations:
    keys:      [off, solid, breathing, neon, wave, sine_wave, kaleidoscope,
                line_wave, snake, ripple, press_action, converge, laser,
                circle_wave, dazzing, meteor, train, fireworks, raindrop]
    sidestrip: [off, solid, breathing, neon, wave, snake]
  colour_sources: [theme, fixed, battery]
  has_speed: true
  directional: [wave]

mchose_base:
  zones: []                         # un solo anillo
  animations: [off, solid, breathing, wave, hardware_battery]
  colour_sources: [theme, fixed, battery]
  has_speed: false
  directional: []
```

### Akko: animación -> `byte[1]`

| animation | byte[1] | animation | byte[1] |
|---|---|---|---|
| off | 0 | converge | 9 |
| solid | 1 | sine_wave | 10 |
| breathing | 2 | kaleidoscope | 11 |
| neon | 3 | line_wave | 12 |
| wave | 4 | laser | 14 |
| ripple | 5 | circle_wave | 15 |
| raindrop | 6 | dazzing | 16 |
| snake | 7 | meteor | 18 |
| press_action | 8 | train | 23 |
| | | fireworks | 24 |

`raindown` (17) **no funciona** en el 5075B — fuera de la lista.

### Akko: `byte[4]` = `0x08 | (dir << 4)`

`right`=0, `left`=1, `down`=2, `up`=3. Solo si `animation in directional`; si no,
`0x08`. Poner cualquier bit del nibble bajo (0x01/0x02/0x04) hace que el firmware
pinte en blanco: **solo `0x08`** en el nibble bajo.

### Akko: velocidad -> `byte[2]`

- Teclas (`0x07`): el firmware invierte -> `byte[2] = 5 - speed` (speed 1 -> 4 lento,
  speed 5 -> 0 rápido).
- Tira (`0x08`): directa -> `byte[2] = speed - 1`.

## Dónde se guarda

- **Ficha del dispositivo** — `~/.config/caelestia/rgb-config.json`:
  ```json
  "device_profiles": {
    "akko_keyboard": { "keys": <efecto>, "sidestrip": <efecto> },
    "mchose_base":   { "ring": <efecto> }
  }
  ```
- **Reglas de batería** — `~/.config/caelestia/battery-lighting.json`, cada acción:
  ```json
  { "target": "akko_keyboard", "zone": "keys", "effect": <efecto> }
  ```

## Migración

`RgbConfig.qml` y `rgb/battery-lighting` (`validate_config` / `seed_config`)
convierten los strings viejos:

| viejo (keys_mode / effect) | nuevo |
|---|---|
| theme | {solid, theme} |
| fixed | {solid, fixed} |
| battery_color | {solid, battery} |
| breathing | {breathing, theme} |
| breathing_battery | {breathing, battery} |
| wave / wave_battery | {wave, theme/battery} |
| stream_battery (sidestrip) | {snake, battery} |
| reactive_press | {press_action, theme} |
| red_static | {solid, fixed #ff0000} |
| red_breathing | {breathing, fixed #ff0000} |
| off / none | {off} |
| theme_breathing (mchose) | {breathing, theme} |
| hardware_battery (mchose) | {hardware_battery, battery} |

## UI

- `configs/quickshell/caelestia/modules/rgbcontrol/EffectEditor.qml` — componente
  compartido: chips de animación (del descriptor), selector de fuente de color +
  ColourPicker, slider de velocidad (si `has_speed`), selector de dirección
  (si la animación elegida está en `directional`).
- `AkkoCard.qml` usa `EffectEditor` x2 (teclas / tira).
- `BatteryActionRow.qml` usa `EffectEditor` x1 (por acción), con el `zone` que
  ya tiene el chip de zona.
- `DeviceCard.qml` (MCHOSE base) usa `EffectEditor` x1.
- `KeyboardPreview.qml` acepta el objeto efecto y anima animation+direction.

## Verificar

- `python -m pytest rgb/tests`
- `python -m py_compile rgb/battery-lighting rgb/sync-rgb.py`
- Sincronizar QML a `~/.config/quickshell/caelestia/` + reiniciar shell
  (`caelestia shell -k …`), confirmar `Configuration Loaded`.
- `akko-poke` sigue disponible para trastear a mano.
- Hardware: cambiar cada eje desde el panel y ver que el teclado obedece por
  2.4 GHz (sin keepalives).
