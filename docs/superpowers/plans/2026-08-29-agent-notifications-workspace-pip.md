# Notificaciones de agentes en el pip del workspace — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que al terminar un agente de IA en un terminal, el pip de su workspace en la barra de Caelestia se encienda (con un puntito de "sin ver"), un hover muestre una tarjeta con el detalle, y el clic ya te lleve — manteniendo el toast nativo rico arriba a la derecha.

**Architecture:** `rgb/agent-notify` (Python, stdlib) captura ventana/workspace/proyecto al terminar el agente y (1) llama por IPC a `qs -c caelestia ipc call agents notify <json>` y (2) lanza `notify-send`. El singleton QML `services/Agents.qml` es la fuente de verdad: mantiene `completedAgents`, resuelve `address → workspace` en vivo y expone `wsMap`/`agentsForWs`/`hasUnseenForWs`/`markSeen`. `Workspace.qml` (+ una capa `AgentBg.qml` estilo `OccupiedBg`) pinta el halo y el puntito. El hover se engancha al sistema de popouts de barra ya existente (`Bar.qml::checkPopout` + un `Popout { name: "agents" }`). El clic lo resuelve Caelestia sin cambios.

**Tech Stack:** Python 3.14 (solo stdlib: `sys`, `os`, `json`, `subprocess`, `argparse`, `time`, `pathlib`), pytest para el CLI, Quickshell/QML (Caelestia), Hyprland IPC (`Quickshell.Hyprland`).

**Spec:** `docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md`

## Global Constraints

- **Rama:** `feat/agent-notifications` (ya creada desde `main`). El spec ya está commiteado ahí.
- **Sin dependencias nuevas de Python.** `agent-notify` usa solo stdlib. Un archivo, sin módulos compartidos (patrón del repo).
- **Coordinación multi-agente:** Gemini trabaja en `vault/` y puede tener `README.md` sin commitear. **Nunca `git add -A`/`git add .`** — añadir siempre archivos explícitos en cada paso "Commit".
- **Textos de usuario en español con tildes** (`qsTr("Completado")`, "terminó hace…"). Nunca ASCII-plano por acentos.
- **Nombres de token QML:** verificar contra Caelestia, no inventar. Rounding real: `extraSmall/small/medium/large/largeIncreased/extraLarge/…/full` (no existe `normal`). Ver `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md`.
- **Tras tocar cualquier QML/widget** (CLAUDE.md): copiar el archivo editado a `~/.config/quickshell/caelestia/` (misma ruta relativa) y reiniciar el shell:
  ```bash
  caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
  ```
  Comprobar en la salida `INFO: Configuration Loaded` sin errores de sintaxis/propiedades QML.
- **No hay tests automáticos de QML en este repo.** La verificación de tareas QML es: shell recarga limpio + checklist manual del propio paso.
- **Fin de cada mensaje de commit:**
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01RGcWYEErnvNrdPk9CQooYE
  ```

---

## Estructura de archivos

| Archivo | Responsabilidad |
| --- | --- |
| `rgb/agent-notify` (modificar) | CLI Python. Captura contexto de la ventana, construye el payload, IPC + `notify-send`. Añade `--task`, `build_parser()`, `build_agent_data()`; `test` inyecta en el workspace activo. |
| `rgb/tests/test_agent_notify.py` (nuevo) | Tests del CLI: parseo de flags/subcomandos, forma del payload, fallback sin `hyprctl`, propagación de código de salida de `run`. |
| `configs/quickshell/caelestia/services/Agents.qml` (modificar) | Fuente de verdad. Entrada con `task`+`seen`; `wsMap`, `liveWs`, `agentsForWs`, `hasUnseenForWs`, `markSeen`; auto-descarte al enfocar la ventana o entrar a su workspace ya cerrada. |
| `configs/quickshell/caelestia/modules/bar/components/workspaces/AgentBg.qml` (nuevo) | Capa de halos detrás de los pips con agente. Estilo `OccupiedBg.qml`. |
| `configs/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml` (modificar) | Instanciar `AgentBg` junto a `OccupiedBg`; exponer `wsAt(y)` para el hit-test del hover. |
| `configs/quickshell/caelestia/modules/bar/components/workspaces/Workspace.qml` (modificar) | Puntito interior de "sin ver" en el pip; virar el color del texto cuando hay agente. |
| `configs/quickshell/caelestia/modules/bar/popouts/AgentsPopout.qml` (nuevo) | Tarjeta(s) del workspace en hover: agente, tarea, proyecto, "terminó hace Xm". |
| `configs/quickshell/caelestia/modules/bar/popouts/Content.qml` (modificar) | `Popout { name: "agents" }`. |
| `configs/quickshell/caelestia/modules/bar/popouts/PopoutState.qml` (modificar) | `property int agentsWs`. |
| `configs/quickshell/caelestia/modules/bar/Bar.qml` (modificar) | Rama `workspaces` en `checkPopout` (+ `markSeen`); **borrar** el `DelegateChoice { roleValue: "agents" }` muerto. |
| `configs/quickshell/caelestia/modules/bar/components/AgentPills.qml` (**borrar**) | Código muerto (nunca se renderiza). |
| `install.sh` (modificar) | Añadir `agent-notify` a la lista de binarios `~/.local/bin`. |
| `docs/RGB_HANDOVER_LINUX.md` o `docs/` runbook (modificar) | Cómo lanzar agentes con notificación (`agent-notify run` / `notify`). |
| `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md` (modificar) | Entrada: el intento anterior (píldora en el cajón) y por qué esta vía lo evita. |

**Nota:** ninguno de estos archivos está en la lista "copias idénticas" de CLAUDE.md (`widgets/Background.qml ⇔ …/background/Background.qml`, `rgb/mchose-battery ⇔ widgets/mchose-battery`). No hay pares gemelos que sincronizar aquí.

---

## Contrato de datos

### Payload IPC  `agents notify <json>`  (lo produce Task 1, lo consume Task 2)

```json
{
  "id": "agent-1756449600000",
  "name": "Claude",
  "task": "rgb: refactor de notificaciones",
  "status": "Completado",
  "dir": "LinuxRicing",
  "ws": 3,
  "address": "0x5578ab12cd00",
  "duration": "2m 14s",
  "terminal": "kitty"
}
```

- `id`: `agent-<epoch_ms>` si no se pasa.
- `task`: texto corto. Si no se pasa `--task`, vale lo mismo que `status`.
- `ws`: entero. `address`: string con o sin prefijo `0x` (Task 2 normaliza).
- Claves siempre presentes; valores pueden ser `""`/`0`.

### Entrada de `Agents.completedAgents`  (define Task 2, consumen Tasks 3–6)

```js
{
  id: "agent-1756449600000",
  name: "Claude",
  task: "rgb: refactor de notificaciones",
  status: "Completado",
  dir: "LinuxRicing",
  ws: 3,                       // workspace capturado al terminar (fallback)
  address: "0x5578ab12cd00",
  duration: "2m 14s",
  time: <Date>,                // Date de llegada
  seen: false                  // pasa a true en el primer hover de su tarjeta
}
```

### API pública de `Agents` (define Task 2)

- `readonly property var wsMap` → `{ [wsId:int]: entry[] }` sobre el workspace **en vivo** de cada agente.
- `function agentsForWs(n: int): var` → array de entradas (vacío si ninguna).
- `function hasUnseenForWs(n: int): bool`.
- `function markSeen(wsOrId): void` — marca `seen:true` las entradas de ese workspace (o la de ese `id`).
- `function focus(address: string): void` — enfoca la ventana y descarta la entrada (ya existe).
- `function clearAll(): void` (ya existe).
- Señales `agentAdded(var)`, `agentRemoved(string)` (ya existen).

---

## Task 1: `agent-notify` — `--task`, refactor testeable, `test` en workspace real

**Files:**
- Modify: `rgb/agent-notify`
- Test: `rgb/tests/test_agent_notify.py` (nuevo)

**Interfaces:**
- Consumes: nada.
- Produces: `build_parser() -> argparse.ArgumentParser`; `build_agent_data(name, status, task, duration, address, ws, terminal) -> dict`; el payload del contrato de datos con la clave nueva `task`.

- [ ] **Step 1: Escribir el test que falla**

Crear `rgb/tests/test_agent_notify.py`:

```python
import importlib.util
import json
from importlib.machinery import SourceFileLoader
from pathlib import Path
import pytest

