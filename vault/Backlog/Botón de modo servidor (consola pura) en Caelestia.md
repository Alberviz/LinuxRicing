---
fileClass: Backlog
tipo: tarea
estado: hecha
prioridad: 2
area: caelestia
origen: Alberto
esfuerzo: M
creado: 2026-09-10
tags:
  - backlog
---

Botón **"Server mode"** en la tarjeta *Quick Toggles* de Caelestia que deja el
portátil en **consola pura** para durar lo máximo en batería con el servidor de
Minecraft abierto. Escalón por encima del `PowerSaving.qml` automático (que se queda
en Hyprland recortado): este **cierra el entorno gráfico entero**
(`systemctl isolate multi-user.target`).

Al pulsar (doble toque de confirmación): perfil `power-saver`, para servicios
cosméticos (`openrgb`, `argb-wave`, `battery-lighting`, `laura`,
`mchose-audio-cleanup`, `ydotool`, `appimagelauncherd`) y procesos sueltos
(`sync-rgb.py`, `mchose-battery`, `magichome-control`, `desktop-deck-helper`,
`gtasks`), `rfkill block bluetooth`, LEDs a negro, y cae a tty.

**No se toca:** `minecraft-server.service`, `minecraft-telegram-bot.service` (ambos
bajo `user@1000` con linger), `playitd` (servicio de sistema) ni la red WiFi.

Vuelta desde la consola: `volver-escritorio`.

Diseño e implementación: [[docs/plans/2026-09-10-modo-servidor-consola]].
Rama `feat/modo-servidor-consola`.
