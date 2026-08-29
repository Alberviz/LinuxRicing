# Runbook de Notificaciones de Agentes de IA en Caelestia

Guía de uso y referencia operativa del sistema de notificaciones enriquecidas e indicadores de estado en los pips de workspace de la barra de Caelestia.

---

## 1. Visión General

Cuando un agente de IA (Claude, Gemini, Antigravity, scripts de compilación, etc.) finaliza una tarea en segundo plano dentro de un terminal de Hyprland, este subsistema garantiza que el usuario reciba:

1. **Toast nativo enriquecido** (arriba a la derecha): Muestra el nombre del agente, proyecto Git, tarea realizada, duración y workspace. Permite hacer clic para saltar y enfocar la ventana directamente.
2. **Halo de acento persistente en el pip del workspace** (`AgentBg`): La barra de Caelestia ilumina el número del espacio de trabajo donde terminó el agente.
3. **Puntito de «sin ver» (*unseen dot*)**: Un punto circular de acento en la esquina del pip indica que la notificación no ha sido inspeccionada.
4. **Tarjeta de detalle en hover (`AgentsPopout`)**: Al pasar el ratón por encima del pip, se despliega una tarjeta con los metadatos completos y el tiempo relativo transcurrido. Al desplegarse, apaga el puntito de «sin ver».
5. **Auto-descarte inteligente**: El halo se apaga automáticamente al enfocar la ventana del terminal o al entrar al workspace si la ventana ya fue cerrada.

---

## 2. Comandos de Lanzamiento y Uso

El script CLI `agent-notify` gestiona la captura del contexto de Hyprland y la comunicación con Quickshell e IPC.

### A. Forma Recomendada: Envoltorio (`run`)

Captura automáticamente la hora de inicio y fin para calcular la duración real de ejecución, además de registrar la ventana activa (`address`), el espacio de trabajo actual (`ws`) y el repositorio Git (`dir`). Al finalizar, propaga el mismo código de salida que el comando ejecutado.

```bash
agent-notify run -n <NombreAgente> -t "<descripción de tarea>" -- <comando...>
```

**Ejemplos prácticos:**

```bash
# Ejecución de sesión interactiva de Claude
agent-notify run -n Claude -t "Refactorización de notificaciones" -- claude

# Ejecución de tarea desasistida de Gemini Antigravity
agent-notify run -n Gemini -t "Actualización de notas de arquitectura" -- agy run "..."

# Tarea de compilación o script largo
agent-notify run -n Antigravity -t "Compilación de kernel Linux" -- make -j$(nproc)
```

---

### B. Disparo Directo al Terminar (`notify`)

Útil para integrar al final de scripts existentes, funciones de shell (`.bashrc`/`.zshrc`), traps de finalización o herramientas que ya controlan su propio ciclo de vida.

```bash
agent-notify notify -n <Nombre> -t "<tarea corta>" [-s <estado>] [-d <duración>] [-w <workspace>] [-a <address>]
```

**Parámetros:**
- `-n, --name`: Nombre del agente o herramienta (por defecto: `Agente`).
- `-t, --task`: Texto descriptivo de la tarea realizada (por defecto toma el valor de `--status`).
- `-s, --status`: Estado de finalización (por defecto: `Completado`).
- `-d, --duration`: Texto de duración personalizada (ej. `2m 14s`).
- `-w, --ws`: Forzar ID de workspace (opcional; por defecto detecta la ventana activa vía `hyprctl`).
- `-a, --address`: Forzar dirección de ventana de Hyprland (opcional; ej. `0x5578ab12cd00`).

**Ejemplo:**

```bash
agent-notify notify -n Gemini -t "Sincronización del Vault completada" -d "45s"
```

---

### C. Prueba Rápida del Sistema (`test`)

Inyecta un agente de prueba simulado («Antigravity») en el **workspace activo real** con una duración de `1m 30s` para verificar visualmente el toast, el halo y la tarjeta popout.

```bash
agent-notify test
```

---

### D. Limpieza Global (`clear`)

Elimina todas las notificaciones de agentes registradas en el servicio de Quickshell y apaga inmediatamente todos los halos y puntitos de los pips de workspace.

```bash
agent-notify clear
```

---

## 3. Experiencia Visual e Interacción

```
[ Terminal WS 3 ] ──(termina agente)──> [ Toast nativo (5s) ] + [ Pip WS 3: Halo + Puntito ]
                                                                      │
                                        ┌─────────────────────────────┴─────────────────────────────┐
                                        ▼                                                           ▼
                             [ Hover sobre Pip 3 ]                                       [ Clic en Pip o Toast ]
                                        │                                                           │
                        Despliega tarjeta AgentsPopout                                  Hyprland enfoca terminal
                        Apaga el puntito (markSeen)                                     Auto-descarta notificación
                        Mantiene el halo de acento                                      Halo se apaga
```