_SRC = Path(__file__).resolve().parents[1] / "agent-notify"


def _load():
    loader = SourceFileLoader("agent_notify", str(_SRC))
    spec = importlib.util.spec_from_loader("agent_notify", loader)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def an():
    return _load()


def test_build_agent_data_has_all_contract_keys(an):
    d = an.build_agent_data(name="Claude", status="Completado", task="rgb refactor",
                            duration="2m 14s", address="0x1", ws=3, terminal="kitty")
    for k in ("id", "name", "task", "status", "dir", "ws", "address", "duration", "terminal"):
        assert k in d
    assert d["task"] == "rgb refactor"
    assert d["ws"] == 3
    assert d["id"].startswith("agent-")


def test_task_defaults_to_status_when_absent(an):
    d = an.build_agent_data(name="X", status="Completado", task=None,
                            duration="", address="", ws=1, terminal="")
    assert d["task"] == "Completado"


def test_parser_notify_accepts_task_flag(an):
    args = an.build_parser().parse_args(["notify", "-n", "Claude", "-t", "mi tarea"])
    assert args.name == "Claude"
    assert args.task == "mi tarea"


def test_parser_run_captures_remainder(an):
    args = an.build_parser().parse_args(["run", "-n", "Claude", "--", "echo", "hi"])
    assert args.name == "Claude"
    assert args.command[-2:] == ["echo", "hi"]


def test_window_fallback_without_hyprctl(an, monkeypatch):
    def boom(*a, **k):
        raise FileNotFoundError("hyprctl")
    monkeypatch.setattr(an.subprocess, "run", boom)
    win = an.get_hyprland_window()
    assert win["ws_id"] == 1
    assert win["address"] == ""


def test_run_wrapper_propagates_exit_code(an, monkeypatch):
    monkeypatch.setattr(an, "get_hyprland_window", lambda: {
        "address": "0x1", "ws_id": 2, "ws_name": "2", "class": "kitty", "title": "", "pid": 1})
    monkeypatch.setattr(an, "notify_agent", lambda **k: None)

    class R:  # fake CompletedProcess
        returncode = 7
    monkeypatch.setattr(an.subprocess, "run", lambda *a, **k: R())
    with pytest.raises(SystemExit) as e:
        an.run_wrapped_command(["false"], name="Claude")
    assert e.value.code == 7
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `cd rgb/tests && python -m pytest test_agent_notify.py -v`
Expected: FAIL — `build_agent_data` / `build_parser` no existen (`AttributeError`).

- [ ] **Step 3: Refactorizar `agent-notify`**

En `rgb/agent-notify`:

1. Añadir `build_agent_data(...)` extrayendo la construcción del dict de `notify_agent`:

```python
def build_agent_data(name="Agente", status="Completado", task=None, duration="",
                     address="", ws=1, terminal="Terminal"):
    return {
        "id": f"agent-{int(time.time() * 1000)}",
        "name": name,
        "task": task if task else status,
        "status": status,
        "address": address,
        "ws": ws,
        "dir": get_project_name(),
        "duration": duration,
        "terminal": terminal,
    }
```

