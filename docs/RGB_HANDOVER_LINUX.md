# 🚀 RGB Handover: Retorno a Linux (Dual-Boot)

> **Fecha:** 26 de Agosto de 2026  
> **Objetivo:** Sincronización RGB unificada de todo el setup en Linux (Hyprland / Matugen / Pywal / OpenRGB).

> ⚠️ **Corregido posteriormente:** el byte `a[4]` y la posición/fórmula del checksum documentados más abajo eran incorrectos (nunca se habían verificado visualmente en hardware, solo vía el driver oficial de Windows). La especificación correcta, verificada contra el driver real de OpenRGB, está en `docs/HARDWARE_PROTOCOLS.md`. Se deja el resto de este documento como registro histórico de la sesión.

---

## 📋 Resumen Ejecutivo de la Sesión de Windows

En esta sesión en Windows logramos descifrar por completo los protocolos propietarios que faltaban, corregir los conflictos de bus SMBus y dejar el script [sync-rgb.py](file:///C:/Users/Alberviz/LinuxRicing/sync-rgb.py) 100% preparado para Linux.

### 🔑 Logros Clave:
1. **Ingeniería Inversa del Teclado Akko 5075B Plus (`3151:4015`):**
   * Desempaquetamos el código fuente de *Akko Cloud Driver* (`iot_driver_v200.exe`).
   * Descubrimos el opcode del **Side-Strip (Barra Lateral)**: `0x08` (`FEA_CMD_SET_SLEDPARAM`).
   * Descubrimos el opcode del **Backlight (Teclas)**: `0x07` (`FEA_CMD_SET_LEDPARAM`).
   * Probado y verificado físicamente en hardware tanto en color verde puro como con la paleta del fondo.
2. **Identificación de Hardware RAM y Placa Base:**
   * **RAMs:** 2x `A-DATA Technology DDR4 3200 (XPG Spectrix)` (5 LEDs por módulo, chip `ENE DRAM`).
   * **Placa Base:** `ASUS TUF GAMING B560M-PLUS` (Conectores ARGB `Aura Addressable 1 & 2` para los ventiladores de la caja).
3. **Lección importante sobre efectos animados en bus SMBus (I2C):**
   * **⚠️ NUNCA ejecutar bucles continuos por software a altos FPS (20-30 FPS) sobre las RAMs:** El bus SMBus/I2C de la placa base es de baja frecuencia (~100 kHz). Enviar actualizaciones continuas por software satura el bus I2C y provoca **parpadeos agresivos e inestabilidad** en las memorias.
   * **Solución idónea:** Aplicación **estática limpia de un solo disparo (`One-Shot`)** al cambiar de fondo de pantalla o tema con Pywal/Matugen.

---

## 🛠️ Especificación de Protocolos y Dispositivos

### 1. Teclado Akko 5075B Plus (`VID 0x3151, PID 0x4015`)
* **Interfaz:** Interfaz `2` (`/dev/hidraw*` en Linux / `MI_02` en Windows).
* **Tamaño del Reporte:** 65 bytes (Report ID `0x00` + 64 bytes de payload).
* **Estructura del Payload:**
  * `a[0]`: Opcode (`0x08` para Barra Lateral / `0x07` para Iluminación de Teclas).
  * `a[1]`: `0x01` (Modo estático encendido).
  * `a[2]`: `0x04` (Velocidad).
  * `a[3]`: `0x04` (Brillo al 100%).
  * `a[4]`: Modo de Color (`0x07` = Color personalizado / Custom RGB; `0x08` = Preset Rosa fijo, ignora el RGB enviado).
  * `a[5]`: Rojo (`0-255`).
  * `a[6]`: Verde (`0-255`).
  * `a[7]`: Azul (`0-255`).
  * `a[63]`: Checksum de 8 bits = `sum(a[0:63]) & 0xFF`.

```python
# Ejemplo de envío para Akko en Linux
dev.send_feature_report(bytearray([0x00]) + sled_payload)  # Barra lateral
time.sleep(0.02)
dev.send_feature_report(bytearray([0x00]) + led_payload)   # Teclas
```

---

### 2. Base de Carga / Dongle MCHOSE K7 Ultra (`VID 0x3837, PID 0x1001`)
* **Interfaz:** Interfaz `2` (`/dev/hidraw*`).
* **Report ID:** `0x11` (Feature Report).
* **Protocolo:** Comando `0x2B` con ofuscación XOR `0xFF`.
* **Estructura del Payload:**
```python
payload = [
    0x2B, 0x01, 0x06, 0x00,
    100, 0x00, 0x03, 0x01, 0x00,
    r_anillo, g_anillo, b_anillo,  # Zona 1: Anillo exterior
    r_centro, g_centro, b_centro,  # Zona 2: Logo central
    0x00, 0x00, 0x00, 0x00, 0x00
]
raw = bytearray([0x11] + [x ^ 0xFF for x in payload])
dev.send_feature_report(raw)
```

---

### 3. Memorias RAM (2x ENE DRAM) y Placa Asus (OpenRGB)
* **Conexión:** Servidor OpenRGB SDK en `localhost:6742`.
* **RAMs:** Conmutar a **Modo `Direct` (Modo 0)** antes de aplicar el color estático.
* **Ventiladores de la Torre:** Redimensionar automáticamente las zonas `Aura Addressable 1` y `Aura Addressable 2` a 30 LEDs si vienen en 0 LEDs:
```python
for z in dev.zones:
    if "Addressable" in z.name and len(z.leds) == 0:
        z.resize(30)
```

---

### 4. Tira LED Magic Home Wi-Fi
* **IP:** `192.168.0.136` (Puerto `5577` TCP via librería `flux_led`).

---

## 💻 Estado de los Archivos en el Repositorio

1. **[sync-rgb.py](file:///C:/Users/Alberviz/LinuxRicing/sync-rgb.py):**
   * Script unificado principal para Linux.
   * Lee la caché de colores de `~/.cache/wal/colors.json` (o los argumentos `R G B` pasados por terminal).
   * Envía en paralelo (`threading`) las órdenes a OpenRGB, MCHOSE Base, Akko Keyboard y Magic Home.
   * **Modo de ejecución estático y limpio de un solo disparo.**
2. **[sync-rgb-windows.py](file:///C:/Users/Alberviz/LinuxRicing/sync-rgb-windows.py):**
   * Versión operativa para Windows (probada y funcionando al 100%).

---

## 🏁 Pasos al iniciar la sesión en Linux:

1. **Asegurar permisos udev de USB HID (si hiciera falta):**
   ```bash
   sudo chmod 666 /dev/hidraw*
   ```
2. **Lanzar OpenRGB en segundo plano con el SDK Server activo:**
   ```bash
   openrgb --server --minimized &
   ```
3. **Ejecutar el sincronizador:**
   ```bash
   python3 ~/LinuxRicing/sync-rgb.py
   ```
   *(O vincularlo al hook de cambio de wallpaper en Hyprland / Matugen / Waybar).*
