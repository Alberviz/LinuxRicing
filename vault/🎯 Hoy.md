---
tags:
  - home
  - backlog
actualizado: 2026-09-01
---

# 🎯 Hoy · ¿Qué hago?

## 🪣 Bucket List — ¿con qué me pongo hoy?

Checklist rápida. Marca `[x]` al terminar; añade líneas tú o pídeselo a un agente.
El detalle de cada cosa vive en su nota del `Backlog/` y en [[Roadmap Maestro de Innovaciones]].

- [ ] Terminar el **sistema de sonido** del ecosistema
- [ ] Terminar el **sistema de notificaciones** de agentes
- [ ] Terminar el **sistema de LEDs** (falta el teclado — ligado a la batería del Akko)
- [ ] **Agente IA para el arranque** (dual-boot) con tema visual propio
- [ ] **Centro de Iluminación RGB** (ventana única de control)
- [ ] **Escenas de 1 clic** (Gaming / Trabajo / Cine / Descanso)
- [ ] **Ambilight** en la tira LED
- [ ] **Letras sincronizadas** en el escritorio
- [ ] **Paridad Windows-Linux** del escritorio

---

Lista viva y priorizada de todo lo que hay pendiente en el setup **LinuxRicing**: lo que
le vas pidiendo a los agentes y los proyectos del [[Roadmap Maestro de Innovaciones]].

> [!tip] Cómo funciona
> - **Las tareas se añaden solas.** Cuando le dices a un agente *«añade esta tarea»* o
>   *«esto para el futuro»*, él crea la nota en `Backlog/` y aparece aquí.
> - **Tú mandas en el orden:** edita `prioridad` (1 = ya … 5 = algún día) y `estado`
>   directamente en la tabla.
> - Cambia de vista con las pestañas de la tabla: **En curso · Hoy · Todo · Por área ·
>   Reciente · Hechas · Tablero**.

---

## 🔨 En curso ahora mismo

![[Backlog.base#🔨 En curso]]

## 🎯 Pendiente (por prioridad)

![[Backlog.base#🎯 Hoy]]

## 🆕 Actividad reciente de los agentes

![[Backlog.base#🆕 Reciente]]

## ✅ Terminado

![[Backlog.base#✅ Hechas]]

---

## 📓 Bitácora de sesiones

*Los agentes añaden una línea por sesión, lo más reciente arriba.*

- **2026-08-29 · Claude** — Sistema de Backlog del vault: carpeta `Backlog/`, `Backlog.base`
  con 7 vistas y esta página. Semilla con el trabajo reciente + el Roadmap accionable.
- **2026-08-29 · Claude** — Convergido a `main` (`9b8d78f`): running-pulse v2 + sonidos de
  notificaciones + backlog del vault. Shell reiniciado y verificado, sonidos activos.
- **2026-08-29 · Claude** — Sonidos de notificaciones de agentes: sonido al iniciar /
  completar / fallar, 4 paletas (`system` + 3 de Kenney CC0), CLI `agent-notify sound-set`.
  Paleta activa: `kenney-glass`.
- **2026-08-29 · Claude** — *Running pulse* v2 del pip: aro palpitante mientras el agente
  trabaja + halo neón solo en el contorno; reproducibilidad de los hooks de Claude Code
  en `install.sh`.
- **2026-08-29 · Claude** — Fix: el teclado Akko reporta transporte USB al cargar por
  cable; fix de la bandera de carga atascada en 2.4 GHz.
- **2026-08-29 · Claude** — Auto-intercepción de las notificaciones nativas de Antigravity
  y Claude hacia el pipeline enriquecido de agentes.
- **2026-08-27 · Gemini + Claude** — Notificaciones de agentes en el pip del workspace
  (v1): CLI `agent-notify`, toasts enriquecidos, halo de acento, tarjeta popout.

---

### Fijar esta nota como pantalla de inicio

Para que Obsidian la abra al arrancar: **Ajustes → Plugins de la comunidad → Explorar →
«Homepage»** (instalar y activar) → en sus opciones, *Homepage* = `🎯 Hoy`. Mientras
tanto está en **Marcadores** (barra lateral).
