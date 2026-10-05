---
fileClass: Backlog
tipo: tarea
estado: pendiente
prioridad: 3
area: widgets
origen: Alberto
esfuerzo: S
creado: 2026-10-05
tags:
  - backlog
---

# Widget de rendimiento muestra también la GPU Intel

El widget de rendimiento solo lee la NVIDIA RTX 4050, que suele estar dormida (P8, 0 %),
mientras Hyprland y Quickshell (escritorio, shader del agujero negro) corren en la
**Intel UHD 770** (`renderD129`). Resultado: la gráfica siempre marca 0 % aunque se esté usando.

Hacer que muestre **las dos GPUs** (uso de la Intel vía `intel_gpu_top -J` o
`/sys/class/drm/card2/…`, NVIDIA vía `nvidia-smi`), etiquetadas.

Relacionada: [[Arreglar rendimiento y uso de la tarjeta gráfica]].
