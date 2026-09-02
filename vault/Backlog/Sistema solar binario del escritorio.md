---
fileClass: Backlog
tipo: tarea
estado: en-curso
prioridad: 2
area: widgets
origen: Alberto
esfuerzo: L
creado: 2026-09-01
tags:
  - backlog
---

# Sistema solar binario del escritorio

Sustituir la columna izquierda de tarjetas de widgets (periféricos, tareas, tira
LED) por un **sistema binario**: dos soles —la **música** y **Laura**— orbitando
un baricentro común. Cada cosa real es un cuerpo que orbita: se mira y dice su
estado (color, brillo, tamaño), se pasa el ratón y da el detalle, se hace clic y
actúa.

- **Sol música** (dominante, siempre visible, `Audio.cava` + now-playing) con
  séquito tipo-S: tira LED y los tres periféricos con batería real.
- **Sol Laura** (tenue y lento hasta que interaccionas con ella) con séquito
  tipo-S: un astro-terminal por sesión de Claude / Antigravity (`Agents.qml`).
- **Circumbinario tipo-P:** cinturón de tareas (recuento real del backlog).
- Color de roles de `Colours.palette` (del wallpaper), nunca hex fijo.
- Estructura portable desde el día 1: `SolarSim` puro + paleta inyectada +
  adaptadores.

> [!info] Estado
> **v1.5 hecha** (2026-09-02, rama `feat/sistema-solar-v1`, sin mergear aún):
> disposición completa, adaptadores reales de batería y LED, cambio de ratón
> M8 → K7 Ultra integrado, 5 bugs de la v1 corregidos, `SolarSystemLayer`
> cableada al shell y verificada (carga limpia, ~5 % CPU en reposo). Los widgets
> siguen siendo la fuente de verdad hasta la v3.
>
> **Decisión pendiente de Alberto** (ver maqueta v1.5): ¿la música vuelve a ser
> sol dominante o se queda como agujero negro en la esquina?
>
> **Siguiente:** v2 (hover / clic / congelar) — necesita iteración en vivo.
>
> Documentos: `docs/sistema-solar-binario.md` · maqueta original
> `artifact 0cf6374a-85f0-4f6a-8003-3aae212b33b1` · maqueta v1.5
> `artifact 6935dde1-72c3-4ba1-8c87-c907f7ba8561`.

Va en [[Roadmap Maestro de Innovaciones]] §2. Comparte el gesto del "borde
inferior iluminado" con el overlay de voz de [[Aurora — plan del overlay|Laura]]
— a unificar en v2/v3.
