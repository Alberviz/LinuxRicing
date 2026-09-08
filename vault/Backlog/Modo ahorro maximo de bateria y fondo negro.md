---
fileClass: Backlog
tipo: tarea
estado: en-curso
prioridad: 1
area: caelestia
origen: Alberto
esfuerzo: M
creado: 2026-09-08
tags:
  - backlog
---

Cuando el portátil esté desconectado de corriente (`UPower.onBattery`) o se active el perfil `power-saver`:
1. Fondo de pantalla en negro puro (`color: "black"`, layer `WlrLayer.Background`), desactivando la carga del wallpaper.
2. Desactivar todos los widgets del fondo ([`Background.qml`](file:///home/alberviz/LinuxRicing/configs/quickshell/caelestia/modules/background/Background.qml)) excepto el reloj ([`DesktopClock.qml`](file:///home/alberviz/LinuxRicing/configs/quickshell/caelestia/modules/background/DesktopClock.qml)), desactivando shaders de blur/shadow en el reloj.
3. Desactivar el visualizador de audio circular (`DesktopCircularMedia`).
4. Animaciones de Caelestia al mínimo (duración `0 ms` instantánea vía [`Anim.qml`](file:///home/alberviz/LinuxRicing/configs/quickshell/caelestia/components/Anim.qml)).
5. Cambiar el perfil de CPU a `power-saver` y relajar composición en Hyprland para ahorro extremo de batería.
