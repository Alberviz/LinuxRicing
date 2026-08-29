# Akko 5075B Plus — Protocolo USB real del dongle 2.4 GHz (RESUELTO)

> **Autor:** Agente de Windows (Claude) · **Fecha:** 2026-08-27, ampliado 2026-08-28/29
> **Estado:** ✅ Color sólido por 2.4 GHz verificado. ✅ **Per-key** capturado (opcode
> `0x0C`). ✅ **Batería/carga descifrada** — el bug del "66 %" en Linux era usar `0xF7`
> en vez de `0x83` (§"Detección de batería"). Bytes exactos capturados con USBPcap.
> ✅ **Transporte 2.4G vs cable** — discriminado por enumeración del PID `0x4015`
> (§"La enumeración del PID `0x4015`"). ✅ **Carga en 2.4G** — flag `resp83[3]`
> validado por tendencia del EMA del nivel (§"detección por tendencia del EMA").

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

### Ejemplos reales de `captures/akko-2.4g-2.4ghz-working.pcapng` (verificado a ojo)

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

`captures/akko-2.4g-script-grpc.pcapng` es una captura de ese fallo: solo se ve el
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

El driver oficial hace un `SET_REPORT 0xF7` **cada ~2 s, sin parar**, mientras está
abierto — también durante las pruebas que funcionaron. Es un **keepalive de RF**, no
una fuente fiable de batería (ver siguiente sección).

---

## Detección de batería y estado de carga (opcodes `0x83` y `0xF7`)

Sniff del 2026-08-29 en 3 fases con el teclado: **(A)** 2.4 GHz sin cable,
**(B)** 2.4 GHz + cable USB enchufado al PC (cargando), **(C)** modo USB-only cargando.
Captura: `captures/akko-2.4g-battery-sniff.pcapng`.

### Dos queries, **distinto formato de respuesta**

Ambas son Feature reports de 64 bytes a la interfaz 2; la respuesta se lee con
`GET_REPORT` (o `readMsg` por el bridge):

| Query | Respuesta | batería | flag "cargando" |
|---|---|---|---|
| **`0x83`** (query de batería; funciona por cable **y** por 2.4 GHz) | `83 <bat%> <chg> 00 …` | **byte[1]** | **byte[2]** (0/1) |
| **`0xF7`** (poll RF del driver) | `<00\|01> <bat%> 00 <chg> 01 01 01 <ck>` | **byte[1]** | **byte[3]** (0/1) |

### Valores medidos

| Fase | Respuesta `0x83` | Respuesta `0xF7` |
|---|---|---|
| **A** · 2.4 GHz, sin cargar | `83 4a 00` → **74 %**, no carga | `00 4a 00 00` → **74 %**, no carga |
| **B** · 2.4 GHz, cargando | `83 54 01` → **84 %**, **cargando** (sube 84→85 en vivo) | `00 42 00 01` → byte[1] pegado en `0x42` (66), chg en byte[3] |
| **C** · USB-only, cargando | `83 00 01` → **byte[1] = `0x00`**, chg en byte[2] | (el dongle sigue devolviendo `00 42 00 01`) |

> El byte[1] de `0xF7` ya había derivado a `0x42` (66) **antes** de enchufar el cable
> (74 → 72 → 66 en ~2 min con el teclado quieto), mientras `0x83` seguía dando 74.
> `0xF7` byte[1] simplemente no es fiable.

### El bug de Linux — "la batería salta a 66"

1. **`0xF7` byte[1] no es una lectura fiable de batería: va a la deriva.** En el sniff,
   con el teclado quieto, pasó de `0x4a` (74) → `0x48` (72) → `0x42` (66) en ~2 min,
   mientras `0x83` se mantenía clavado en `0x4a` (74) todo ese rato. Al empezar a
   cargar, `0x83` reveló el nivel real subiendo (84 → 85) y `0xF7` se quedó pegado
   en `0x42` (66). El "66" que ve Linux = ese byte[1] de `0xF7`.
2. Linux sondea **`0xF7`** y lee byte[1] como batería → muestra un valor que deriva y
   se pega en 66.
3. Encima el flag de carga de `0xF7` está en **byte[3]**, no en byte[2]. Si Linux mira
   byte[2] (que sigue `00`), ni se entera de que está cargando.
