# Motor unificado de iluminación reactiva a la batería — diseño

**Fecha:** 2026-08-27
**Rama:** `feat/battery-lighting-engine` (desde `main`)
**Estado:** diseño aprobado, pendiente de plan de implementación

## Problema

Hoy la reacción de la iluminación a la batería está repartida y escrita a fuego en tres sitios
que no se hablan entre sí:

- `rgb/mchose-battery` → `apply_akko_battery_lighting()`: reglas fijas del Akko (gradiente al
  cargar, rojo respiración ≤ 20 %), aplicadas en cada tick del timer de 60 s.
- `rgb/sync-rgb.py` → `sync_akko_keyboard()`: **las mismas reglas duplicadas**, aplicadas en
  cada cambio de tema/wallpaper.
- `rgb/mchose-config` + `MchoseConfig.qml`: efecto del anillo de la base MCHOSE al cargar / con
  batería baja, configurable pero **solo afecta al propio anillo**.

El frontend `AkkoCard.qml` / `AkkoConfig.qml` (rama ya mergeada) guarda preferencias del teclado
en `~/.config/caelestia/akko-config.json` pero **ningún backend las lee**.

No hay forma de decir "cuando los auriculares bajen del 20 %, que parpadee en rojo el anillo de
la base y la torre". Eso es lo que pide este trabajo: enrutar cualquier evento de batería de
cualquier dispositivo a cualquier zona RGB.

## Objetivo

Un **motor de reglas** único: un config, un aplicador, un resolutor de prioridad. Sustituye a
todo lo anterior. UI nueva en la pestaña "Notificaciones" del Centro de Iluminación.

### Fuera de alcance (v1)

- Paridad en Windows (`rgb/sync-rgb-windows.py`). Se hará después contra el mismo esquema.
- Efectos musicales / Ambilight del catálogo del firmware.
- Selector de color manual por acción (el color lo decide el efecto: tema / nivel de batería / rojo).

## Arquitectura

```
baterías (V9 Pro · K7 Ultra · Akko 5075B)
   │  lectura HID / UPower  (ÚNICO lector: el daemon)
   ▼
battery-lighting  (daemon systemd --user, Restart=always)
   ├─ escribe  ~/.cache/mchose_battery.json     (telemetría; lo consumen widgets y --notify)
   ├─ lee      ~/.config/caelestia/battery-lighting.json
   ├─ resuelve prioridad por zona:  critical > low > charging > (sin alerta → tema)
   ├─ aplica el efecto ganador a cada zona reclamada
   ├─ escribe  ~/.cache/battery_alerts.json     (zona → {effect, trigger, source})
   └─ envía notificaciones de escritorio (batería baja / crítica)  → sustituye a `mchose-battery --notify`

sync-rgb.py (cambio de tema/wallpaper)
   └─ antes de pintar cada zona: si está en battery_alerts.json, NO la pisa

rgb-notify-flash (pulso de notificación)
   └─ al restaurar: vuelve al efecto de alerta si la zona está reclamada, si no al color de tema
```

### Cadencia adaptativa

- **Reposo:** sondeo cada `poll.idle_seconds` (def. 60).
- **Cargando + hay alguna regla `charging` con efecto de medidor sobre ese origen:** cada
  `poll.charging_seconds` (def. 3) mientras siga enchufado. Vuelve a 60 s al desenchufar.
- Nunca por debajo de 2 s (la radio 2.4 GHz del Akko se corrompe con escrituras muy seguidas —
  `vault/…/Base de Datos de Errores.md`). Las escrituras al Akko además solo se emiten cuando el
  estado calculado cambia (nivel apreciable, trigger, efecto), no cada tick.

### Único dueño de la telemetría

Para no colisionar en el bus HID (sobre todo el dongle del Akko), **solo el daemon lee batería**.
`mchose-battery --json` (lo consumen los widgets Quickshell y Waybar) pasa a servir desde
`~/.cache/mchose_battery.json`; si el daemon no corre, cae a lectura directa como fallback
(comportamiento actual) para no romper los widgets. `mchose-battery --notify` y su timer se
retiran: las notificaciones de escritorio las emite el daemon.

`v9_headset` sólo puede ser **origen** (los auriculares no tienen RGB direccionable); no aparece
como `target`.

## Componentes

### 1. `rgb/battery-lighting` (nuevo, ejecutable Python, sin dependencias entre scripts)

Sigue el estilo del repo: helpers HID propios copiados, nada de módulo compartido.

