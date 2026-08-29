# Akko 5075B Plus — protocolo USB HID

Consolida la especificación (antes en `docs/HARDWARE_PROTOCOLS.md` §1). Para el
detalle de cómo se verificó el modo 2.4 GHz y el per-key, ver
[`USB_FINDINGS_2.4G.md`](USB_FINDINGS_2.4G.md).

## Transporte

- Feature Report, `Report ID 0x00` + 64 bytes de payload (65 en total).
- En Windows viaja como `SET_REPORT`: `bmRequestType=0x21`, `bRequest=0x09`,
  `wValue=0x0300`, `wIndex=0x0002` (interfaz 2), `wLength=64`.
- En Linux: `ioctl(fd, HIDIOCSFEATURE(65), b"\x00" + payload)` sobre el nodo
  `/dev/hidraw*` cuya ruta física contiene `:1.2`. **Feature report, no `write()`**
  (`write()` manda un Output report y el teclado lo ignora).
- **2.4 GHz = igual que cable.** El dongle (`PID 0x4011`) acepta el mismo paquete.
  No hace falta `setLightType`, `changeWirelessLoopStatus`, ni un "commit `0x88`"
  (esto último era una teoría; las capturas USB la refutaron — `0x88` es una
  lectura, `FEA_CMD_GET_SLEDPARAM`).

```python
def HIDIOCSFEATURE(size):  # enviar
    return (3 << 30) | (size << 16) | (ord("H") << 8) | 0x06
def HIDIOCGFEATURE(size):  # leer respuesta
    return (3 << 30) | (size << 16) | (ord("H") << 8) | 0x07
```

## Opcodes

| Opcode | Nombre | Rol |
|---|---|---|
| `0x07` | `FEA_CMD_SET_LEDPARAM` | Iluminación de teclas (backlight) |
| `0x08` | `FEA_CMD_SET_SLEDPARAM` | Iluminación de la tira lateral (SLED) |
| `0x0C` | `FEA_CMD_SET_USERPIC` | Búfer del lienzo per-key |
| `0x83` | `FEA_CMD_GET_BATTERY` | Batería y estado de carga |
| `0x86` | `FEA_CMD_GET_KBOPTION` | Palanca Win/Mac, WinLock, opciones HW |
| `0x87` / `0x88` | `GET_LEDPARAM` / `GET_SLEDPARAM` | Leer estado RGB de teclas / tira |
| `0x80` / `0x8F` | `GET_REV` / `GET_INFOR` | Firmware / identificador de modelo |

Checksum común (**"BIT7"**): `byte[8] = (0xFF - (sum(byte[0..7]) & 0xFF)) & 0xFF`.

## A. Color sólido — teclas (`0x07`) y tira lateral (`0x08`)

Estructura idéntica para ambos opcodes:

| byte | valor | notas |
|---|---|---|
| 0 | `0x07` / `0x08` | opcode |
| 1 | modo | `0x01` = fijo/sólido (ver catálogo abajo) |
| 2 | velocidad | `0..4`. Para `0x07` el firmware la invierte como `4 - speed`; para `0x08` es directa |
| 3 | brillo | `0x04` = 100 % (rango `0..4`) |
| 4 | flags + dirección | `byte[4] = 0x08 \| (dir << 4)`. Bit `0x08` = `AKKO_FLAGS_CUSTOM_RGB` (color de 24 bits) y **debe ir solo** en el nibble bajo — poner `0x01`/`0x02`/`0x04` hace que el firmware ignore el color y lo pinte en blanco. Nibble alto = dirección para los efectos direccionales (Wave, verificado): `0x08` →, `0x18` ←, `0x28` ↓, `0x38` ↑; `0x48`+ apaga. |
| 5..7 | `R, G, B` | `0..255` |
| 8 | checksum BIT7 | |
| 9..63 | `0x00` | relleno |

Ejemplos reales verificados a ojo (de `captures/akko-2.4g-2.4ghz-working.pcapng`):

| Color | `0x07` (teclas) | `0x08` (tira) |
|---|---|---|
| Rojo `255,0,0` | `07 01 04 04 08 ff 00 00 e8` | `08 01 04 04 08 ff 00 00 e7` |
| Verde `0,255,0` | `07 01 04 04 08 00 ff 00 e8` | `08 01 04 04 08 00 ff 00 e7` |
| Azul `0,0,255` | `07 01 04 04 08 00 00 ff e8` | `08 01 04 04 08 00 00 ff e7` |
| Blanco `255,255,255` | `07 01 04 04 08 ff ff ff ea` | `08 01 04 04 08 ff ff ff e9` |