4. El "84 % subiendo" que da `rgb/sync-rgb-windows.py` **sí es correcto**: usa `0x83`
   (no `0xF7`) y lee `payload[1]`/`payload[2]`. `0x83` responde de verdad por el bus
   2.4 GHz (visto ~10 veces en el sniff: `83 54 01`, `83 55 01`).

### La enumeración del PID `0x4015` = posición física de la palanca (Linux)

Descubierto el 2026-08-29. En Linux, el PID wired `0x4015` **solo enumera cuando
la palanca del teclado está en posición cable**. Con la palanca en 2.4G, aunque
el cable USB esté enchufado al PC, el teclado **no expone la interfaz HID
cableada** — `lsusb` solo muestra `3151:4011` (el dongle). Verificado en vivo:
palanca en 2.4G + cable al PC → solo `3151:4011`.

Por tanto la presencia de `0x4015` es un discriminador fiable del transporte
activo:

| `0x4015` en bus | `0x4011` en bus | Transporte activo |
|---|---|---|
| ✅ | (indiferente) | **Cable USB** (palanca en cable) |
| ❌ | ✅ | **2.4 GHz** (palanca en 2.4G; el cable, si está, es solo para cargar) |

> Nota: la tabla previa de este documento afirmaba que "2.4G + cable al PC" sí
> enumeraba `0x4015`. En Linux **no** es así. Puede que en Windows el driver
> fuerce la enumeración, o que la observación original mezclara estados.

Defensa extra: si `0x4015` enumera pero **no contesta a `0x83`** por su nodo (se
ha visto devolver todo ceros con la palanca en 2.4G) y además está el dongle, el
código trata el transporte como 2.4G.

### El bug de firmware: `resp83[3]` queda PEGADO en `1`

Cuando el teclado está en modo 2.4G con el cable enchufado y después se
desenchufa, **`resp83[3]` permanece en `1` indefinidamente**. El firmware no
emite ninguna actualización espontánea al quitar el cable — el flag de carga
solo se actualiza cuando hay una transición activa (enchufar de nuevo, o
reiniciar la sesión HID).

Evidencia directa:
- lsusb mostraba solo `3151:4011` (sin cable)
- resp83: `00 83 5d 01 00 00 00 00 7c 00` → bat=93%, chg=1 → **incorrecto**
- La batería bajaba (97→93→90%) mientras el firmware decía "cargando"

### El `0x83` por RF devuelve frames RANCIOS

El 2026-08-29, con la palanca en 2.4G, `resp83` (nivel **y** flag de carga) no es
consistente entre lecturas: `resp83[2]` saltaba 53–97 entre polls consecutivos, y
`resp83[3]` (flag de carga) llegaba a `1` en el daemon mientras una sonda
independiente lo leía `0` cinco veces seguidas — cada lector recibe un frame
distinto. El ciclo `0x83`→`0xF7`→`0xFC` termina en `0xFC` =
`FEA_CMD_GET_CACHED_RESPONSE`; el dongle sirve del búfer un frame que puede ser
viejo (de cuando la batería estaba a otro nivel, o cuando aún cargaba). No hay
forma fiable de forzar un frame fresco desde Linux. **Ni el nivel ni el flag de
`0x83` se pueden usar crudos.**

### Solución aplicada (2026-08-29)

**Archivo:** `rgb/battery-lighting` y `rgb/mchose-battery`, rama del dongle 2.4G.
Reemplaza el parche `wired_present and resp83[3]==1`, que rompía el caso legítimo
"palanca en 2.4G + cable cargando" (con la palanca en 2.4G el PID `0x4015` no
enumera → forzaba `charging=False`).

- **Transporte:** enumeración de `0x4015` (ver sección anterior).
- **Nivel:** EMA `0.8·prev + 0.2·raw`; si el salto es > 25 puntos se deriva el EMA
  ±4 hacia él (para seguir cambios reales grandes sin congelarse en un glitch).
- **Carga:** `is_chg` = las TRES condiciones a la vez:
  1. `resp83[3] == 1` en la lectura actual, y
  2. ≥ 2 de las últimas 6 lecturas también fueron `1` (`akko_chg_hist`) —
     descarta frames rancios sueltos con `chg=1`, y
  3. el EMA no ha caído > 6 puntos bajo el **ancla**: el ancla se fija en la
     transición `0→1` y **trepa** con el EMA mientras carga, así que al
     desenchufar basta con que el nivel baje ~6 puntos desde el pico para
     detectar el fin de carga aunque el flag se quede pegado en `1`.

