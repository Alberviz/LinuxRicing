---
fileClass: Backlog
tipo: tarea
estado: pendiente
prioridad: 3
area: escritorio
origen: Alberto
esfuerzo: M
creado: 2026-10-05
flujo: "[[Sistema solar binario del escritorio]]"
tags:
  - backlog
---

# Cometa de tareas reactivo al número de tareas

Hacer que el cometa de tareas del sistema solar **reaccione a las tareas que hay**: su
tamaño, la cola, el brillo o la velocidad dependen de cuántas tareas hay abiertas, de cuántas
están en curso y de su prioridad (p. ej. más urgentes = más brillante/rápido; sin tareas,
cometa tenue o ausente; muchas P1 = señal de alerta). Hoy solo la longitud de la cola crece
con el recuento.

Los datos ya llegan de `Tasks.qml` (`tareas`, `pendientes`, estado y prioridad). Decidir
viendo: mockups con 2-3 comportamientos antes de implementar. Respetar las reglas de
animación de CLAUDE.md (nada de bucles permanentes ni `shadowBlur`).
