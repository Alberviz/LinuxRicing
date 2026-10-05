---
fileClass: Backlog
tipo: tarea
estado: idea
prioridad: 5
area: escritorio
origen: Alberto
esfuerzo: M
creado: 2026-10-05
tags:
  - backlog
---

# Rediseño visual del cometa de tareas (meteorito)

> **Estado: aparcada (2026-10-05).** Alberto pidió mockups, los vio y decidió **no seguir por ahora**
> porque no tiene claro cómo hacerlo. Todo el trabajo hecho y las decisiones pendientes están
> documentados para retomarlo sin repetir nada.

## Qué es
Rediseñar el aspecto del **cometa de tareas** (el «meteorito») del sistema solar del escritorio.
Hoy es una línea fina + halo + punto, y **solo la longitud de la cola** transmite información.
Relacionada con [[Cometa de tareas reactivo al número de tareas]] (la parte de comportamiento: este
rediseño es la parte *visual*).

## Qué hay hecho
- Mockup interactivo con 6 variantes: `docs/sistema-solar-v3-mockup/cometa-variantes.html`
  (sliders de tareas / P1 / zoom, casilla de hover) y captura `cometa-variantes.png`.
- Documento de diseño completo con variantes, decisiones abiertas y plan de implementación:
  **`docs/sistema-solar-cometa-rediseno.md`**.

## Variantes exploradas
A Roca · B Bola de fuego · C Enjambre · D Cuentas · **E Polvo estelar** (cada tarea = una mota en
una nube difusa) · **F Campo de asteroides** (cada tarea = un asteroide). Recomendación del agente:
E (con cabeza rocosa de A opcional) o D si se quiere lo más sobrio.

## Para retomarla
1. Abrir el mockup, elegir variante (o mezcla).
2. Responder las «Decisiones abiertas» de `docs/sistema-solar-cometa-rediseno.md` §5.
3. Rama dedicada (`feat/cometa-rediseno`), implementar según §6, restart de Quickshell (ver CLAUDE.md).
