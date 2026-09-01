---
tipo: tarea
estado: idea
area: agentes
origen: Alberto
esfuerzo: M
creado: 2026-09-01
tags:
  - backlog
---

Cerrar el sistema de notificaciones de agentes. La v1 (toasts, halo de acento,
popout, auto-descarte) y el *running pulse* v2 ya están; falta:

- **Estado de error:** halo ámbar + pip cuando un agente termina con fallo o
  cancelado. → [[Estado error — halo ámbar en el pip]]
- **Agente fuera de vista:** indicador en el extremo de la tira de pips cuando el
  workspace del agente no está paginado. → [[Indicador de agente en workspace fuera de vista]]
- *Running pulse* estilo **arc / spinner** como alternativa. → [[Running pulse — estilo arc (spinner)]]
- Repasar los falsos positivos del pulso "en curso" (ver [[Base de Datos de Errores]]).

Diseño en [[Notificaciones de Agentes]] §6.
