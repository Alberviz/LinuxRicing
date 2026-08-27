---
tags: [windows, ricing, widgets, quickshell, qml, yasb, komorebi, glazewm, tiling]
actualizado: 2026-08-27
---

# 🖥️ Windows · Replicación de Widgets, Tiling y UI del Rice

En Linux contamos con un ecosistema de vanguardia: **Hyprland** (compositor Wayland) + **Quickshell / Caelestia** (interfaz completa basada en QML y Qt Quick) + **Matugen** + **Spicetify**.

Dado que Quickshell depende del protocolo Wayland *layer-shell* (exclusivo de Linux), en Windows no puede ejecutarse tal cual como compositor shell. Sin embargo, **es 100% viable replicar exactamente la misma experiencia estética y funcional** mediante varias arquitecturas complementarias.

---

## 🧭 1. Comparativa de Componentes: Linux vs Alternativas en Windows

| Componente                     | Linux (Setup Activo)           | Alternativa A (Máxima Fidelidad QML) | Alternativa B (Stack Moderno YASB + Komorebi) | Alternativa C (Web / Zebar) |
| ------------------------------ | ------------------------------ | ------------------------------------ | --------------------------------------------- | --------------------------- |
| **Tiling Window Manager**      | Hyprland                       | GlazeWM / Komorebi                   | **Komorebi + whkd**                           | GlazeWM                     |
| **Barra Superior de Estado**   | Quickshell (Caelestia Bar)     | PySide6 / QML Frameless Bar          | **YASB (Yet Another Status Bar)**             | Zebar Bar                   |
| **Deck de Widgets Escritorio** | `Background.qml` (4-en-1 Deck) | **PySide6 Desktop Deck (QML)**       | Rainmeter / Custom YASB Popups                | Zebar Desktop Overlay       |
| **Telemetría de Batería**      | `mchose-battery` CLI           | `mchose-battery-windows.py`          | **`yasb_mchose.py` (SVG dinámico)**           | Zebar Custom Script         |
| **Visualizador de Audio**      | CAVA circular orbital          | QML Shader / CAVA Win32              | **CAVA Windows (`.config/cava`)**             | WebGL Canvas                |
| **Sincronización Spotify**     | Spicetify + `color.ini`        | Spicetify Windows                    | **Spicetify Windows**                         | Spicetify Windows           |
| **Lanzador de Apps & Fondos**  | Caelestia Launcher (`Super+W`) | PySide6 QML Launcher                 | **Flow Launcher / PowerToys Run**             | Flow Launcher               |
| **Atajos Globales de Teclado** | `hyprland/keybinds.lua`        | AutoHotkey v2 (AHK)                  | **`whkd` + AutoHotkey v2**                    | AutoHotkey v2               |

---

## 🚀 2. Solución 1: PySide6 + QML Nativo en Windows (Máxima Reutilización de Código)

> [!TIP]
> **QML y Qt Quick no son exclusivos de Linux**: lo único exclusivo de Linux es el backend Wayland layer-shell de Quickshell. El motor gráfico QML de Qt se ejecuta de forma nativa en Windows con aceleración por hardware DirectX/OpenGL.

### ¿Cómo funciona?
Se crea un contenedor ultraligero en Python usando **PySide6 (Qt 6.x)** que instancia una ventana sin bordes (`Qt.FramelessWindowHint`), con fondo transparente (`Qt.WA_TranslucentBackground`) y anclada al fondo del escritorio (`Qt.WindowStaysOnBottomHint` o acoplada mediante Win32 API al proceso `WorkerW` del explorador de Windows):

```python
# desktop_deck_windows.py (Esquema)
import sys
from PySide6.QtWidgets import QApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtCore import QUrl, Qt

app = QApplication(sys.argv)
view = QQuickView()
view.setFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint | Qt.SubWindow)
view.setColor(Qt.transparent)
view.setSource(QUrl.fromLocalFile("widgets/Background.qml"))
view.show()
sys.exit(app.exec())
```

