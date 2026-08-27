# 🔬 Especificación Técnica de Protocolos de Hardware

Este documento consolida los protocolos de ingeniería inversa y especificaciones de comunicación para todos los dispositivos del setup en Linux y Windows.

---

## 1. Teclado Akko 5075B Plus (`VID 0x3151, PID 0x4015 / 0x4011`)

- **Microcontrolador / Firmware:** ROYUAN B-series USB HID (`PID 0x4015` en modo cable USB, `PID 0x4011` en modo 2.4 GHz).
- **Interfaz de Control:** Interface 2 (`MI_02` en Windows, `/dev/hidraw*` con `:1.2` en Linux).
- **Tipo de Reporte:** Feature Report de 65 bytes (`Report ID 0x00` + 64 bytes de payload).
- **Opcodes Principales:**
  - `0x08` (`FEA_CMD_SET_SLEDPARAM`): **Configurar Barra Lateral / Side-Strip (SLED)**.
  - `0x07` (`FEA_CMD_SET_LEDPARAM`): **Configurar Iluminación Principal de Teclas (LED Backlight)**.
  - `0x83` (`FEA_CMD_GET_BATTERY`): **Consultar Batería y Estado de Carga**.
  - `0x86` (`FEA_CMD_GET_KBOPTION`): **Consultar Opciones de Hardware, Modo de Palanca (Win/Mac) y WinLock**.
  - `0x87` (`FEA_CMD_GET_LEDPARAM`): **Consultar Estado de RGB de Teclas**.
  - `0x88` (`FEA_CMD_GET_SLEDPARAM`): **Consultar Estado de RGB de Barra Lateral**.
  - `0x80` (`FEA_CMD_GET_REV`): **Consultar Versión de Firmware**.
  - `0x8F` (`FEA_CMD_GET_INFOR`): **Consultar Identificador de Hardware / Modelo**.

### A. Control de Iluminación RGB (Opcodes `0x07` y `0x08`):
- **Estructura del Payload (64 bytes):**
  - `byte[0]`: Opcode (`0x08` para Barra Lateral SLED / `0x07` para Teclas LED).
  - `byte[1]`: Modo (ver tablas completas más abajo).
  - `byte[2]`: Velocidad. *(Nota técnica: Para el opcode `0x07`, la velocidad se invierte internamente como `4 - speed`; para `0x08` es directa `0..4`)*.
  - `byte[3]`: Brillo (`0x04` = 100%, rango 0 a 4).
  - `byte[4]`: Flags (`option | dazzle`). Para color RGB personalizado sólido: **`0x07`** (`e.DAZZLE`).
  - `byte[5]`: Rojo (`0 - 255`).
  - `byte[6]`: Verde (`0 - 255`).
  - `byte[7]`: Azul (`0 - 255`).
  - `byte[8]`: **Checksum BIT7** = `0xFF - (sum(byte[0..8]) & 0xFF)`.
  - `byte[9..63]`: Relleno (`0x00`).

- **Catálogo Completo de Modos SLED (Barra Lateral - Opcode `0x08`):**
  - `0`: `LightOff` (Apagado)
  - `1`: `LightAlwaysOn` (Estático / Sólido)
  - `2`: `LightBreath` (Respiración monocolor)
  - `3`: `LightNeon` (Ciclo de colores espectral)
  - `4`: `LightWave` (Ola de color horizontal)
  - `5`: `LightSnake` (Steady Stream / Flujo continuo)
  - `20`: `LightMusicFollow3` (Ritmo musical)
  - `21`: `LightScreenColor` (Ambilight / Pantalla)
  - `22`: `LightMusicFollow2` (Ritmo musical 2)