### Componentes de la Interfaz:
- **Toast nativo de escritorio:** Se ubica en la esquina superior derecha con el glifo 🤖 en el título, icono de sistema `-i utilities-terminal`, identidad de app `caelestia-agents`, proyecto, tarea, duración y workspace. Expira automáticamente tras ~5 segundos.
- **Pip del Workspace (Barra):**
  - **Halo de acento (`AgentBg.qml`):** Capa con resplandor suave en `m3primary` y desenfoque (*glow*) renderizada dentro del recorte de la barra.
  - **Puntito de novedad:** Rectángulo redondeado de 4 px en la esquina superior del indicador numérico.
  - **Contraste de color:** El dígito del workspace adopta el color `m3onPrimaryContainer` para maximizar la legibilidad sobre el halo luminoso.
- **Tarjeta Popout (`AgentsPopout.qml`):**
  - Al posicionar el cursor sobre el pip, se abre una tarjeta flotante estilizada con tokens Material You.
  - Contiene: Icono `smart_toy`, nombre del agente, texto de la tarea, nombre del proyecto, tiempo relativo (*«hace X min»* o *«ahora mismo»*), duración de ejecución, chip de estado *«✔ Completado»* y mensaje instructivo de navegación.

---

## 4. Ciclo de Vida y Auto-Descarte

El singleton `services/Agents.qml` gestiona el ciclo de vida sin requerir intervención manual constante:

1. **Al enfocar la ventana:** Si el usuario hace clic en el terminal o cambia a él mediante atajos de teclado (`onActiveToplevelChanged`), el agente asociado a esa dirección de ventana (`address`) se descarta automáticamente y el halo se apaga.
2. **Al entrar al workspace (ventana cerrada):** Si el agente terminó en un terminal que se cerró automáticamente al finalizar el comando, al ingresar al espacio de trabajo correspondiente (`onFocusedWorkspaceChanged`), el sistema detecta que la ventana ya no existe en `Hyprland.toplevels` y descarta la notificación.
3. **Persistencia tras expiración del toast:** Si el usuario no atiende el toast durante los primeros 5 segundos, el toast desaparece pero el halo y el puntito del pip se mantienen en la barra hasta que el usuario visite el terminal o limpie el estado.
4. **Deduplicación por terminal:** Si un mismo terminal ejecuta múltiples tareas sucesivas, la nueva finalización reemplaza a la anterior, actualiza la tarea y restablece el estado de «sin ver» (`seen: false`).

---

## 5. Resiliencia y Casos Extremos

- **Degradación sin Quickshell IPC:** Si `quickshell` no se encuentra en ejecución o falla la llamada IPC, `agent-notify` degrada limpiamente a `notify-send` estándar, manteniendo el soporte de foco mediante el hint de escritorio `-h string:address:0x...`.
- **Ventana movida de Workspace:** Si el usuario traslada la ventana del terminal a otro espacio de trabajo antes o después de que finalice, `Agents.liveWs()` consulta en tiempo real `Hyprland.toplevels` y mueve el halo de acento dinámicamente al pip del nuevo workspace.
- **Modo No Molestar (DND) y Pantalla Completa:** Las notificaciones emergentes son suprimidas por la política de Caelestia, pero el halo en la barra y el registro interno en `Agents.qml` se generan con normalidad sin interrumpir.
- **Multi-Monitor:** Cada instancia de la barra en monitores secundarios proyecta el halo sobre el workspace correspondiente respetando `perMonitorWorkspaces`.

---

## 6. Versión 2 — Pulso «en curso» y contorno neón

