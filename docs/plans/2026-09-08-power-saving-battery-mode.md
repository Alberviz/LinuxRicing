# Plan de Implementación: Modo Ahorro Máximo de Batería y Fondo Negro

> **Para Gemini:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Objetivo:** Activar automáticamente un modo de ahorro extremo de energía cuando el equipo esté en batería o en perfil power-saver, poniendo el fondo negro, desactivando los widgets secundarios y el visualizador de audio, anulando animaciones en Quickshell e Hyprland y reduciendo el consumo de CPU y GPU.

**Arquitectura:** Un nuevo servicio singleton `PowerSaving.qml` centraliza la detección del estado (`UPower.onBattery`, `PowerProfiles` y porcentaje bajo). Controla el perfil de CPU, relaja la composición en Hyprland, fuerza la duración de animación en `Anim.qml` a 0ms, y conmuta `Background.qml` a fondo negro con únicamente `DesktopClock` activo sin shaders.

**Tech Stack:** QML, Quickshell (`Quickshell.Services.UPower`, `Quickshell.Wayland`), Hyprland IPC, Linux `power-profiles-daemon`.

---

### Tarea 1: Crear el servicio singleton `PowerSaving.qml` y registrarlo

**Archivos:**
- Crear: `configs/quickshell/caelestia/services/PowerSaving.qml`
- Modificar: `configs/quickshell/caelestia/modules/ServiceLoader.qml`

**Paso 1: Escribir `PowerSaving.qml`**
Implementar el singleton con:
- `readonly property bool active: (UPower.onBattery) || (PowerProfiles.profile === PowerProfile.PowerSaver) || (UPower.displayDevice.isLaptopBattery && UPower.displayDevice.percentage <= 0.20)`
- `property int previousProfile: PowerProfile.Balanced`
- Gestión de Hyprland (`applyOptions` para `animations:enabled: 0`, `decoration:shadow:enabled: 0`, `decoration:blur:enabled: 0` al activarse; `reload` al desactivarse).
- Conmutación automática de `PowerProfiles.profile = PowerProfile.PowerSaver` en batería y restauración de `previousProfile` al enchufar.

**Paso 2: Registrar en `ServiceLoader.qml`**
Añadir `PowerSaving;` a la lista de singletons precargados en `ServiceLoader.qml`.

---

### Tarea 2: Minimizar animaciones de Quickshell en `Anim.qml`

**Archivos:**
- Modificar: `configs/quickshell/caelestia/components/Anim.qml`

**Paso 1: Modificar `duration` en `Anim.qml`**
Importar `qs.services` y devolver `0` de duración si `PowerSaving.active` es `true`.

---

### Tarea 3: Modificar `Background.qml` y `DesktopClock.qml`

**Archivos:**
- Modificar: `configs/quickshell/caelestia/modules/background/Background.qml`
- Modificar: `configs/quickshell/caelestia/modules/background/DesktopClock.qml`

**Paso 1: Actualizar `Background.qml`**
- Importar `qs.services`.
- Forzar `color: PowerSaving.active ? "black" : (contentItem.Config.background.wallpaperEnabled ? "black" : "transparent")`.
- Forzar `WlrLayershell.layer: (PowerSaving.active || contentItem.Config.background.wallpaperEnabled) ? WlrLayer.Background : WlrLayer.Bottom`.
- Wallpaper loader: `active: Config.background.wallpaperEnabled && !PowerSaving.active`.
- DesktopCircularMedia: condicionar a `!PowerSaving.active` con un Loader o `active`/`visible` para detener Cava y animación.
- Desactivar `peripheralsLoader`, `deckLoader`, `ledStripLoader` con `active: Config.background.desktopClock.enabled && !PowerSaving.active`.

**Paso 2: Actualizar `DesktopClock.qml`**
- Importar `qs.services`.
- En `blurEnabled`: desactivar si `PowerSaving.active`.
- En `shadowEnabled`: desactivar si `PowerSaving.active`.

---

### Tarea 4: Sincronización y reinicio de Caelestia Quickshell

**Archivos:**
- Sincronizar: `configs/quickshell/caelestia/*` -> `~/.config/quickshell/caelestia/`
- En `shell.qml`: asegurar que `Background {}` esté activo en la configuración instalada.

**Paso 1: Sincronizar archivos**
Copiar los archivos actualizados a `~/.config/quickshell/caelestia/`.

**Paso 2: Reiniciar shell**
Ejecutar:
```bash
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```
Verificar `INFO: Configuration Loaded` sin fallos.

---

### Tarea 5: Verificación en vivo y documentación

**Paso 1: Probar conmutación de perfil**
Probar `powerprofilesctl set power-saver` y `powerprofilesctl set balanced`.
Verificar que la UI responde de inmediato (fondo negro, widgets desaparecen, reloj se mantiene nítido, animaciones instantáneas).

**Paso 2: Documentar y actualizar bitácora**
- Actualizar `vault/Backlog/Modo ahorro maximo de bateria y fondo negro.md` a `estado: hecha`.
- Añadir entrada a `vault/🎯 Hoy.md` en «Bitácora de sesiones».
- Commit de la rama `feat/power-saving-black-bg` y merge a `refactor/background-modularize`.
