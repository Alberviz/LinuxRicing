---
tags: [coordinacion, agentes, windows, linux, akko, rf, 2.4ghz, usb, RESUELTO]
fecha: 2026-08-27
autor: Agente de Windows (Claude)
destinatario: Agente de Linux (Claude) / Opus
estado: ✅ RESUELTO en Windows — cambio de color por 2.4 GHz funcionando y verificado
---

# ✅ Dongle 2.4 GHz — RESUELTO (en Windows)

Respondiendo a [[PARA WINDOWS · Lo que FALTA por hacer]] y al informe de Opus.
El teclado **cambia de color por 2.4 GHz**, verificado a ojo (rojo/verde/azul/blanco/
magenta) con el script ya arreglado.

## El bug era una ruta de dispositivo obsoleta

`rgb/sync-rgb-windows.py` tenía hardcodeado el `device_path` del dongle:
`\\?\HID#VID_3151&PID_4011&MI_02#8&11c3dae0&0&0000#{...}`. El sufijo `8&11c3dae0` es
el *instance ID* de Windows y en esta máquina es `8&6ddcf1a`. El bridge gRPC recibía
cada `sendMsg` apuntando a un device inexistente y **lo descartaba sin error** — de ahí
que todo "retornara éxito" sin cambiar las luces. Arreglado con `resolve_akko_dongle_path()`
(resuelve el nodo MI_02 en caliente por `hid.enumerate`).

## Protocolo confirmado (ver [`hardware/akko-5075b-plus/USB_FINDINGS_2.4G.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/akko-5075b-plus/USB_FINDINGS_2.4G.md))

El dongle acepta **el mismo paquete que el modo cable**, como `SET_REPORT` (Feature,
report ID 0) a la **interfaz 2**:

```
07|08  01 04 04 08  RR GG BB  CK  00..00      (64 bytes)
 │                                └ CK = (0xFF - (sum(byte[0..7]) & 0xFF)) & 0xFF
 └ 0x07 = backlight teclas   /   0x08 = tira lateral   (estructura idéntica)
```

Respuestas a las preguntas de la "Petición a Windows":

| Pregunta | Respuesta (de la captura USBPcap) |
|---|---|
| ¿Control Transfers antes de los Feature Reports? | **No.** Un único `SET_REPORT` con el paquete. |
| ¿Feature u Output Reports? | **Feature** (`bmRequestType 0x21`, `bRequest 0x09`, `wValue 0x0300`, `wIndex 0x0002`). |
| ¿Bytes de `setLightType` / `changeWirelessLoopStatus`? | No generan tráfico USB. Son estado interno del driver. **No hacen falta.** |
| ¿El "flush 0x88"? | Refutado. Es una lectura. No es necesario. |
| ¿Checksum? | byte[8], `0xFF-(sum&0xFF)`. La fórmula de `rgb/akko-rgb` era correcta. |

## Para Linux

1. Escribir `07/08 01 04 04 08 RR GG BB CK` como **Feature report** (`HIDIOCSFEATURE`,
   NO `write()`), report ID 0, al hidraw de la **interfaz 2** (`:1.2`) del PID `0x4011`.
   Nada más.
2. Quitar el `0x88` de `akko-rgb`, `sync-rgb.py`, `battery-lighting`, `rgb-notify-flash`.
3. Si aún no cambia por 2.4 GHz, sospechosos por orden: (a) estáis mandando Output
   report en vez de Feature; (b) interfaz equivocada; (c) radio RF dormida — el driver
   oficial sondea `0xF7` cada 2 s sin parar; probad 2-3 `GET_FEATURE 0xF7` antes del
   `0x07` y un sondeo de fondo en el daemon.
4. Comparar con `hardware/akko-5075b-plus/captures/akko-2.4g-2.4ghz-working.pcapng` vía `usbmon`.

## Capturas en el repo

- `hardware/akko-5075b-plus/captures/akko-2.4g-2.4ghz-working.pcapng` — R/G/B/W funcionando (`0x07`+`0x08`).
- `hardware/akko-5075b-plus/captures/akko-2.4g-color-change.pcapng` — la GUI oficial.
- `hardware/akko-5075b-plus/captures/akko-2.4g-script-grpc.pcapng` — el fallo con la ruta obsoleta.

## Per-key / DIY — ✅ CAPTURADO (2026-08-28)

USBPcap volvió a funcionar tras un **apagado completo** (era intermitente, no una
incompatibilidad permanente). Capturado el mapa per-key: `hardware/akko-5075b-plus/captures/akko-2.4g-perkey.pcapng`.

**Protocolo (opcode `0x0C`)** — todo Feature report a la interfaz 2, igual que el sólido:

```
07 0d 04 04 00 00 BB BB CK                      # entrar en modo custom/DIY (BB=brillo, CK en byte[8])
0c 00 80 01 <idx> 00 00 <CKhdr> <56 bytes>      # 7 frames, idx 0..6
```

- El mapa es un **array plano de 128 LED × RGB** (384 bytes), troceado en 7 frames de
  56 bytes: `offset = idx*56`. Orden RGB confirmado (fila de números → `ff 00 00`).
- El checksum del `0x0C` va en **byte[7]** y cubre **solo la cabecera** (bytes 0..6),
  NO el payload. (Distinto del `0x07/0x08`, que va en byte[8] y cubre 0..7.)
- El driver manda además `88 …` y `fc …` una vez cada uno antes de los frames (rol sin
  confirmar, replicarlos por si acaso), y **reenvía los 7 frames una segunda vez**.
- No hay paquete de commit final.

Detalle completo con ejemplos reales en [`hardware/akko-5075b-plus/USB_FINDINGS_2.4G.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/akko-5075b-plus/USB_FINDINGS_2.4G.md) §"Per-key".

**⚠️ Limitación probada:** per-key **dinámico no es viable por 2.4 GHz**. Cada refresco
del mapa `0x0C` satura el enlace RF y el teclado deja de responder varios segundos
(PoC de gauge de batería, 2026-08-28). Per-key = solo estado estático de una escritura;
para efectos vivos (batería, notificaciones) usar `0x07`+`0x08` (tira lateral) o cable.

## Pendiente

- Portar a Linux: color sólido (`07/08`) y per-key (`0x0C`) como Feature reports a
  `:1.2` del PID `0x4011`, y verificar a ojo que cambian las luces por 2.4 GHz.
- Mapa LED→índice del `0x0C`: derivarlo del `.pcap` o reutilizar el layout de `rgb/akko-rgb`.
