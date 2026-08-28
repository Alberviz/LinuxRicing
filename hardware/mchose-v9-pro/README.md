# 🎧 Auriculares MCHOSE V9 Pro

Auriculares inalámbricos (2.4 GHz + Bluetooth). Sin RGB direccionable. Lo que
interesa aquí es la **telemetría de batería**, que hasta esta reorganización solo
existía como comentario dentro de `rgb/mchose-battery`.

- **DSP / controlador:** C-Media CM2025.
- **Canal:** en modo dongle 2.4 GHz se expone como HID; en Windows por Interface 0,
  `UsagePage 0xFFA0`. Report de 64 bytes, **sin ofuscación** (a diferencia del ratón).

## Identificadores

| Modo | VID | PID | Notas |
|---|---|---|---|
| Dongle 2.4 GHz | `0x291D` | `0x385D` | verificado (batería) |
| Bluetooth | — | — | 🚧 sniff hecho por Alberto, pendiente de volcar aquí (ver abajo) |

## Estado

| Capacidad | Estado | Detalle |
|---|---|---|
| Telemetría de batería por 2.4 GHz | ✅ | cmd `55 65 01`; respuesta `55 65 <nivel> <estado>`. [`PROTOCOL.md`](PROTOCOL.md). |
| Telemetría de batería por Bluetooth | 🚧 | Alberto confirma que se hizo sniffing del canal BT; **falta documentar el paquete BT aquí**. |
| Iluminación RGB | ❌ | el dispositivo no tiene LEDs direccionables. |

## Cómo se usa en el rice

- `get_v9_pro_battery()` en `rgb/mchose-battery` (Linux, hidraw crudo) y en
  `rgb/mchose-battery-windows.py` (Windows, `hidapi`).
- `rgb/battery-lighting` lo trata como fuente `v9_headset` (default
  `2.4G Inalámbrico`).
- Se muestra en el widget de periféricos (`--waybar-headset` / salida `--json`).

## Historia

El comando salió de capturar el tráfico del dongle mientras el software oficial
leía la batería: un paquete corto `55 65 01 00…` provoca una respuesta `55 65`
con nivel y estado. Lecturas en directo verificadas (90 %, descargando). El canal
Bluetooth se sniffó aparte; ese volcado aún no está en el repo.

### TODO — sniff Bluetooth

Cuando se recupere: añadir a [`PROTOCOL.md`](PROTOCOL.md) el nombre del servicio/
característica GATT o el report HID-over-GATT, el formato de la respuesta de
batería en BT, y si el comando `55 65 01` se reutiliza tal cual.
