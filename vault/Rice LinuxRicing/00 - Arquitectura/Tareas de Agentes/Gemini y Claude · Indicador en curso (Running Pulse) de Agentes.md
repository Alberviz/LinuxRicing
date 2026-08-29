---
tipo: tarea
estado: planificado
asignado: Claude & Gemini
prioridad: alta
fecha_creacion: 2026-08-29
fecha_objetivo: 2026-08-30
tags:
  - agentes
  - quickshell
  - qml
  - running-pulse
  - hyprland
---

# Tarea: Indicador «En Curso» (*Running Pulse*) de Agentes en Pip de Workspace

## 1. Contexto y Objetivos

Con la **Fase 1 (v1)** de notificaciones de agentes terminada y mergeada en `main`, los agentes avisan cuando completan una tarea mostrando un halo sólido y un puntito de «sin ver» en el pip del workspace, además de un toast interactivo.

**Fase 2 (Esta tarea):**
Implementar el estado **«En Curso» (*Running*)**:
1. Mientras un agente de IA (Antigravity, Gemini, Claude Code) está pensando o ejecutando herramientas, el pip del workspace donde reside muestra una **respiración/pulso luminoso suave** (animación de opacidad y escala continua).
2. Color diferenciado para ejecución (color secundario/terciario) vs completado (primario sólido).
3. Soporte en el CLI `agent-notify` para `start`, `finish` y ejecución con `run`.
4. Visualización en la tarjeta flotante `AgentsPopout.qml` del tiempo en vivo y la tarea activa.
5. Transición automática a `completed` al finalizar el comando/prompt.

---

## 2. Documentos de Referencia Canónicos

1. **Especificación de Diseño v2:**
   - [`docs/superpowers/specs/2026-08-30-agent-running-pulse-workspace-pip-design.md`](file:///home/alberviz/LinuxRicing/docs/superpowers/specs/2026-08-30-agent-running-pulse-workspace-pip-design.md)
2. **Especificación de Diseño v1:**
   - [`docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md`](file:///home/alberviz/LinuxRicing/docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md)
3. **Runbook Operativo de Notificaciones:**
   - [`docs/AGENT_NOTIFICATIONS.md`](file:///home/alberviz/LinuxRicing/docs/AGENT_NOTIFICATIONS.md)
4. **Nota de Feature en el Vault:**
   - [[Rice LinuxRicing/01 - Linux/Widgets/Notificaciones de Agentes|Notificaciones de Agentes en Workspaces]]

---

## 3. Reparto de Trabajo Recomendado

- **Gemini (`vault/`, `docs/`, `agent-notify` CLI, tests Python):**
  - Actualizar `rgb/agent-notify` con los subcomandos `start` y `finish`.
  - Añadir tests unitarios en `rgb/tests/test_agent_notify.py` para el ciclo de vida `running` ➔ `completed`.
  - Documentar en el Vault y actualizar runbooks.
- **Claude (`configs/quickshell/caelestia/`, QML UI):**
  - Modificar `services/Agents.qml` para gestionar `runningAgents` e IPC `start`/`complete`.
  - Implementar en `AgentBg.qml` las animaciones de pulso (`SequentialAnimation on opacity / scale`).
  - Actualizar `AgentsPopout.qml` para renderizar la sección de agentes activos con temporizador dinámico.
  - Sincronizar y verificar en vivo con el reinicio de Quickshell.

---

## 4. Criterios de Aceptación (DoD)

- [ ] `agent-notify start -n Claude -t "Compilando kernel"` enciende el pulso luminoso en el workspace del terminal.
- [ ] El pulso oscila suavemente (periodo ~1.5s) sin consumir excesiva CPU.
- [ ] Al ejecutar `agent-notify notify` / `finish`, el pulso se transforma limpiamente en el halo sólido y puntito de sin ver de v1.
- [ ] Al enfocar la ventana o hacer clic en el workspace, ambos estados se descartan limpiamente.
- [ ] Todos los tests de `pytest rgb/tests/test_agent_notify.py` pasan al 100%.
- [ ] Shell reiniciado sin errores de QML.
