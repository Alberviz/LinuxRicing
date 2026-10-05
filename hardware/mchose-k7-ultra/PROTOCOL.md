# MCHOSE K7 Ultra / Base 8K — protocolo USB HID

Consolida la especificación (antes en `docs/HARDWARE_PROTOCOLS.md` §2 y en el vault).

## Transporte y ofuscación

- Feature Report, `Report ID 0x11`, longitud total 21 bytes.
- Interfaz `:1.2` (`UsagePage 0xFF01` / `Col02`), nodo `/dev/hidraw*` resuelto
  dinámicamente.
- **Todos** los bytes de payload van con `XOR 0xFF`. Al enviar:

  ```python
  raw = bytearray([0x11] + [x ^ 0xFF for x in payload])   # payload = 20 bytes
  dev.send_feature_report(raw)
  ```

  Al leer: `dec = [buf[0]] + [b ^ 0xFF for b in buf[1:]]`.

## A. Iluminación del anillo LED — comando `0x2B` (payload de 20 bytes)

| byte | valor | notas |
|---|---|---|
| 0 | `0x2B` | opcode de iluminación |
| 1 | `0x01` | subcomando / constante |
| 2 | `TARGET_ID` | `0x06` fijo · `0x02` breathing · `0x01` batería (firmware) · `0x07` wave arcoíris |
| 3 | `0x00` | reservado |
| 4 | brillo | `0..100` |
| 5 | velocidad | `0..4` |
| 6 | `MODE_ID` | `0x01` = activo |
| 7 | `COLOR_MODE` | `0x01` color personalizado · `0x00` auto |
| 8 | `0x00` | dirección / reservado |
| 9..11 | `R, G, B` | anillo LED |
| 12..14 | `R, G, B` | duplicado / relleno (mismo color) |
| 15..19 | `0x00` | padding |

Encabezado observado en capturas: `[0x2B, 0x01, TARGET, 0x00]` +
`[100, speed, 0x03, 0x01, 0x00]` para estático.

### Targets confirmados en hardware

| Target | Efecto en la base |
|---|---|
| `0x06` | color fijo constante (sincronizado con Material You, cero parpadeo) |
| `0x02` | respiración monocolor con `R1,G1,B1` |
| `0x01` | modo batería oficial del firmware (respiración verde/ámbar/rojo) |
| `0x07` | ola arcoíris ARGB autónoma (calculada en ROM) |

## B. Telemetría de batería — comando `0x06`

- **Solicitud:** `req = [0x11, 0x06 ^ 0xFF] + [0xFF] * 19`, vía
  `send_feature_report`. En modo base (`PID 0x1001`) conviene reintentar ~6 veces a
  ~40 ms para pillar el pulso RF de 3.65 s.
- **Respuesta:** `get_feature_report(0x11, 64)`, luego `XOR 0xFF` desde `byte[1]`:
  - `dec[0..1]` = `0x11 0x06` (echo).
  - `dec[2..3]` = VID `0x38 0x37`.
  - `dec[11]` = **porcentaje de batería** `0..100`.
  - `dec[12]` = **estado de carga**: `0x00` descargando · `0x01` ⚡ cargando
    (en la base `PID 0x1001` o por cable `PID 0x4150`).

- Ejemplo real (dongle 1001, batería 65 %): `dec = 11 06 37 38 50 41 1c 05 05 00 09 41 00`
  (`dec[11]=0x41`, `dec[12]=0`). A veces la respuesta llega toda a ceros (pulso RF
  perdido): reintentar.
- **Detección de carga por cable (2026-10-05):** al enchufar el cable el ratón enumera
  como `3837:4150`, no como `1001`. El lector debe buscar ambos PIDs; si el USB `4150`
  existe, el ratón se está cargando aunque el reporte HID no se lea. (En la sesión de
  sondeo el cable no llegó a conectarse, así que el layout exacto de `4150` sigue sin
  verificar en vivo.)

- **Bytes reales en la base (2026-10-05, ratón al 65 %)** — descargando:
  Feature `dec = 11 06 37 38 50 41 1c 05 05 00 09 41 00 ..` y push
  `13 e2 01 01 00 41 01 03 06 28 4b 37`; cargando: Feature `dec[12]=01` y push
  `dec[4]=01` (`13 e2 01 01 01 41 ...`). Además llegan push `13 e5 06 ..` y
  `13 e5 2b ..` que no llevan batería, y ~50 % de los Feature vuelven a ceros
  (`11 06 00 ..`): hay que drenar todos los push y reintentar ~2 s.

Referencia de implementación: `get_k7_ultra_battery()` en `rgb/mchose-battery`
(Linux) y `rgb/mchose-battery-windows.py` (Windows).

## Herramientas

- `rgb/mchose-lighting <static|breathing|wave|battery|off> [#hex]`
- `rgb/mchose-pcap-analyzer.py <archivo.pcapng>` — decodifica y desglosa campos.