| Modo | Uso |
|---|---|
| `battery-lighting --daemon` | Bucle principal. Lo lanza `battery-lighting.service`. |
| `battery-lighting --tick` | Un ciclo (lee, resuelve, aplica) y sale. Para pruebas y para el arranque. |
| `battery-lighting --apply <rule-id>` | Fuerza una regla (botón "Probar" de la UI). |
| `battery-lighting --clear` | Suelta todas las alertas y repinta al tema. |
| `battery-lighting --dump` | Imprime estado resuelto en JSON (debug). |

Responsabilidades:

1. **Telemetría:** lee V9 / K7 / Akko (código portado de `mchose-battery`), escribe la caché.
2. **Resolución:** para cada regla activa (su `source` cumple el `trigger`), expande sus
   `actions`; agrupa por `(target, zone)`; el trigger más severo gana; empate → orden de la
   lista. Resultado: mapa `zona → acción ganadora`.
3. **Aplicación:** por cada zona, renderiza el efecto (ver §"Efectos"). Sólo emite al hardware
   si la acción difiere de la última emitida a esa zona (`~/.cache/battery_lighting_state.json`).
4. **Estado compartido:** escribe `~/.cache/battery_alerts.json` para `sync-rgb.py` y
   `rgb-notify-flash`. Zonas sin alerta → se eliminan del fichero y se repintan una vez al color
   de tema (llamando a `sync-rgb.py --only <device>` o pintando directo).
5. **Notificaciones de escritorio:** misma lógica de umbrales que hoy tiene `mchose-battery`
   (`notify-send`, dedupe por nivel en la caché).

### 2. `~/.config/caelestia/battery-lighting.json`

```json
{
  "poll": { "idle_seconds": 60, "charging_seconds": 3 },
  "critical_threshold": 10,
  "rules": [
    {
      "id": "akko-charging",
      "source": "akko_keyboard",
      "trigger": "charging",
      "actions": [
        { "target": "akko_keyboard", "zone": "keys",     "effect": "battery_meter" },
        { "target": "akko_keyboard", "zone": "sidestrip", "effect": "stream_battery" }
      ]
    },
    {
      "id": "akko-low",
      "source": "akko_keyboard",
      "trigger": "low",
      "threshold": 20,
      "actions": [ { "target": "akko_keyboard", "zone": "both", "effect": "red_breathing" } ]
    }
  ]
}
```

- `source`: `akko_keyboard | mchose_mouse | v9_headset`
- `trigger`: `charging | low | critical`
  - `low`: `threshold` entero 5–40 (paso 5).
  - `critical`: usa `critical_threshold` global (def. 10). Prioridad máxima.
  - `charging`: activo mientras el origen esté enchufado / en base.
- `action`: `{ target, zone?, effect }`
  - `target`: `akko_keyboard | mchose_base | magichome | openrgb`
  - `zone`: sólo si `target == akko_keyboard`: `keys | sidestrip | both`
  - `effect`: enum según destino/zona (tabla abajo). Efecto desconocido → `none` + log.

Validación: JSON malformado o esquema inválido → se ignora el fichero, se usan las reglas
sembradas, se avisa por log (`journalctl --user -u battery-lighting`).

### 3. Efectos por destino

| destino / zona | efectos válidos |
|---|---|
| `akko_keyboard` / `keys` | `theme` · `battery_meter` · `breathing_battery` · `stream` · `red_breathing` · `red_static` · `none` |
| `akko_keyboard` / `sidestrip` | `stream_battery` · `breathing` · `solid_theme` · `red_breathing` · `red_static` · `none` |
| `mchose_base` | `theme_breathing` · `battery_color` · `hardware_battery` · `wave` · `red_breathing` · `red_static` · `none` |
| `magichome` | `battery_color` · `solid_theme` · `red` · `none` |
| `openrgb` | `battery_meter` (zonas ARGB) · `solid_theme` · `red` · `none` |

- **`battery_meter`**: relleno proporcional al nivel, de abajo arriba.
  - Akko `keys`: lienzo tecla-a-tecla (`0x07` modo `0x0D` + 7 paquetes `0x0C`), relleno por
    filas. Se redibuja al cambiar el nivel de forma apreciable, **nunca por frame**.
  - `openrgb` zonas ARGB (Aura Addressable 1/2, 60 LED): relleno LED a LED, animación suave
    aprovechando la infraestructura de `argb-wave.py`.
  - Cualquier otro destino: degrada a `battery_color` / `stream_battery`.
- **`battery_color` / `breathing_battery` / `stream_battery`**: color según nivel por el gradiente
  HSV ya existente (`get_akko_battery_level_color`): ≤15 % rojo → ámbar → amarillo → lima →
  verde 100 %.