Implementada en `feat/agent-running-pulse` (commit `ea42e44`). Spec y decisiones:
[`docs/superpowers/specs/2026-08-30-agent-running-pulse-workspace-pip-design.md`](file:///home/alberviz/LinuxRicing/docs/superpowers/specs/2026-08-30-agent-running-pulse-workspace-pip-design.md).

Resumen operativo:

- **Estado `running`:** mientras un agente procesa, el pip de su workspace muestra un
  **contorno neón** (no relleno). Estilo por defecto `blink` (contorno blanco
  parpadeando); alternativa `breathe`. Al terminar, el contorno pasa a **verde fijo**
  del tema y aparece el **badge de «sin ver»** (con contador) en la esquina.
- **Disparo (Claude Code):** hooks en `~/.claude/settings.json` —
  `UserPromptSubmit` → `agent-notify hook prompt`, `Stop` → `agent-notify hook stop`.
  El CLI resuelve el terminal exacto subiendo por el árbol de procesos del hook, así
  que el halo **siempre cae en el workspace correcto**.
- **Disparo (Antigravity):** interceptación de su notificación nativa en `Notifs.qml`
  (no tiene hooks). Con una sola sesión `agy` es fiable; con varias, cae a heurística.
- **CLI nuevo:** `agent-notify start|finish|hook {prompt,stop}`. `run` emite inicio y
  fin. Estilo conmutable: `agent-notify style {blink|breathe|arc}` y
  `agent-notify marker {badge|wedge}` (escriben `~/.config/caelestia/agents-config.json`).

### Limitaciones vigentes

- **Estado `error` (halo ámbar):** aplazado; un `Error (N)` se marca como completado normal.
- **Persistencia en memoria:** `runningAgents` / `completedAgents` viven en el singleton
  QML; `caelestia shell -k` los limpia.
- **Workspaces fuera de rango visible:** si el workspace no está en el grupo paginado
  de la barra (`Config.bar.workspaces.shown`), el halo no se muestra hasta desplazar la paginación.
- **`arc` (spinner girando):** estilo de pulso previsto pero aún no implementado.

---

## 7. Instalación y reproducibilidad

Qué se necesita en la máquina y cómo lo deja `install.sh`:

| Pieza | Origen en el repo | Destino | Lo hace `install.sh` |
| :--- | :--- | :--- | :--- |
| CLI `agent-notify` | `rgb/agent-notify` | `~/.local/bin/agent-notify` | Sí (paso 6c) |
| QML del bar / servicio | `configs/quickshell/caelestia/…` | `~/.config/quickshell/caelestia/…` | Sí (sincronización de configs) |
| Estilo del marcador | — | `~/.config/caelestia/agents-config.json` | Sí, semilla `{ runningStyle: "blink", unseenMarker: "badge" }` si no existe (paso 6e) |
| Hooks de Claude Code | `configs/claude/agent-hooks.json` | `~/.claude/settings.json` (claves `hooks.UserPromptSubmit` y `hooks.Stop`) | Sí si hay `jq`: fusión idempotente con `.bak` (paso 6f); si no, imprime la instrucción |

### Fusión manual de los hooks (sin `jq` o a mano)

```bash
jq -s '.[0] * .[1]' ~/.claude/settings.json configs/claude/agent-hooks.json \
  > ~/.claude/settings.json.new && mv ~/.claude/settings.json.new ~/.claude/settings.json
```

Los hooks se cargan **al arrancar cada sesión de Claude Code**: una sesión ya abierta
antes de instalarlos no dispara el pulso hasta relanzar `claude`.

- `UserPromptSubmit` → `agent-notify hook prompt` (marca `running`, lee `cwd`/`prompt` del JSON por stdin).
- `Stop` → `agent-notify hook stop` (marca `completed` + toast).

Ambos comandos van con `>/dev/null 2>&1 || true` para no ensuciar el contexto ni bloquear el prompt.

**Antigravity** no usa hooks: lo intercepta `services/Notifs.qml` a partir de su
notificación nativa de kitty.

---

## 8. Sonidos de notificación

`services/Agents.qml` reproduce un sonido corto *fire-and-forget* (`pw-play`) en tres
momentos, enganchado en `start()` y `_addCompleted()` — cubre tanto la vía del CLI
`agent-notify` como la interceptación de notificaciones nativas de Antigravity:

| Evento | Propiedad | Sonido (paleta `system`) |
| --- | --- | --- |
| Agente inicia tarea | `soundStart` | `audio-volume-change.oga` |
| Agente completa | `soundComplete` | `complete.oga` |
| Agente termina con `Error (N)` o `Cancelado` | `soundError` | `dialog-error.oga` |

A diferencia del halo ámbar (aplazado), el sonido **sí** distingue el estado de error:
`_addCompleted()` comprueba `status` contra `/error|cancel|fall/i`.

### Paletas

`rgb/sounds/<paleta>/{start,complete,error}.ogg` — `install.sh` las despliega a
`~/.config/caelestia/sounds/`. Incluidas: `system` (freedesktop), `kenney-soft`,
`kenney-glass`, `kenney-arcade` (Kenney Interface Sounds, CC0). Ver
[`rgb/sounds/README.md`](file:///home/alberviz/LinuxRicing/rgb/sounds/README.md).

```bash
agent-notify sound-set                  # lista paletas
agent-notify sound-preview kenney-soft   # audición: start → complete → error
agent-notify sound-set kenney-soft       # activar
agent-notify sound {on|off}              # interruptor global
```

### Configuración

Claves en `~/.config/caelestia/agents-config.json`, recargadas en caliente:

- `soundEnabled` (bool) — interruptor global.
- `soundVolume` (0.0–1.0, por defecto `0.6`).
- `soundStart`, `soundComplete`, `soundError` — rutas absolutas (las escribe `sound-set`,
  o apúntalas a mano a cualquier `.oga`/`.wav`/`.ogg`).

El sonido se **omite** si el modo No Molestar (`Notifs.dnd`) está activo, igual que los toasts.

---

## 9. Documentación y Especificaciones Relacionadas

- **Especificación de Diseño:** [`docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md`](file:///home/alberviz/LinuxRicing/docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md)
- **Plan de Implementación:** [`docs/superpowers/plans/2026-08-29-agent-notifications-workspace-pip.md`](file:///home/alberviz/LinuxRicing/docs/superpowers/plans/2026-08-29-agent-notifications-workspace-pip.md)
- **Nota de Arquitectura y Widgets:** [[Notificaciones de Agentes]]
- **Registro de Pruebas de QA:** [[QA · Notificaciones de Agentes]]
