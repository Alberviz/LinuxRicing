---
fileClass: Backlog
tipo: tarea
estado: en-curso
prioridad: 4
area: assistant
origen: Alberto
esfuerzo: M
creado: 2026-09-01
tags:
  - backlog
  - aurora
---

Cambiar el nombre de la IA de voz de **Aurora** a **Laura** en todo el proyecto,
una vez terminado el overlay (fase 6). Alcance: `assistant/` (código, prompts,
`config.toml`, `aurora.service` → `laura.service`, sockets), el módulo de
Quickshell `modules/assistant/` (singleton `Aurora.qml`, namespaces de las
ventanas, etc.), los atajos de Hyprland, y las notas del vault
([[Asistente de voz con IA local]], [[Aurora — plan del overlay]]). Ver
[[Roadmap Maestro de Innovaciones]].

## Progreso

- **Hecho (código, Claude):** `assistant/` completo (`laurad.py`, `laura.service`,
  `laura-toggle`, `config.toml`, prompts, sockets `laura.sock` /
  `laura-events.sock`) y el módulo de Quickshell (singleton `Laura.qml`,
  namespaces `laura-orb` / `laura-bar`, referencias).
- **Pendiente de Alberto:** reinstalar el servicio de usuario
  (`disable --now aurora` → `enable --now laura`) y cambiar el atajo de
  Hyprland a `laura-toggle`.
- **Pendiente (vault, Gemini):** renombrar en las notas.
- **Pendiente:** el overlay se rehace entero (unificar modos, luz de bordes);
  el rename final de esas ventanas va con ese rediseño.
