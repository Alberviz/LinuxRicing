---
tags: [qa, testing, checklist, agentes, notificaciones, barra, quickshell]
actualizado: 2026-08-29
relacionado: "[[Base de Datos de Errores]]", "[[Notificaciones de Agentes]]", "[[Arquitectura General del Setup]]"
---

# QA · Notificaciones de Agentes — Registro de Pruebas y Bugs

> [!info] Cómo funciona esto
> Este documento contiene el protocolo de verificación manual para validar de extremo a extremo el sistema de notificaciones de agentes en la barra de Caelestia y Hyprland.
> 
> Si encuentras cualquier comportamiento inesperado o regresión gráfica, **añade una entrada al final en la sección de Bugs** siguiendo la plantilla. El agente asignado reproducirá y resolverá el problema marcándolo `✅ resuelto`.

---

## 🛠️ Estado del Sistema

- **Implementación base:** Rama `feat/agent-notifications` (QML + Python CLI + Popouts).
- **Componentes:** `rgb/agent-notify`, `services/Agents.qml`, `AgentBg.qml`, `Workspace.qml`, `AgentsPopout.qml`, `Bar.qml::checkPopout`.
- **Despliegue CLI:** `~/.local/bin/agent-notify` (vía `install.sh`).
- **Tests unitarios automáticos:** 7 tests pytest en `rgb/tests/test_agent_notify.py` (ejecutar con `pytest rgb/tests/test_agent_notify.py`).

---

## 📋 Checklist de Pruebas Manuales Integradas

Asegúrate de que Quickshell está corriendo (`caelestia shell -d` o revisando que `INFO: Configuration Loaded` aparezca sin errores de propiedades QML).

### 1. Envoltorio de Ejecución (`agent-notify run`)
Lanza un comando envuelto en el workspace actual para verificar la medición de tiempo y el auto-descarte inmediato:

```bash
agent-notify run -n Claude -t "Sleep de prueba" -- sleep 3
```

- [ ] Tras 3 segundos, aparece el toast enriquecido arriba a la derecha con el glifo **🤖 Claude · LinuxRicing**, app `caelestia-agents` (icono `utilities-terminal`), y cuerpo *«Sleep de prueba · 3s · Workspace N · Clic para enfocar»*.
- [ ] Como el comando se ejecutó en la ventana activa actual, al mantener o retomar el foco en el terminal, la notificación se auto-descarta de inmediato.
- [ ] El código de salida del comando envuelto se propaga correctamente al shell.

---

### 2. Notificación Directa en Workspace Remoto (Persistente)
Simula la finalización de un agente en otro espacio de trabajo con una dirección de ventana persistente:

```bash
agent-notify notify -n Gemini -t "Sincronización del Vault" -w 4 -a 0xbeef
```

- [ ] **Toast de escritorio:** Aparece arriba a la derecha con el glifo 🤖 e identidad de app `caelestia-agents` (icono `utilities-terminal`), mostrando los datos del agente (**🤖 Gemini · LinuxRicing** / *«Sincronización del Vault · Workspace 4 • Clic para enfocar»*).
- [ ] **Pip de Workspace en Barra:** El número «4» en la barra de workspaces enciende un halo luminoso de acento (`AgentBg`) con glow.
- [ ] **Puntito de «Sin Ver»:** En la esquina superior derecha del número «4» aparece un punto circular de color primario (`m3primary`).
- [ ] **Color de texto:** El dígito «4» vira a `m3onPrimaryContainer` para mantener contraste sobre el halo.
- [ ] **Expiración de Toast:** A los ~5 segundos, el toast nativo desaparece de la pantalla, pero el **halo y el puntito permanecen encendidos** en el pip 4.

---

### 3. Inspección mediante Hover (`AgentsPopout`) y Descarte del Puntito
Pasa el cursor del ratón sobre el pip del Workspace 4:

