# Akko 5075B Plus — Protocolo USB real del dongle 2.4 GHz (RESUELTO)

> **Autor:** Agente de Windows (Claude) · **Fecha:** 2026-08-27, ampliado 2026-08-28
> **Estado:** ✅ Cambio de color sólido por 2.4 GHz **conseguido y verificado
> visualmente**. ✅ **Per-key / iluminación personalizada capturada** (opcode `0x0C`,
> ver §"Per-key"). Bytes exactos capturados con USBPcap.

---

## TL;DR

El dongle 2.4 GHz acepta **exactamente el mismo paquete que el modo cable**, enviado
como **Feature report (`SET_REPORT`) a la interfaz 2**. No hay protocolo nuevo, ni
handshake, ni "flush", ni bloqueo de wireless loop, ni `setLightType`.

```
SETUP:  bmRequestType = 0x21   (Host→Device | Class | Interface)
        bRequest      = 0x09   (SET_REPORT)
        wValue        = 0x0300 (report type 3 = Feature, report ID 0x00)
        wIndex        = 0x0002 (interfaz 2)
        wLength       = 64

DATA (64 bytes):
  byte[0]     = 0x07  backlight (teclas)   |  0x08  tira lateral (side-strip)
  byte[1]     = 0x01
  byte[2]     = 0x04
  byte[3]     = brillo (0x04)
  byte[4]     = 0x08  flags = AKKO_FLAGS_CUSTOM_RGB
  byte[5]     = R
  byte[6]     = G
  byte[7]     = B
  byte[8]     = CK = (0xFF - (sum(byte[0..7]) & 0xFF)) & 0xFF
  byte[9..63] = 0x00
```

`0x07` y `0x08` tienen **estructura idéntica**. Se mandan uno detrás de otro
(~250 ms de separación en la captura, pero back-to-back también funciona).

### Ejemplos reales de `docs/pcap/akko-2.4g-2.4ghz-working.pcapng` (verificado a ojo)

| Color | Backlight (0x07) | Side-strip (0x08) |
|---|---|---|
| Rojo `255,0,0`   | `07 01 04 04 08 ff 00 00 e8` | `08 01 04 04 08 ff 00 00 e7` |
| Verde `0,255,0`  | `07 01 04 04 08 00 ff 00 e8` | `08 01 04 04 08 00 ff 00 e7` |
| Azul `0,0,255`   | `07 01 04 04 08 00 00 ff e8` | `08 01 04 04 08 00 00 ff e7` |
| Blanco `255,255,255` | `07 01 04 04 08 ff ff ff ea` | `08 01 04 04 08 ff ff ff e9` |

Checksum confirmado con las 4 muestras: p.ej. rojo `0x07+01+04+04+08+ff = 0x117`;
`0x117 & 0xFF = 0x17`; `0xFF - 0x17 = 0xE8`. ✓

---

## Cómo se llegó aquí (y qué era el bug)

Método: capturas USBPcap del dongle `3151:4011` (bus 3, device address 6, root hub
`USB\ROOT_HUB30\4&1c1e67e3` vía hub ASMedia `174C:2074`, control device `\\.\USBPcap3`)
con el driver oficial en marcha (`iot_driver_v200.exe`, bridge gRPC `127.0.0.1:3814`).

### El bug: ruta de dispositivo obsoleta y hardcodeada

`rgb/sync-rgb-windows.py` tenía la ruta del dongle **hardcodeada**:

```
\\?\HID#VID_3151&PID_4011&MI_02#8&11c3dae0&0&0000#{...}
```

En esta máquina el nodo real es `…#8&6ddcf1a&0&0000#…`. El sufijo `8&xxxxxxxx` es el
*instance ID* de Windows y **cambia entre máquinas y entre reconexiones**. El bridge
gRPC recibía cada `sendMsg` con un `device_path` inexistente y lo **descartaba en
silencio, sin error** — por eso los 4+ intentos anteriores "retornaban éxito" pero las
luces no cambiaban.

`docs/pcap/akko-2.4g-script-grpc.pcapng` es una captura de ese fallo: solo se ve el
sondeo `0xF7`, ningún `0x07`.

### Con la ruta resuelta dinámicamente → funciona

`sendMsg(0x07)` + `sendMsg(0x08)` crudos, `checksum_type=1`, `dangle_type=1`, **sin
nada más**, producen los `SET_REPORT` de arriba y el teclado cambia de color.

### Hipótesis descartadas por las capturas

