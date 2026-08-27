# Akko 5075B Plus — Protocolo USB real del dongle 2.4 GHz

> **Autor:** Agente de Windows (Claude)
> **Fecha:** 2026-08-27
> **Método:** captura USBPcap del dongle `3151:4011` con el driver oficial de Akko
> en marcha, comparando (A) cambio de color desde la GUI de Akko Cloud Driver
> —que **sí** funciona— contra (B) `rgb/sync-rgb-windows.py` por la ruta gRPC
> —que **no** cambia el color—.
> **Capturas:** `docs/pcap/akko-2.4g-color-change.pcapng` (A) y
> `docs/pcap/akko-2.4g-script-grpc.pcapng` (B).

---

## TL;DR para el agente de Linux

1. El dongle 2.4 GHz acepta **exactamente el mismo paquete de iluminación que el modo
   cable**. No hay protocolo nuevo.
2. Se envía como **`SET_REPORT` (Feature report, report ID 0x00) a la interfaz 2** del
   dongle — el mismo nodo hidraw `:1.2` que ya usáis para la batería `0xF7`.
3. **NO** hay que enviar nada más: ni `setLightType`, ni `changeWirelessLoopStatus`,
   ni el paquete `0x08` de la tira lateral en la misma ráfaga, ni el "flush `0x88`".
4. **El "flush `0x88`" hay que quitarlo de todos los scripts.** En la captura que SÍ
   funciona, lo único que se manda tras el `0x07` es una *lectura* `0x88 …77` (status),
   no una escritura. `0x88` nunca ha hecho de commit — el informe de Opus tenía razón.
5. La fórmula de checksum del repo (`rgb/akko-rgb`) **es correcta** y coincide byte a
   byte con lo que manda el driver oficial.
6. Por qué fallaba `sync-rgb-windows.py`: al llamar `setLightType(light_type=2)` +
   `changeWirelessLoopStatus(lock)` antes del `sendMsg(0x07)`, **el driver deja de
   emitir el paquete `0x07` al bus USB** (ver §3). Esas llamadas gRPC no son opcodes
   USB y además envenenan el estado del driver.

---

## 1. Identificación del dispositivo

```
Bus USBPcap:      \\.\USBPcap3  (root hub USB\ROOT_HUB30\4&1c1e67e3, vía hub ASMedia 174C:2074)
usb.idVendor:     0x3151
usb.idProduct:    0x4011
device_address:   6   (en esa sesión)
Interfaz usada:   2   (wIndex = 0x0002)
```

## 2. El paquete que FUNCIONA (captura A, GUI)

Cada cambio de color en la GUI genera **un solo** control transfer OUT:

```
SETUP:  bmRequestType = 0x21   (Host→Device | Class | Interface)
        bRequest      = 0x09   (SET_REPORT)
        wValue        = 0x0300 (HID report type 3 = Feature, report ID = 0x00)
        wIndex        = 0x0002 (interface 2)
        wLength       = 0x0040 (64 bytes)

DATA (64 bytes):
        byte[0]   = 0x07   opcode: backlight / teclas
        byte[1]   = 0x01
        byte[2]   = 0x04
        byte[3]   = 0x04   brillo (la GUI mandó 0x04)
        byte[4]   = 0x08   flags = AKKO_FLAGS_CUSTOM_RGB
        byte[5]   = R
        byte[6]   = G
        byte[7]   = B
        byte[8]   = CK     checksum
        byte[9..63] = 0x00
```

### Checksum (verificado con 2 muestras reales)

```
CK = (0xFF - (sum(byte[0..7]) & 0xFF)) & 0xFF
```

| payload[0..8] | R,G,B | CK calc |
|---|---|---|
| `07 01 04 04 08 ff ac 00 3c` | 255,172,0 | 24+255+172+0 = 451; 451&0xFF = 0xC3; 0xFF-0xC3 = **0x3C** ✓ |
| `07 01 04 04 08 4a 90 e2 2b` | 74,144,226 | 24+74+144+226 = 468; 468&0xFF = 0xD4; 0xFF-0xD4 = **0x2B** ✓ |

Es **idéntico** a `rgb/akko-rgb` (modo cable). Confirmado: mismo formato, mismo checksum.

### Secuencia completa por cambio de color (captura A)

```
… (fondo constante: SET_REPORT 0xF7 cada ~2 s = sondeo de batería wireless)
OUT  SET_REPORT  07 01 04 04 08 RR GG BB CK …      ← LA ESCRITURA DE COLOR
OUT  SET_REPORT  88 00 00 00 00 00 00 77 …          ← lectura de estado (arg byte[7]=0x77)
IN   GET_REPORT  → 00 39 00 00 01 …                 ← ACK/status
OUT  SET_REPORT  fc 00 …                            ← "get cached response"
IN   GET_REPORT  → …
… (vuelve el sondeo 0xF7)
```

