# 🛸 RESUMEN TÉCNICO Y HANDOVER DE LA SESIÓN DE HOY (26 de Agosto de 2026)

Este documento contiene un resumen detallado y exhaustivo de todos los desarrollos, arquitecturas, ingeniería inversa de hardware, widgets y configuraciones creadas en el sistema Arch Linux + Hyprland + Caelestia + Quickshell de **Alberviz**.

---

## 🎯 1. PERFIL DEL USUARIO Y FILOSOFÍA DEL RICE

- **Ecosistema**: Arch Linux / Hyprland / Caelestia / Quickshell / Matugen (Material You M3) / OpenRGB.
- **Filosofía Estética**: Material Design 3 con extracción dinámica de paleta desde el fondo de pantalla (`scheme.json`). Interfaz futurista, reactiva, minimalista, con física fluida e interactividad completa.
- **Hardware Integrado**:
  - **Teclado**: Akko 5075B Plus (con retroiluminación y tira LED lateral independiente).
  - **Ratón y Base**: MCHOSE K7 Ultra + Base/Dongle 8K inalámbrica.
  - **Tira LED Iluminación Ambiental**: Magic Home Wi-Fi LED Strip (controlada por `flux_led` y `/home/alberviz/.local/bin/magichome-control`).
  - **Componentes PC**: Placa Base ASUS TUF GAMING B560M-PLUS y Memorias RAM ENE DRAM (controladas vía OpenRGB SDK).
  - **GPU**: Nvidia GeForce RTX (monitorizada vía `nvidia-smi`).
- **Productividad**: Integración nativa de Google Tasks (`gtasks` CLI en Python con backend OAuth2 y cache local).

---

## 🛠️ 2. RESUMEN DE HITOS Y TRABAJO REALIZADO HOY

### A. Corrección y Sincronización RGB de Hardware (`sync-rgb.py`)
1. **Teclado Akko 5075B Plus**:
   - Se diagnosticó que el opcode `0x08` controla la **tira de luz lateral (side-strip)** de forma independiente a la retroiluminación de las teclas (`0x01`).
   - Se implementó el envío directo vía `ioctl(HIDIOCSFEATURE)` a `/dev/hidraw2` con modo estático (`0x01`), velocidad `0x04`, brillo `0x04`, modo de color `0x08` y checksum de 8 bits.
2. **Base MCHOSE 8K**:
   - Protocolo invertido de comando `0x2B` con payload de 17 bytes y prefijo `0x11`, enviado a la interfaz USB HID `:1.2` (`hidraw7`).
3. **Tira Magic Home Wi-Fi**:
   - Conexión vía socket directo TCP (`flux_led`) con fallback a script CLI en timeout.
4. **OpenRGB**:
   - Sincronización en paralelo de RAM y placa ASUS TUF mediante SDK TCP (`localhost:6742`).

### B. Corrección Global de Carátulas de Audio (Spotify, YouTube, Local)
1. **Problema**: Spotify en Linux emite URIs con esquema `spotify:image:<hash>` que Qt Quick `Image` / `FadeImage` no puede renderizar, provocando carátulas vacías.
2. **Solución Global en `Players.qml`**:
   - Se migró la configuración de Caelestia a `~/.config/quickshell/caelestia/services/Players.qml`.
   - Se implementó sanitización y autoconversión de URIs:
     - `spotify:image:<hash>` ➔ `https://i.scdn.co/image/<hash>`
     - `https://open.spotify.com/image/<hash>` ➔ `https://i.scdn.co/image/<hash>`
     - Rutas locales `/home/...` ➔ `file:///home/...`
     - YouTube/YouTube Music ➔ `https://img.youtube.com/vi/<id>/hqdefault.jpg`
3. **Icono de Respaldo**: En caso de no existir carátula, se renderiza un vinilo/álbum animado de Material You.

### C. FASE 1: Sincronización de Spotify con Spicetify y Matugen
1. **Configuración de Tema**:
   - Se activó el tema `caelestia` en Spicetify (`spicetify config current_theme caelestia`).
2. **Hook Dinámico (`sync_spicetify`)**:
   - En [`sync-rgb.py`](/home/alberviz/.config/caelestia/sync-rgb.py), se añade la función `sync_spicetify()` que lee `~/.local/state/caelestia/scheme.json` en cada cambio de fondo y regenera `~/.config/spicetify/Themes/caelestia/color.ini`.
   - Ejecuta `spicetify apply -q` en segundo plano, adaptando instantáneamente toda la interfaz de Spotify al color del wallpaper.

