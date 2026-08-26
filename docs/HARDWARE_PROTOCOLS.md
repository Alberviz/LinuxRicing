# 🔬 Especificación Técnica de Protocolos de Hardware

Este documento consolida los protocolos de ingeniería inversa y especificaciones de comunicación para todos los dispositivos del setup en Linux y Windows.

---

## 1. Teclado Akko 5075B Plus (`VID 0x3151, PID 0x4015`)

- **Microcontrolador / Firmware:** ROYUAN B-series USB HID.
- **Interfaz de Control:** Interface 2 (`MI_02` en Windows, `/dev/hidraw*` con `:1.2` en Linux).
- **Tipo de Reporte:** Feature Report de 65 bytes (`Report ID 0x00` + 64 bytes de payload).
- **Opcodes Principales:**
  - `0x08` (`FEA_CMD_SET_SLEDPARAM`): **Barra Lateral / Side-Strip (SLED)**.
  - `0x07` (`FEA_CMD_SET_LEDPARAM`): **Iluminación Principal de Teclas (LED Backlight)**.
- **Estructura del Payload (64 bytes):**
  - `byte[0]`: Opcode (`0x08` para SLED / `0x07` para LED).
  - `byte[1]`: Modo (`0x01` = Estático, `0x00` = Apagado, `0x02` = Respiración).
  - `byte[2]`: Velocidad (`0x04`).
  - `byte[3]`: Brillo (`0x04` = 100%, rango 0 a 4).
  - `byte[4]`: Flags (`option | dazzle`). Para color RGB personalizado sólido: **`0x08`**.
  - `byte[5]`: Rojo (`0 - 255`).
  - `byte[6]`: Verde (`0 - 255`).
  - `byte[7]`: Azul (`0 - 255`).
  - `byte[8]`: **Checksum** = `0xFF - (sum(byte[0..8]) & 0xFF)` (complemento a uno de la suma de los 8 primeros bytes).
  - `byte[9..63]`: Relleno (`0x00`).
- **⚠️ Dos correcciones importantes sobre versiones anteriores de este documento** (23-08-2026, tras depuración exhaustiva del bug de "barra lateral en rosa fijo"):
  1. El checksum va en el **byte 8**, no en el byte 63, y es un complemento a uno (`0xFF - suma`), no una suma directa. Con el checksum en la posición equivocada el firmware descartaba el paquete en silencio: no había error de HID, pero el LED nunca cambiaba.
  2. El byte `[4]` **no** sigue el esquema genérico ROYUAN `(option<<4)|flags` con `0x07`=custom/`0x08`=preset. Para la familia Akko B-series específicamente, es un valor plano y `0x08` es el que selecciona "usar el RGB personalizado"; `0x07` en este firmware hace que el LED cicle en rainbow. Verificado contra el driver real de OpenRGB (`Controllers/RoyuanKeyboardController/RoyuanKeyboardController.cpp`, perfil `AkkoBSeries()`), que sí controla el backlight con éxito en producción.
- **Llamada ioctl (Linux):**
  ```python
  def HIDIOCSFEATURE(size):
      return (3 << 30) | (size << 16) | (ord("H") << 8) | 0x06

  payload[8] = 0xFF - (sum(payload[:8]) & 0xFF)
  raw = bytearray([0x00]) + payload
  fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw)), raw)
  ```

---

## 2. Base de Carga / Dongle MCHOSE K7 Ultra (`VID 0x3837, PID 0x1001`)

- **Controlador:** RealTek SoC HID (Interface 2).
- **Tipo de Reporte:** Feature Report de 21 bytes (`Report ID 0x11` + 20 bytes payload).
- **Ofuscación:** Todos los bytes del payload están invertidos con operación binaria XOR `0xFF`.
- **Estructura del Payload (20 bytes):**
  - `byte[0..3]`: Encabezado `[0x2B, 0x01, 0x06, 0x00]` (Comando `0x2B`).
  - `byte[4..8]`: `[100, 0x00, 0x03, 0x01, 0x00]` (Brillo 100, Velocidad 3, Modo Estático 1).
  - `byte[9..11]`: **Zona 1 (Anillo Exterior):** `[r_anillo, g_anillo, b_anillo]`.
  - `byte[12..14]`: **Zona 2 (Logo Central):** `[r_centro, g_centro, b_centro]`.
  - `byte[15..19]`: Relleno `[0x00, 0x00, 0x00, 0x00, 0x00]`.
- **Envío con XOR:**
  ```python
  raw = bytearray([0x11] + [x ^ 0xFF for x in payload])
  fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw)), raw)
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