2. `notify_agent(...)` pasa a aceptar `task=None` y usar el helper:

```python
def notify_agent(name="Agente", status="Completado", task=None, duration="",
                 custom_address=None, custom_ws=None):
    win = get_hyprland_window()
    address = custom_address if custom_address else win["address"]
    ws = custom_ws if custom_ws else win["ws_id"]
    agent_data = build_agent_data(name=name, status=status, task=task, duration=duration,
                                  address=address, ws=ws, terminal=win["class"])
    send_quickshell_ipc(agent_data)
    send_desktop_notification(agent_data)
    print(f"✓ Notificacion enviada: {name} en Workspace {ws} ({agent_data['dir']})")
```

3. `send_desktop_notification`: usar `agent_data["task"]` en el cuerpo en vez de `status` cuando difieran:

```python
    task = agent_data.get("task", "")
    status = agent_data.get("status", "Completado")
    body_parts = [task] if task and task != status else [f"Estado: {status}"]
    if duration:
        body_parts.append(f"Duracion: {duration}")
    body_parts.append(f"Workspace {ws} • Clic para enfocar")
```

4. Extraer `build_parser()` con **todo** el `argparse` actual (parser raíz + subparsers `run`/`notify`/`test`/`clear`), añadiendo `--task`/`-t` al parser raíz y al subparser `notify`:

```python
def build_parser():
    parser = argparse.ArgumentParser(description="Agent Notification & Focus Manager for Caelestia")
    parser.add_argument("--name", "-n", default="Agente")
    parser.add_argument("--status", "-s", default="Completado")
    parser.add_argument("--task", "-t", default=None)
    parser.add_argument("--duration", "-d", default="")
    parser.add_argument("--address", "-a", default=None)
    parser.add_argument("--ws", "-w", default=None, type=int)
    sub = parser.add_subparsers(dest="subcommand")
    rp = sub.add_parser("run")
    rp.add_argument("--name", "-n")
    rp.add_argument("--task", "-t", default=None)
    rp.add_argument("command", nargs=argparse.REMAINDER)
    npx = sub.add_parser("notify")
    npx.add_argument("--name", "-n", default="Agente")
    npx.add_argument("--status", "-s", default="Completado")
    npx.add_argument("--task", "-t", default=None)
    npx.add_argument("--duration", "-d", default="")
    npx.add_argument("--address", "-a", default=None)
    npx.add_argument("--ws", "-w", default=None, type=int)
    sub.add_parser("test")
    sub.add_parser("clear")
    return parser
```

5. `main()` usa `build_parser()` y pasa `task` en las rutas `run`/`notify`/default. `run_wrapped_command` acepta `task` y lo pasa a `notify_agent`.

6. `test` inyecta en el **workspace activo real** (no forzar ws):

