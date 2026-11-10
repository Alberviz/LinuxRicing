# Especificación: Píldora Expandible & Feedback Cinético para Herramientas de Laura (Zero-Chatter)

**Fecha:** 2026-11-10  
**Autor:** Gemini  
**Rama:** `feat/laura-holo`  
**Estado:** Diseño cinemático alineado con Alberto  
**Mockup Interactivo:** `docs/laura-v2/mockup-holo-acciones.html`

---

## 1. Visión y Principios Clave (Definidos por Alberto)

1. **No a un reproductor o panel estático al uso:**
   - No necesitamos una botonera con play/pause/prev/next estática flotando.
   - El componente debe ser una **animación de transición de estado que ilustre exactamente qué acaba de ocurrir** (Motion-First State Transition).

2. **Un solo cuerpo morfable (La píldora crece hacia arriba):**
   - Nada de tarjetas flotantes separadas en el aire ni conectores artificiales.
   - **La misma píldora de Laura (`pill` en `LauraOverlay.qml`) crece verticalmente hacia arriba de forma orgánica** (`height: 64px → 160px`) mediante una curva elástica continua (`cubic-bezier(0.16, 1, 0.3, 1)`), revelando la animación cinemática en su compartimento superior y replegándose sola tras 2,5 segundos.

3. **Zero-Chatter / Velocidad extrema sin voz lenta:**
   - Evitar confirmaciones habladas redundantes: que Laura diga *"He pasado a la siguiente canción"* o *"He subido el volumen al 70%"* añade 2-3 segundos de latencia innecesaria de TTS y corta la música.
   - **La acción ocurre al milisegundo**, la píldora se expande al instante y la animación en pantalla confirma el cambio al ojo humano de forma limpia y certera.

---

## 2. Coreografía de las Animaciones Cinéticas

### A. Siguiente Canción / Anterior (Slide & Handoff)
- **Animación:**
  * La canción saliente se desliza hacia la izquierda con `opacity: 1 → 0` y `translateX(0 → -120%)`.
  * La nueva canción entra desde la derecha con inercia elástica (`translateX(120% → 0)` y `opacity: 0 → 1`).
  * La miniatura de carátula hace un swap fluido con desenfoque de movimiento suave.
- **Texto en la píldora:** `Spotify · Siguiente pista` (sin audio TTS).

### B. Pausar / Reanudar Música (Impacto Cinético «Pum»)
- **Animación de Pausa:**
  * Icono de pausa brota con escala `1.6 → 1.0` en un golpe seco de impacto central.
  * Un anillo de choque radial emana desde el centro (`wave-burst`: escala `0.7 → 2.2` con `opacity: 0.9 → 0`).
  * Carátula se oscurece / pausa su ecualizador.
- **Animación de Play:** Estallido de luz del color Material You activo y reactivación del ecualizador.

### C. Volumen y Brillo (Medidor en Delta con Inercia)
- **Animación:**
  * Muestra una línea fantasma punteada con el valor donde estaba antes el volumen (ej. `50%`).
  * La barra se llena con inercia elástica hasta el nuevo valor (ej. `75%`).
  * El porcentaje numérico realiza un conteo dinámico progresivo en vivo (`50% → 55% → 60% → 75%`).

---

## 3. Arquitectura de Implementación en Caelestia

### 1. `LauraOverlay.qml` (Modificación de la Píldora)
- La píldora pasa a tener una propiedad reactiva `property var activeAction: null`.
- Cuando llega un evento de acción:
  * `height` se anima a la altura expandida (`col.implicitHeight + 96px`).
  * El compartimento superior carga el delegado cinemático correspondiente (`SlideTrack`, `ImpactPause`, `DeltaSlider`).
  * Un `Timer` de 2,5 segundos dispara el repliegue suave hacia abajo.

### 2. En el Daemon Python (`assistant/laura/`)
- Para órdenes atómicas de herramientas simples (`spotify pasar`, `spotify pausar`, `volumen N`, `brillo N`):
  * **Modo silencioso activado:** No se genera TTS hablado en Kokoro/Piper.
  * El retorno de la tool emite inmediatamente por el socket de eventos:
    ```json
    {
      "type": "holo",
      "op": "action_motion",
      "action": {
        "tipo": "next_track | pause | play | volume | brightness",
        "prev": "RUN AWAY",
        "next": "DIABLITA",
        "from": 50,
        "to": 75
      }
    }
    ```
  * Latencia de ejecución: $\sim 30\text{ ms}$.

---

## 4. Próximos pasos
1. Validar el mockup interactivo en `docs/laura-v2/mockup-holo-acciones.html`.
2. Crear la rama dedicada `feat/laura-pildora-cinetica`.
3. Implementar la expansión superior en `LauraOverlay.qml`.
4. Añadir el modo silencioso en `assistant/laura/` para acciones directas de sistema.
