---
fileClass: Backlog
tipo: tarea
estado: pendiente
prioridad: 3
area: rgb
origen: Alberto
esfuerzo: L
creado: 2026-08-29
tags:
  - backlog
---

El **sistema de sonido completo y complejo** de todo el setup, más allá de los sonidos
de agentes que ya están hechos: una paleta sonora coherente y discreta para **todos**
los eventos del ecosistema.

- **Categorías de evento:** conexión / desconexión de dispositivos (2.4 GHz, BT, USB-C),
  batería baja, carga completada, OSD de volumen y brillo, cambio de perfil / escena,
  captura de pantalla y grabación, y toast de notificación entrante (opcional, por app).
- **Emparejado con la iluminación:** cada sonido dispara a la vez su flash RGB
  correspondiente, desde el mismo punto, para un feedback audiovisual sincronizado.
- **Configuración:** volumen global, activar/desactivar por categoría, y ruta de cada
  sonido — expuesto en el panel «Sonidos» de `NotificacionesView.qml`
  (ver [[Panel de ajustes de Sonidos]]).
- **Assets:** ampliar `rgb/sounds/` con paletas por categoría; base en `pw-play`.

Diseño detallado en [[Roadmap Maestro de Innovaciones]] §7. Sustituye a la nota previa
«Sonido del ecosistema — hardware, OSD y captura».
