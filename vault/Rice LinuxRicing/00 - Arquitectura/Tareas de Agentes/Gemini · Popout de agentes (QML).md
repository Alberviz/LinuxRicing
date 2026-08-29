---
tags: [tarea-agente, gemini, qml, caelestia, agentes]
para: Gemini
de: Claude
creado: 2026-08-29
estado: pendiente
modelo-sugerido: Gemini 2.5 Pro (QML nuevo + encaje con el estilo Caelestia + resolución de imports)
---

# Gemini · Popout de agentes (tarjeta al hover del pip)

> **Eres el agente `agents-popout`.** Este documento es tu única fuente de instrucciones.
> Léelo entero antes de tocar nada. No tienes contexto previo de esta sesión.

## 0. Contexto en una frase

Cuando un agente de IA termina en un terminal, el **pip de su workspace** en la barra de
Caelestia se enciende, y al hacer **hover** sobre ese pip debe salir una **tarjeta** con
el agente, la tarea, el proyecto y "terminó hace X min". Tú construyes esa tarjeta y la
registras en el sistema de popouts de la barra. El disparador del hover (en `Bar.qml`) y
el servicio `Agents` los hace Claude — tú **codificas contra su API, no la implementas**.

## 1. Lee primero (en este orden)

1. `/home/alberviz/LinuxRicing/CLAUDE.md` — flujo de ramas, coordinación multi-agente, **reinicio obligatorio del shell tras cambios QML**.
2. `docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md` — el diseño. Secciones **§Componentes → 4 (`AgentsPopout.qml`) y 5 (`Content.qml`)** y **§Arquitectura**.
3. `docs/superpowers/plans/2026-08-29-agent-notifications-workspace-pip.md` — **Task 5 entera** (trae el código completo de `AgentsPopout.qml` y los cambios de `Content.qml` / `PopoutState.qml`). Lee también **"Contrato de datos → API pública de `Agents`" y "Entrada de `Agents.completedAgents`"**. Ignora las demás tasks.
4. Estilo de la casa — otros popouts de barra, para el tono visual y **cómo resuelven los imports** (mismo directorio, sin import explícito):
   - `configs/quickshell/caelestia/modules/bar/popouts/Battery.qml`
   - `configs/quickshell/caelestia/modules/bar/popouts/Bluetooth.qml`
   - `configs/quickshell/caelestia/modules/bar/popouts/Content.qml` (el `component Popout`, y cómo se listan `Battery`, `Network`, etc.)
   - `configs/quickshell/caelestia/modules/bar/popouts/PopoutState.qml`

## 2. Rama y aislamiento

```
cd /home/alberviz/LinuxRicing
git worktree add .worktrees/gemini-agents-popout -b feat/agents-popout feat/agent-notifications
cd .worktrees/gemini-agents-popout
```

- Trabaja **solo** en:
  - `configs/quickshell/caelestia/modules/bar/popouts/AgentsPopout.qml` (**nuevo**)
  - `configs/quickshell/caelestia/modules/bar/popouts/Content.qml` (añadir un `Popout { name: "agents" }`)
  - `configs/quickshell/caelestia/modules/bar/popouts/PopoutState.qml` (añadir `property int agentsWs: 0`)
- **NO toques** `services/Agents.qml`, `modules/bar/Bar.qml`, `modules/bar/components/workspaces/*`, `rgb/`, `docs/`, `vault/`, `README.md`. Son de Claude o de Alberto.
- **Nunca `git add -A` / `git add .`**.
- Commits terminan con `Co-Authored-By: Gemini <noreply@google.com>`.
- **Textos de usuario en español con tildes** (`qsTr("Clic en el workspace para saltar ahí")`, "hace %1 min", "Completado"…).

## 3. El contrato: API de `Agents` (la hace Claude — TÚ SOLO LA CONSUMES)

`import qs.services` → `Agents`. No la modifiques. Codifica contra esto:

- `Agents.agentsForWs(n: int) -> array` de entradas (vacío si ninguna).
- Cada **entrada**: `{ id, name, task, status, dir, ws, address, duration, time: <Date>, seen: bool }`.
- (También existen `wsMap`, `hasUnseenForWs`, `markSeen`, `focus` — no los necesitas para la tarjeta.)

Tu `AgentsPopout` recibe `required property int ws` y pinta `Agents.agentsForWs(ws)` (normalmente 1 tarjeta, puede haber varias). Si la lista queda vacía mientras está abierto, no hace falta que lo cierres tú — de eso se encarga `Bar.qml`.

## 4. Alcance exacto

Ejecuta **Task 5** del plan, pasos 1-5:

1. Crear `AgentsPopout.qml` (el plan trae el código completo: `Column` de `StyledRect` con cabecera `smart_toy` + nombre, tarea, `dir • hace Xm • en <duración>`, chip "Completado", pie "Clic en el workspace para saltar ahí"). Ajusta el estilo para que case con `Battery.qml`/`Bluetooth.qml` (tokens de padding/rounding/tipografía reales de Caelestia — **verifica los nombres de token**, no inventes; `rounding` real: `extraSmall/small/medium/large/…/full`).
2. `PopoutState.qml`: `property int agentsWs: 0`.
3. `Content.qml`: `Popout { name: "agents"; sourceComponent: AgentsPopout { ws: root.popouts.agentsWs } }`. Comprueba cómo resuelve `Battery` (mismo directorio) y replica el mecanismo de import.
4. Sincronizar a `~/.config/quickshell/caelestia/modules/bar/popouts/` y recargar el shell:
   ```
   caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
   ```
   Esperado: `INFO: Configuration Loaded`, sin errores `AgentsPopout` / `Content` / `PopoutState`. (El popout **no se mostrará todavía** — el disparador del hover lo añade Claude en Task 6. Basta con que el shell cargue limpio y `qmllint` no proteste.)
5. Commit.

## 5. Verificación

```
qmllint configs/quickshell/caelestia/modules/bar/popouts/AgentsPopout.qml \
        configs/quickshell/caelestia/modules/bar/popouts/Content.qml \
        configs/quickshell/caelestia/modules/bar/popouts/PopoutState.qml
```
Sin errores nuevos. Shell recarga con `INFO: Configuration Loaded`.

Prueba opcional (si quieres ver la tarjeta aislada): añade temporalmente en `Content.qml`
un `Popout { name: "agents" }` visible y fuérzalo — pero **revierte** ese hack antes del commit.

## 6. Cuando termines

- Deja la rama `feat/agents-popout` lista. **NO la mergees** — lo hace Claude.
- Informe en `vault/Rice LinuxRicing/00 - Arquitectura/Tareas de Agentes/Gemini · Popout de agentes — INFORME.md`:
  - Archivos creados/editados + commits.
  - Salida de `qmllint` y del log del shell (`journalctl --user -t quickshell -n 40 --no-pager`).
  - Cómo resolviste el import de `AgentsPopout` en `Content.qml`.
  - Dudas sobre el contrato de `Agents` o desviaciones.
- Avisa a Alberto.
