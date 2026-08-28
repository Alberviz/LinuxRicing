---
tags: [windows, hardware, rgb, bateria, mchose, akko, openrgb]
actualizado: 2026-08-29
---

# 💡 Windows · Estado del Hardware, Luces y Batería

Este documento resume el **estado real verificado en directo en Windows 11** de todos los dispositivos de hardware, periféricos, iluminación RGB y lectura de batería.

> [!NOTE]
> **Base Canónica de Hardware:** Las especificaciones detalladas de ingeniería inversa, opcodes y paquetes están consolidadas en el directorio [`hardware/`](file:///C:/Users/Alberviz/LinuxRicing/hardware).

---

## 📊 1. Resumen Ejecutivo del Estado del Hardware

| Dispositivo | Identificador (VID:PID) | Control de Iluminación RGB | Lectura de Batería | Estado en Windows |
|---|---|---|---|---|
| [**Ratón MCHOSE K7 Ultra / Base 8K**](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-k7-ultra) | `VID 0x3837, PID 0x1001` (Base 8K)<br>`VID 0x3837, PID 0x4150` (Cable USB) | ✅ **100% Funcional** (Feature Report `0x11`, Cmd `0x2B`) | ✅ **100% Funcional** (Report `0x11` Cmd `0x06` -> **89%**, `0x01` Cargando) | **OK** |
| [**Auriculares MCHOSE V9 Pro**](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-v9-pro) | `VID 0x291D, PID 0x385D` | N/A (Sin RGB direccionable) | ✅ **100% Funcional** (UsagePage `0xFFA0`, Cmd `0x55 0x65` -> **90%**, Descargando) | **OK** |
| [**Teclado Akko 5075B Plus**](file:///C:/Users/Alberviz/LinuxRicing/hardware/akko-5075b-plus) | `VID 0x3151, PID 0x4011` (2.4G)<br>`VID 0x3151, PID 0x4015` (USB) | ✅ **100% Funcional** (Feature Report `0x07`/`0x08` vía hidraw / gRPC) | ✅ **100% Funcional** (Opcode `0x83` -> **80%**, `0x01` Cargando USB) | **OK** |
| [**Placa Base ASUS TUF B560M-PLUS**](file:///C:/Users/Alberviz/LinuxRicing/hardware/asus-tuf-b560m) | OpenRGB SDK (`localhost:6742`) | ✅ **100% Funcional** (Aura Mainboard + Ventiladores ARGB) | N/A (Alimentación ATX) | **OK** |
| **Memorias RAM A-DATA Spectrix** | 2x ENE DRAM via OpenRGB | ✅ **100% Funcional** (Modo 0 `Direct`, sin parpadeo I2C) | N/A (Alimentación DIMM) | **OK** |
| [**Tira LED Magic Home**](file:///C:/Users/Alberviz/LinuxRicing/hardware/magic-home-strip) | Wi-Fi IP `192.168.0.136:5577` | ✅ **100% Funcional** (Socket TCP directo con `flux_led`) | N/A (Alimentación 12V) | **OK** |

---

## 🔋 2. Telemetría de Batería en Windows

En Windows se ha implementado el monitor [`rgb/mchose-battery-windows.py`](file:///C:/Users/Alberviz/LinuxRicing/rgb/mchose-battery-windows.py) que lee el estado de todos los periféricos mediante `hidapi`:

```bash
# Salida en tabla humana
python rgb/mchose-battery-windows.py

# Salida en JSON para barras de estado y widgets
python rgb/mchose-battery-windows.py --json
```

### Detalle de Protocolos de Batería:

### A. Auriculares MCHOSE V9 Pro (`0x291D:0x385D`)
- **Canal de Comunicación:** Interfaz 0, Usage Page `65424` (`0xFFA0`).
- **Comando de Consulta:** Paquete de 64 bytes que comienza por `[0x55, 0x65, 0x01] + [0x00]*61`.
- **Respuesta:**
  - `byte[0..1]`: `0x55 0x65` (Cabecera de confirmación).
  - `byte[2]`: Nivel de batería exacto en porcentaje (`0 - 100%`).
  - `byte[3]`: Código de estado (`0` o `3` = Cargando, `2` = Descargando / En uso inalámbrico).
- **Lectura en directo:** **90%** (Descargando). Ver detalles en [`hardware/mchose-v9-pro/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-v9-pro/PROTOCOL.md).

### B. Ratón MCHOSE K7 Ultra (`0x3837:0x1001 / 0x4150`)
- **Canal de Comunicación:** Interfaz 2 (`MI_02`), Usage Page `65281` (`0xFF01` / `Col02`).
- **Identificadores:**
  - **`PID 0x1001`**: Modo Inalámbrico (Base 8K). Emite telemetría en pulsos periódicos de **3.65 segundos** continuos.
  - **`PID 0x4150`**: Modo Cable Directo USB. Respuesta instantánea continua con reportes push `0x13`.
- **Comando de Consulta:** Feature Report de 21 bytes con Report ID `0x11` y comando `0x06` invertido con `XOR 0xFF`:
  ```python
  req = bytearray([0x11, 0x06 ^ 0xFF] + [0xFF] * 19)
  dev.send_feature_report(req)
  ```
- **Respuesta (Feature Report `0x11`):**
  - Se obtienen 64 bytes mediante `dev.get_feature_report(0x11, 64)`.
  - Se aplica `XOR 0xFF` a partir del segundo byte (`byte ^ 0xFF`).
  - `dec[11]`: Nivel de batería (**`89%`**).
  - `dec[12]`: Estado de carga (**`1` = `⚡ Cargando`** en la base o por cable USB, **`0` = Descargando**).
- **Lectura en directo:** **89%** (⚡ Cargando por USB). Ver [`hardware/mchose-k7-ultra/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-k7-ultra/PROTOCOL.md).

### C. Teclado Akko 5075B Plus (`0x3151:0x4011 / 0x4015`)
- En modo **2.4G inalámbrico** se identifica como **`PID 0x4011`** (se consulta mediante gRPC con `dangledevtype=1` y Opcode `0x83` o Feature Report directo).
- En modo **cable USB directo** se identifica como **`PID 0x4015`** (se consulta mediante Feature Report directo con Opcode `0x83`).
- **Respuesta de Batería (Opcode `0x83`):**
  - `Byte[1]`: Batería (**`80%`**).
  - `Byte[2] / Byte[3]`: Estado de alimentación (**`0x01` = `⚡ Cargando activamente por USB`**).
- **Lectura en directo:** **80%** (⚡ Cargando por USB). Ver [`hardware/akko-5075b-plus/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/akko-5075b-plus/PROTOCOL.md).

---

## 🌈 3. Control de Iluminación RGB en Windows

La sincronización se realiza mediante [`rgb/sync-rgb-windows.py`](file:///C:/Users/Alberviz/LinuxRicing/rgb/sync-rgb-windows.py), el cual procesa todos los dispositivos en hilos concurrentes:

### A. Base MCHOSE K7 Ultra (Anillo LED)
- **Report ID:** `0x11`
- **Comando:** `0x2B` (Invertido con XOR `0xFF`)
- Ver estructura canónica en [`hardware/mchose-k7-ultra/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-k7-ultra/PROTOCOL.md).

### B. Teclado Akko 5075B Plus (Teclas + Lightstrip Lateral Reactivo)
- **Report ID:** `0x00` (Buffer de 65 bytes: `0x00` + 64 bytes).
- **Zonas y Reglas de Iluminación:**
  - **1. Backlight (Teclas) - Opcode `0x07`:**
    - Siempre sincronizado con el color primario del tema (Material You) o color fijo seleccionado.
    - Modo: `0x01` (Estático), Velocidad: `0x04`, Brillo: `0x04`, Flags: `0x08`.
  - **2. Lightstrip Lateral Derecho (Side-Strip) - Opcode `0x08`:**
    - *Estado Normal / Reposo:* Color del sistema sincronizado (`mode = 0x01`, `flags = 0x08`).
    - *Estado Batería Baja (≤ 15%):* Respiración (*Breathing*) en **Rojo puro** (`mode = 0x02`, `flags = 0x08`, `RGB: 255, 0, 0`).
    - *Estado En Carga (al enchufar el teclado):* Flujo continuo (*Steady Stream* `0x05` / efecto ARGB) con **gradiente progresivo de color** según porcentaje de batería actual.
- **Soporte Dual:** Envío directo vía `hidapi` (interfaz 2 `:1.2`) con respaldo vía gRPC (`127.0.0.1:3814`) si el Akko Cloud Driver está en ejecución. Ver [`hardware/akko-5075b-plus/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/akko-5075b-plus/PROTOCOL.md).

### C. Placa Base ASUS TUF y RAM A-DATA Spectrix
- Se conecta al servidor local de OpenRGB en `localhost:6742`.
- Modo `Direct` (Modo 0) para evitar reinicio a ciclo *Rainbow*.

### D. Tira LED Magic Home
- Control por Wi-Fi mediante conexión TCP en puerto `5577` (`flux_led`).

---

## 🧪 4. Registro de Verificación en Directo

Ejecución de prueba realizada en la máquina:

```text
========================================================
--- Pure Wallpaper Colors (Red / Magenta / Purple / Rose) ---
   * Color 1 (Magenta):    (208, 0, 255)
   * Color 2 (Purple):     (126, 0, 255)
   * Color 3 (Rose Pink):  (255, 0, 184)
   * Color 4 (Crimson):    (255, 0, 37)
========================================================
[MCHOSE Base] Synced Ring: (255, 0, 37), Center: (208, 0, 255)
[OpenRGB] Synced RAM (Solid (208, 0, 255) & (126, 0, 255)) and Fans ((208, 0, 255))
[Akko Keyboard (HID 2.4G Wireless)] Synced Backlight: (208, 0, 255), Side-Strip: (255, 0, 184)
[MagicHome] Synced Room Ambient: (126, 0, 255)
```