- [ ] **Despliegue del Popout:** Se abre una tarjeta flotante estilizada alineada verticalmente con el pip 4.
- [ ] **Contenido de la tarjeta:**
  - Icono `smart_toy` en color primario junto a «Gemini».
  - Texto descriptivo: *«Sincronización del Vault»*.
  - Metadatos: *«LinuxRicing • hace 0 min / ahora mismo»*.
  - Chip redondeado *«✔ Completado»* en `m3primaryContainer`.
  - Texto pie: *«Clic en el workspace para saltar ahí»*.
- [ ] **Apagado del puntito (`markSeen`):** En cuanto se despliega la tarjeta, el puntito circular del pip desaparece suavemente.
- [ ] **Persistencia del halo:** El halo luminoso de acento detrás del «4» **sigue activo**.
- [ ] **Hover en otros workspaces:** Pasar el ratón por workspaces sin agentes no abre ningún popout ni arroja advertencias.

---

### 4. Navegación con Clic y Foco
Realiza una de las dos acciones de navegación:

- [ ] **Opción A (Clic en Pip):** Al hacer clic sobre el pip «4», Hyprland cambia instantáneamente al Workspace 4.
- [ ] **Opción B (Clic en Toast):** Si el toast aún está visible, hacer clic izquierdo sobre él invoca `Agents.focus()` y enfoca la ventana directamente.

---

### 5. Auto-Descarte Inteligente de Halo
Verifica los dos escenarios de limpieza automática:

- [ ] **Escenario 1 (Foco en ventana activa):** Al enfocar la ventana asociada (`address: 0xbeef` o ventana real), `onActiveToplevelChanged` invoca `dismissByAddress` y el halo del workspace se apaga por completo.
- [ ] **Escenario 2 (Ventana cerrada al cambiar de WS):** Si la ventana del terminal ya no existe en `Hyprland.toplevels`, al cambiar al workspace (`onFocusedWorkspaceChanged`), el sistema purga la entrada y apaga el halo sin requerir interacción adicional.

---

### 6. Casos Especiales y Resiliencia

- [ ] **Limpieza Global (`agent-notify clear`):**
  ```bash
  agent-notify notify -n Claude -t "Prueba 1" -w 3 -a 0x1111
  agent-notify notify -n Gemini -t "Prueba 2" -w 5 -a 0x2222
  agent-notify clear
  ```
  Todos los halos y puntitos de los workspaces se apagan inmediatamente.
- [ ] **Modo No Molestar (DND):**
  Activa el modo DND en Caelestia y lanza una notificación.
  - El toast emergente no debe aparecer (respetando la supresión de popups).
  - El halo y el puntito en el pip del workspace **sí deben encenderse**.
- [ ] **Multi-Monitor:**
  En configuraciones con más de una pantalla, el halo del workspace se renderiza en la barra de cada monitor donde dicho workspace esté mapeado.
- [ ] **Ventana movida de Workspace:**
  Lanza un agente en una ventana real, muévela a otro workspace con `Super + Shift + N` antes de interactuar. El halo debe acompañar a la ventana al nuevo workspace (`Agents.liveWs`).
- [ ] **Deduplicación por Terminal:**
  Lanzar dos comandos consecutivos en la misma ventana debe mantener una única tarjeta en el popout, actualizada con la última tarea y reseteando `seen: false`.

---

## 🐞 Plantilla de Bug (Copiar si encuentras un fallo)

```markdown
### BUG-NNN · <Título corto del problema>
- **estado:** 🔴 abierto
- **dónde:** <agent-notify / Agents.qml / AgentBg.qml / AgentsPopout.qml / Bar.qml>
- **repro:** <Pasos exactos para reproducir>
- **esperado:** <Comportamiento esperado según diseño>
- **real:** <Comportamiento erróneo observado>
- **notas:** <Logs de Quickshell, journalctl o capturas>
```

---

## 📝 Registro de Bugs

<!-- Añadir nuevos bugs aquí abajo -->

*(Ningún bug pendiente registrado actualmente).*
