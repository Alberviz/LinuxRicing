---
title: Diagnóstico y Handoff Bluetooth - MCHOSE K7 Ultra
date: 2026-09-02
tags:
  - hardware
  - bluetooth
  - linux
  - hyprland
  - debugging
status: resuelto
---

# 🖱️ Diagnóstico de Conexión Bluetooth — MCHOSE K7 Ultra

> [!success] RESUELTO (2026-09-02, Claude)
> La causa era **`ControllerMode = dual`** en `/etc/bluetooth/main.conf`. Con el
> controlador Intel en modo dual, el firmware Telink del ratón no podía completar
> el emparejamiento SMP: el descubrimiento GATT iba bien (no exige cifrado) pero
> las lecturas de las características HID (que sí lo exigen) devolvían **ATT 0x0E
> "unlikely error"** en vez de `0x05/0x0F`, así que BlueZ nunca escalaba a
> pairing, el enlace quedaba sin cifrar y el ratón lo abortaba regenerando su
> dirección estática aleatoria.
> **Arreglo:** `ControllerMode = le` (LE puro) + reiniciar `bluetooth` + limpiar
> fantasmas. Ratón ahora `Bonded: yes` / `Connected: yes` con 2 LTK en el kernel
> y nodos uhid creados. Detalle completo en `Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md` (2026-09-02).

> [!warning]- Estado del Problema (histórico)
> El ratón **MCHOSE K7 Ultra** (modo Bluetooth LE / HOGP) no completa la negociación de emparejamiento. El ordenador marca la conexión como establecida, pero el ratón sigue parpadeando, aborta la conexión a los pocos segundos, cambia de dirección MAC aleatoria y reaparece como un nuevo dispositivo ("dispositivo fantasma").

---

## 🖥️ 1. Entorno del Sistema

- **Distribución / OS**: CachyOS / Arch Linux (x86_64, Linux Kernel 6.x)
- **Entorno Gráfico**: Hyprland (Wayland)
- **Stack Bluetooth**: BlueZ 5.7x + `systemd` (`bluetooth.service` activo)
- **Controlador Bluetooth**: Intel Bluetooth HCI (`btusb`, `btintel`, firmware `ibt-1040-4150.sfi` cargado)
  - MAC del controlador: `40:D1:33:7C:0F:8C`
- **Gestor / Agente instalado**: `blueman` (`blueman-applet` añadido a autostart en `execs.lua`)
- **Módulos del Kernel verificados**: `bluetooth`, `btusb`, `btintel`, `uhid`, `rfkill` (todos cargados).

---

## 🔍 2. Síntoma Exacto y Comportamiento del Hardware

1. El ratón se pone en modo emparejamiento Bluetooth (LED parpadeando rápido).
2. BlueZ / Blueman detecta el ratón bajo un identificador `MCHOSE K7 Ultra` con una dirección BLE aleatoria (ejemplos: `EC:98:EC:F2:38:A7`, `EA:28:22:9C:4D:6E`, `E4:CE:1D:3C:06:EA`).
3. Al pulsar **Conectar**:
   - BlueZ establece el enlace BLE inicial (`Connected: yes`).
   - Se leen e inspeccionan los servicios GATT con éxito:
     - `00001800` (Generic Access)
     - `00001801` (Generic Attribute)
     - `0000180a` (Device Information)
     - `0000180f` (Battery Service)
     - `00001812` (Human Interface Device / HID over GATT)
4. **El punto de fallo**:
   - El LED del ratón **nunca deja de parpadear**.
   - A los 2–3 segundos, el firmware del ratón finaliza el enlace unilateralmente (no recibe la respuesta SMP/clave esperada o rechaza los parámetros de conexión).
   - El ratón genera una **nueva dirección MAC aleatoria (BLE RPA)** y vuelve a emitir en modo búsqueda.
   - En Blueman / `bluetoothctl`, la entrada anterior queda como un "fantasma" desconectado o en bucle `In Progress`, y aparece una entrada nueva abajo con la nueva MAC.

---

## ⚙️ 3. Configuraciones y Pruebas ya Realizadas