```python
    elif args.subcommand == "test":
        notify_agent(name="Antigravity", status="Completado",
                     task="Prueba de notificacion de agente", duration="1m 30s")
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `cd rgb/tests && python -m pytest test_agent_notify.py -v`
Expected: PASS (6 passed).

- [ ] **Step 5: Verificación manual rápida**

Run: `python rgb/agent-notify test` (con el shell corriendo)
Expected: sale el toast arriba a la derecha con "Antigravity" y el cuerpo "Prueba de notificacion de agente · 1m 30s · Workspace N · Clic para enfocar". (El pip aún no reacciona — eso es Task 3.)

- [ ] **Step 6: Commit**

```bash
git add rgb/agent-notify rgb/tests/test_agent_notify.py
git commit -m "feat(agent-notify): add --task, testable build helpers, real-ws test"
```

---

## Task 2: `Agents.qml` — fuente de verdad con estado por workspace

**Files:**
- Modify: `configs/quickshell/caelestia/services/Agents.qml` (reescritura del cuerpo)

**Interfaces:**
- Consumes: payload del contrato (Task 1).
- Produces: la "API pública de `Agents`" del contrato de datos — `wsMap`, `agentsForWs(n)`, `hasUnseenForWs(n)`, `markSeen(wsOrId)`, entrada con `task`/`status`/`seen`/`time`.

- [ ] **Step 1: Reescribir `Agents.qml`**

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

Singleton {
    id: root

    property list<var> completedAgents: []
    readonly property int count: completedAgents.length

    signal agentAdded(var agent)
    signal agentRemoved(string id)

    // Nudge para recomputar wsMap cuando cambia el foco o el nº de ventanas.
    readonly property var wsMap: {
        const _deps = [Hypr.activeWsId, Hyprland.toplevels.values.length, completedAgents.length];
        const m = ({});
        for (const a of root.completedAgents) {
            const w = root.liveWs(a.address, a.ws);
            (m[w] = m[w] || []).push(a);
        }
        return m;
    }

    function _normAddr(addr: string): string {
        if (!addr)
            return "";
        let s = String(addr).toLowerCase();
        return s.startsWith("0x") ? s.slice(2) : s;
    }

    function liveWs(address: string, fallbackWs: int): int {
        const norm = _normAddr(address);
        if (norm) {
            const t = Hyprland.toplevels.values.find(tl => root._normAddr(tl.address) === norm);
            if (t && t.workspace && t.workspace.id)
                return t.workspace.id;
        }
        return fallbackWs || 1;
    }

    function agentsForWs(n: int): var {
        return root.wsMap[n] || [];
    }

    function hasUnseenForWs(n: int): bool {
        return (root.wsMap[n] || []).some(a => !a.seen);
    }

    function notify(dataStr: string): void {
        try {
            const data = typeof dataStr === "string" ? JSON.parse(dataStr) : dataStr;
            if (!data || typeof data !== "object")
                return;

            const address = data.address || "";
            const entry = {
                id: data.id || `agent-${Date.now()}`,
                name: data.name || "Agente",
                task: data.task || data.status || "Completado",
                status: data.status || "Completado",
                dir: data.dir || "",
                ws: data.ws || 1,
                address: address,
                duration: data.duration || "",
                time: new Date(),
                seen: false
            };

            // Una entrada por terminal: una nueva finalizacion reemplaza.
            const na = root._normAddr(address);
            root.completedAgents = [
                ...root.completedAgents.filter(a => a.id !== entry.id && (na === "" || root._normAddr(a.address) !== na)),
                entry
            ];
            root.agentAdded(entry);
        } catch (e) {
            console.warn("Agents.notify: error parsing:", e, dataStr);
        }
    }

    function markSeen(wsOrId): void {
        const target = wsOrId;
        let changed = false;
        root.completedAgents = root.completedAgents.map(a => {
            const match = (typeof target === "number")
                ? root.liveWs(a.address, a.ws) === target
                : a.id === target;
            if (match && !a.seen) {
                changed = true;
                return Object.assign(({}), a, { seen: true });
            }
            return a;
        });
    }

    function focus(address: string): void {
        if (!address || address.length === 0)
            return;
        const target = address.startsWith("0x") ? address : `0x${address}`;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:${target}" })` : `focuswindow address:${target}`);
        root.dismissByAddress(target);
    }

    function dismiss(id: string): void {
        root.completedAgents = root.completedAgents.filter(a => a.id !== id);
        root.agentRemoved(id);
    }

    function dismissByAddress(address: string): void {
        const norm = root._normAddr(address);
        root.completedAgents = root.completedAgents.filter(a => root._normAddr(a.address) !== norm);
    }

    function clearAll(): void {
        root.completedAgents = [];
    }

    // Al enfocar la ventana del agente -> descartar.
    Connections {
        target: Hyprland

        function onActiveToplevelChanged(): void {
            const active = Hyprland.activeToplevel;
            if (active && active.address)
                root.dismissByAddress(active.address);
        }

        // Al entrar a un workspace cuya ventana de agente ya no existe -> descartar.
        function onFocusedWorkspaceChanged(): void {
            const wsId = Hyprland.focusedWorkspace?.id;
            if (!wsId)
                return;
            root.completedAgents = root.completedAgents.filter(a => {
                const onThisWs = root.liveWs(a.address, a.ws) === wsId;
                const stillOpen = Hyprland.toplevels.values.some(t => root._normAddr(t.address) === root._normAddr(a.address));
                return !(onThisWs && !stillOpen);
            });
        }
    }

    IpcHandler {
        target: "agents"

        function notify(data: string): void { root.notify(data); }
        function focus(address: string): void { root.focus(address); }
        function dismiss(id: string): void { root.dismiss(id); }
        function markSeen(ws: int): void { root.markSeen(ws); }
        function clearAll(): void { root.clearAll(); }
        function list(): string { return JSON.stringify(root.completedAgents); }
    }
}
```

- [ ] **Step 2: Sincronizar y recargar el shell**

```bash
cp configs/quickshell/caelestia/services/Agents.qml ~/.config/quickshell/caelestia/services/Agents.qml
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```

Expected: log con `INFO: Configuration Loaded`, sin errores `Agents.qml:` ni `Unable to assign`.

- [ ] **Step 3: Verificar la API por IPC**

```bash
python rgb/agent-notify test
caelestia shell ipc call agents list
```

Expected: `list` devuelve un JSON con un objeto que tiene `task`, `seen:false`, `status`, `time`.

- [ ] **Step 4: Verificar el auto-descarte**

Con el agente inyectado, cambia manualmente al workspace activo que se capturó y vuelve; repite `agents list`.
Expected: si entras en esa misma ventana (la que estaba activa al lanzar `test`), la lista queda vacía. (Es esperable que `test` se auto-descarte enseguida porque se inyecta sobre la ventana activa — para pruebas persistentes usa Task 8.)

- [ ] **Step 5: Commit**

```bash
git add configs/quickshell/caelestia/services/Agents.qml
git commit -m "feat(agents): workspace-aware agent state (wsMap, seen, markSeen, auto-dismiss)"
```

---

## Task 3: `AgentBg.qml` + halo tras el pip

**Files:**
- Create: `configs/quickshell/caelestia/modules/bar/components/workspaces/AgentBg.qml`
- Modify: `configs/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml`

**Interfaces:**
- Consumes: `Agents.wsMap` / `Agents.agentsForWs(n)` (Task 2); patrón de `OccupiedBg.qml` (`workspaces` Repeater, `groupOffset`).
- Produces: componente visual `AgentBg` montado dentro del `StyledClippingRect` de `Workspaces.qml`.

- [ ] **Step 1: Crear `AgentBg.qml`**

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property Repeater workspaces
    required property int groupOffset

    function getWsIdx(ws: int): int {
        let i = ws - 1;
        while (i < 0)
            i += Config.bar.workspaces.shown;
        return i % Config.bar.workspaces.shown;
    }

    Repeater {
        model: ScriptModel {
            // ids de workspace (int) que tienen algun agente
            values: Object.keys(Agents.wsMap).map(k => parseInt(k, 10)).filter(n => Agents.wsMap[n].length > 0)
        }

        StyledRect {
            id: halo

            required property int modelData

            readonly property int idx: root.getWsIdx(modelData)
            readonly property Item pip: root.workspaces.count > idx ? root.workspaces.itemAt(idx) : null
            readonly property bool inGroup: modelData > root.groupOffset && modelData <= root.groupOffset + Config.bar.workspaces.shown

            visible: inGroup && pip
            anchors.horizontalCenter: root.horizontalCenter

            y: (pip?.y ?? 0) - 1
            implicitWidth: Tokens.sizes.bar.innerWidth - Tokens.padding.small + 2
            implicitHeight: (pip?.size ?? 0) + 2
            radius: Tokens.rounding.full

            color: Colours.palette.m3primary
            opacity: 0.22

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.6
                blurMax: 12
            }

            scale: 0
            Component.onCompleted: scale = 1
            Behavior on scale {
                Anim { easing: Tokens.anim.standardDecel }
            }
            Behavior on y {
                Anim {}
            }
        }
    }
}
```