> **Minimizar las señales al teclado.** No se manda nada al Akko salvo cuando el
> usuario pide un cambio: nada de keepalives ni pulsos `0xF7` periódicos "para
> que no se duerma" — cualquier señal repetida cada pocos segundos vuelve a
> congelar el teclado. El driver oficial de Windows sí sondea `0xF7` cada ~2 s
> (y por eso el `0xF7` "keepalive" existía como hipótesis), pero en Linux **no se
> replica**. Si una escritura de color se pierde por 2.4 GHz sobre un enlace
> frío, se busca otra solución antes que un keepalive.

### Catálogo de modos (`byte[1]`)

- **Teclas (`0x07`):** `0` Off · `1` AlwaysOn (sólido) · `2` Breath · `3` Neon ·
  `4` Wave · `5` Ripple · `6` Raindrop · `7` Snake · `8` PressAction (reactivo) ·
  `9` Converage · `10` SineWave · `11` Kaleidoscope · `12` LineWave ·
  `13` UserPicture (lienzo per-key) · `14` Laser · `15` CircleWave · `16` Dazzing ·
  `17` RainDown · `18` Meteor · `19` PressActionOff · `20..22` música / pantalla ·
  `23` Train · `24` FireWorks.
- **Tira lateral (`0x08`):** `0` Off · `1` AlwaysOn · `2` Breath · `3` Neon ·
  `4` Wave · `5` Snake (steady stream) · `20` MusicFollow3 · `21` ScreenColor
  (ambilight) · `22` MusicFollow2.

> ⚠️ **El modo `5` NO es el mismo en las dos zonas.** En la tira lateral (`0x08`)
> es un *flujo* continuo; en las teclas (`0x07`) es *Ripple*, reactivo, y no se
> ve nada sin pulsar teclas. El efecto "flujo/stream" solo tiene sentido en la
> tira. En las teclas, para algo animado usar `4` Wave.
>
> **El stack de Linux solo usa efectos de una sola escritura** (`1` sólido,
> `2` Breath, `4` Wave). El lienzo per-key (modo `13`/`0x0D` + `0x0C`, §C) **no
> se usa**: por 2.4 GHz congela el teclado ~1 s por pasada y el firmware del
> 5075B no conmuta a ese modo de forma fiable.

## B. Telemetría de batería (`0x83`)

- **Solicitud:** 64 bytes, `byte[0]=0x83`, `byte[7]` checksum BIT7 (`0x7C`).
- **Respuesta:**
  - `byte[0]` = `0x83` (echo). *(Por hidraw crudo el echo puede caer en `byte[1]`;
    ver el manejo en `rgb/mchose-battery` y `rgb/mchose-battery-windows.py`.)*
  - `byte[1]` = **porcentaje de batería** `0..100`.
  - `byte[2]` = **estado de alimentación**: `0x00` descargando (2.4 GHz) ·
    `0x01` ⚡ cargando por cable · `0x02` 🔋 carga completa.
  - `byte[3]` = `batteryLp` (bandera de batería baja).

En modo 2.4 GHz (`PID 0x4011`), para obtener la respuesta `0x83` a través de la radio RF se ejecuta el ciclo canónico capturado:
1. Enviar solicitud `0x83` (`83 00 00 00 00 00 00 7C`).
2. Sondear con keepalive `0xF7` hasta que el transceptor RF indique frame listo (`resp[1] == 0x01` o `0x83`).
3. Enviar `0xFC` (`FEA_CMD_GET_CACHED_RESPONSE`) para volcar el búfer de respuesta.
4. Leer con `GET_REPORT`: devuelve `83 <bat%> <cargando> 00 ...`.

Por cable (`PID 0x4015`) mientras carga `byte[1]` puede volver `0` (regla: si `cargando == 1` y `bat == 0`, mantener el último nivel conocido).

> ⚠️ **No usar `0xF7` para la batería.** El poll `0xF7` del driver oficial es un
> keepalive de RF; su `byte[1]` contiene el centinela `0x42` (66 en decimal) y su
> flag de carga está en `byte[3]`, no `byte[2]`. Es la causa del bug del "66 %" en
> Linux. Ver [`USB_FINDINGS_2.4G.md`](USB_FINDINGS_2.4G.md) §"Detección de batería".

## C. Per-key / lienzo (`0x07` modo `0x0D` + `0x0C`) — NO usado

> ⚠️ **El stack de Linux ya no usa el lienzo per-key.** Refrescar el lienzo por
> 2.4 GHz deja el teclado sin responder ~0.5–1 s por pasada y el firmware del
> 5075B no conmuta a modo lienzo de forma fiable. Se retiró de `rgb/sync-rgb.py`
> y `rgb/battery-lighting` (efectos `battery_meter_keys` / `battery_meter_rows` /
> `battery_meter`). Se documenta aquí por si sirve por **cable** en el futuro,
> donde no hay contención de radio. PoC en
> [`USB_FINDINGS_2.4G.md`](USB_FINDINGS_2.4G.md).

