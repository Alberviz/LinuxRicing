# MCHOSE Peripherals Linux Integration (Headset V9 Pro & Mouse K7 Ultra)

> **Nota para Antigravity / Asistente IA en la máquina Linux:**
> Este documento contiene el contexto completo de ingeniería inversa por USB/HID capturado en Windows con USBPcap/Wireshark. Puedes utilizar esta información para instalar las reglas `udev`, configurar el script de lectura de batería y crear módulos para Waybar, Polybar, Rofi o scripts de inicio.

---

## 1. Dispositivos Soportados y Protocolos Descifrados

### A. Auriculares MCHOSE V9 Pro
- **Vendor ID (VID):** `0x291D` (10525)
- **Product ID (PID):** `0x385D` (14429)
- **Chipset:** C-Media CM2025 DSP (Inalámbrico 2.4 GHz)
- **Interfaz HID:** `UsagePage: 0xFF90` (Colección 5)
- **Protocolo de Lectura:**
  - **Petición (Output Report / Write - 64 bytes):**
    `[0x55, 0x65, 0x01, 0x00, 0x00, ...]` (64 bytes)
  - **Respuesta (Input Report / Read - 64 bytes):**
    `[0x55, 0x65, BATTERY_BYTE, STATUS_BYTE, ...]`
    - `Byte 2 (BATTERY_BYTE)`: Porcentaje decimal directo (`0x46` = 70%).
    - `Byte 3 (STATUS_BYTE)`: Estado de energía:
      - `1`: Cargando (Cable / Base)
      - `2`: Descargando (Uso inalámbrico)
      - `0`: Reposo / Desconectado

---

### B. Ratón MCHOSE K7 Ultra
- **Vendor ID (VID):** `0x3837` (14391)
- **Product ID (PID):** `0x1001` (4097)
- **Chipset:** RealTek Wireless Gaming Mouse
- **Interfaz HID:** Interface 2, `UsagePage: 0xFF01` (Colección 2)
- **Protocolo de Lectura:**
  - **Cifrado/Ofuscación:** Todos los paquetes de datos están invertidos con máscara **XOR `0xFF`**.
  - **Secuencia de inicialización (Feature Reports):**
    1. Feature Report `0x11`: `[0x11, 0xF9] + [0xFF] * 19`
    2. Feature Report `0x12`: `[0x12, 0x98] + [0xFF] * 63`
    3. Feature Report `0x12`: `[0x12, 0x97] + [0xFF] * 63`
    4. Feature Report `0x11`: `[0x11, 0xFB, 0x55] + [0xFF] * 18`
  - **Respuesta de telemetría (Report ID `0x13`):**
    - `Decoded = [data[0], data[1]^0xFF, data[2]^0xFF, ...]`
    - `Decoded[1]` == `0xE2` (Encabezado de telemetría)
    - `Decoded[3]` == Estado de carga (`1`: Descargando, `2`: Cargando, `0`: Reposo)
    - `Decoded[5]` == **Porcentaje de batería exacto** (0-100 decimal)
    - `Decoded[9..16]` == Nombre de producto ASCII (`"K7 Ultra"`)

---

## 2. Instalación en Arch Linux / Ubuntu / Debian

### Paso 1: Instalar dependencias
```bash
# Arch Linux:
sudo pacman -S python python-hidapi

# Ubuntu / Debian:
sudo apt update && sudo apt install python3 python3-hidapi
# O en un virtualenv / pip:
pip install hidapi
```

### Paso 2: Configurar permisos udev (Sin necesidad de sudo)
Crea el archivo `/etc/udev/rules.d/99-mchose.rules`:

```bash
sudo tee /etc/udev/rules.d/99-mchose.rules << 'EOF'
# MCHOSE V9 Pro (Auriculares)
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="291d", ATTRS{idProduct}=="385d", MODE="0666"

# MCHOSE K7 Ultra (Ratón)
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3837", ATTRS{idProduct}=="1001", MODE="0666"
EOF
```

Recargar reglas:
```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

---

## 3. Uso del Script `mchose_battery.py`

Dar permisos de ejecución:
```bash
chmod +x mchose_battery.py
```

### Modos de ejecución:
1. **Modo consola / Humano:**
   ```bash
   ./mchose_battery.py
   ```
2. **Modo JSON completo:**
   ```bash
   ./mchose_battery.py --json
   ```
3. **Módulo para Waybar (Auriculares):**
   ```bash
   ./mchose_battery.py --waybar-headset
   ```
4. **Módulo para Waybar (Ratón):**
   ```bash
   ./mchose_battery.py --waybar-mouse
   ```

---

## 4. Configuración para Waybar (Hyprland / Sway)

En tu `~/.config/waybar/config.jsonc`:

```jsonc
"custom/mchose_headset": {
    "format": "{}",
    "return-type": "json",
    "interval": 30,
    "exec": "/home/TU_USUARIO/.local/bin/mchose_battery.py --waybar-headset"
},
"custom/mchose_mouse": {
    "format": "{}",
    "return-type": "json",
    "interval": 30,
    "exec": "/home/TU_USUARIO/.local/bin/mchose_battery.py --waybar-mouse"
}
```
