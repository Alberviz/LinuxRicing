# Capturas USB — Dongle 2.4 GHz Akko (VID 0x3151 / PID 0x4011)

Capturado en Windows 11 con **USBPcap** (`\\.\USBPcap3`, root hub del dongle),
device address 6. Driver oficial en marcha: `iot_driver_v200.exe` (bridge gRPC
`127.0.0.1:3814`) + `Akko Cloud Driver.exe`. Fecha: 2026-08-27.

| Fichero | Qué es | ¿Cambió el color? |
|---|---|---|
| `akko-2.4g-2.4ghz-working.pcapng` | **Referencia.** Rojo/verde/azul/blanco al backlight (`0x07`) y tira lateral (`0x08`), por `sendMsg` gRPC crudo con la ruta de dispositivo correcta. | **SÍ** (verificado a ojo) |
| `akko-2.4g-color-change.pcapng` | Cambios de color desde la GUI oficial de Akko Cloud Driver. | SÍ |
| `akko-2.4g-script-grpc.pcapng` | `sync-rgb-windows.py` **con la ruta hardcodeada obsoleta** → el bridge descarta los `sendMsg` en silencio. | NO (solo se ve el sondeo `0xF7`) |

## Conclusión

Ver **`docs/AKKO_2.4G_USB_FINDINGS.md`** para el análisis completo.

El dongle acepta el **mismo paquete que el modo cable**, como `SET_REPORT` (Feature,
report ID 0) a la interfaz 2. Sin `setLightType`, sin bloqueo de wireless loop, sin
`0x08` obligatorio emparejado, sin "flush `0x88`".

```
bmRequestType=0x21  bRequest=0x09  wValue=0x0300  wIndex=0x0002  wLength=64
payload[64] = 07|08  01 04 04 08  RR GG BB  CK  00...00
CK = (0xFF - (sum(payload[0..7]) & 0xFF)) & 0xFF     # == rgb/akko-rgb
```

El bug que bloqueaba todo: `rgb/sync-rgb-windows.py` tenía el `device_path` del dongle
hardcodeado (`8&11c3dae0`), inválido en esta máquina (`8&6ddcf1a`). El sufijo
`8&xxxxxxxx` es el instance ID de Windows y cambia entre máquinas/reconexiones.

## Reabrir

```bash
wireshark docs/pcap/akko-2.4g-2.4ghz-working.pcapng
# filtro:  usb.transfer_type == 0x02 && usb.data_len > 8
```