- [ ] **Step 2: Montar `AgentBg` en `Workspaces.qml`**

En `Workspaces.qml`, junto al `Loader` que carga `OccupiedBg` (dentro del `Item` que tiene `anchors.fill: parent`), añadir:

```qml
        AgentBg {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall
            workspaces: workspaces
            groupOffset: root.groupOffset
        }
```

(`workspaces` es el `id` del `Repeater` interno; `root.groupOffset` ya existe en `Workspaces.qml`.)

- [ ] **Step 3: Sincronizar y recargar**

```bash
cp configs/quickshell/caelestia/modules/bar/components/workspaces/AgentBg.qml ~/.config/quickshell/caelestia/modules/bar/components/workspaces/AgentBg.qml
cp configs/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml ~/.config/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```

Expected: `INFO: Configuration Loaded`, sin errores `AgentBg` / `Workspaces`.

- [ ] **Step 4: Verificación manual**

```bash
python rgb/agent-notify notify -n Claude -t "prueba halo" -w 4 -a 0xdead
```

(`-w 4` fuerza un workspace donde no estás, `-a 0xdead` una address inexistente → no se auto-descarta.)
Expected: detrás del "4" en la barra aparece un halo de color de acento con glow. `caelestia shell ipc call agents clearAll` → el halo desaparece.

- [ ] **Step 5: Commit**

```bash
git add configs/quickshell/caelestia/modules/bar/components/workspaces/AgentBg.qml configs/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml
git commit -m "feat(bar): agent halo behind workspace pips (AgentBg)"
```

---

## Task 4: puntito interior de "sin ver" en el pip

**Files:**
- Modify: `configs/quickshell/caelestia/modules/bar/components/workspaces/Workspace.qml`

**Interfaces:**
- Consumes: `Agents.hasUnseenForWs(n)` y `Agents.agentsForWs(n)` (Task 2).
- Produces: nada para otras tareas.

- [ ] **Step 1: Añadir propiedades derivadas y el dot**

En `Workspace.qml`, tras `readonly property bool hasWindows: …`:

```qml
    readonly property bool hasAgent: Agents.agentsForWs(ws).length > 0
    readonly property bool agentUnseen: Agents.hasUnseenForWs(ws)
```

Añadir el import si falta: `import qs.services` (ya está — usa `Hypr`/`Icons`).

Dentro del `StyledText { id: indicator … }`, como hijo:

```qml
        Rectangle {
            width: 4
            height: 4
            radius: 2
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 1
            anchors.topMargin: 1
            color: Colours.palette.m3primary
            visible: scale > 0
            scale: root.agentUnseen ? 1 : 0
            Behavior on scale {
                Anim { easing: Tokens.anim.standardDecel }
            }
        }
```

Y en `indicator.color`, añadir el caso "hay agente" para contraste sobre el halo:

```qml
        color: root.hasAgent
            ? Colours.palette.m3onPrimaryContainer
            : (Config.bar.workspaces.occupiedBg || root.isOccupied || root.activeWsId === root.ws
               ? Colours.palette.m3onSurface
               : Colours.layer(Colours.palette.m3outlineVariant, 2))
```

- [ ] **Step 2: Sincronizar y recargar**

```bash
cp configs/quickshell/caelestia/modules/bar/components/workspaces/Workspace.qml ~/.config/quickshell/caelestia/modules/bar/components/workspaces/Workspace.qml
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```

Expected: `INFO: Configuration Loaded`, sin errores.

- [ ] **Step 3: Verificación manual**

```bash
python rgb/agent-notify notify -n Claude -t "prueba dot" -w 4 -a 0xdead
```

Expected: el "4" tiene halo **y** un puntito de acento en su esquina superior derecha, sin salirse del recorte. `agents clearAll` → desaparecen ambos.

- [ ] **Step 4: Commit**

```bash
git add configs/quickshell/caelestia/modules/bar/components/workspaces/Workspace.qml
git commit -m "feat(bar): unseen-agent dot on workspace pip"
```

---

## Task 5: `AgentsPopout.qml` + registro del popout

**Files:**
- Create: `configs/quickshell/caelestia/modules/bar/popouts/AgentsPopout.qml`
- Modify: `configs/quickshell/caelestia/modules/bar/popouts/Content.qml`
- Modify: `configs/quickshell/caelestia/modules/bar/popouts/PopoutState.qml`

**Interfaces:**
- Consumes: `Agents.agentsForWs(ws)` (Task 2); patrón de popout (`Battery.qml`, el `component Popout` de `Content.qml`).
- Produces: `AgentsPopout` con `property int ws`; `PopoutState.agentsWs:int`; `Popout { name: "agents" }` (lo dispara Task 6).

- [ ] **Step 1: Crear `AgentsPopout.qml`**

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.utils