- **Catálogo de Modos Principales Backlight (Teclas - Opcode `0x07`):**
  - `0`: `LightOff`, `1`: `LightAlwaysOn` (Estático), `2`: `LightBreath`, `3`: `LightNeon`, `4`: `LightWave`, `5`: `LightRipple` (Ondas), `6`: `LightRaindrop`, `7`: `LightSnake`, `8`: `LightPressAction` (Reactivo), `9`: `LightConverage`, `10`: `LightSineWave`, `11`: `LightKaleidoscope`, `12`: `LightLineWave`, `13`: `LightUserPicture` (Lienzo por tecla), `14`: `LightLaser`, `15`: `LightCircleWave`, `16`: `LightDazzing`, `17`: `LightRainDown`, `18`: `LightMeteor`, `19`: `LightPressActionOff`, `20..22`: Modos Música/Pantalla, `23`: `LightTrain`, `24`: `LightFireWorks`.

### B. Telemetría de Batería y Carga (Opcode `0x83`):
- **Solicitud (Host ➔ Teclado):** Buffer de 64 bytes con `byte[0] = 0x83`, `byte[7]` = Checksum BIT7 (`0x7C`).
- **Respuesta (Teclado ➔ Host):**
  - `byte[0]`: `0x83` (Echo del comando).
  - `byte[1]`: **Porcentaje de Batería** (`0 - 100%`). *(En modo 2.4 GHz `PID 0x4011` reporta el nivel exacto de la celda de litio; en modo cable USB `PID 0x4015` reporta alimentación directa)*.
  - `byte[2]`: **Estado de Alimentación / Carga**:
    - `0x00`: **Descargando / Modo Batería (Wireless 2.4 GHz)**.
    - `0x01`: **⚡ Cargando activamente por cable USB**.
    - `0x02`: **🔋 Carga completa (100%)**.
  - `byte[3]`: `batteryLp` (Umbral / bandera de batería baja).
  - `byte[7]`: Checksum BIT7.

### C. Protocolo de Transmisión Inalámbrica 2.4 GHz (Dongle `PID 0x4011`):
Cuando el teclado opera sobre el transceptor inalámbrico 2.4 GHz, las transmisiones directas al bus colisionan con el bucle de sondeo continuo del dongle. La máquina de estados oficial requiere:
1. **Target ID en Dongle:** Pasar `dangledevtype = 1` (`KEYBOARD`) en protobuf `SendMsg` para que el dongle active el transmisor de radiofrecuencia hacia el teclado.
2. **Conmutación de Modo de Luz:** Enviar RPC `setLightType(device_path, light_type=2, dangle_type=1)` antes de inyectar comandos de color.
3. **Bloqueo de Bucle RF (`changeWirelessLoopStatus`):**
   - Transmitir paquete de Teclas (`0x07`).
   - Invocar `changeWirelessLoopStatus(lock=True)` para pausar el sondeo de teclas durante la ráfaga.
   - Transmitir paquete de Barra Lateral SLED (`0x08`).
   - Enviar paquete de sincronización y vaciado de pipeline `0x88` (`FEA_CMD_GET_SLEDPARAM`).
   - Invocar `changeWirelessLoopStatus(lock=False)` para reanudar el tráfico RF normal.
4. **Modo Lienzo por Tecla (`LightUserPicture` - Opcode `0x0C`):**
   - Permite direccionamiento ARGB individual de las 130 teclas mediante 7 paquetes de 56 bytes RGB (`0x0C`).

### C. Estado de la Palanca / Switch y Opciones (Opcode `0x86`):
- **Solicitud:** Buffer de 64 bytes con `byte[0] = 0x86`, `byte[1] = 0x00` (Perfil 0).
- **Respuesta:**
  - `byte[2]`: Banderas de estado:
    - Bit 0 (`& 0x01`): Bloqueo de Tecla Windows (*WinLock*).
    - Bit 1 (`& 0x02`): **Palanca de Sistema** (`0` = Windows / PC, `1` = Mac / macOS).
    - Bit 3 (`& 0x08`): Intercambio WASD / Flechas de dirección.
    - Bit 4 (`& 0x10`): LEDs de teclas apagados.
    - Bit 5 (`& 0x20`): LEDs de tira lateral apagados.
    - Bit 7 (`& 0x80`): Bloqueo total de teclado.
  - `byte[4]`: Modo de Ahorro de Energía (`1` = Activo).

