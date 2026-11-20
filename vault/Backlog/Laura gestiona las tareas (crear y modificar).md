---
fileClass: Backlog
tipo: tarea
estado: hecha
prioridad: 3
area: agentes
origen: Alberto
esfuerzo: M
creado: 2026-10-05
tags:
  - backlog
---

# Laura gestiona las tareas (crear y modificar)

Dar a Laura acceso a las tareas para que pueda **leerlas, crear nuevas y modificar las
existentes** por voz («Laura, apunta que…», «marca como hecha…»). Nueva tool en
`assistant/tools.py`. Decidir qué fuente toca: Google Tasks (helper `widgets/gtasks`, ver
[[Sync bidireccional con Google Tasks]]) y/o el backlog del vault (`vault/Backlog/`).
