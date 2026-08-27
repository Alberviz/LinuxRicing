# Capturas USB — Dongle 2.4 GHz Akko (VID 0x3151 / PID 0x4011)

Capturado en Windows 11 con **USBPcap** (`\\.\USBPcap3`, root hub del dongle),
filtrado al `device_address` del dongle. Driver oficial en marcha:
`iot_driver_v200.exe` (bridge gRPC en `127.0.0.1:3814`) + `Akko Cloud Driver.exe`.
Fecha: 2026-08-27.

| Fichero | Cómo se disparó | ¿Cambió el color? |
|---|---|---|
| `akko-2.4g-color-change.pcapng` | Cambios de color desde la GUI de **Akko Cloud Driver** (varios, custom + presets) | **SÍ** (backlight y tira lateral) |
| `akko-2.4g-script-grpc.pcapng`  | `python rgb/sync-rgb-windows.py` (ruta gRPC: `setLightType` + `sendMsg 0x07` + `changeWirelessLoopStatus` + `sendMsg 0x08` + `sendMsg 0x88`) | **NO** — el `0x07` nunca llegó al bus USB |

## Conclusión (ver informe completo en `docs/AKKO_2.4G_USB_FINDINGS.md`)

El dongle acepta el **mismo paquete de iluminación que en modo cable**, enviado como
`SET_REPORT` (Feature) a la interfaz 2. No hace falta ni `setLightType`, ni bloqueo de
wireless loop, ni paquete `0x08` extra, ni "flush `0x88`".

```
bmRequestType = 0x21   (Host→Device | Class | Interface)
bRequest      = 0x09   (SET_REPORT)
wValue        = 0x0300 (report type 3 = Feature, report ID 0x00)
wIndex        = 0x0002 (interface 2)
wLength       = 64
payload[64]   = 07 01 04 04 08 RR GG BB CK 00 00 ... 00
                │  │  │  │  │  └──────┘ └─ checksum
                │  │  │  │  └─ flags 0x08 = AKKO_FLAGS_CUSTOM_RGB
                │  │  │  └─ brillo (0x04 en la captura)
                │  │  └─ 0x04
                │  └─ 0x01
                └─ opcode 0x07 (backlight)
CK = (0xFF - (sum(payload[0..7]) & 0xFF)) & 0xFF     # idéntico a rgb/akko-rgb
```

Ejemplos reales de la captura GUI:
- `07 01 04 04 08 ff ac 00 3c` → RGB(255,172,0)
- `07 01 04 04 08 4a 90 e2 2b` → RGB(74,144,226)

## Reabrir

```bash
wireshark docs/pcap/akko-2.4g-color-change.pcapng
# filtro útil:  usb.transfer_type == 0x02 && usb.data_len > 0
```
