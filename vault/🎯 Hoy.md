---
tags:
  - home
  - backlog
actualizado: 2026-09-01
---

# 🎯 Hoy · ¿Qué hago?

## 💡 Ideas — ¿con qué me pongo hoy?

Tu base de datos de ideas. **Elige una y ponte:** en la tabla, cambia su **Estado**
de `idea` a `pendiente` (y ponle una **prioridad**) — con eso baja sola a *En curso /
Pendiente* de aquí abajo. Para añadir una idea nueva, crea una nota en `Backlog/` con
`estado: idea` (o dile a un agente «apunta la idea …»).

![[Backlog.base#💡 Ideas]]

---

Abajo, la parte estructurada: lo que ya has elegido, con prioridades y estado. Las
tareas de detalle las van añadiendo los agentes cuando se lo pides.

> [!tip] Cómo funciona
> - **`idea` → `pendiente` → `en-curso` → `hecha`.** Tú promocionas ideas y ordenas
>   prioridad (1 = ya … 5 = algún día) editando la tabla; los agentes hacen el resto.
> - Cambia de vista con las pestañas: **Ideas · En curso · Hoy · Todo · Por área ·
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

- **2026-09-01 · Claude** — Flujo de dos niveles en esta página: nuevo estado `idea` +
  vista «💡 Ideas» arriba (base de datos de ideas); promocionar = cambiar `estado` a
  `pendiente` en la tabla. Fix del widget del teclado Akko por cable (transporte real,
  sin batería inventada). Investigado el falso positivo del *running pulse* de agentes.
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
