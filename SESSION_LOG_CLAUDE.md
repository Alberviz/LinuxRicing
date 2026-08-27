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

### E. FASE 3: Ingeniería Inversa USB HID y Control de Iluminación MCHOSE 8K

1. **Herramienta Automatizada de Análisis de Capturas (`mchose-pcap-analyzer`)**:
   - Creada en `/home/alberviz/.local/bin/mchose-pcap-analyzer` y [`~/LinuxRicing/rgb/mchose-pcap-analyzer.py`](/home/alberviz/LinuxRicing/rgb/mchose-pcap-analyzer.py).
   - **Metodología de Análisis para Claude / Modelos**:
     ```bash
     # Extrae automáticamente paquetes salientes del Host, aplica XOR 0xFF y desglosa campos
     mchose-pcap-analyzer /tmp/captura.pcapng
     ```
   - **Cómo funciona el protocolo MCHOSE (VID: `0x3837`, PID: `0x1001`)**:
     - Las transferencias se realizan mediante `SET_REPORT` (Feature Report) con Report ID `0x11` en la interfaz `:1.2` (`/dev/hidraw7`).
     - Todos los bytes de payload van **ofuscados con `XOR 0xFF`**.
     - **Estructura del Comando `0x2B` (20 bytes)**:
       ```
       [0x2B, 0x01, TARGET_ID, 0x00, BRIGHTNESS, SPEED, MODE, COLOR_MODE, 0x00, R1, G1, B1, R2, G2, B2, 0x00, 0x00, 0x00, 0x00, 0x00]
       ```
     - **Target IDs**:
       - `0x02`: Anillo LED de la Base de Carga 8K (*Base Ring*).
       - `0x06` / `0x07`: Iluminación interna del ratón / sensor.
     - **Modos de Iluminación (`MODE`)**:
       - `0`: Apagado (*Off*)
       - `1`: Respiración (*Breathing*)
       - `2`: Ola / Arcoíris dinámico (*Wave / Rainbow Cycle*)
       - `3`: Color Fijo Estático (*Static Solid*)
   - **Herramienta CLI de Control Rápido**:
     ```bash
     mchose-lighting breathing "#ff9800"   # Modo respiración ámbar
     mchose-lighting wave                  # Modo ola arcoíris dinámico
     mchose-lighting static "#00e5ff"     # Modo color fijo
     ```

### F. Atajos de Teclado Hyprland y Selector de Fondos

1. **Lanzador Directo de Wallpapers (`Super + W`)**:
   - Se configuró en [`~/.config/hypr/hyprland/keybinds.lua`](/home/alberviz/.config/hypr/hyprland/keybinds.lua) vinculado a `caelestia shell wallpapers open`.
   - Se modificó [`Content.qml`](/home/alberviz/.config/quickshell/caelestia/modules/launcher/Content.qml) y [`Shortcuts.qml`](/home/alberviz/.config/quickshell/caelestia/modules/Shortcuts.qml) para inyectar reactivamente `>wallpaper ` en la barra de búsqueda y desplegar de inmediato el carrusel horizontal con miniaturas de fondos de pantalla.
   - `Super + Shift + W`: Cambia a un fondo aleatorio instantáneamente.

---

## 📁 3. ESTRUCTURA DE ARCHIVOS Y RUTAS CLAVE

| Componente | Ruta de Configuración Activa | Ruta en Repositorio (`~/LinuxRicing/`) |
|---|---|---|
| **Caelestia Quickshell** | `~/.config/quickshell/caelestia/` | `~/LinuxRicing/configs/quickshell/caelestia/` |
| **Widget Deck & Fondo** | `~/.config/quickshell/caelestia/modules/background/Background.qml` | `~/LinuxRicing/widgets/Background.qml` |
| **Sincronización RGB + Spotify** | `~/.config/caelestia/sync-rgb.py` | `~/LinuxRicing/rgb/sync-rgb.py` |
| **Analizador de Capturas PCAP** | `~/.local/bin/mchose-pcap-analyzer` | `~/LinuxRicing/rgb/mchose-pcap-analyzer.py` |
| **Controlador Iluminación Base** | `~/.local/bin/mchose-lighting` | `~/LinuxRicing/rgb/mchose-lighting` |
| **Batería MCHOSE** | `~/.local/bin/mchose-battery` | `~/LinuxRicing/rgb/mchose-battery` |
| **Servicio MPRIS / Carátulas** | `~/.config/quickshell/caelestia/services/Players.qml` | `~/LinuxRicing/configs/quickshell/caelestia/services/Players.qml` |
| **Helper Deck (Clima / HW)** | `~/.local/bin/desktop-deck-helper` | `~/LinuxRicing/widgets/desktop-deck-helper` |
| **Google Tasks CLI** | `~/.local/bin/gtasks` | `~/LinuxRicing/widgets/gtasks` |
| **Control MagicHome LED** | `~/.local/bin/magichome-control` | `~/LinuxRicing/rgb/magichome-control` |
| **Tema Spicetify Caelestia** | `~/.config/spicetify/Themes/caelestia/` | `~/LinuxRicing/configs/spicetify/Themes/caelestia/` |
| **Atajos Hyprland Activos** | `~/.config/hypr/hyprland/keybinds.lua` | `~/LinuxRicing/configs/hypr/hyprland/keybinds.lua` |
| **Variables Hyprland** | `~/.config/hypr/variables.lua` | `~/LinuxRicing/configs/hypr/variables.lua` |
| **Instalador Modular** | `~/LinuxRicing/install.sh` | `~/LinuxRicing/install.sh` |

---

## 🚀 4. RESUMEN DE HITOS Y ESTADO DEL SISTEMA

- **100% Completado**: Sincronización Material You global (OpenRGB, Teclado Akko, Base MCHOSE, MagicHome LED, Spotify Spicetify).
- **100% Completado**: Deck interactivo de 4 tarjetas con scroll de ratón y Google Tasks reactivo.
- **100% Completado**: Ingeniería inversa de paquetes USB HID para la base MCHOSE 8K (Breathing, Wave, Static).
- **100% Completado**: Selector de wallpapers visual con `Super + W` directo en el lanzador.
- **100% Completado**: Instalador `install.sh` empaquetado y respaldado en Git `main`.