| Escenario | Resultado |
|---|---|
| 2.4G + cable (PC o cargador de pared), cargando | `Cargando` ✅ |
| 2.4G, cable quitado, flag ya a `0` | `Descargando` ✅ en el siguiente poll (≤ 3 s en cadencia de carga) |
| 2.4G, cable quitado, flag PEGADO en `1` | `Cargando` unos minutos, hasta que el EMA baje > 6 bajo el pico → `Descargando` |
| Frame rancio suelto con `chg=1` mientras descarga | ignorado (regla 2) |

**Bug relacionado corregido en el daemon:** `tick()` llamaba a `write_alerts(new)`
*después* de liberar zonas con `apply_zone(zk, None)`. Como `apply_zone(None)`
delega el "volver a estático" en `sync-rgb.py`, y éste se salta las zonas que
`battery_alerts.json` todavía reclame, la tira lateral se quedaba **clavada en el
wave de carga** tras dejar de cargar. Ahora `write_alerts(new)` va antes de la
liberación.

**Mejora pendiente (baja prioridad):** el `mchose-battery.timer` de systemd
lanza `mchose-battery --notify` (flag que ya no existe) cada 60 s → el servicio
falla en bucle. Retirar ese timer/servicio; de paso, un lector menos sobre el
dongle. **Vía limpia para el flag pegado:** sniff en Windows buscando un opcode
que reporte VBUS, o un evento del driver al conectar/desconectar el cable.

## Per-key / iluminación personalizada (DIY) — opcode `0x0C`

Capturado el 2026-08-28 con USBPcap funcionando de nuevo (ver runbook §4). El usuario
pintó en Akko Cloud Driver, modo DIY, la fila de números en rojo y unas letras en otro
color, y dio a aplicar. Captura: `captures/akko-2.4g-perkey.pcapng`.

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
4. Comparar trama a trama con `captures/akko-2.4g-2.4ghz-working.pcapng` usando
   `usbmon` en el lado Linux.
5. **Batería:** leer con `0x83` (no `0xF7`). Ver §"Detección de batería y estado de
   carga". `[1]`=%, `[2]`=cargando; si carga, ignorar el %. Mantener un sondeo `0xF7`
   de fondo solo como keepalive de RF.

---

## Capturas en el repo

| Fichero | Contenido |
|---|---|
| `captures/akko-2.4g-2.4ghz-working.pcapng` | **Referencia.** Rojo/verde/azul/blanco al backlight (`0x07`) y tira lateral (`0x08`) por gRPC `sendMsg` crudo con la ruta correcta. Verificado a ojo. |
| `captures/akko-2.4g-color-change.pcapng` | Cambio de color desde la GUI oficial de Akko Cloud Driver (misma escritura `0x07`). |
| `captures/akko-2.4g-script-grpc.pcapng` | El fallo: `sync-rgb-windows.py` con la ruta obsoleta → solo sondeo `0xF7`, ningún `0x07`. |
| `captures/akko-2.4g-perkey.pcapng` | **Per-key / DIY.** Fila de números en rojo + letras en otro color desde la GUI. Muestra `07 0d` (modo custom) + 7 frames `0x0C` × 2 pasadas. |
| `captures/akko-2.4g-battery-sniff.pcapng` | **Detección de batería/carga**, 3 fases (2.4 GHz sin cargar / 2.4 GHz cargando / USB-only cargando). Respuestas `0x83` y `0xF7`. Explica el bug del "66 %". |

Filtro útil en Wireshark: `usb.transfer_type == 0x02 && usb.data_len > 8`

---

## Correcciones de documentación (del informe de Opus)

- `PROTOCOL.md` / la doc histórica: flag de RGB personalizado = **`0x08`**
  (`AKKO_FLAGS_CUSTOM_RGB`). Confirmado. *(Corregido en `731ecf0`.)*
- Toda mención a `0x88` como "pipeline commit" / "RF flush": **refutada por captura USB**.
- Checksum: byte[8], `0xFF-(sum[0..7]&0xFF)`. Confirmado con 6 muestras reales.