### D. FASE 2: Deck de Widgets Interactivo en el Escritorio (`DesktopWidgetDeck`)
1. **Arquitectura Multi-Tarjeta Deslizable**:
   - En [`Background.qml`](/home/alberviz/.config/quickshell/caelestia/modules/background/Background.qml), se creó el componente `DesktopWidgetDeck` que consolida 4 tarjetas en un solo espacio con ancho de 640px:
     - **Tarjeta 0 (📋 Tareas)**: Google Tasks con lista de tareas, checkboxes interactivos, contador de pendientes y sincronización debounce.
     - **Tarjeta 1 (⛅ Clima)**: Temperatura local, icono meteorológico, descripción, humedad, velocidad del viento, hora de amanecer y atardecer.
     - **Tarjeta 2 (⚡ Hardware)**: Barras animadas con telemetría en tiempo real: CPU %, RAM usada/total, GPU Temp °C y uso, y VRAM %.
     - **Tarjeta 3 (⏱️ Focus)**: Temporizador Pomodoro (25 min enfoque / 5 min descanso), con controles de reproducción/reset y botón de **Luz de Concentración** (ilumina la tira LED en ámbar cálido `#ff9800`).
2. **Navegación e Interactividad**:
   - Selector de píldoras superiores con animación fluida (`CAnim`).
   - **Cambio por rueda de ratón (Scroll)**: Al colocar el cursor sobre el deck y mover la rueda del ratón, se cambia de tarjeta suavemente.
   - Puntos indicadores inferiores con píldora expandible activa.
3. **Backend Helper (`desktop-deck-helper`)**:
   - Creado en `/home/alberviz/.local/bin/desktop-deck-helper` para servir datos de clima (con caché de 15 minutos en `/tmp/caelestia-weather-cache.json`) y telemetría de hardware en JSON ultra-rápido (<50ms).

---

## 📁 3. ESTRUCTURA DE ARCHIVOS Y RUTAS CLAVE

| Componente | Ruta de Configuración Activa | Ruta en Repositorio (`~/LinuxRicing/`) |
|---|---|---|
| **Caelestia Quickshell** | `~/.config/quickshell/caelestia/` | `~/LinuxRicing/configs/quickshell/caelestia/` |
| **Widget Deck & Fondo** | `~/.config/quickshell/caelestia/modules/background/Background.qml` | `~/LinuxRicing/widgets/Background.qml` |
| **Sincronización RGB + Spotify** | `~/.config/caelestia/sync-rgb.py` | `~/LinuxRicing/rgb/sync-rgb.py` |
| **Servicio MPRIS / Carátulas** | `~/.config/quickshell/caelestia/services/Players.qml` | `~/LinuxRicing/configs/quickshell/caelestia/services/Players.qml` |
| **Helper Deck (Clima / HW)** | `~/.local/bin/desktop-deck-helper` | `~/LinuxRicing/widgets/desktop-deck-helper` |
| **Google Tasks CLI** | `~/.local/bin/gtasks` | `~/LinuxRicing/widgets/gtasks` |
| **Batería MCHOSE** | `~/.local/bin/mchose-battery` | `~/LinuxRicing/rgb/mchose-battery` |
| **Control MagicHome LED** | `~/.local/bin/magichome-control` | `~/LinuxRicing/rgb/magichome-control` |
| **Tema Spicetify Caelestia** | `~/.config/spicetify/Themes/caelestia/` | `~/LinuxRicing/configs/spicetify/Themes/caelestia/` |
| **Atajos Hyprland** | `~/.config/hypr/config/binds.lua` | `~/LinuxRicing/configs/hypr/config/binds.lua` |

---

## 🚀 4. PRÓXIMOS PASOS PROGRAMADOS

1. **FASE 3**: Alertas visuales de batería baja en periféricos y detección de carga en la base MCHOSE.
2. **Atajo Directo de Fondos**: Configurar `SUPER + W` en `binds.lua` para abrir el selector de fondos o Caelestia nexus.
3. **Instalador Modular para Nuevo Portátil (`install.sh`)**: Script interactivo con TUI/GUI para desplegar todo este rice en un nuevo dispositivo en minutos.
4. **Shutdown del sistema**: Al finalizar todas las verificaciones.

