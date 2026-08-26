# Contexto de la Configuración de Widgets y Background (Caelestia / Quickshell)

Este documento resume la arquitectura, funcionamiento, historial de cambios y estado actual de los widgets de escritorio implementados en el entorno Caelestia / Quickshell para futuras conversaciones.

---

## 1. Arquitectura y Ubicación de Archivos

- **Archivo principal de widgets**: `/etc/xdg/quickshell/caelestia/modules/background/Background.qml`
- **Configuración general de Caelestia**: `/home/alberviz/.config/caelestia/shell.json`
- **Comandos de gestión del Shell**:
  - Reiniciar/arrancar en segundo plano: `caelestia shell -k ; sleep 0.5 ; caelestia shell -d`
  - Ver logs en tiempo real: `caelestia shell -l`
- **Scripts auxiliares del sistema**:
  - Estado de periféricos (MCHOSE): `/home/alberviz/.local/bin/mchose-battery --json`
  - Tareas de Google (gtasks): `/home/alberviz/.local/bin/gtasks` (`--json`, `--toggle <id>`)
  - Control de tira LED MagicHome: `/home/alberviz/.local/bin/magichome-control` (`--status`, `--toggle`)
  - Sincronización de colores RGB: `/home/alberviz/.config/caelestia/sync-rgb.py`

---

## 2. Componentes y Widgets en `Background.qml`

El archivo define una ventana `StyledWindow` (`id: win`) con la propiedad booleana `transparentWidgets` (por defecto `true`).

### A. Periféricos (`DesktopPeripherals`)
- **Cabecera**:
  - Título: `Periféricos`
  - **Botón de Transparencia**: `StyledRect` circular de 28×28 con icono `blur_on` / `blur_off`. Al pulsar conmuta `win.transparentWidgets = !win.transparentWidgets`.
  - **Botón de Recarga**: `StyledRect` circular de 28×28 con icono `refresh` / `sync` que ejecuta `proc.running = true`.
- **Tarjetas de dispositivos (`DeviceItem`)**:
  - Auriculares ("V9 Pro"), Ratón ("K7 Ultra"), Teclado ("Akko B").
  - Muestran porcentaje de batería, estado de conexión y carga.
  - Fondo: `win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh`.

### B. Notas / Google Tasks (`DesktopTasks`)
- **Cabecera**:
  - Icono `task_alt` y título `tasksRoot.listTitle`.
  - **Botón de Recarga**: `StyledRect` circular de 28×28 con icono `refresh` / `sync` que recarga `gtasksProc`.
- **Filas de tareas (`TaskRow`)**:
  - Casilla de verificación para marcar como completada/pendiente con debounce de 1.2s.
  - Fondo: `completed ? "transparent" : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)`.

### C. Tira LED / Iluminación Ambiente (`DesktopLedStrip`)
- **Cabecera**:
  - Título: `Iluminación Ambiente`.
  - **Indicador de estado**: `MaterialIcon` con icono `lightbulb` (o `sync` si conecta), cuyo color cambia a `Colours.palette.m3primary` cuando la tira está encendida (`isPowered`).
- **Tarjeta 1 (Encendido/Apagado)**:
  - Muestra "ON"/"OFF" y "Encendida"/"Apagada". Al clicar conmuta la energía (`togglePower()`).
  - Fondo: `ledRoot.isPowered ? Qt.alpha(Colours.palette.m3primary, 0.18) : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)`.
- **Tarjeta 2 (Sincronización y Color)**:
  - Muestra un círculo con el color hexadecimal actual (`currentHex`) y el botón "Re-sincronizar" (`syncColors()`).
  - Fondo: `win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh`.

### D. Reproductor Circular y Visualizador (`DesktopCircularMedia`)
- Visualizador orbital concéntrico de 360° reactivo a CAVA.
- Carátula circular de 240px con borde de acento y soporte de clic para reproducir/pausar (`Players.active?.togglePlaying()`).
- Título de la pista y artista centrados.

---

## 3. Resumen de Cambios y Ajustes Realizados

1. **Fondo semitransparente unificado para botones interactivos**:
   - Todos los botones de control en cabeceras (`blur_on/blur_off`, botones de recargar `refresh`) ahora utilizan `StyledRect` con dimensiones 28×28, `radius: Tokens.rounding.full`, y el mismo fondo translúcido que las notas:
     ```qml
     color: win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5)
     ```
   - Tienen `StateLayer` integrado para respuesta táctil/hover y animación fluida con `CAnim`.

2. **Restauración del Widget de Tira LED**:
   - Se mantuvo intacto el icono indicador `lightbulb` en la cabecera (evitando duplicar el botón de recarga que ya reside en la tarjeta de sincronización).
   - Se verificó que las tarjetas de encendido y sincronización sigan respondiendo a clics y ejecuten sus respectivos scripts de control.

3. **Corrección de Lints y Advertencias QML**:
   - Se estandarizó el uso de `Tokens.font.icon.small` (evitando tokens no declarados como `extraSmall`).
   - Se corrigió el binding de radio en el `StateLayer` de la carátula circular (`coverCircle.radius`).