Column {
    id: root

    required property int ws
    readonly property var agents: Agents.agentsForWs(ws)

    spacing: Tokens.spacing.small

    function ago(t: var): string {
        const m = Math.floor((Date.now() - new Date(t).getTime()) / 60000);
        if (m < 1)
            return qsTr("ahora mismo");
        if (m < 60)
            return qsTr("hace %1 min").arg(m);
        const h = Math.floor(m / 60);
        return qsTr("hace %1 h").arg(h);
    }

    Repeater {
        model: ScriptModel {
            values: root.agents
        }

        StyledRect {
            id: card

            required property var modelData

            implicitWidth: Math.max(col.implicitWidth + Tokens.padding.large * 2, 200)
            implicitHeight: col.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: col

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.extraSmall

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "smart_toy"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        text: card.modelData.name
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.label.large
                    }
                }

                StyledText {
                    Layout.maximumWidth: 280
                    text: card.modelData.task
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                StyledText {
                    text: {
                        const parts = [];
                        if (card.modelData.dir)
                            parts.push(card.modelData.dir);
                        parts.push(root.ago(card.modelData.time));
                        if (card.modelData.duration)
                            parts.push(qsTr("en %1").arg(card.modelData.duration));
                        return parts.join(" • ");
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }

                StyledRect {
                    Layout.topMargin: Tokens.spacing.extraSmall
                    implicitWidth: stateRow.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: stateRow.implicitHeight + Tokens.padding.extraSmall * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primaryContainer

                    RowLayout {
                        id: stateRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "check_circle"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: card.modelData.status
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.label.small
                        }
                    }
                }

                StyledText {
                    Layout.topMargin: Tokens.spacing.extraSmall
                    text: qsTr("Clic en el workspace para saltar ahi")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.small
                }
            }
        }
    }
}
```

- [ ] **Step 2: `agentsWs` en `PopoutState.qml`**

Añadir junto a las demás `property` de `PopoutState.qml`:

```qml
    property int agentsWs: 0
```

- [ ] **Step 3: `Popout` en `Content.qml`**

Dentro del `Item { id: content … }`, junto a los demás `Popout {}`:

```qml
        Popout {
            name: "agents"
            sourceComponent: AgentsPopout {
                ws: root.popouts.agentsWs
            }
        }
```

Añadir el import arriba si hace falta (`AgentsPopout.qml` está en la misma carpeta → resuelve por directorio; si el archivo usa `import "."` implícito no hace falta, si no, añadir `import qs.modules.bar.popouts`). Comprobar cómo resuelve `Battery`/`Network` (misma carpeta, sin import explícito) y replicar.

- [ ] **Step 4: Sincronizar y recargar**

```bash
cp configs/quickshell/caelestia/modules/bar/popouts/AgentsPopout.qml ~/.config/quickshell/caelestia/modules/bar/popouts/AgentsPopout.qml
cp configs/quickshell/caelestia/modules/bar/popouts/Content.qml ~/.config/quickshell/caelestia/modules/bar/popouts/Content.qml
cp configs/quickshell/caelestia/modules/bar/popouts/PopoutState.qml ~/.config/quickshell/caelestia/modules/bar/popouts/PopoutState.qml
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```

Expected: `INFO: Configuration Loaded`, sin errores `AgentsPopout` / `Content` / `PopoutState`. (El popout aún no se muestra — falta el disparador de Task 6.)

- [ ] **Step 5: Commit**

```bash
git add configs/quickshell/caelestia/modules/bar/popouts/AgentsPopout.qml configs/quickshell/caelestia/modules/bar/popouts/Content.qml configs/quickshell/caelestia/modules/bar/popouts/PopoutState.qml
git commit -m "feat(bar): agents popout card (not yet wired to hover)"
```

---

## Task 6: hover sobre el pip → popout

**Files:**
- Modify: `configs/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml` (exponer `wsAt`)
- Modify: `configs/quickshell/caelestia/modules/bar/Bar.qml` (`checkPopout`)

**Interfaces:**
- Consumes: `Agents.agentsForWs(n)` / `Agents.markSeen(n)` (Task 2); `PopoutState.agentsWs` + `Popout{name:"agents"}` (Task 5); patrón de la rama `statusIcons` en `checkPopout`.
- Produces: `Workspaces.wsAt(yInWorkspaces: real) -> Item|null` (devuelve el `Workspace` bajo esa Y, con su `.ws:int`).

- [ ] **Step 1: `wsAt` en `Workspaces.qml`**

Dentro del `StyledClippingRect { id: root … }` de `Workspaces.qml`, añadir:

```qml
    function wsAt(yInRoot: real): var {
        const p = mapToItem(layout, layout.width / 2, yInRoot);
        const c = layout.childAt(p.x, p.y);
        return (c && c.isWorkspace) ? c : null;
    }
```

(`layout` es el `id` del `ColumnLayout` interno; los `Workspace` llevan `readonly property bool isWorkspace: true` y `readonly property int ws`.)

- [ ] **Step 2: rama `workspaces` en `Bar.qml::checkPopout`**

En `checkPopout`, tras la rama `} else if (id === "activeWindow" …) {` y antes del cierre:

```qml
        } else if (id === "workspaces") {
            const wsw = ch.item; // Workspaces (StyledClippingRect)
            const wsItem = wsw && wsw.wsAt ? wsw.wsAt(mapToItem(wsw, 0, y).y) : null;
            if (wsItem && Agents.agentsForWs(wsItem.ws).length > 0) {
                popouts.agentsWs = wsItem.ws;
                popouts.currentName = "agents";
                popouts.currentCenter = Qt.binding(() => wsItem.mapToItem(root, 0, wsItem.height / 2).y);
                popouts.hasCurrent = true;
                Agents.markSeen(wsItem.ws);
            } else if (popouts.currentName === "agents") {
                popouts.hasCurrent = false;
            }
        }
