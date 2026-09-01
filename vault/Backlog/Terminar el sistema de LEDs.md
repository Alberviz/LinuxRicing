---
tipo: tarea
estado: idea
area: rgb
origen: Alberto
esfuerzo: L
creado: 2026-09-01
tags:
  - backlog
---

Cerrar el sistema de iluminación. La sincronización de tema y el motor reactivo a
la batería ya están; falta sobre todo lo del **teclado**:

- **Telemetría de batería del Akko:** por cable el firmware no da % (documentado,
  el widget ya no lo inventa); falta una lectura 2.4 GHz fiable sin EMA.
  → [[Telemetría de batería real del teclado Akko]]
- **Daemon modular `rgbd`:** unificar los scripts sueltos en un servicio
  asíncrono con eventos y cero colisiones de bus.
  → [[Daemon modular de iluminación (rgbd)]]
- LED del **cuerpo del ratón K7 Ultra**.
  → [[Iluminación del cuerpo del ratón MCHOSE K7 Ultra]]

Panorama en [[Iluminación - Estado actual]] y [[Backlog - Efectos de iluminación]].
