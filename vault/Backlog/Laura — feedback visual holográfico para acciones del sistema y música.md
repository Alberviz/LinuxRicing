---
fileClass: Backlog
tipo: tarea
estado: hecha
prioridad: 2
area: laura
origen: Alberto
esfuerzo: M
creado: 2026-11-10
tags:
  - backlog
---

# Laura — píldora expandible con feedback cinético y modo silencioso rápido

## Concepto clave (visión de Alberto)

1. **No a un reproductor o panel estático:**
   - No queremos botoneras estáticas ni widgets flotantes descolgados.
   - Debe ser una **animación cinemática que muestre qué acaba de ocurrir** (ej: la canción anterior se desliza y entra la nueva; el volumen muestra la marca previa y sube con inercia elástica; pausar hace un impacto «pum»).

2. **La propia píldora de Laura crece hacia arriba (un solo cuerpo):**
   - El chasis de la píldora (`LauraOverlay.qml`) se **expande verticalmente hacia arriba de forma orgánica** (`64px → 160px`), mostrando la animación en su compartimento superior, y se repliega sola tras 2.5 segundos.

3. **Modo Zero-Chatter (Máxima velocidad sin voz lenta):**
   - En acciones simples de sistema (pasar canción, volumen, brillo), **Laura no habla en voz alta** (*«He pasado a la siguiente canción»* añade 3 segundos lentos de TTS innecesarios).
   - La orden se ejecuta en 30 ms, la píldora se expande al instante y la animación confirma visualmente la acción en milisegundos con fluidez extrema.

## Recursos
- Mockup interactivo funcional: `docs/laura-v2/mockup-holo-acciones.html`
- Especificación técnica: `docs/superpowers/specs/2026-11-10-laura-holo-acciones.md`
