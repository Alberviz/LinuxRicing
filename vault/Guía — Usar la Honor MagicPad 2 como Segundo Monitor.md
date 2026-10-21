# Guía: Usar la Honor MagicPad 2 como Segundo Monitor en Linux (Hyprland + Sunshine)

Esta guía detalla la configuración y el flujo de uso para convertir la **Honor MagicPad 2** en un segundo monitor ultra-fluido (144 Hz, panel OLED 3K, aceleración por hardware NVENC con RTX 4050).

---

## 🛠️ Componentes instalados y arquitectura

1. **Hyprland Headless Monitor (`Tablet`):**
   - Configurado en `configs/hypr/config/monitors.lua` con modo `3000x1920@144`, posición `auto-right` y escala `1.6`.
   - Se crea y destruye dinámicamente sin reiniciar el entorno gráfico.

2. **Sunshine (`sunshine`):**
   - Servidor de streaming para Moonlight con soporte NVENC (HEVC / AV1 / H.264).
   - Configurado en `~/.config/sunshine/sunshine.conf` para capturar la salida `output_name = Tablet`.
   - Gestión mediante servicio de usuario systemd: `app-dev.lizardbyte.app.Sunshine.service`.

3. **Script de Control (`caelestia-tablet-display`):**
   - Ubicación: `~/.local/bin/caelestia-tablet-display` (fuente en `widgets/caelestia-tablet-display`).
   - Comandos:
     - `caelestia-tablet-display on`: Crea la pantalla virtual y levanta Sunshine.
     - `caelestia-tablet-display off`: Elimina la pantalla y apaga Sunshine.
     - `caelestia-tablet-display toggle`: Alterna el estado.
     - `caelestia-tablet-display status`: Reporta `active` o `inactive`.
     - `caelestia-tablet-display pair <PIN>`: Empareja un cliente Moonlight introduciendo su PIN.

4. **Integración en Caelestia Shell:**
   - **Quick Toggles:** Botón con icono `tablet_android` en la barra de utilidades.
   - **Nexus Panel:** Interruptor en la página de utilidades (`UtilitiesPanel.qml`).
   - **Servicio QML:** `qs.services.TabletDisplay` monitoriza en tiempo real las pantallas activas y el estado IPC.

---

## 🚀 Pasos para empezar (Para Alberto)

### 1. En la Tablet (Honor MagicPad 2)
1. Instala **Moonlight Game Streaming** desde Google Play Store.
2. Abre los Ajustes de Moonlight (engranaje):
   - **Resolución:** 3000×1920 (o Nativa).
   - **FPS:** 120 o 144 fps.
   - **Bitrate:** 40 - 60 Mbps.

### 2. En el PC
1. Activa el monitor virtual pulsando el botón de la tablet en los **Quick Toggles** de Caelestia Shell (o ejecutando `caelestia-tablet-display on`).

### 3. Emparejamiento (Solo una vez)
1. En Moonlight (tablet), pulsa sobre tu equipo (`LinuxBeast` / `192.168.1.86`).
2. Aparecerá un código PIN de 4 cifras (ej. `1234`).
3. En la terminal de tu PC ejecuta:
   ```bash
   caelestia-tablet-display pair 1234
   ```
   *(O ve a `https://localhost:47990` con user/pass `alberto`/`alberto` y mételo en la pestaña PIN).*

### 4. Conexión
Toca sobre **"Tablet Display (Honor MagicPad 2)"** en Moonlight. ¡Disfruta de tu segundo monitor a 144 Hz!
