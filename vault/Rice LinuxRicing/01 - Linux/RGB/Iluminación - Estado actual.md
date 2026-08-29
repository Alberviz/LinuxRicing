---
tags: [rice, rgb, referencia]
actualizado: 2026-08-29
---

# Iluminación · Estado actual

Foto de cómo funciona el control RGB del setup **antes** del proyecto [[Centro de Iluminación RGB]]. Sirve de referencia; verificar contra el código antes de tocar nada.

> [!NOTE]
> **Base de Conocimiento de Hardware Canónica:** Las especificaciones detalladas de ingeniería inversa y protocolos residen en [`hardware/`](file:///C:/Users/Alberviz/LinuxRicing/hardware).

## Dispositivos con luz

| Dispositivo | ID / transporte | Controlado por | Zonas | Capacidades reales |
|---|---|---|---|---|
| [**Base de carga MCHOSE 8K**](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-k7-ultra) | USB HID `3837:1001`, iface `:1.2`, Feature Report `0x11`, payload XOR `0xFF`, cmd `0x2B` | `mchose-lighting`, `mchose-config`, `mchose-battery`, `sync-rgb.py` | Anillo LED exterior | Estático (`target 0x06`), respiración monocolor (`0x02`), batería firmware (`0x01`), ola arcoíris ARGB por hardware (`0x07`), off. Brillo 0-100, velocidad 0-4. Ver [`hardware/mchose-k7-ultra/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-k7-ultra/PROTOCOL.md) |
| [**Teclado Akko 5075B Plus**](file:///C:/Users/Alberviz/LinuxRicing/hardware/akko-5075b-plus) | USB HID `3151:4015` (USB) / `3151:4011` (2.4G), ROYUAN B-series, iface 2, Feature Report 65 B | `sync-rgb.py:sync_akko_keyboard`, `mchose-battery` | Retro de teclas (opcode `0x07`) + tira lateral (opcode `0x08`) | Backlight sólido sincronizado; Tira lateral reactiva: Steady Stream (`0x05`) con gradiente progresivo al cargar, Breathing rojo (`0x02`) con batería ≤ 20%, y color estático del tema en normal. Telemetría real de batería (opcode `0x83`). Ver [`hardware/akko-5075b-plus/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/akko-5075b-plus/PROTOCOL.md) |
| [**Placa ASUS TUF B560M-PLUS + RAM + ventiladores**](file:///C:/Users/Alberviz/LinuxRicing/hardware/asus-tuf-b560m) | OpenRGB SDK `localhost:6742` | `sync-rgb.py:sync_openrgb` | `Aura Mainboard` (4 LEDs), `Aura Addressable 1/2` (ventiladores), RAM `ENE DRAM` (5 LEDs/módulo) | Solo color estático de un disparo (modo Direct). **El bus SMBus/I2C es lento: nunca loops a alto FPS** |
| [**Tira LED Magic Home Wi-Fi**](file:///C:/Users/Alberviz/LinuxRicing/hardware/magic-home-strip) | TCP `192.168.0.136:5577`, librería `flux_led` | `magichome-control`, `sync-rgb.py:sync_magichome` | 1 zona | Color estático + power on/off. Sin modos ni brillo |
| [**Cuerpo del ratón MCHOSE K7 Ultra**](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-k7-ultra) | mismo `3837:1001` | — | LED interior | **No caracterizado todavía** (ambigüedad target `0x06` vs `0x07`) |
| [**Auriculares MCHOSE V9 Pro**](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-v9-pro) | USB HID `291D:385D`, cmd `[0x55, 0x65, 0x01]` | `mchose-battery` | — | Telemetría real de batería (byte 2: 0-100%) y estado real verificado (byte 3: `0x03`=Cargando, `0x02`=Descargando/Inalámbrico, `0x00`=En espera). Ver [`hardware/mchose-v9-pro/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-v9-pro/PROTOCOL.md) |

## Scripts (repo `rgb/`, instalados en `~/.local/bin/` y `~/.config/caelestia/`)

- **`sync-rgb.py`** — capa unificada. **No acepta argumentos.** Lee el color del tema (env `SCHEME_COLOURS` o `~/.local/state/caelestia/scheme.json` → `colours.primary`), lo satura x3.5 para LEDs físicos, y lo aplica en 5 hilos a: OpenRGB, MagicHome, base MCHOSE, teclado Akko y Spicetify (`color.ini` Material You).
- **`mchose-config`** (≡ `mchose-config.py` ≡ `mchose-lowbat-mode`) — `charge|lowbat|threshold <opción>`. Persiste `~/.config/caelestia/mchose-config.json` = `{charging_effect, low_battery_effect, low_battery_threshold}`. Tras guardar llama a `mchose-battery --trigger-lighting`.
- **`mchose-lighting <modo> [#hex]`** — aplicación instantánea de un modo a la base.
- **`mchose-battery`** — telemetría de batería (`--json`) y, además, máquina de estados de iluminación de la base y del teclado: aplica efecto al acoplar el ratón o enchufar el teclado, alerta al bajar de umbral, restaura el tema al desacoplar (caché en `~/.cache/mchose_battery.json`).
- **`magichome-control [--status|--toggle|--on|--off|--color #hex]`**.
- Herramientas de ingeniería inversa: `mchose-test-modes`, `mchose-mode-finder.py`, `mchose-argb-test.py`, `mchose-pcap-analyzer`, `mchose-sniffer.py`, `mchose-base-test`, `mchose-base-demo`.

## Cuándo se re-sincroniza el color

- `postHook` de `theme` y `wallpaper` en `~/.config/caelestia/cli.json` → `sync-rgb.py`.
- Al arrancar Hyprland (`configs/hypr/hyprland/execs.lua`).
- Preview con debounce al navegar wallpapers (`services/Wallpapers.qml`).
- Botón "Re-sincronizar" del widget de tira LED y fin de Pomodoro en `Background.qml`.
- Al desacoplar el ratón de la base sin batería baja (`mchose-battery`).

## Config persistente hoy

Solo `~/.config/caelestia/mchose-config.json` (3 claves de la base). **No hay** config para el color de reposo (siempre `primary` del tema), ni para el teclado, OpenRGB o MagicHome, ni para el color del ratón.

## Deudas / inconsistencias conocidas

- `install.sh` solo despliega `sync-rgb.py`, `mchose-battery` y `magichome-control`; `mchose-config` y `mchose-lighting` se copian a mano.
- `configs/quickshell/caelestia/modules/background/Background.qml` está **duplicado byte a byte** en `widgets/Background.qml`; hay que editar los dos.
- El `target` del color estático de la base ha cambiado varias veces entre commits (`0x02`/mode `0x03` → `0x02`/mode `0x00` → `0x06`/mode `0x01`). Los docs no están 100 % alineados con el código.
- Ambigüedad `target 0x06` vs `0x07`: la iluminación del cuerpo del ratón sigue sin caracterizarse.
