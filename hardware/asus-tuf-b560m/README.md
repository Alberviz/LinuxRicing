# 🖥️ Placa ASUS TUF GAMING B560M-PLUS + RAM A-DATA XPG Spectrix

Componentes internos con RGB, controlados vía **OpenRGB** (no hay protocolo propio
que ingenierizar aquí — OpenRGB ya hizo ese trabajo). Se documenta la configuración
y las precauciones.

## Hardware

| Componente | Controlador | Zonas / LEDs |
|---|---|---|
| Placa ASUS TUF B560M-PLUS | Aura (OpenRGB) | `Aura Mainboard` (4 LEDs, estático), `Aura Addressable 1` (60), `Aura Addressable 2` (60) |
| 2× A-DATA XPG Spectrix DDR4 | `ENE DRAM` (OpenRGB) | 5 LEDs por módulo |
| Ventiladores torre ASUS ARGB | vía cabezal ARGB de la placa | direccionables |

- **Acceso:** OpenRGB SDK, TCP `localhost:6742` (servicio `systemd/openrgb.service`).
- **Modo operativo:** `Direct` (modo 0 en DRAM y placa) — sin parpadeo, el color se
  escribe en cada actualización.

## Estado

| Capacidad | Estado |
|---|---|
| Color sólido sincronizado con Material You | ✅ (`rgb/sync-rgb.py`, one-shot) |
| Animación continua (ola de color) | ✅ solo en la rama `feature/argb-wave` (`rgb/argb-wave.py`, ~12.5 FPS) |
| Batería / telemetría | — (alimentación ATX/DIMM) |

## ⚠️ Precaución del bus SMBus / I2C

La comunicación con las RAM va por el bus I2C de la placa (~100 kHz). Escribir muy
seguido lo satura y provoca cuelgues o parpadeos. Por eso:

- La rama `main` aplica **color estático de un solo disparo** (`sync-rgb.py` en el
  postHook de tema de Caelestia).
- La rama `feature/argb-wave` añade un daemon que corre a `FRAME_SECONDS = 0.08`
  (~12.5 FPS) usando `zone.set_colors(..., fast=True)` para animar RAM + ventiladores
  sin saturar el bus.

## Cómo se usa en el rice

- `systemd/openrgb.service` — arranca el servidor SDK en segundo plano.
- `rgb/sync-rgb.py` — conecta al SDK y fija el color del tema en modo Direct.
- `rgb/argb-wave.py` — (rama aparte) anima las zonas direccionables.