| Teoría previa | Veredicto |
|---|---|
| Hace falta `setLightType` antes del `sendMsg` | ❌ Falso. Con o sin él, funciona. |
| `changeWirelessLoopStatus(lock/unlock)` alrededor | ❌ Innecesario. No genera tráfico USB propio (es estado interno del driver). |
| Paquete `0x08` de la tira lateral emparejado obligatorio | ❌ Independiente; cada opcode es su propia escritura. |
| "Flush pipeline commit" con `Opcode 0x88` | ❌ **Falso.** `0x88` es `FEA_CMD_GET_SLEDPARAM`, una lectura. En la captura de la GUL aparece solo como lectura de verificación (`88 …77`) *después* de escribir, y **no es necesaria**. |
| Checksum en byte[63] o `sum&0xFF` | ❌ Es byte[8], `0xFF-(sum&0xFF)` — la fórmula de `rgb/akko-rgb` ya era correcta. |

### `checksum_type` del bridge gRPC (para referencia Windows)

| valor | efecto en el bus |
|---|---|
| **1** | RGB intacto en [5][6][7], **checksum en byte[8]** con `0xFF-(sum[0..7]&0xFF)` ← el correcto |
| 0 / 3 | mete el checksum en byte[7] y pisa el canal B |
| 2 | no añade checksum |

### El sondeo `0xF7`

El driver oficial hace un `SET_REPORT 0xF7` (query de batería wireless) **cada ~2 s,
sin parar**, mientras está abierto — también durante las pruebas que funcionaron. Ver
§ recomendaciones para Linux.

---

## Per-key / iluminación personalizada (DIY) — opcode `0x0C`

Capturado el 2026-08-28 con USBPcap funcionando de nuevo (ver runbook §4). El usuario
pintó en Akko Cloud Driver, modo DIY, la fila de números en rojo y unas letras en otro
color, y dio a aplicar. Captura: `docs/pcap/akko-2.4g-perkey.pcapng`.

### Secuencia completa que manda el driver al pulsar "aplicar"

Todo son `SET_REPORT` (Feature, `wValue=0x0300`, `wIndex=0x0002`, 64 bytes) a la
interfaz 2, igual que el color sólido:

| # | Paquete (primeros bytes) | Rol |
|---|---|---|
| 1 | `07 0d 04 04 00 00 c8 c8 53` | **Entrar en modo custom/DIY.** `0x07` sub `0x0d` (el color sólido es sub `0x01`). `c8 c8` = brillo (200) teclas + lateral. CK en byte[8] con la regla de siempre `0xFF-(sum[0..7]&0xFF)`. |
| 2 | `88 00 00 00 00 00 00 77` | Housekeeping (apareció 1 vez). CK header en byte[7]. Rol exacto sin confirmar; replicarlo por si acaso. |
| 3 | `fc 00 00 00 …` | Housekeeping (apareció 1 vez). Rol sin confirmar. |
| 4 | **7 × frame `0x0C`** (idx 0..6) | **El mapa RGB.** Ver abajo. |
| — | (se reenvían los 7 frames una segunda vez) | El driver manda el mapa **dos veces** seguidas. Con una sola pasada probablemente basta. |

No hay paquete de "commit" final: el último frame aplica el mapa. Durante todo esto
sigue el sondeo `0xF7` cada ~2 s.

### Frame `0x0C` (mapa de teclas)

```
byte[0]     = 0x0C
byte[1]     = 0x00
byte[2..3]  = 0x0180 little-endian = 384 = longitud total del mapa en bytes (128 LED × 3)
byte[4]     = índice de frame (0..6)
byte[5..6]  = 0x00 0x00
byte[7]     = CK = (0xFF - (sum(byte[0..6]) & 0xFF)) & 0xFF   ← SOLO la cabecera, NO el payload
byte[8..63] = payload: hasta 56 bytes del array RGB plano
```

- El mapa es un **array plano de 128 entradas RGB** (`R,G,B` por LED, orden RGB
  confirmado: la fila de números salió con `ff 00 00` = rojo), indexado por número de
  LED del teclado.
- Se trocea en **7 frames**: `offset = idx * 56`, `len = min(56, 384 - offset)`.
  Frames 0..5 llevan 56 bytes, el frame 6 lleva los 48 restantes; el resto va a `0x00`.
- El checksum del `0x0C` **es distinto del `0x07/0x08`**: va en byte[7] y cubre solo
  los 7 bytes de cabecera (el payload no entra en el checksum).

Ejemplo real (frame 0, primera pasada):
```
0c 00 80 01 00 00 00 72 | 00 00 00 ff 00 00 00 00 00 00 00 00 00 00 00 00 ...
                     └CK   └ LED0=(0,0,0)  LED1=(ff,0,0)=rojo  LED2=(0,0,0) ...
```

### ⚠️ Limitación: per-key dinámico NO es viable por 2.4 GHz

