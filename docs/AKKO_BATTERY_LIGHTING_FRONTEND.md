# Iluminación de batería del teclado Akko — frontend

Diseño y frontend para controlar cómo reacciona la iluminación del **Akko 5075B**
a los eventos de batería (cargando / batería baja), replicando lo que ya existía
para la base del ratón MCHOSE pero adaptado a las **dos zonas** del teclado:
retroiluminación de teclas + tira lateral.

> **Estado: solo frontend.** No hay motor detrás. El Akko no expone su nivel de
> batería por el enlace de 2.4 GHz (el driver propietario de Windows usa un
> transporte RF que no está ingenierizado a la inversa — ver
> `docs/HARDWARE_PROTOCOLS.md` §1.B). La pantalla guarda las preferencias del
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

**Retroiluminación al cargar** (`charging.backlight`):

| clave | etiqueta | idea de implementación (pendiente) |
| --- | --- | --- |
| `theme` | Tema | color sólido del tema (0x07 modo 0x01) — discreto |
| `fill` | Barra de carga | relleno por filas de abajo arriba según `%` usando el lienzo tecla a tecla (0x07 modo 0x0D + 0x0C); se re-renderiza en cada tick, **sin animación rápida** (la radio 2.4 GHz se corrompe si se escribe muy seguido — ver Base de Datos de Errores) |
| `breathing` | Respiración | respiración en color según nivel de batería (rojo→ámbar→verde) |
| `stream` | Flujo | *steady stream* por firmware (0x07 modo 0x05) en color de batería |

**Tira lateral al cargar** (`charging.sidestrip`): `stream_battery` (defecto,
comportamiento actual de `sync-rgb.py`), `breathing`, `solid`, `none`.

**Batería baja** (`low_battery.backlight` y `.sidestrip`): `red_breathing`
(defecto), `red_static`, `none`.

**Umbral** (`low_battery_threshold`): 5–40 %, pasos de 5. Defecto 20.

**`reactive_enabled`**: interruptor maestro. Si está apagado, el teclado solo
sigue el color global del tema.

## Qué falta para que funcione (backend, otra rama/sesión)

1. Telemetría de batería del Akko por 2.4 GHz (el bloqueante real).
2. `apply_akko_battery_lighting()` en `rgb/mchose-battery` y `sync_akko_keyboard()`
   en `rgb/sync-rgb.py` deben leer `akko-config.json` en vez de tener las reglas
   escritas a fuego.
3. Renderer del efecto `fill` tecla a tecla (protocolo del lienzo ya documentado
   en `docs/HARDWARE_PROTOCOLS.md` §1.D; mapa de coordenadas parcial — validar
   contra hardware).
4. Botón «Probar» en `AkkoCard` (ahora hay una nota informativa en su lugar).
