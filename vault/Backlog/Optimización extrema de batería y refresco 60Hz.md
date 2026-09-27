---
fileClass: Backlog
tipo: tarea
estado: hecha
prioridad: 1
area: caelestia
origen: Alberto
esfuerzo: M
creado: 2026-09-27
tags:
  - backlog
  - bateria
  - powersave
---

# Optimización extrema de batería y refresco de pantalla a 60Hz

Ampliación integral del modo de ahorro de energía cuando el portátil está desconectado (`UPower.onBattery` o perfil `power-saver`):

## Acciones implementadas y verificadas:
1. **Tasa de refresco dinámica (144Hz ↔ 60Hz):**
   - Conmutación automática de la pantalla interna (`eDP-2`) a **60.00 Hz** en batería y restauración a **144.00 Hz** en corriente AC mediante `hyprctl eval "hl.monitor({ output = 'eDP-2', mode = '1920x1080@60.00Hz' })"`.
2. **Intel Turbo Boost off en batería:**
   - Desactivación de picos de 55W+ en la CPU Intel Alder Lake-HX con `intel_pstate/no_turbo = 1` y restauración con corriente.
3. **WiFi Power Save:**
   - Activación de ahorro de energía 802.11 (`iw dev wlan0 set power_save on`) en batería.
4. **Suspensión de dGPU NVIDIA (RTD3):**
   - Configurado runtime PM en `auto`, verificado estado `suspended` (0 W).
5. **Apagado de Bluetooth:**
   - Apagado automático de la radio Bluetooth al entrar en batería (`bluetoothctl power off`), manteniéndola reactivable manualmente en cualquier momento desde el panel.
6. **Desactivación de autoinicio de correo:**
   - Eliminado `Mailspring.desktop` de `~/.config/autostart/` y enlazado simbólicamente a `/dev/null` para evitar que vuelva a auto-iniciarse.
7. **Parada de servicios cosméticos y servidores de fondo en batería:**
   - Parada automática de `argb-wave.service`, `laura.service`, `minecraft-telegram-bot.service` y `openrgb.service`.
   - Apagado de tiras LED y retroiluminación de teclado (`platform::kbd_backlight`).
8. **Orquestación en `PowerSaving.qml`:**
   - Creado `/usr/local/bin/caelestia-power-root` y `widgets/caelestia-power-tweaks` (`~/.local/bin/caelestia-power-tweaks`), integrados en `PowerSaving.qml` reactivo al estado de corriente.
   - Sincronizado a `~/.config/quickshell/caelestia/` y shell reiniciado limpiamente.