- **`red_*`**: rojo puro (255,0,0), respiración (`0x02`) o fijo (`0x01`).
- **`hardware_battery` / `wave`**: modos autónomos del firmware de la base MCHOSE (ya soportados
  por `mchose-lighting`).
- **`none`**: la zona no se toca; sigue el color global del tema.

### 4. Prioridad y coexistencia

- `~/.cache/battery_alerts.json`: `{ "<target>:<zone>": { "effect", "trigger", "source", "level" } }`.
  Zonas del Akko siempre como `akko_keyboard:keys` / `akko_keyboard:sidestrip` (nunca `both`).
- `sync-rgb.py`: cada `sync_*` consulta el fichero; si su zona está, la salta. Función helper
  local `_battery_alert_for(target, zone)`.
- `rgb-notify-flash`: `restore()` repinta a tema salvo que la zona esté reclamada → repinta al
  efecto de alerta (invoca `battery-lighting --tick`).
- Cuando el daemon libera una zona, es él quien la repinta al tema (una sola vez).

### 5. Sembrado y migración

Primer arranque sin `battery-lighting.json`:

1. Si existe `~/.config/caelestia/akko-config.json`: traducir
   (`charging.backlight`/`charging.sidestrip` → regla `akko_keyboard/charging`;
   `low_battery.*` + `low_battery_threshold` → regla `akko_keyboard/low`).
2. Si existe `~/.config/caelestia/mchose-config.json`: traducir `charging_effect` /
   `low_battery_effect` / `low_battery_threshold` → reglas `mchose_mouse/charging` y
   `mchose_mouse/low` sobre `mchose_base`.
3. Lo que falte, sembrar por defecto:
   - `akko_keyboard/charging` → keys `battery_meter`, sidestrip `stream_battery`
   - `akko_keyboard/low` (≤20) → both `red_breathing`
   - `mchose_mouse/charging` → `mchose_base` `theme_breathing`
   - `mchose_mouse/low` (≤20) → `mchose_base` `red_breathing`
   - `v9_headset`: sin reglas

Los ficheros viejos se dejan en disco (no se borran) pero dejan de leerse.

### 6. UI — sección "Reacciones de batería" (`NotificacionesView.qml`)

- Nuevo singleton `services/BatteryLightingConfig.qml` que refleja `battery-lighting.json`
  (mismo patrón que `RgbConfig` / `AkkoConfig`: `FileView` + debounce 250 ms + setters).
  Además, tras guardar, dispara `battery-lighting --tick` para aplicar sin esperar.
- `modules/rgbcontrol/BatteryRuleCard.qml`: tarjeta de regla, plegable. Cabecera: icono del
  origen + disparador + resumen. Cuerpo: slider de umbral (si `low`), lista de acciones,
  "+ Añadir acción", botón "Probar" (`battery-lighting --apply <id>`), borrar regla.
- `modules/rgbcontrol/BatteryActionRow.qml`: destino → (zona, si Akko) → efecto. Menús con las
  opciones válidas del destino.
- "+ Añadir regla": diálogo simple → dispositivo (de los conectados) → disparador.
- `KeyboardPreview.qml` reutilizado dentro de `BatteryActionRow` cuando el destino es el Akko.
- **Se eliminan:** la sección de batería de `AkkoCard.qml` (queda solo aspecto normal / color
  global del teclado) y el bloque "Eventos de batería" de la ficha de la Base en
  `DispositivosView.qml`. `AkkoConfig.qml` y `MchoseConfig.qml` se retiran (los sustituye
  `BatteryLightingConfig.qml`); `KeyboardPreview.qml` se mantiene (lo reusa la UI nueva).
- Textos en español, con tildes.

### 7. systemd

- `systemd/battery-lighting.service` (`--user`, `ExecStart=… battery-lighting --daemon`,
  `Restart=always`, `After=graphical-session.target`).
- `install.sh`: instala el servicio, `systemctl --user enable --now battery-lighting.service`,
  y `disable --now mchose-battery.timer` (migración). El `.timer` y su `.service` de
  notificación se retiran del repo.

## Flujo de datos (ejemplo)

1. K7 Ultra al 18 %, descargando. Daemon (tick de 60 s) lee 18 %.
2. Regla `mchose-mouse/low` (umbral 20) activa. Acción: `mchose_base` → `red_breathing`.
3. No hay regla `critical` ni otra de mayor prioridad sobre `mchose_base:_`. Gana.
4. Daemon emite `0x2B` al anillo (rojo respiración), escribe
   `battery_alerts.json = {"mchose_base:_": {...}}`, manda `notify-send` "Batería baja: Ratón".
