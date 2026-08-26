# 🔮 ROADMAP DE INNOVACIONES Y FUTURAS MEJORAS (Alberviz Rice)

Este documento recoge ideas avanzadas, arquitecturas y propuestas para continuar expandiendo el rice de Hyprland + Caelestia en el futuro.

---

## 🌟 1. MODO AMBILIGHT / SCREEN-MIRRORING PARA LA TIRA LED (Magic Home)
- **Concepto**: Proyectar la iluminación del monitor hacia la pared en tiempo real al jugar o ver películas/series.
- **Implementación**:
  - Un daemon en Python / C++ usando `pipewire` o `grim` con captura a baja resolución (16x9 píxeles) del borde superior de la pantalla.
  - Envío de color promediado a través de socket TCP directo a la IP de la tira Magic Home cada 100ms.
  - Activación mediante toggle en el widget `DesktopLedStrip` o atajo `SUPER + ALT + A`.

---

## 🎵 2. OVERLAY DE LETRAS EN TIEMPO REAL (Synced Lyrics)
- **Concepto**: Mostrar las letras de la canción actual sincronizadas línea a línea sobre el visualizador orbital en el escritorio.
- **Implementación**:
  - Integrar backend con `sptlrx` o la API de letras de Spotify / LRCLIB.
  - Subrayado dinámico de la estrofa actual en Material You `m3primary`.

---

## 💻 3. TOUCHPAD GESTURES & PERFILES DE BATERÍA PARA EL PORTÁTIL
- **Concepto**: Adaptación inteligente de rendimiento cuando el instalador detecte un portátil:
  - **Hyprland Gestures**: Deslizar 3 dedos horizontalmente para cambiar de espacio de trabajo, 3 dedos hacia arriba para abrir el launcher de Caelestia.
  - **Ahorro de Batería**: Integración con `power-profiles-daemon` o `auto-cpufreq` para reducir la tasa de refresco a 60Hz y atenuar widgets en modo batería.

---

## 🎮 4. OVERLAY HUD PARA GAMING (MangoHud / Gamescope Theme Sync)
- **Concepto**: Que el HUD de monitorización en juegos (MangoHud) use exactamente los mismos colores de Material You del fondo de pantalla activo.
- **Implementación**:
  - Inyectar variables de color en `~/.config/MangoHud/MangoHud.conf` desde `sync-rgb.py`.

---

## 🌐 5. SINCRONIZACIÓN CON DISCORD / VENCORD Y NAVEGADOR
- **Concepto**: Temas dinámicos de Discord y Firefox/Brave adaptados al wallpaper:
  - Generar un archivo `~/.config/Vencord/themes/material-you.theme.css` con variables CSS generadas desde `scheme.json`.

