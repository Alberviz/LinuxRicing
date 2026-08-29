# Iluminación de batería del teclado Akko — frontend

Diseño y frontend para controlar cómo reacciona la iluminación del **Akko 5075B**
a los eventos de batería (cargando / batería baja), replicando lo que ya existía
para la base del ratón MCHOSE pero adaptado a las **dos zonas** del teclado:
retroiluminación de teclas + tira lateral.

> **Estado: solo frontend.** No hay motor detrás. El Akko no expone su nivel de
> batería por el enlace de 2.4 GHz (el driver propietario de Windows usa un
> transporte RF que no está ingenierizado a la inversa — ver
> `PROTOCOL.md` §B (telemetría de batería)). La pantalla guarda las preferencias del
> usuario; cuando exista telemetría de batería, el backend leerá el mismo
> fichero y accionará el hardware.

## Piezas

| Archivo | Rol |
| --- | --- |
| `configs/quickshell/caelestia/services/AkkoConfig.qml` | Singleton que refleja `~/.config/caelestia/akko-config.json`. Propiedades + setters que persisten (debounce 250 ms vía `FileView.setText`). No llama a hardware. |
| `configs/quickshell/caelestia/modules/rgbcontrol/AkkoCard.qml` | La ficha del teclado en la pestaña **Dispositivos** del Centro de Iluminación. Sustituye al placeholder anterior. |
| `configs/quickshell/caelestia/modules/rgbcontrol/KeyboardPreview.qml` | Maqueta animada no interactiva del teclado (rejilla 15×5 + tira lateral) que previsualiza el efecto seleccionado. Puramente decorativa. |
| `configs/quickshell/caelestia/modules/rgbcontrol/DispositivosView.qml` | Modificado: usa `AkkoCard`; la ficha de la base MCHOSE arranca colapsada para no alargar el panel. |

`AkkoConfig` no necesita registro: Quickshell expone como singleton cualquier
`.qml` con `pragma Singleton` bajo `services/` (igual que `MchoseConfig`).

## Esquema de `~/.config/caelestia/akko-config.json`

```json
{
  "reactive_enabled": true,
  "charging":     { "backlight": "fill",          "sidestrip": "stream_battery" },
  "low_battery":  { "backlight": "red_breathing",  "sidestrip": "red_breathing" },
  "low_battery_threshold": 20
}
```

### Efectos

**Retroiluminación al cargar** (`charging.backlight`) — solo modos de firmware de
una escritura:

| clave | etiqueta | implementación |
| --- | --- | --- |
| `theme` | Tema | color sólido del tema (`0x07` modo `1`) — discreto |
| `wave` / `wave_battery` | Ola | `0x07` modo `4`, animada por el teclado, en color de tema o de batería |
| `breathing_battery` | Respiración (batería) | `0x07` modo `2` en color según nivel (rojo→ámbar→verde) |
| `breathing` | Respiración | `0x07` modo `2` en color de tema |

> El relleno tecla a tecla (`fill` / `battery_meter`) **se retiró**: el lienzo
> per-key congela el teclado ~1 s por pasada sobre 2.4 GHz. Ver `PROTOCOL.md` §C.

**Tira lateral al cargar** (`charging.sidestrip`): `stream_battery` (defecto),
`breathing` / `breathing_battery`, `solid_theme`, `none`.

Mientras carga, el daemon reescribe el efecto cuando el nivel cruza un escalón de
10 % para que el gradiente de color avance (1 paquete de firmware, sin congelar).

**Batería baja** (`low_battery.backlight` y `.sidestrip`): `red_breathing`
(defecto), `red_static`, `none`.

**Umbral** (`low_battery_threshold`): 5–40 %, pasos de 5. Defecto 20.

**`reactive_enabled`**: interruptor maestro. Si está apagado, el teclado solo
sigue el color global del tema.

## Qué falta para que funcione (backend) — HECHO / SUPERADO

Implementado por el motor **`battery-lighting`** (`rgb/battery-lighting` →
`~/.local/bin/battery-lighting`, unidad `systemd/battery-lighting.service`).
Diseño completo en
`docs/superpowers/specs/2026-08-27-battery-lighting-engine-design.md`.

1. ~~Telemetría de batería del Akko por 2.4 GHz~~ — el motor la lee vía
   `--dump` (Opcode `0x83`), con fallback a UPower para el ratón.
2. ~~Reglas escritas a fuego en `mchose-battery` / `sync-rgb.py`~~ — el motor
   lee el perfil editable `~/.config/caelestia/battery-lighting.json`
   (con migración de los antiguos `akko-config.json` / `mchose-config.json`).
3. ~~Renderer del efecto `fill` / medidor tecla a tecla~~ — **retirado.** El
   lienzo per-key congela el teclado ~1 s por pasada sobre 2.4 GHz; los efectos
   del teclado son ahora solo modos de firmware de una escritura (`wave`,
   `breathing_battery`, …). Ver `PROTOCOL.md` §C.
4. Botón «Probar» en `AkkoCard` — Fase 2 (frontend); el motor ya expone
   `battery-lighting --apply <perfil>` para el disparo inmediato.