### Ventajas:
1. **Reutilización directa de los componentes QML**: El deck 4-en-1 (Google Tasks, Hardware, Clima, Pomodoro) y las animaciones de energía `CAnim` se ejecutan idénticos a Linux.
2. **Estilo Material Design 3 exacto**: Mismos colores, radio de esquinas y tipografías.
3. **Consumo mínimo de memoria RAM**: ~30-40 MB.

---

## 🪟 3. Solución 2: Stack YASB + Komorebi + AHK (Ya instalado en el sistema)

En el sistema actual de Windows ya existen las configuraciones de:
- **YASB (`C:\Users\Alberviz\.config\yasb\config.yaml`)**:
  - Barra superior flotante con bordes redondeados, desenfoque acrílico (*acrylic blur*) y soporte CSS.
  - Widget personalizado de batería de periféricos MCHOSE (`yasb_mchose.py`) con iconos vectoriales SVG interactivos.
  - Módulos de reproducción multimedia, control de volumen, workspaces y menú de energía.
- **Komorebi**:
  - Gestor dinámico de ventanas tipo *Tiling* (equivalente a Hyprland).
  - Control de espacios de trabajo (*workspaces*), márgenes (*gaps*) y reglas de ventanas.

### Atajos Globales con AutoHotkey v2 (`rice-binds.ahk`):
Permite replicar con exactitud los atajos de Hyprland en Windows:

```autohotkey
; Win + W: Selector de Wallpapers
#w:: {
    Run("python C:\Users\Alberviz\LinuxRicing\rgb\sync-rgb-windows.py")
}

; Win + Space: Lanzador de aplicaciones
#Space:: {
    Send("#{s}") ; O invocar Flow Launcher
}

; Win + Alt + A: Toggle Ambilight Tira LED
#!a:: {
    Run("python C:\Users\Alberviz\LinuxRicing\rgb\magichome-toggle.py")
}
```

---

## 🌐 4. Solución 3: Zebar (Ecosistema Web Moderno)

**Zebar** es una alternativa moderna diseñada específicamente para Windows que permite crear barras y widgets flotantes usando **HTML, CSS, JavaScript / React**:

- **Fácil integración con Tailwind CSS o Material Design 3 CSS**.
- **Acceso nativo a telemetría de CPU, RAM, GPU, batería y red sin scripts adicionales**.
- **Ventanas transparentes nativas con soporte para Mica y Acrylic Blur**.

---

## 🎵 5. Sincronización de Spotify (Spicetify) y CAVA en Windows

### A. Spicetify en Windows:
- Spotify en Windows soporta Spicetify en `%LOCALAPPDATA%\spicetify\`.
- Al cambiar el wallpaper, `sync-rgb-windows.py` puede regenerar el archivo `color.ini` del tema `caelestia` y ejecutar `spicetify apply -q`, manteniendo Spotify sincronizado exactamente igual que en Linux.

### B. Visualizador de Audio CAVA:
- Configurado en `C:\Users\Alberviz\.config\cava\config`.
- Cuenta con shaders personalizados (`shaders/bar_spectrum.frag`, `shaders/orion_circle.frag`) para proyectar el espectro musical sobre el fondo de pantalla.

---

## 📊 Matriz de Decisión para el Setup en Windows

| Requisito | Solución Recomendada |
|---|---|
| Quiero que el **deck de widgets se vea 100% igual que en Linux** (mismo QML) | **PySide6 + QML Desktop Deck** |
| Quiero una **barra superior ligera, moderna y estable** | **YASB** (ya configurado) |
| Quiero **gestión de ventanas automática con atajos estilo Hyprland** | **Komorebi + whkd / GlazeWM** |
| Quiero **control y telemetría de batería en tiempo real** | **`rgb/mchose-battery-windows.py` + `yasb_mchose.py`** |
| Quiero **sincronización de color con un solo clic/evento** | **`rgb/sync-rgb-windows.py`** |