Probado el 2026-08-28 con un PoC de gauge de batería en la fila de números. Cada
refresco del mapa (`07 0d` + 7 frames `0x0C`, y el driver lo manda 2 veces) **satura
el enlace RF**: el dongle multiplexa el mapa y los input reports del teclado sobre la
misma radio, así que **mientras se sube el mapa el teclado no responde** (ventana
muerta de varios segundos con una animación; ~0.5–1 s incluso con una sola pasada).

- **Efectos per-key animados / periódicos (batería que se actualiza, notificaciones):
  descartados por 2.4 GHz.** El teclado se vuelve inusable durante cada update.
- Per-key sí sirve para un estado **estático** que se escribe una vez.
- Por **cable** no hay contención de radio → per-key dinámico sí sería viable ahí.
- Para batería en modo inalámbrico, usar color sólido (`0x07`) + tira lateral (`0x08`)
  como ya hace `rgb/sync-rgb-windows.py` (1–2 paquetes, apenas molesta al tecleo).

### Para Linux (per-key)

1. Construir el array de 128×3 bytes con el color por tecla (mapa LED→índice: derivar
   del `.pcap` o del layout que ya use `rgb/akko-rgb`).
2. Mandar `07 0d 04 04 00 00 BB BB CK` (Feature, if 2) para entrar en modo custom,
   `BB` = brillo.
3. (Opcional/seguro) replicar `88 …` y `fc …`.
4. Mandar 7 Feature reports `0c 00 80 01 <idx> 00 00 <CK_header> <56 bytes>`, idx 0→6.
5. Repetir el bloque de 7 una vez más como hace el driver (opcional).

---

## Recomendaciones para Linux

1. **Aplicar color por 2.4 GHz = aplicar color por cable.** Escribir
   `07/08 01 04 04 08 RR GG BB CK` + ceros (64 bytes) como **Feature report**
   (`ioctl HIDIOCSFEATURE`, no `write()` que manda Output report), report ID `0x00`,
   al nodo hidraw de la **interfaz 2** (`bInterfaceNumber == 2`) del PID `0x4011`.
2. **Nada más.** Quitar de `akko-rgb`, `sync-rgb.py`, `battery-lighting`,
   `rgb-notify-flash` el paquete `0x88`. No portar `setLightType` /
   `changeWirelessLoopStatus` / doble escritura obligatoria.
3. Si con eso **aún** no cambia por 2.4 GHz, los sospechosos que quedan son, en orden:
   - **Feature vs Output report.** El bus muestra `wValue=0x0300` (Feature). Si Linux
     usa `write()` sobre `/dev/hidrawX` está mandando un Output report → no vale.
   - **Interfaz equivocada.** Tiene que ser la `:1.2` del dongle, no `:1.0` ni `:1.1`.
   - **Radio dormida.** El driver oficial nunca deja de sondear `0xF7` cada 2 s.
     Probar: hacer 2-3 `GET_FEATURE`/`0xF7` justo antes del `0x07`, y en un daemon
     mantener un sondeo `0xF7` de fondo a 2 s para tener el enlace RF "caliente".
4. Comparar trama a trama con `docs/pcap/akko-2.4g-2.4ghz-working.pcapng` usando
   `usbmon` en el lado Linux.

---

## Capturas en el repo

| Fichero | Contenido |
|---|---|
| `docs/pcap/akko-2.4g-2.4ghz-working.pcapng` | **Referencia.** Rojo/verde/azul/blanco al backlight (`0x07`) y tira lateral (`0x08`) por gRPC `sendMsg` crudo con la ruta correcta. Verificado a ojo. |
| `docs/pcap/akko-2.4g-color-change.pcapng` | Cambio de color desde la GUI oficial de Akko Cloud Driver (misma escritura `0x07`). |
| `docs/pcap/akko-2.4g-script-grpc.pcapng` | El fallo: `sync-rgb-windows.py` con la ruta obsoleta → solo sondeo `0xF7`, ningún `0x07`. |
| `docs/pcap/akko-2.4g-perkey.pcapng` | **Per-key / DIY.** Fila de números en rojo + letras en otro color desde la GUI. Muestra `07 0d` (modo custom) + 7 frames `0x0C` × 2 pasadas. |

Filtro útil en Wireshark: `usb.transfer_type == 0x02 && usb.data_len > 8`

---

## Correcciones de documentación (del informe de Opus)

- `docs/HARDWARE_PROTOCOLS.md`: flag de RGB personalizado = **`0x08`**
  (`AKKO_FLAGS_CUSTOM_RGB`). Confirmado. *(Corregido en `731ecf0`.)*
- Toda mención a `0x88` como "pipeline commit" / "RF flush": **refutada por captura USB**.
- Checksum: byte[8], `0xFF-(sum[0..7]&0xFF)`. Confirmado con 6 muestras reales.