```

`Agents` ya resuelve vía `import qs.services` (Bar.qml ya lo importa).

- [ ] **Step 3: Sincronizar y recargar**

```bash
cp configs/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml ~/.config/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml
cp configs/quickshell/caelestia/modules/bar/Bar.qml ~/.config/quickshell/caelestia/modules/bar/Bar.qml
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```

Expected: `INFO: Configuration Loaded`, sin errores.

- [ ] **Step 4: Verificación manual**

```bash
python rgb/agent-notify notify -n Claude -t "refactor del popout de agentes" -w 4 -a 0xdead
```

Expected:
1. El "4" tiene halo + puntito.
2. Hover sobre el "4" → sale la tarjeta a la derecha de la barra, alineada al pip, con "Claude", la tarea, "LinuxRicing · hace 0 min · en …", chip "Completado".
3. Al hacer hover, el **puntito desaparece** (markSeen), el halo se queda.
4. Hover sobre otro workspace sin agente → no sale nada.
5. `agents clearAll` → todo limpio.

- [ ] **Step 5: Commit**

```bash
git add configs/quickshell/caelestia/modules/bar/components/workspaces/Workspaces.qml configs/quickshell/caelestia/modules/bar/Bar.qml
git commit -m "feat(bar): show agents popout on workspace-pip hover, mark seen"
```

---

## Task 7: limpieza del código muerto del intento anterior

**Files:**
- Delete: `configs/quickshell/caelestia/modules/bar/components/AgentPills.qml`
- Modify: `configs/quickshell/caelestia/modules/bar/Bar.qml` (quitar `DelegateChoice "agents"`)
- Verify: `configs/quickshell/caelestia/modules/notifications/Notification.qml`

**Interfaces:**
- Consumes: nada.
- Produces: nada.

- [ ] **Step 1: Borrar `AgentPills.qml`**

```bash
git rm configs/quickshell/caelestia/modules/bar/components/AgentPills.qml
rm -f ~/.config/quickshell/caelestia/modules/bar/components/AgentPills.qml
```

- [ ] **Step 2: Quitar el `DelegateChoice` muerto de `Bar.qml`**

Borrar el bloque completo (nunca se renderiza — ningún entry tiene id `"agents"`):

```qml
            DelegateChoice {
                roleValue: "agents"
                delegate: EntryWrapper {
                    AgentPills {
                        objectName: "taskbarAgentPills"
                    }
                }
            }
```

- [ ] **Step 3: Verificar `Notification.qml`**

Confirmar que `Notification.qml` conserva (del revert) el `onClicked` que enruta a `Agents.focus`:

```qml
        onClicked: event => {
            if (event.button !== Qt.LeftButton)
                return;
            const addr = root.modelData.hints?.address ?? "";
            if (addr && String(addr).length > 0) {
                Agents.focus(String(addr));
                root.modelData.close();
                return;
            }
            // … resto original …
        }
```

Si no está, añadirlo (con `import qs.services` si falta). Si está, no tocar.

- [ ] **Step 4: Sincronizar y recargar**

```bash
cp configs/quickshell/caelestia/modules/bar/Bar.qml ~/.config/quickshell/caelestia/modules/bar/Bar.qml
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```

Expected: `INFO: Configuration Loaded`, sin errores; la barra se ve igual que antes (workspaces, tray, clock, statusIcons, power).

- [ ] **Step 5: Commit**

```bash
git add configs/quickshell/caelestia/modules/bar/Bar.qml configs/quickshell/caelestia/modules/bar/components/AgentPills.qml
git commit -m "chore(bar): drop dead AgentPills experiment"
```

---

## Task 8: checkpoint integrado + `install.sh` + docs

**Files:**
- Modify: `install.sh`
- Modify: `docs/RGB_HANDOVER_LINUX.md` (o el runbook de agentes que exista; si no, crear `docs/AGENT_NOTIFICATIONS.md`)
- Modify: `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: nada.

- [ ] **Step 1: `install.sh` despliega `agent-notify`**

En el bucle `for bin in …` (sección "6c. Binarios CLI en ~/.local/bin"), añadir `agent-notify`:

```sh
    for bin in agent-notify akko-rgb battery-lighting magichome-control mchose-battery \
               mchose-lighting rgb-notify-flash; do
```

Y actualizar el comentario de cabecera (línea ~17) para incluir `agent-notify`.

- [ ] **Step 2: Checklist manual integrado**

Con el shell corriendo:

```bash
# 1. Wrapper: lanza un comando y notifica al terminar, en el ws actual
agent-notify run -n Claude -t "sleep de prueba" -- sleep 3
```

Expected: al terminar el `sleep`, toast arriba a la derecha; y como se lanzó en el ws actual, entrar en ese terminal lo auto-descarta.

```bash
# 2. Notificacion directa en un ws remoto (persistente)
agent-notify notify -n Gemini -t "sync del vault" -w 4 -a 0xbeef
```

Expected checklist:
- [ ] Toast rico arriba a la derecha (Gemini · sync del vault · Workspace 4).
- [ ] El pip "4" en la barra: halo de acento + puntito.
- [ ] Toast expira solo a los ~5 s → el halo + puntito siguen.
- [ ] Hover sobre "4" → tarjeta con Gemini / "sync del vault" / "hace 0 min" / chip Completado; el puntito se apaga, el halo no.
- [ ] Clic en "4" → Hyprland cambia al workspace 4.
- [ ] `agent-notify clear` → halo y puntito desaparecen.
- [ ] Segundo monitor (si hay): el halo del "4" también se ve en su barra.
- [ ] Con DND activo (`caelestia … dnd`): `notify` no saca toast pero **sí** pone el halo.

- [ ] **Step 3: Doc de uso**