### `/etc/bluetooth/main.conf`
```ini
[General]
JustWorksRepairing = always
FastConnectable = true
Privacy = off
ControllerMode = dual
Experimental = true
AlwaysPairable = true
PairableTimeout = 0
AutoEnable = true
```

### `/etc/bluetooth/input.conf`
```ini
[General]
IdleTimeout = 0
UserspaceHID = true
ClassicBondedOnly = false
LEAutoSecurity = true
```

### Otras acciones ejecutadas:
- Agente D-Bus nativo de emparejamiento automático (`NoInputNoOutput` / `KeyboardDisplay`) ejecutado en Python con `GLib.MainLoop`.
- Instalación de `blueman` y ejecución de `blueman-applet`.
- Limpieza completa de `/var/lib/bluetooth/` y reseteo del adaptador con `rfkill` y `systemctl restart bluetooth`.
- `bluetoothctl pair` falla directamente con `org.bluez.Error.AuthenticationFailed` o `Too small pair device response` (lo habitual en ratones BLE HOGP sin soporte SMP clásico).
- `bluetoothctl connect` conecta inicialmente pero aborta por timeout del periférico (`le-connection-abort-by-local`).

---

## 📋 4. Prompt para Claude (Listo para Copiar)

```markdown
Tengo un problema persistente conectando mi ratón gaming **MCHOSE K7 Ultra** por Bluetooth en **Arch Linux / CachyOS con Hyprland**.

### Resumen del problema:
Cuando intento conectar el ratón por Bluetooth LE:
1. El sistema (BlueZ / Blueman) detecta el ratón (`MCHOSE K7 Ultra`, UUID HID `00001812-0000-1000-8000-00805f9b34fb`).
2. Al conectar, BlueZ marca `Connected: yes` y resuelve los atributos GATT (`Battery Service`, `HID`, etc.).
3. Sin embargo, el ratón **sigue con el LED parpadeando rápido**, no acepta el enlace, y a los 2-3 segundos el ratón se desconecta por su cuenta.
4. Al desconectarse, el ratón genera una **nueva dirección MAC aleatoria (BLE RPA)** y vuelve a aparecer como un dispositivo nuevo en la lista de escaneo, dejando el anterior como "fantasma".

### Entorno:
- **SO**: Arch Linux / CachyOS (Kernel 6.x)
- **Compositor**: Hyprland (Wayland)
- **Stack**: BlueZ 5.7x + `blueman` (con `blueman-applet` activo)
- **Controlador BT**: Intel HCI (`btintel` / `btusb`, firmware `ibt-1040-4150.sfi` cargado)
- **Módulos**: `bluetooth`, `btusb`, `btintel`, `uhid`, `rfkill` cargados y funcionales.

### Ya se ha probado sin éxito:
1. En `/etc/bluetooth/main.conf`:
   `JustWorksRepairing = always`, `FastConnectable = true`, `Privacy = off`, `ControllerMode = dual`, `Experimental = true`, `AlwaysPairable = true`.
2. En `/etc/bluetooth/input.conf`:
   `UserspaceHID = true`, `ClassicBondedOnly = false`, `LEAutoSecurity = true`.
3. Se han probado agentes D-Bus con `NoInputNoOutput`, `DisplayYesNo` y `KeyboardDisplay`.
4. El comando `pair` da `AuthenticationFailed` / `Too small pair device response`. El comando `connect` conecta brevemente pero el ratón aborta la conexión.

### ¿Qué necesito?
Analiza a nivel de protocolo BLE / BlueZ / kernel Linux por qué el firmware del ratón MCHOSE (chipset Telink/Nordic) rechaza la negociación tras la resolución GATT:
1. ¿Podría ser un conflicto con los parámetros de conexión L2CAP del kernel (`conn_min_interval`, `conn_max_interval`, `conn_latency`, `supervision_timeout` en `/sys/kernel/debug/bluetooth/hci0/`)?
2. ¿Cómo capturar y diagnosticar exactamente con `btmon` la causa del descarte (`LL_REJECT_IND`, `SMP Pairing Failed`, o fallo de cifrado LTK)?
3. ¿Qué configuración específica de BlueZ, kernel quirk o script de conexión forzada permite consolidar la vinculación HOGP sin que el ratón aborte?
```