### D. Interfaz gRPC en Windows (`127.0.0.1:3814`):
- Si el proceso `iot_driver_v200.exe` está activo, retiene el dispositivo USB HID. La comunicación se realiza mediante HTTP POST gRPC-Web con Report ID transparente:
  - `driver.DriverGrpc/sendMsg`: Envía buffer con `checksumtype = 0` (`CheckSumType.BIT7`).
  - `driver.DriverGrpc/readMsg`: Devuelve buffer `VenderMsg` con la respuesta del microcontrolador.

### E. Matriz RGB Tecla por Tecla / Custom Canvas (Opcodes `0x07` y `0x0C`):
- **1. Activar Modo Lienzo Personalizado (`FEA_CMD_SET_LEDPARAM = 0x07`):**
  - `byte[0]`: `0x07`
  - `byte[1]`: **`0x0D` (13 = Modo `LightUserPicture`)**
  - `byte[2]`: `0x04` (Velocidad)
  - `byte[3]`: `0x04` (Brillo 100%)
  - `byte[4..63]`: `0x00`
  - `byte[8]`: Checksum de complemento a uno.

- **2. Transmisión del Búfer de Matriz (`FEA_CMD_SET_USERPIC = 0x0C` / 12):**
  - La matriz completa consta de **392 bytes de datos RGB** (130 teclas * 3 bytes).
  - Se transmiten en **7 fragmentos secuenciales** de 64 bytes (8 bytes cabecera + 56 bytes payload RGB):
    - `chunk[0]`: `0x0C` (`FEA_CMD_SET_USERPIC`).
    - `chunk[1]`: `0x00` (Índice de imagen / perfil).
    - `chunk[2]`: `0x80` (128, byte bajo de longitud 384).
    - `chunk[3]`: `0x01` (1, byte alto de longitud 384).
    - `chunk[4]`: **`chunk_index` (`0, 1, 2, 3, 4, 5, 6`)**.
    - `chunk[5..7]`: `0x00, 0x00, 0x00`.
    - `chunk[8..63]`: 56 bytes de color RGB de teclas (`R, G, B, R, G, B...`).

- **3. Mapeo Físico de Coordenadas de Teclas (Paso de Columna = 6):**
  - **Fila Números (`1, 2, 3, ..., 0`):** `[ 7, 13, 19, 25, 31, 37, 43, 49, 55, 61, 67, 73 ]`
  - **Fila QWERTY (`Q, W, E, ..., P`):** `[ 8, 14, 20, 26, 32, 38, 44, 50, 56, 62, 68 ]`
  - **Fila ASDF (`A, S, D, ..., L`):** `[ 9, 15, 21, 27, 33, 39, 45, 51, 57, 63, 69 ]`
  - **Fila ZXCV (`Z, X, C, ..., M`):** `[ 10, 16, 22, 28, 34, 40, 46, 52, 58, 64 ]`
  - **Fila Inferior (`Ctrl, Alt, Espacio...`):** `[ 11, 17, 23, 29, 35, 41, 47, 53, 59 ]`

- **Llamada ioctl (Linux):**
  ```python
  def HIDIOCSFEATURE(size):
      return (3 << 30) | (size << 16) | (ord("H") << 8) | 0x06

  def HIDIOCGFEATURE(size):
      return (3 << 30) | (size << 16) | (ord("H") << 8) | 0x07

  # Enviar solicitud
  raw = bytearray([0x00]) + req_payload
  fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw)), raw)

  # Leer respuesta
  resp = bytearray(65)
  fcntl.ioctl(fd, HIDIOCGFEATURE(len(resp)), resp)
  ```

---

## 2. Ratón MCHOSE K7 Ultra y Base 8K (`VID 0x3837, PID 0x1001 / 0x4150`)