5. Cambia el wallpaper → `sync-rgb.py` corre, ve `mchose_base:_` reclamado, no pinta el anillo.
6. K7 se pone en la base → siguiente tick lo ve `charging`. Regla `low` deja de cumplirse;
   `mchose-mouse/charging` pasa a activa → anillo `theme_breathing`. Alerta liberada.

## Errores y degradación

| Situación | Comportamiento |
|---|---|
| `battery-lighting.json` inválido | Se ignora, reglas sembradas, log de aviso. |
| Efecto no válido para el destino | `none` para esa acción + log. |
| Dongle Akko presente pero sin telemetría 2.4 GHz | `source akko_keyboard` inactivo salvo por cable; reglas del Akko no disparan (igual que hoy). |
| Mapa de coordenadas tecla-a-tecla no valida en hardware | `battery_meter` en `keys` degrada a `breathing_battery`. Se marca en el doc y en el log. Torre·ARGB no se ve afectada. |
| Daemon caído | `mchose-battery` cae a lectura directa para widgets; sin reacción de iluminación hasta que systemd lo reinicie. |
| OpenRGB no corriendo | Acciones `openrgb` se saltan con log; el resto sigue. |

## Pruebas

- **Unitario (pytest en `rgb/tests/` — nuevo):**
  - Resolución de prioridad: tablas de reglas activas → mapa de zonas esperado (crítica gana,
    empate por orden, `both` se expande a dos zonas).
  - Migración: `akko-config.json` / `mchose-config.json` de ejemplo → reglas esperadas.
  - Validación de esquema: JSON basura → reglas sembradas.
  - Render de `battery_meter`: nivel → nº de filas/LEDs encendidos.
- **Integración (con hardware, manual, checklist en el plan):**
  - Cada efecto en cada destino a mano vía `--apply`.
  - Enchufar/desenchufar el K7 y ver el cambio de cadencia y de efecto.
  - Cambiar wallpaper con una alerta activa: la zona no se pisa.
  - `rgb-notify-flash --test` con alerta activa: restaura al efecto de alerta.
  - Validar el mapa de coordenadas del lienzo del Akko; ajustar o degradar.
- **No regresión:** con `battery-lighting.json` sembrado por migración, el comportamiento del
  Akko y de la base es el de hoy.

## Archivos

**Nuevos**
- `rgb/battery-lighting`
- `rgb/tests/test_battery_lighting.py` (+ `conftest.py` si hace falta)
- `systemd/battery-lighting.service`
- `configs/quickshell/caelestia/services/BatteryLightingConfig.qml`
- `configs/quickshell/caelestia/modules/rgbcontrol/BatteryRuleCard.qml`
- `configs/quickshell/caelestia/modules/rgbcontrol/BatteryActionRow.qml`

**Modificados**
- `rgb/sync-rgb.py` — quitar reglas de batería escritas a fuego de `sync_akko_keyboard`; añadir
  consulta a `battery_alerts.json` en cada `sync_*`.
- `rgb/mchose-battery` — dejar de leer HID cuando el daemon está vivo; servir desde caché;
  quitar `apply_akko_battery_lighting` (se porta al daemon).
- `rgb/rgb-notify-flash` — `restore()` respeta alertas activas.
- `configs/quickshell/caelestia/modules/rgbcontrol/AkkoCard.qml` — quitar sección de batería.
- `configs/quickshell/caelestia/modules/rgbcontrol/DispositivosView.qml` — quitar bloque de
  batería de la Base.
- `configs/quickshell/caelestia/modules/rgbcontrol/NotificacionesView.qml` — nueva sección.
- `configs/quickshell/caelestia/modules/rgbcontrol/RgbControl.qml` / `Content.qml` — si hace
  falta registrar la sección nueva.
- `install.sh` — servicio nuevo, migración del timer.
- `docs/HARDWARE_PROTOCOLS.md`, `docs/AKKO_BATTERY_LIGHTING_FRONTEND.md` — actualizar.
- `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md` — registrar hallazgos.

**Retirados**
- `systemd/mchose-battery.service`, `systemd/mchose-battery.timer`
- `rgb/mchose-config` (lo sustituye la UI del motor; `rgb/mchose-lighting` se queda para aplicar
  modos a mano).
- `configs/quickshell/caelestia/services/AkkoConfig.qml`, `MchoseConfig.qml`.
