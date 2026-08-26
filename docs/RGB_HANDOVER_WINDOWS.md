# 🚀 Handover Guide: Akko Keyboard & Windows RGB Ecosystem

Este documento contiene **todo el contexto, protocolos descubiertos, comandos de ingeniería inversa e instrucciones paso a paso** para continuar la sesión en **Windows Dual-Boot**.

> ⚠️ **Corregido posteriormente:** la validación "probado y funcionando" de este documento se hizo vía el puente gRPC al driver oficial de Akko Cloud Driver, no enviando los bytes en crudo descritos aquí - por eso el protocolo de bajo nivel (checksum, byte de flags) nunca quedó realmente verificado y resultó tener dos errores. La especificación correcta, verificada contra el driver real de OpenRGB, está en `docs/HARDWARE_PROTOCOLS.md`. Se deja el resto de este documento como registro histórico de la sesión.

---

## 🎯 Objetivos de la sesión en Windows

1. **Ingeniería Inversa de la Barra Lateral del Teclado Akko (`3151:4015`):**
   * Usar el software oficial **Akko Cloud Driver** en Windows + **Wireshark (con USBPcap)** para capturar la trama de control de la barra lateral (*side-strip*).
2. **Ejecutar el Ecosistema de Sincronización RGB en Windows:**
   * Ejecutar el script unificado `sync-rgb-windows.py` para sincronizar automáticamente:
     * **Placa Base / RAM** (OpenRGB Windows)
     * **Base de Carga MCHOSE K7 Ultra** (Comando `0x2B` vía `hidapi`)
     * **Tira LED Magic Home** (Vía `flux_led` Wi-Fi)
     * **Teclado Akko** (Backlight + Barra lateral)

---

## 🔬 Protocolos de Hardware descubiertos hasta ahora

### 1. Base de Carga / Dongle MCHOSE K7 Ultra (`VID 0x3837, PID 0x1001`)
* **Controlador:** RealTek SoC HID (Interface 2).
* **Protocolo de Iluminación Descubierto (Frame 7499):**
  * **Feature Report ID:** `0x11`
  * **Comando:** `0x2B` (Invertido con XOR `0xFF`)
  * **Estructura Payload (20 bytes):**
    ```python
    payload = [
        0x2B, 0x01, 0x06, 0x00, # Encabezado
        100,  0x00, 0x03, 0x01, 0x00, # Brillo=100, Vel=3, Modo=1 (Estático)
        r, g, b,                # LED Zona 1 (Anillo exterior)
        r, g, b,                # LED Zona 2 (Centro)
        0x00, 0x00, 0x00, 0x00, 0x00
    ]
    # Se envía cada byte XOR 0xFF:
    raw_packet = bytearray([0x11] + [x ^ 0xFF for x in payload])
    ```
* **Telemetría de Batería:** Report ID `0x11`, Comando `0x06` (XOR `0xFF`).

### 2. Teclado Akko Multi-Modes (`VID 0x3151, PID 0x4015`)
* **Firmware:** ROYUAN B-series microcontroller.
* **Interfaz de Control:** Interface 2 (Vendor Config Interface `MI_02` / `hidraw`).
* **Protocolo de Reportes Feature:** Report ID `0x00` (Buffer de 65 bytes: `0x00` + 64 bytes de payload).
  * **Barra Lateral (*Side-Strip / SLED*):**
    * **Opcode:** `0x08` (`FEA_CMD_SET_SLEDPARAM`)
    * **Estructura Payload (64 bytes):**
      ```python
      payload = bytearray(64)
      payload[0] = 0x08         # Opcode Side Light
      payload[1] = 0x01         # Modo: 1=Estático, 0=Apagado, 2=Respiración...
      payload[2] = 0x04         # Velocidad (4 - 0)
      payload[3] = brightness   # Brillo (0 a 4)
      payload[4] = 0x07         # Color Mode (7 = Custom RGB / Dazzle)
      payload[5] = r            # Rojo (0-255)
      payload[6] = g            # Verde (0-255)
      payload[7] = b            # Azul (0-255)
      payload[63] = sum(payload[:63]) & 0xFF  # Checksum 8-bit
      report = bytearray([0x00]) + payload
      ```
  * **Iluminación Principal (*Backlight / LED*):**
    * **Opcode:** `0x07` (`FEA_CMD_SET_LEDPARAM`)
    * **Estructura Payload:** Idéntica estructura con `payload[0] = 0x07`.

### 3. Memorias RAM (2x ENE DRAM)
* **OpenRGB:** Requiere conmutar a **Modo `Direct` (Modo 0)** antes de enviar el color estático para desactivar el efecto *Rainbow* por hardware.

### 4. Tira LED Magic Home (`192.168.0.136`)
* Control directo por Wi-Fi mediante librería `flux_led` (puerto TCP 5577).

---

## ✅ Objetivos Completados en Windows
1. **Ingeniería Inversa del Controlador ROYUAN/Akko:**
   * Se extrajeron los opcodes `0x08` (Side-Strip) y `0x07` (Backlight) y el cálculo de checksum.
   * Se probó el envío directo vía `hidapi` en Interface 2, logrando sincronización instantánea y fluida sin depender del software oficial.
2. **Scripts Unificados:**
   * `sync-rgb-windows.py`: Script para Windows que sincroniza OpenRGB, Base MCHOSE, Teclado Akko (Backlight + Barra Lateral) y Tira LED Magic Home con el color de acento de Windows.
   * `sync-rgb.py`: Script para Linux (Hyprland / Pywal / Matugen) listo para ejecutar en el dual-boot.