Sólo la línea `0x07` importa para aplicar el color. `0x88…77` y `0xFC` son lecturas de
verificación que hace la GUI; no son necesarias para que el color se aplique.

> Nota: en esta ventana de captura sólo se observó el opcode `0x07` (backlight). No se
> capturó un paquete `0x08` (tira lateral) aislado. Muy probablemente la tira lateral
> use `0x08` con la misma estructura y el mismo transporte; conviene una captura
> dedicada cambiando SÓLO la tira lateral si hace falta confirmarlo.

## 3. Lo que hace `sync-rgb-windows.py` (captura B) — y por qué NO funciona

La ruta gRPC (`setLightType` → `sendMsg 0x07` → `changeWirelessLoopStatus` →
`sendMsg 0x08` → `sendMsg 0x88`) produce en el bus USB **esto**:

```
OUT  SET_REPORT  fe 40 00 …          ← opcode 0xFE, arg 0x40   (modo / handshake)
OUT  SET_REPORT  f6 0a 00 …          ← opcode 0xF6, arg 0x0A
OUT  SET_REPORT  8f 00 … 70          ← opcode 0x8F, arg byte[7]=0x70  (query)
OUT  SET_REPORT  87 00 … 78          ← opcode 0x87, arg byte[7]=0x78  (query)
OUT  SET_REPORT  fc 00 …             ← get cached response
OUT  SET_REPORT  f7 00 …             ← sondeo batería
```

**No aparece ningún `0x07`. No aparecen los bytes RGB. No aparece ningún `0x08`.**

Es decir: el `Akko Cloud Driver` recibe el `sendMsg` con el payload `0x07`+RGB, pero
tras `setLightType(light_type=2, dangle_type=1)` y/o `changeWirelessLoopStatus`
**no traduce ese `sendMsg` a un SET_REPORT en el bus**. Los opcodes `0xFE 0x40`,
`0xF6 0x0A`, `0x8F…70`, `0x87…78` son lo que el driver emite para esas llamadas de
gestión — no son la escritura de iluminación.

Confirma el diagnóstico del informe de Opus: `setLightType` y `changeWirelessLoopStatus`
son **métodos RPC internos del driver**, no opcodes, y meterlos en la secuencia rompe
la escritura de color.

## 4. Recomendaciones concretas para Linux

1. **Aplicar color por 2.4 GHz = aplicar color por cable**, pero escribiendo en el
   nodo hidraw de la **interfaz 2 del PID `0x4011`** (el mismo que ya seleccionáis para
   `0xF7`). Un único `SET_REPORT` Feature, report ID 0, 64 bytes,
   `07 01 04 04 08 RR GG BB CK`.
2. **Quitar el `0x88` de** `akko-rgb`, `sync-rgb.py`, `battery-lighting`,
   `rgb-notify-flash`. No hace nada útil y ensucia el pipeline.
3. **No** portar `setLightType` / `changeWirelessLoopStatus` / la doble escritura
   `0x07`+`0x08`+`0x88` de `sync-rgb-windows.py`. Ese script es la referencia de lo que
   **no** hay que hacer.
4. Para la tira lateral: probar `0x08` con la misma estructura
   (`08 01 04 04 08 RR GG BB CK` o el layout que ya tengáis) por el mismo transporte.
5. Si tras esto sigue sin cambiar por 2.4 GHz en Linux, el sospechoso pasa a ser el
   **transporte hidraw** (¿`SET_REPORT` vía `ioctl HIDIOCSFEATURE` con el byte de
   report ID 0x00 al principio? ¿longitud 64 vs 65?), no el contenido del paquete.

## 5. Correcciones de documentación pendientes (del informe de Opus)

- `docs/HARDWARE_PROTOCOLS.md`: el flag de RGB personalizado es **`0x08`**
  (`AKKO_FLAGS_CUSTOM_RGB`), no `0x07`. Confirmado por esta captura. *(Ya corregido en
  el commit `731ecf0`; verificar que quedó bien.)*
- Toda mención a `0x88` como "pipeline commit" / "RF flush" debe marcarse como
  **refutada por captura USB** (`docs/pcap/akko-2.4g-color-change.pcapng`).
- `RGB_HANDOVER_LINUX.md` / `RGB_HANDOVER_WINDOWS.md`: checksum en **byte[8]** con
  `0xFF-(sum&0xFF)`, no byte[63] ni `sum&0xFF`.