- **Identificadores de Hardware:**
  - **`PID 0x1001`**: Modo Inalámbrico (Base 8K / Dongle receptor).
  - **`PID 0x4150`**: Modo Cable Directo USB.
- **Controlador:** RealTek SoC HID (Interface 2, `UsagePage 0xFF01` / `Col02`).
- **Tipo de Reporte:** Feature Report de 21 bytes (`Report ID 0x11` + 20 bytes payload) e Input Reports (`0x13`).
- **Ofuscación:** Todos los bytes del payload están invertidos con operación binaria XOR `0xFF`.

### A. Telemetría de Batería y Estado de Carga (Comando `0x06`):
- **Solicitud (Host ➔ Base/Ratón):**
  ```python
  req = bytearray([0x11, 0x06 ^ 0xFF] + [0xFF] * 19)
  dev.send_feature_report(req)
  ```
- **Respuesta (Base/Ratón ➔ Host):** Feature Report `0x11` decodificado con `byte ^ 0xFF`:
  - `dec[0..1]`: `0x11 0x06` (Echo).
  - `dec[2..3]`: VID `0x3837`.
  - `dec[11]`: **Porcentaje de Batería** (`0 - 100%`).
  - `dec[12]`: **Estado de Carga**:
    - `0x00`: **Descargando / En Uso**.
    - `0x01`: **⚡ Cargando activamente** (en la Base inalámbrica con `PID 0x1001` o por cable directo con `PID 0x4150`).
- **Comportamiento Temporal:** En modo Base 8K (`PID 0x1001`), la telemetría se emite en pulsos RF periódicos cada **`3.65 segundos`** sin desconectarse.

### B. Control de Iluminación Anillo LED de la Base (Comando `0x2B`):
- **Estructura del Payload (20 bytes):**
  - `byte[0..3]`: Encabezado `[0x2B, 0x01, 0x06, 0x00]` (Comando `0x2B`, `0x06` = Sólido, `0x02` = Breathing, `0x07` = Wave).
  - `byte[4..8]`: `[100, 0x00, 0x03, 0x01, 0x00]` (Brillo 100, Velocidad 3, Modo Estático 1).
  - `byte[9..11]`: **Anillo LED RGB:** `[r, g, b]`.
  - `byte[12..14]`: **Relleno duplicado:** `[r, g, b]`.
  - `byte[15..19]`: Relleno `[0x00, 0x00, 0x00, 0x00, 0x00]`.
- **Envío con XOR:**
  ```python
  raw = bytearray([0x11] + [x ^ 0xFF for x in payload])
  dev.send_feature_report(raw)
  ```

---

## 3. Placa Base y Memorias RAM (OpenRGB SDK)

- **Placa Base:** ASUS TUF GAMING B560M-PLUS.
  - Zonas: `Aura Mainboard` (4 LEDs, estático), `Aura Addressable 1` (60 LEDs), `Aura Addressable 2` (60 LEDs).
- **RAMs:** 2x A-DATA XPG Spectrix DDR4 (Controlador `ENE DRAM`, 5 LEDs por módulo).
- **Modo Operativo:** Modo `Direct` (Modo 0 en DRAM y Motherboard).
- **Precaución de bus SMBus/I2C:**
  - La comunicación con las RAMs se hace a través del bus I2C de la placa base (~100 kHz).
  - Por eso `main` solo aplica color estático de un solo disparo (`sync-rgb.py`). Si se necesita animación continua, la rama `feature/argb-wave` añade un daemon (`argb-wave.py`) que corre a ~12.5 FPS (`FRAME_SECONDS = 0.08`) usando `zone.set_colors(..., fast=True)` para mantener estabilidad sin saturar el bus.

---

## 4. Tira LED Magic Home Wi-Fi (`192.168.0.136`)

- **Protocolo:** TCP en puerto `5577` a través de la librería `flux_led` (o fallback CLI con `magichome-control`).
- **Comandos:** `bulb.turnOn()`, `bulb.setRgb(r, g, b)`.
