---
tags: [tarea-agente, gemini, documentacion, vault, agentes]
para: Gemini
de: Claude
creado: 2026-08-29
estado: pendiente
modelo-sugerido: Gemini 2.5 Pro (hay que leer y sintetizar spec + plan y escribir prosa de vault coherente)
---

# Gemini · Documentación del sistema de notificaciones de agentes

> **Eres el agente `agent-notif-docs`.** Este documento es tu única fuente de instrucciones.
> Léelo entero antes de tocar nada. No tienes contexto previo de esta sesión.

## 0. Contexto en una frase

Claude y otros dos agentes de Gemini están implementando un sistema nuevo: cuando un
agente de IA termina en un terminal, sale un toast rico y **el pip de su workspace en la
barra de Caelestia se enciende** (con un puntito de "sin ver"); hover sobre el pip → tarjeta
con el detalle; clic → Caelestia te lleva. Tú escribes **toda la documentación** de esto:
el runbook de uso, la nota de vault, la entrada de la base de datos de errores, y las
actualizaciones de arquitectura/roadmap/QA.

## 1. Lee primero (en este orden)

1. `/home/alberviz/LinuxRicing/CLAUDE.md` — flujo de ramas, coordinación multi-agente.
2. `docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md` — **el diseño completo. Es tu fuente de verdad. No inventes comportamiento que no esté aquí o en el plan.**
3. `docs/superpowers/plans/2026-08-29-agent-notifications-workspace-pip.md` — **Task 8** (el checklist manual del paso 2 es la base de tu nota de QA) y la tabla de estructura de archivos.
4. Ejemplos de estilo de la casa en el vault:
   - `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md` (formato de entrada: síntoma · causa · arreglo — **añade, no reescribas**)
   - `vault/Rice LinuxRicing/00 - Arquitectura/QA · Motor de Batería.md` (formato de nota de QA)
   - `vault/Rice LinuxRicing/00 - Arquitectura/Arquitectura General del Setup.md`
   - `vault/Rice LinuxRicing/00 - Arquitectura/Roadmap Maestro de Innovaciones.md`
   - `vault/Rice LinuxRicing/01 - Linux/Widgets/` (nivel y tono de las notas de feature)

## 2. Rama y aislamiento

```
cd /home/alberviz/LinuxRicing
git worktree add .worktrees/gemini-agent-docs -b feat/agent-notif-docs feat/agent-notifications
cd .worktrees/gemini-agent-docs
```

- Trabaja **solo** en `docs/` y `vault/`.
- **NO toques** `rgb/`, `configs/`, `widgets/`, `install.sh`, ni `README.md` (lo está editando Alberto ahora mismo).
- **Nunca `git add -A` / `git add .`** — añade rutas explícitas (hay cambios de Alberto sin commitear en el árbol).
- Commits terminan con `Co-Authored-By: Gemini <noreply@google.com>`.
- Todo en **español con tildes**.

## 3. Entregables

### 3a. `docs/AGENT_NOTIFICATIONS.md` (nuevo) — runbook de uso
- Cómo lanzar un agente con aviso:
  - `agent-notify run -n <Nombre> -t "<tarea corta>" -- <comando…>` — forma recomendada (captura inicio y fin → duración real).
  - `agent-notify notify -n <Nombre> -t "<tarea>" [-w N] [-a 0x…]` — disparo directo al terminar.
  - `agent-notify clear` — apaga todos los pips.
  - `agent-notify test` — inyecta un agente de prueba en el workspace activo.
- Qué se ve: toast rico arriba a la derecha (agente · proyecto · tarea · WS · duración · "clic para enfocar") + el pip del workspace encendido con puntito + tarjeta al hover + clic para saltar.
- Cómo se apaga un pip: al enfocar la ventana del agente, o al entrar a su workspace si la ventana ya no existe, o con `agent-notify clear`.
- Limitaciones v1: sin estado "en curso"; la lista no persiste al reiniciar el shell; un agente en un workspace fuera del grupo mostrado en la barra no pinta pip.
- Enlaza al spec y al plan.

### 3b. Entrada en `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md`
Añade bajo `## 2026-08-29` (el plan Task 8 paso 4 trae el texto propuesto; puedes mejorarlo):
- Síntoma: al encoger la notificación de agente a un circulito, el fondo oscuro seguía a ~360px y los `ClippingRectangle` cortaban la burbuja/números.
- Causa: en Caelestia los paneles del cajón comparten un `BlobGroup` (metabola SDF), cada delegado va en `ClippingRectangle`, y `sidebar` ancla a `notifications.bottom`. Meter algo persistente y pequeño ahí choca con las 4 cosas a la vez. Revertido en `e6569fc`.
- Arreglo: rediseño (rama `feat/agent-notifications`) — el estado vive en el pip del workspace (halo estilo `OccupiedBg` + puntito), el detalle en un popout de barra, el clic lo resuelve Caelestia. Spec: `docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md`.

### 3c. `vault/Rice LinuxRicing/01 - Linux/Widgets/Notificaciones de Agentes.md` (nuevo) — nota de feature
- Qué problema resuelve (los 3 del spec §Problema: cero contexto, fugacidad, sin vuelta atrás).
- Cómo funciona el flujo (resume el §"Flujo de datos" del spec).
- Los estados del pip: normal / activo / **agente terminó ahí** (halo de acento + puntito "sin ver").
- Piezas: `rgb/agent-notify`, `services/Agents.qml`, `AgentBg.qml`, `AgentsPopout.qml`, la rama `workspaces` de `Bar.qml::checkPopout`.
- Wikilinks a: la nota de la barra/Caelestia si existe, la Base de Datos de Errores, el spec.
- Qué quedó fuera de v1 (estado "en curso", etc.).

### 3d. Actualizar `Arquitectura General del Setup.md` y `Roadmap Maestro de Innovaciones.md`
- En Arquitectura General: un párrafo o entrada sobre el subsistema de notificaciones de agentes (dónde vive, qué lo dispara).
- En el Roadmap: si hay una fila relacionada, márcala; si no, añade "Notificaciones de agentes en el pip del workspace" como **hecho (v1)** con nota de lo que falta (estado "en curso").

### 3e. `vault/Rice LinuxRicing/00 - Arquitectura/QA · Notificaciones de Agentes.md` (nuevo)
Copia el checklist manual de **Task 8 paso 2** del plan como lista de QA reutilizable
(formato de `QA · Motor de Batería.md`): casos, resultado esperado, casilla. Incluye
multi-monitor, DND, y el auto-descarte.

## 4. Verificación

- Los `.md` renderizan bien (sin frontmatter roto, wikilinks válidos).
- La entrada de la Base de Datos de Errores está **añadida**, no sobrescribe nada.
- Nada fuera de `docs/` y `vault/` tocado: `git diff --stat feat/agent-notifications..HEAD` solo muestra esas dos carpetas.

## 5. Cuando termines

- Deja la rama `feat/agent-notif-docs` lista. **NO la mergees** — lo hace Claude.
- Informe en `vault/Rice LinuxRicing/00 - Arquitectura/Tareas de Agentes/Gemini · Documentación notificaciones de agentes — INFORME.md`:
  - Archivos creados/editados + commits.
  - Cualquier hueco del spec/plan que hayas tenido que rellenar con criterio (y con qué).
- Avisa a Alberto.