En el runbook (o `docs/AGENT_NOTIFICATIONS.md` nuevo), documentar:
- `agent-notify run -n <Nombre> -t "<tarea>" -- <comando…>` — forma recomendada (captura inicio y fin, duración real).
- `agent-notify notify -n <Nombre> -t "<tarea>" [-w N] [-a 0x…]` — disparo directo al terminar.
- `agent-notify clear` — limpia todos los pips.
- Qué hace: toast rico + pip del workspace encendido + hover-card + clic para saltar.
- Limitación v1: sin estado "en curso"; la lista no persiste al reiniciar el shell; agente en un workspace fuera del grupo mostrado no pinta pip.

- [ ] **Step 4: Base de Datos de Errores**

Añadir bajo `## 2026-08-29` en `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md`:

```markdown
### La "píldora persistente" de agente rompía el cajón de notificaciones de Caelestia
- **Síntoma:** al encoger la notificación de agente a un circulito de 48 px, el fondo
  oscuro (`PanelBg`) seguía ocupando ~360 px y los `ClippingRectangle` cortaban la
  burbuja y los números.
- **Causa:** en Caelestia los paneles del cajón comparten un `BlobGroup` (metabola SDF),
  cada delegado va envuelto en `ClippingRectangle`, y `sidebar` está anclada a
  `notifications.bottom` — meter un elemento persistente y pequeño ahí choca con las
  cuatro cosas a la vez. Revertido en `e6569fc`.
- **Arreglo:** rediseño (rama `feat/agent-notifications`). El estado persistente vive en
  el **pip del workspace** en la barra (halo estilo `OccupiedBg` + puntito), el detalle
  en un popout de barra, y el clic lo resuelve Caelestia. Nada nuevo en el cajón de
  notificaciones. Spec: `docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md`.
```

- [ ] **Step 5: Commit**

```bash
git add install.sh docs/RGB_HANDOVER_LINUX.md docs/AGENT_NOTIFICATIONS.md "vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md"
git commit -m "docs(agents): install.sh deploy, usage runbook, error-db entry"
```

(Ajustar los paths de `git add` a los archivos realmente tocados — no usar `git add -A`.)

- [ ] **Step 6: Merge de vuelta a `main`**

Cuando Alberto dé el visto bueno (usar `superpowers:finishing-a-development-branch`):

```bash
git checkout main
git pull --ff-only 2>/dev/null || true
git merge --no-ff feat/agent-notifications
```

Resolver a favor de dejar `README.md` como esté en `main` si hay conflicto (es trabajo de Alberto/Gemini). Reinstalar (`./install.sh`) y recargar el shell una última vez.

---

## Self-review (cobertura del spec)

| Requisito del spec | Task |
| --- | --- |
| Toast nativo rico al terminar (agente, proyecto, tarea, ws, duración, clic-enfoca) | Task 1 (cuerpo con `task`) + `Notification.qml` ya enruta el clic (Task 7 verifica) |
| `agent-notify` captura address/ws/proyecto/duración; IPC + `notify-send`; degrada si falla `qs ipc` | Task 1 (ya existía; se añade `task`) |
| `Agents` fuente de verdad: `task`, `seen`, `liveWs`, `agentsForWs`, `hasUnseenForWs`, `markSeen` | Task 2 |
| Dedup por address (una entrada por terminal, reemplaza y resetea `seen`) | Task 2 (`notify`) |
| Auto-descarte al enfocar la ventana / al entrar al ws con la ventana ya cerrada | Task 2 (`Connections`) |
| Halo de acento en el pip del workspace del agente, dentro del recorte, estilo `OccupiedBg` | Task 3 |
| Puntito interior mientras `seen === false` | Task 4 |
| Color del texto del pip vira con agente para contraste | Task 4 |
| Hover sobre el pip → popout-card (nombre, tarea, proyecto, "hace Xm", estado) | Tasks 5 + 6 |
| Popout reusa el sistema de barra (`checkPopout` + `Popout{}`) | Tasks 5 + 6 |
| `markSeen` al abrir el hover | Task 6 |
| Clic en el pip → Caelestia cambia de workspace (sin cambios) | — (nativo; Task 8 lo verifica) |
| Multi-monitor: halo en cada barra que muestre ese ws | Task 3 (Repeater por barra) + Task 8 verifica |
| DND/fullscreen: toast suprimido pero halo/entrada sí | `Notifs.shouldShowPopup` ya lo hace; Task 8 verifica |
| Limpieza: borrar `AgentPills.qml` + `DelegateChoice "agents"` | Task 7 |
| Conservar dedup de `Notifs.qml` y `focus_on_activate=false` | — (no se tocan) |
| `install.sh` despliega `agent-notify` | Task 8 |
| Fuera de alcance v1: "en curso", badge numérico externo, persistencia, animación de vuelo, indicador de ws oculto | No implementado (correcto) |

**Placeholder scan:** sin `TBD`/`TODO`; todos los pasos de código llevan el bloque real.

**Type consistency:** `wsMap` (objeto `{int: entry[]}`), `agentsForWs(n)->array`, `hasUnseenForWs(n)->bool`, `markSeen(wsOrId)`, `liveWs(address, fallbackWs)->int`, `_normAddr(addr)->string` — usados igual en Tasks 3/4/6. Entrada con `.name/.task/.status/.dir/.ws/.address/.duration/.time/.seen` — misma forma en Task 2 (creación) y Task 5 (consumo). `PopoutState.agentsWs:int` ↔ `AgentsPopout.ws:int` ↔ `Content.qml` binding — coherente. `Workspaces.wsAt(y)->Item|null` con `.ws:int`/`.isWorkspace:bool` — definido en Task 6 Step 1, consumido en Task 6 Step 2.