1. **Entrar en modo lienzo:** `0x07` con `byte[1]=0x0D`, `byte[2]=0x04`,
   `byte[3]=0x04`, resto `0x00`, checksum en `byte[8]`.
   (Capturado del driver: `07 0d 04 04 00 00 BB BB CK`, `BB` = brillo teclas/tira.)
2. **Transmitir el mapa RGB** en **7 frames `0x0C`** de 64 bytes:

   | byte | valor |
   |---|---|
   | 0 | `0x0C` |
   | 1 | `0x00` (índice de imagen/perfil) |
   | 2..3 | `0x80 0x01` = 384 LE = longitud total del mapa (128 LED × 3) |
   | 4 | `chunk_index` `0..6` |
   | 5..7 | `0x00` |
   | 7 (byte) | checksum BIT7 **solo de la cabecera** `byte[0..6]` (el payload NO entra) |
   | 8..63 | hasta 56 bytes del array RGB plano (`offset = idx*56`) |

   Frames 0..5 llevan 56 bytes; el frame 6 lleva los 48 restantes. El driver oficial
   manda los 7 frames **dos veces**; con una pasada suele bastar. No hay paquete de
   "commit" — el último frame aplica.

3. **Mapa físico de coordenadas** (paso de columna = 6), índice de LED por tecla:
   - Números `1..0`: `[7,13,19,25,31,37,43,49,55,61,67,73]`
   - QWERTY `Q..P`: `[8,14,20,26,32,38,44,50,56,62,68]`
   - ASDF `A..L`: `[9,15,21,27,33,39,45,51,57,63,69]`
   - ZXCV `Z..M`: `[10,16,22,28,34,40,46,52,58,64]`
   - Fila inferior: `[11,17,23,29,35,41,47,53,59]`

   > **PENDIENTE:** mapa sin validar contra hardware real; solo relevante si
   > algún día se reactiva el lienzo por cable.

## D. Iluminación reactiva a batería

Ya no está escrita a fuego: la gobierna el daemon `rgb/battery-lighting`
(`systemd/battery-lighting.service`) desde `~/.config/caelestia/battery-lighting.json`
(reglas: origen, disparador, acciones con efecto por zona). Todos los efectos del
teclado son **modos de firmware de una sola escritura** (`_AKKO_EFFECTS` en el
daemon):

| efecto | teclas `0x07` | tira `0x08` |
|---|---|---|
| `theme` / `solid_theme` | modo `1` color de tema | modo `1` color de tema |
| `breathing` / `breathing_battery` | modo `2` (tema / color de batería) | modo `2` |
| `wave` / `wave_battery` | modo `4` (tema / color de batería) | — |
| `stream_battery` | — (modo 5 en teclas es Ripple) | modo `5` flujo, color de batería |
| `red_static` / `red_breathing` | modo `1` / `2` en rojo `255,0,0` | ídem |

- **Color de batería:** `≤15 %` rojo → ámbar → lima → `100 %` verde (HSV).
- **Mientras carga**, el daemon reescribe el efecto cuando el nivel cruza un
  escalón de 10 % para que el gradiente avance (1 paquete de firmware, sin
  congelar el teclado).

## E. Palanca / opciones (`0x86`)

- **Solicitud:** `byte[0]=0x86`, `byte[1]=0x00` (perfil 0).
- **Respuesta `byte[2]`** (banderas): bit0 WinLock · bit1 palanca de sistema
  (`0` = Windows, `1` = Mac) · bit3 swap WASD/flechas · bit4 LEDs de teclas off ·
  bit5 LEDs de tira off · bit7 bloqueo total. `byte[4]`: ahorro de energía (`1` = on).

## F. Puente gRPC en Windows (`127.0.0.1:3814`)

Si `iot_driver_v200.exe` está activo, retiene el HID. Se habla con él por HTTP POST
`grpc-web+proto`:

- `driver.DriverGrpc/sendMsg` — envía el buffer; `checksumtype` **1** = deja el RGB
  intacto y pone el checksum en `byte[8]` (los valores `0`/`3` lo meten en `byte[7]`
  y pisan el canal B; `2` no añade checksum). Pasar `dangledevtype = 1` (KEYBOARD).
- `driver.DriverGrpc/readMsg` — devuelve el `VenderMsg` de respuesta.

El driver hace un `SET_REPORT 0xF7` cada ~2 s sin parar mientras está abierto: es un
**keepalive de RF** (mantiene "caliente" el enlace), no una lectura fiable de batería
— para eso, `0x83` (ver §B).
