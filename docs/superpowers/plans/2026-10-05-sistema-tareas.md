# Sistema unificado de tareas — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que Alberto vea todas sus tareas (notas de `Backlog/` de varios repos) en un widget abajo a la derecha y en el cometa de tareas, y que Laura pueda listarlas, crearlas y cambiarles el estado.

**Architecture:** Un script Python (`tasks-index`) lee un registro de repos, parsea el frontmatter de cada `Backlog/*.md` y escribe `~/.cache/tasks.json`; es también el único que escribe en las notas (`set`, `add`). Un singleton QML `Tasks` lo ejecuta por `Timer` y alimenta el widget, el cometa y su panel. Laura llama al mismo script desde tres tools.

**Tech Stack:** Python 3 (solo stdlib), Quickshell/QML (Caelestia), Obsidian URI (`obsidian://`), tools de `assistant/tools.py`.

**Spec:** `docs/superpowers/specs/2026-10-05-sistema-tareas-design.md`

## Global Constraints

- Trabajar **solo** en el worktree `~/LinuxRicing-tareas` (rama `feat/sistema-tareas`). No tocar `~/LinuxRicing` (árbol de otra sesión de Claude).
- Sin tests automáticos: Alberto prueba a mano. Cada tarea termina con una **verificación manual** con salida esperada.
- Tras CUALQUIER cambio de QML: sincronizar a `~/.config/quickshell/caelestia/` y **restart completo**: `caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d` y comprobar `INFO: Configuration Loaded` sin errores. Nunca fiarse del hot-reload.
- Prohibido `FrameAnimation { running: true }` incondicional; sin `shadowBlur` en Canvas; el widget solo se repinta al cambiar el JSON.
- Quickshell no tiene `~/.local/bin` en el PATH: invocar `tasks-index` por ruta absoluta (`$HOME/.local/bin/tasks-index`).
- Copias idénticas: si se toca `rgb/mchose-battery` o `widgets/mchose-battery`, verificar `diff -q` (no aplica a este plan salvo que se toquen).
- Commits en español, con la línea final `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Al empezar a trabajar en la tarea del backlog `Sistema unificado de tareas`, su `estado` ya es `en-curso`; al terminar, `hecha` (nunca borrar la nota). Al cerrar la sesión, una línea arriba de «📓 Bitácora de sesiones» en `vault/🎯 Hoy.md`.

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `widgets/tasks-index` (nuevo) | scan / set / add. Única lógica de lectura/escritura de notas |
| `configs/caelestia/task-repos.json` (nuevo, plantilla) | Registro de repos; `install.sh` lo copia a `~/.config/caelestia/` si no existe |
| `configs/quickshell/caelestia/services/Tasks.qml` (nuevo) | Singleton: ejecuta `tasks-index`, expone `repos`, `tareas`, `pendientes`, `abrir`, `marcarHecha` |
| `configs/quickshell/caelestia/services/SolarSystemModel.qml` (mod) | Sustituye el adaptador `taskCount` por `Tasks` |
| `configs/quickshell/caelestia/modules/background/TasksWidget.qml` (nuevo) | Widget abajo a la derecha |
| `configs/quickshell/caelestia/modules/background/TasksPanel.qml` (nuevo) | Panel completo con filtros (abre el cometa) |
| `configs/quickshell/caelestia/modules/background/solarsystem/SolarSystem.qml` (mod) | Señal `cometClicked` + `MouseArea` en la cabeza del cometa |
| `configs/quickshell/caelestia/modules/background/solarsystem/SolarSystemLayer.qml` (mod) | Instancia widget y panel; cablea `cometClicked` |
| `assistant/tools.py` (mod) | `listar_tareas`, `crear_tarea`, `cambiar_estado` |
| `install.sh` (mod) | Despliega `tasks-index` y la plantilla del registro |

---

### Task 1: `tasks-index` (indexador) + registro de repos

**Files:**
- Create: `widgets/tasks-index`
- Create: `configs/caelestia/task-repos.json`
- Modify: `install.sh` (junto al bloque de `gtasks`, ~línea 241)

**Interfaces:**
- Produces: CLI `tasks-index scan [--print]`, `tasks-index set <repo> <nota> <estado>`, `tasks-index add <repo> "<título>" [-p N] [-a area]`. `scan --print` imprime el JSON del esquema de la spec. `set`/`add` imprimen un JSON de una línea: `{"ok": true, "tarea": {...}}` o `{"ok": false, "error": "...", "candidatos": [...]}` y reescanean el caché.
- Produces: `~/.cache/tasks.json` con `{"generado", "avisos", "repos": [{"nombre","vault","hechas","ideas","tareas":[{"id","titulo","estado","prioridad","area","esfuerzo","ruta","uri"}]}]}`.

- [ ] **Step 1: Crear la plantilla del registro**

`configs/caelestia/task-repos.json`:

```json
[
  {"nombre": "LinuxRicing", "backlog": "~/LinuxRicing/vault/Backlog", "vault": "vault"},
  {"nombre": "Universidad", "backlog": "~/Documentos/Universidad/Backlog", "vault": "Universidad"},
  {"nombre": "Minecraft", "backlog": "~/minecraft-server/vault/Backlog", "vault": "vault"},
  {"nombre": "OpenGym", "backlog": "~/proyectos/opengym-fork/Backlog", "vault": "opengym-fork"}
]
```

- [ ] **Step 2: Escribir `widgets/tasks-index`**

```python
#!/usr/bin/env python3
"""tasks-index — agrupa las tareas (notas de Obsidian) de todos los repos registrados.

  tasks-index scan [--print]               escribe ~/.cache/tasks.json
  tasks-index set <repo> <nota> <estado>   cambia solo la línea `estado:` de la nota
  tasks-index add <repo> "título" [-p N] [-a area]   crea una nota nueva

Cada nota es un .md con frontmatter (`estado`, `prioridad`, `area`, `esfuerzo`).
`set` y `add` imprimen una línea JSON {"ok": ...} y reescanean el caché.
"""
import argparse
import json
import os
import re
import sys
import tempfile
import urllib.parse
from datetime import datetime
from pathlib import Path

REPOS_FILE = Path.home() / ".config/caelestia/task-repos.json"
CACHE_FILE = Path.home() / ".cache/tasks.json"
ESTADOS = ("pendiente", "en-curso", "hecha", "idea")
FM_RE = re.compile(r"\A---\n(.*?)\n---\n", re.S)


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def load_repos() -> list[dict]:
    try:
        repos = json.loads(REPOS_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    for r in repos:
        r["_dir"] = Path(os.path.expanduser(r["backlog"]))
    return repos


def parse_frontmatter(text: str) -> dict | None:
    m = FM_RE.match(text)
    if not m:
        return None
    fm = {}
    for line in m.group(1).split("\n"):
        k, sep, v = line.partition(":")
        if sep and not line.startswith((" ", "\t", "-")):
            fm[k.strip()] = v.strip().strip('"')
    return fm


def norm_prio(v) -> int:
    if v == "alta":
        return 1
    try:
        return max(1, min(5, int(v)))
    except (TypeError, ValueError):
        return 5


def scan() -> dict:
    out = {"generado": datetime.now().isoformat(timespec="seconds"), "avisos": [], "repos": []}
    for r in load_repos():
        d = r["_dir"]
        repo = {"nombre": r["nombre"], "vault": r["vault"], "hechas": 0, "ideas": 0, "tareas": []}
        if d.is_dir():
            for f in sorted(d.glob("*.md")):
                try:
                    fm = parse_frontmatter(f.read_text(encoding="utf-8"))
                except OSError as e:
                    out["avisos"].append(f"{f}: {e}")
                    continue
                if fm is None or fm.get("estado") not in ESTADOS:
                    continue
                estado = fm["estado"]
                if estado == "hecha":
                    repo["hechas"] += 1
                    continue
                if estado == "idea":
                    repo["ideas"] += 1
                    continue
                rel = urllib.parse.quote(f"Backlog/{f.stem}")
                repo["tareas"].append({
                    "id": f"{r['nombre']}/{f.stem}", "titulo": f.stem, "estado": estado,
                    "prioridad": norm_prio(fm.get("prioridad")), "area": fm.get("area", ""),
                    "esfuerzo": fm.get("esfuerzo", ""), "ruta": str(f),
                    "uri": f"obsidian://open?vault={urllib.parse.quote(r['vault'])}&file={rel}",
                })
        repo["tareas"].sort(key=lambda t: (t["estado"] != "en-curso", t["prioridad"], t["titulo"]))
        out["repos"].append(repo)
    atomic_write(CACHE_FILE, json.dumps(out, ensure_ascii=False))
    return out


def find_repo(nombre: str) -> dict | None:
    for r in load_repos():
        if r["nombre"].lower() == nombre.lower():
            return r
    return None


def resolve_note(repo: dict, nota: str):
    """(Path, None) si hay una candidata clara; (None, [candidatos]) si no."""
    d = repo["_dir"]
    exact = d / f"{nota}.md"
    if exact.is_file():
        return exact, None
    q = nota.lower()
    cands = [f for f in sorted(d.glob("*.md")) if q in f.stem.lower()] if d.is_dir() else []
    if len(cands) == 1:
        return cands[0], None
    return None, [c.stem for c in cands]


def cmd_set(args) -> dict:
    repo = find_repo(args.repo)
    if not repo:
        return {"ok": False, "error": f"repo desconocido: {args.repo}"}
    if args.estado not in ESTADOS:
        return {"ok": False, "error": f"estado inválido: {args.estado}"}
    path, cands = resolve_note(repo, args.nota)
    if path is None:
        return {"ok": False, "error": "nota no encontrada o ambigua", "candidatos": cands}
    text = path.read_text(encoding="utf-8")  # releer justo antes de escribir
    m = FM_RE.match(text)
    if not m:
        return {"ok": False, "error": "la nota no tiene frontmatter"}
    fm_block = m.group(1)
    if re.search(r"^estado:.*$", fm_block, re.M):
        fm_block = re.sub(r"^estado:.*$", f"estado: {args.estado}", fm_block, count=1, flags=re.M)
    else:
        fm_block += f"\nestado: {args.estado}"
    atomic_write(path, f"---\n{fm_block}\n---\n" + text[m.end():])
    scan()
    return {"ok": True, "tarea": path.stem, "estado": args.estado}


def cmd_add(args) -> dict:
    repo = find_repo(args.repo)
    if not repo:
        return {"ok": False, "error": f"repo desconocido: {args.repo}"}
    titulo = re.sub(r'[\\/:*?"<>|]', "", args.titulo).strip()
    if not titulo:
        return {"ok": False, "error": "título vacío"}
    path = repo["_dir"] / f"{titulo}.md"
    if path.exists():
        return {"ok": False, "error": "ya existe una tarea con ese título"}
    body = (
        "---\nfileClass: Backlog\ntipo: tarea\nestado: pendiente\n"
        f"prioridad: {norm_prio(args.prioridad)}\narea: {args.area}\norigen: Alberto\n"
        f"esfuerzo: M\ncreado: {datetime.now().date().isoformat()}\ntags:\n  - backlog\n---\n\n# {titulo}\n"
    )
    atomic_write(path, body)
    scan()
    return {"ok": True, "tarea": titulo}


def main() -> int:
    p = argparse.ArgumentParser(prog="tasks-index")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan")
    s.add_argument("--print", action="store_true", dest="do_print")
    st = sub.add_parser("set")
    st.add_argument("repo"); st.add_argument("nota"); st.add_argument("estado")
    ad = sub.add_parser("add")
    ad.add_argument("repo"); ad.add_argument("titulo")
    ad.add_argument("-p", "--prioridad", default=3)
    ad.add_argument("-a", "--area", default="general")
    args = p.parse_args()
    if args.cmd == "scan":
        data = scan()
        if args.do_print:
            print(json.dumps(data, ensure_ascii=False))
        return 0
    res = cmd_set(args) if args.cmd == "set" else cmd_add(args)
    print(json.dumps(res, ensure_ascii=False))
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: Hacerlo ejecutable e instalar**

```bash
cd ~/LinuxRicing-tareas
chmod +x widgets/tasks-index
mkdir -p ~/.config/caelestia ~/.local/bin
[ -f ~/.config/caelestia/task-repos.json ] || cp configs/caelestia/task-repos.json ~/.config/caelestia/task-repos.json
cp widgets/tasks-index ~/.local/bin/tasks-index
```

- [ ] **Step 4: Añadir el despliegue a `install.sh`**

Justo después del bloque de `gtasks` (línea ~247, tras el `fi` de `SELECTED_GTASKS`), añadir:

```bash
# 4b. Instalar tasks-index (sistema unificado de tareas)
if [ -f "$BASE_DIR/widgets/tasks-index" ]; then
    mkdir -p "$HOME/.local/bin" "$HOME/.config/caelestia"
    cp -u "$BASE_DIR/widgets/tasks-index" "$HOME/.local/bin/tasks-index"
    chmod +x "$HOME/.local/bin/tasks-index"
    [ -f "$HOME/.config/caelestia/task-repos.json" ] || cp "$BASE_DIR/configs/caelestia/task-repos.json" "$HOME/.config/caelestia/task-repos.json"
    echo -e "  ${SUCCESS}✔ tasks-index instalado en ~/.local/bin${RESET}"
fi
```

Actualizar también el comentario de cabecera de `install.sh` (línea ~19) añadiendo `tasks-index` a la lista de `widgets/{...}`.

- [ ] **Step 5: Verificación manual**

```bash
tasks-index scan --print | python3 -m json.tool | head -40
tasks-index add LinuxRicing "Tarea de prueba tasks-index" -p 4 -a infra
tasks-index set LinuxRicing "prueba tasks-index" en-curso
tasks-index set LinuxRicing "prueba tasks-index" hecha
tasks-index set LinuxRicing "tarea inexistente xyz" hecha; echo "exit=$?"
```

Esperado: el primer comando lista `LinuxRicing` con tareas `en-curso` primero, luego `pendiente` por prioridad, con `hechas` e `ideas` como contadores y sin `hecha`/`idea` en `tareas`; los repos sin `Backlog/` aparecen con `tareas: []`; `add` y `set` imprimen `{"ok": true,...}`; el último imprime `{"ok": false, "error": "nota no encontrada o ambigua", "candidatos": []}` con `exit=1`. Comprobar con `git -C ~/LinuxRicing diff --stat` que la nota de prueba solo cambió su línea `estado:`. **Borrar la nota de prueba:** `rm ~/LinuxRicing/vault/Backlog/"Tarea de prueba tasks-index.md"` y `tasks-index scan`.

- [ ] **Step 6: Commit**

```bash
cd ~/LinuxRicing-tareas
git add widgets/tasks-index configs/caelestia/task-repos.json install.sh
git commit -m "feat(tareas): tasks-index, indexador de tareas multi-repo (scan/set/add)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Singleton `Tasks.qml` y cometa alimentado por él

**Files:**
- Create: `configs/quickshell/caelestia/services/Tasks.qml`
- Modify: `configs/quickshell/caelestia/services/SolarSystemModel.qml` (propiedades `taskList` ~l.155 y `_pendingTasks` ~l.152; eliminar el bloque `Process { id: taskCount ... }` y su `Timer`, ~l.551-583)

**Interfaces:**
- Consumes: `~/.local/bin/tasks-index` de la Task 1 (`scan --print`, `set`).
- Produces: singleton `Tasks` con `property var repos`, `readonly property var tareas` (lista plana ordenada, cada elemento = tarea del JSON + `repo`), `readonly property int pendientes`, `function refresh()`, `function abrir(t)`, `function marcarHecha(t)`.

- [ ] **Step 1: Crear `services/Tasks.qml`**

```qml
pragma Singleton
pragma ComponentBehavior: Bound

// Tasks — tareas de todos los repos registrados (notas de Backlog/ de Obsidian).
// Toda la lógica vive en `tasks-index`; aquí solo se ejecuta y se expone.
// Sin demonio: un Timer de 30 s y un refresco tras cada cambio. Quickshell no
// tiene ~/.local/bin en el PATH, de ahí la ruta absoluta.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var repos: []
    property var avisos: []

    // Lista plana: en curso primero, luego por prioridad.
    readonly property var tareas: {
        const out = [];
        for (const r of repos)
            for (const t of r.tareas)
                out.push(Object.assign({ repo: r.nombre }, t));
        out.sort((a, b) => ((a.estado === "en-curso") ? 0 : 1) - ((b.estado === "en-curso") ? 0 : 1)
                           || a.prioridad - b.prioridad);
        return out;
    }
    readonly property int pendientes: tareas.length

    function refresh(): void {
        if (!scanProc.running)
            scanProc.running = true;
    }

    function abrir(t): void {
        Quickshell.execDetached(["xdg-open", t.uri]);
    }

    function marcarHecha(t): void {
        setProc.command = ["sh", "-c", "\"$HOME/.local/bin/tasks-index\" set \"$1\" \"$2\" hecha", "sh", t.repo, t.titulo];
        setProc.running = true;
    }

    Process {
        id: scanProc
        command: ["sh", "-c", "\"$HOME/.local/bin/tasks-index\" scan --print"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.repos = d.repos;
                    root.avisos = d.avisos;
                } catch (e) {
                    console.warn("Tasks: JSON inválido de tasks-index:", e);
                }
            }
        }
    }

    Process {
        id: setProc
        onExited: root.refresh()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
```

- [ ] **Step 2: Reemplazar el adaptador en `SolarSystemModel.qml`**

Cambiar las dos propiedades para que sean bindings a `Tasks`:

```qml
    property int _pendingTasks: Tasks.pendientes
    ...
    property var taskList: Tasks.tareas.map(t => ({ prio: t.prioridad, title: t.titulo }))
```

(Mantener el comentario original de `taskList` y la línea donde esté declarada; solo cambia el valor inicial por el binding.) Eliminar por completo el bloque `// ---------- Adaptador: tareas pendientes del backlog ----------` con su `Process { id: taskCount ... }` y el `Timer` de 60 s que lo dispara (~l.551-583), incluidas las asignaciones `root.taskList = out; root._pendingTasks = out.length;`. Añadir `import qs.services` si no estuviera (ya está en la l.18).

- [ ] **Step 3: Sincronizar y reiniciar el shell**

```bash
cd ~/LinuxRicing-tareas/configs/quickshell/caelestia
cp services/Tasks.qml services/SolarSystemModel.qml ~/.config/quickshell/caelestia/services/
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```

- [ ] **Step 4: Verificación manual**

Esperado: la salida contiene `INFO: Configuration Loaded` sin errores QML. El cometa de tareas sigue apareciendo y, al pasar el ratón, lista las 3 primeras tareas (ahora de **todos** los repos, incluidas las `en-curso`). Comprobar que la cuenta del cometa coincide con `tasks-index scan --print | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(len(r['tareas']) for r in d['repos']))"`. Comprobar CPU del shell en reposo (`top -b -n1 | grep -i qs`), sin subidas respecto a antes.

- [ ] **Step 5: Commit**

```bash
cd ~/LinuxRicing-tareas
git add configs/quickshell/caelestia/services/Tasks.qml configs/quickshell/caelestia/services/SolarSystemModel.qml
git commit -m "feat(tareas): singleton Tasks y cometa alimentado por tasks-index

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Maqueta del widget (gate visual de Alberto)

**Files:**
- Create: `docs/superpowers/mockups/tareas-widget.html` (maqueta estática, no se despliega)

**Interfaces:** ninguna; es una decisión visual.

Alberto decide viendo, no leyendo. Antes de escribir el QML del widget y del panel, enseñarle 3 variantes.

- [ ] **Step 1: Generar la maqueta HTML** con una captura del escritorio (fondo negro + esquina inferior derecha) y tres variantes del widget con datos reales de `tasks-index scan --print`:
  - **A — Lista agrupada por repo** (cabecera «N tareas», botón «Abrir en Obsidian», filas con casilla, título y pastilla de prioridad, «+N más»).
  - **B — Lista plana por prioridad**, con el repo como etiqueta pequeña por fila.
  - **C — Compacta**: solo `en-curso` y las P1-P2, con contador de las demás.
  
  Usar los colores del tema (Material You) y la tipografía mono del shell. Incluir también el panel completo del cometa (chips de filtro por repo y prioridad).

- [ ] **Step 2: Servir y enseñar** (artifact o navegador) y **preguntar a Alberto cuál elige** (y qué cambia). No continuar a la Task 4 sin respuesta.

- [ ] **Step 3: Commit** de la maqueta elegida.

```bash
git add docs/superpowers/mockups/tareas-widget.html
git commit -m "docs(tareas): maqueta del widget de tareas

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `TasksWidget.qml` y `TasksPanel.qml` + clic en el cometa

> La plantilla de abajo implementa la **variante A**. Si en la Task 3 Alberto elige otra, ajustar la agrupación/estructura de las filas; los contratos con `Tasks` no cambian.

**Files:**
- Create: `configs/quickshell/caelestia/modules/background/TasksWidget.qml`
- Create: `configs/quickshell/caelestia/modules/background/TasksPanel.qml`
- Modify: `configs/quickshell/caelestia/modules/background/solarsystem/SolarSystem.qml` (señal junto a `signal configClicked()` ~l.184; `MouseArea` en `cometLayer` ~l.812)
- Modify: `configs/quickshell/caelestia/modules/background/solarsystem/SolarSystemLayer.qml`

**Interfaces:**
- Consumes: singleton `Tasks` de la Task 2.
- Produces: componentes `TasksWidget {}` (Item anclable) y `TasksPanel { open: bool; signal closed() }`; `SolarSystem.cometClicked()`.

- [ ] **Step 1: `TasksWidget.qml`**

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

// Widget de tareas (abajo a la derecha). Sin animaciones: solo se repinta al cambiar Tasks.
StyledRect {
    id: root

    readonly property int maxRows: 8
    readonly property var visibles: Tasks.tareas.slice(0, maxRows)
    readonly property int extra: Math.max(0, Tasks.tareas.length - maxRows)

    // Notas de Obsidian: la de Hoy del primer repo registrado.
    function abrirObsidian(): void {
        Quickshell.execDetached(["xdg-open", "obsidian://open?vault=vault&file=%F0%9F%8E%AF%20Hoy"]);
    }

    visible: Tasks.tareas.length > 0
    implicitWidth: 360
    implicitHeight: col.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.large
    color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.82)

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: `${Tasks.pendientes} tareas`
                color: Colours.palette.m3primary
                font: Tokens.font.title.small
            }
            StyledRect {
                implicitWidth: 28; implicitHeight: 28
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHigh
                MaterialIcon {
                    anchors.centerIn: parent
                    text: "open_in_new"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurface
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.abrirObsidian()
                }
            }
        }

        Repeater {
            model: root.visibles
            delegate: RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "check_box_outline_blank"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Tasks.marcarHecha(row.modelData)
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.titulo
                    elide: Text.ElideRight
                    color: row.modelData.estado === "en-curso" ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    font: Tokens.font.label.medium
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Tasks.abrir(row.modelData)
                    }
                }
                StyledText {
                    text: `${row.modelData.repo} · P${row.modelData.prioridad}`
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }
            }
        }

        StyledText {
            visible: root.extra > 0
            text: `+${root.extra} más (clic en el cometa)`
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
        }
    }
}
```

- [ ] **Step 2: `TasksPanel.qml`** (panel completo con filtro por repo y prioridad; fondo que cierra al hacer clic fuera)

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property bool open: false
    property string repoFiltro: ""     // "" = todos
    property int prioMax: 5            // muestra prioridad <= prioMax
    signal closed()

    visible: open

    readonly property var lista: Tasks.tareas.filter(t =>
        (repoFiltro === "" || t.repo === repoFiltro) && t.prioridad <= prioMax)

    // Velo: clic fuera cierra.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.closed() }
    }

    StyledRect {
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 64)
        height: Math.min(parent.height - 96, col.implicitHeight + Tokens.padding.large * 2)
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledText {
                text: `${root.lista.length} de ${Tasks.pendientes} tareas`
                color: Colours.palette.m3primary
                font: Tokens.font.title.medium
            }

            // Chips de repo
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                Repeater {
                    model: [""].concat(Tasks.repos.map(r => r.nombre))
                    delegate: StyledRect {
                        id: chip
                        required property string modelData
                        implicitWidth: chipLabel.implicitWidth + Tokens.padding.large
                        implicitHeight: chipLabel.implicitHeight + Tokens.padding.small
                        radius: Tokens.rounding.full
                        color: root.repoFiltro === modelData ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHigh
                        StyledText {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: chip.modelData === "" ? "Todos" : chip.modelData
                            font: Tokens.font.label.small
                            color: root.repoFiltro === chip.modelData ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.repoFiltro = chip.modelData }
                    }
                }
            }

            // Chips de prioridad
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                Repeater {
                    model: [{ t: "Todas", v: 5 }, { t: "P1-P2", v: 2 }, { t: "P1-P3", v: 3 }]
                    delegate: StyledRect {
                        id: pchip
                        required property var modelData
                        implicitWidth: plabel.implicitWidth + Tokens.padding.large
                        implicitHeight: plabel.implicitHeight + Tokens.padding.small
                        radius: Tokens.rounding.full
                        color: root.prioMax === modelData.v ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHigh
                        StyledText {
                            id: plabel
                            anchors.centerIn: parent
                            text: pchip.modelData.t
                            font: Tokens.font.label.small
                            color: root.prioMax === pchip.modelData.v ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.prioMax = pchip.modelData.v }
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(contentHeight, 420)
                clip: true
                spacing: Tokens.spacing.small
                model: root.lista
                delegate: RowLayout {
                    id: row
                    required property var modelData
                    width: ListView.view.width
                    spacing: Tokens.spacing.small
                    MaterialIcon {
                        text: "check_box_outline_blank"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Tasks.marcarHecha(row.modelData) }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.titulo
                        elide: Text.ElideRight
                        color: row.modelData.estado === "en-curso" ? Colours.palette.m3primary : Colours.palette.m3onSurface
                        font: Tokens.font.label.medium
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Tasks.abrir(row.modelData) }
                    }
                    StyledText {
                        text: `${row.modelData.repo} · P${row.modelData.prioridad}`
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Señal y clic en el cometa (`SolarSystem.qml`)**

Junto a `signal configClicked()` (~l.184) añadir:

```qml
    signal cometClicked()
```

Dentro de `Item { id: cometLayer ... }` (~l.812), como último hijo antes de su `}` de cierre (después del `Column { id: cometTasks ... }`), añadir un área sobre la cabeza del cometa:

```qml
        MouseArea {
            visible: cometLayer.c !== null
            x: cometLayer.c ? cometLayer.c.x - 24 * cometLayer.sc : 0
            y: cometLayer.c ? cometLayer.c.y - 24 * cometLayer.sc : 0
            width: 48 * cometLayer.sc
            height: 48 * cometLayer.sc
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cometClicked()
        }
```

- [ ] **Step 4: Cablear en `SolarSystemLayer.qml`**

Dentro del `StyledWindow`, **fuera del `Loader`** (para que el widget siga visible en modo ahorro con fondo negro), añadir tras el cierre del `Loader { id: solarLoader ... }`:

```qml
        property bool tasksPanelOpen: false

        TasksWidget {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 32
            anchors.bottomMargin: 32
        }

        TasksPanel {
            anchors.fill: parent
            open: win.tasksPanelOpen
            onClosed: win.tasksPanelOpen = false
        }
```

y en el `SolarSystem { ... }` del `sourceComponent` añadir junto a `onConfigClicked`:

```qml
                onCometClicked: win.tasksPanelOpen = true
```

(`win` es el `id` del `StyledWindow`; `TasksWidget`/`TasksPanel` están en el directorio padre `modules/background/`, así que el import relativo del módulo ya los resuelve con `import ".."` si hace falta; añadir `import ".."` al principio de `SolarSystemLayer.qml` y comprobar la carga.)

- [ ] **Step 5: Sincronizar y reiniciar el shell**

```bash
cd ~/LinuxRicing-tareas/configs/quickshell/caelestia
rsync -a modules/background/ ~/.config/quickshell/caelestia/modules/background/
cp services/*.qml ~/.config/quickshell/caelestia/services/
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```

- [ ] **Step 6: Verificación manual (la hace Alberto)**

Esperado: `INFO: Configuration Loaded` sin errores. Abajo a la derecha aparece el widget con las tareas de todos los repos; clic en una casilla la marca `hecha` (comprobar con `git -C ~/LinuxRicing diff` que solo cambió su línea `estado:` y que desaparece del widget en ≤ unos segundos); clic en el título abre la nota en Obsidian; el botón de la cabecera abre Obsidian; clic en el cometa abre el panel y los chips filtran; clic fuera del panel lo cierra; el resto del escritorio sigue respondiendo (clic en Configuración abre el panel RGB). CPU del shell en reposo sin subidas. En modo ahorro el widget sigue visible.

- [ ] **Step 7: Commit**

```bash
cd ~/LinuxRicing-tareas
git add configs/quickshell/caelestia/modules/background/TasksWidget.qml configs/quickshell/caelestia/modules/background/TasksPanel.qml configs/quickshell/caelestia/modules/background/solarsystem/SolarSystem.qml configs/quickshell/caelestia/modules/background/solarsystem/SolarSystemLayer.qml
git commit -m "feat(tareas): widget de tareas, panel completo y clic en el cometa

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Laura — tools de tareas

**Files:**
- Modify: `assistant/tools.py` (funciones antes de `DISPATCH` ~l.232; entradas en `DISPATCH` y `TOOLS`)

**Interfaces:**
- Consumes: `~/.local/bin/tasks-index` (Task 1): `set` y `add` imprimen una línea JSON; `scan --print` el JSON completo.
- Produces: tools `listar_tareas(repo: str = "", estado: str = "")`, `crear_tarea(titulo: str, repo: str = "LinuxRicing", prioridad: int = 3, area: str = "general")`, `cambiar_estado(tarea: str, estado: str, repo: str = "LinuxRicing")`.

- [ ] **Step 1: Funciones** (antes de `DISPATCH`)

```python
_TASKS_BIN = str(__import__("pathlib").Path.home() / ".local/bin/tasks-index")


def _tasks(*args: str) -> dict:
    p = _run([_TASKS_BIN, *args])
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except (IndexError, ValueError):
        return {"ok": False, "error": (p.stderr or "tasks-index no respondió").strip()}


def listar_tareas(repo: str = "", estado: str = "") -> dict:
    """Tareas abiertas. Sin filtros: las en curso y las de prioridad 1-2."""
    d = _tasks("scan", "--print")
    if "repos" not in d:
        return d
    out = []
    for r in d["repos"]:
        if repo and r["nombre"].lower() != repo.lower():
            continue
        for t in r["tareas"]:
            if estado and t["estado"] != estado:
                continue
            if not estado and not (t["estado"] == "en-curso" or t["prioridad"] <= 2):
                continue
            out.append({"repo": r["nombre"], "titulo": t["titulo"],
                        "estado": t["estado"], "prioridad": t["prioridad"]})
    return {"ok": True, "tareas": out[:15], "total": len(out)}


def crear_tarea(titulo: str, repo: str = "LinuxRicing", prioridad: int = 3, area: str = "general") -> dict:
    return _tasks("add", repo, titulo, "-p", str(prioridad), "-a", area)


def cambiar_estado(tarea: str, estado: str, repo: str = "LinuxRicing") -> dict:
    """estado: pendiente | en-curso | hecha. Si el nombre es ambiguo devuelve candidatos."""
    return _tasks("set", repo, tarea, estado)
```

- [ ] **Step 2: Registrar en `DISPATCH`**

```python
    "listar_tareas": listar_tareas,
    "crear_tarea": crear_tarea,
    "cambiar_estado": cambiar_estado,
```

- [ ] **Step 3: Esquemas en `TOOLS`** (antes del `]` final de la lista, tras `escalar_a_gemini`)

```python
    {
        "type": "function",
        "function": {
            "name": "listar_tareas",
            "description": "Lista las tareas pendientes de Alberto de todos sus repos. Úsala cuando pregunte qué tiene que hacer o qué tiene pendiente.",
            "parameters": {"type": "object", "properties": {
                "repo": {"type": "string", "description": "limitar a un repo (LinuxRicing, Universidad, Minecraft, OpenGym)"},
                "estado": {"type": "string", "description": "pendiente, en-curso o hecha"},
            }},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "crear_tarea",
            "description": "Apunta una tarea nueva en el backlog de un repo (por defecto LinuxRicing).",
            "parameters": {"type": "object", "properties": {
                "titulo": {"type": "string", "description": "título corto de la tarea"},
                "repo": {"type": "string", "description": "repo donde apuntarla"},
                "prioridad": {"type": "integer", "description": "1 urgente … 5 algún día"},
                "area": {"type": "string", "description": "área (escritorio, rgb, agentes, infra…)"},
            }, "required": ["titulo"]},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "cambiar_estado",
            "description": "Cambia el estado de una tarea existente (pendiente, en-curso, hecha). Si la respuesta trae `candidatos`, pregunta a Alberto cuál de ellos quiere en vez de adivinar.",
            "parameters": {"type": "object", "properties": {
                "tarea": {"type": "string", "description": "título o parte del título de la tarea"},
                "estado": {"type": "string", "description": "pendiente, en-curso o hecha"},
                "repo": {"type": "string", "description": "repo de la tarea"},
            }, "required": ["tarea", "estado"]},
        },
    },
```

- [ ] **Step 4: Verificación manual (sin voz)**

```bash
cd ~/LinuxRicing-tareas/assistant
python3 -c "
import tools
print(tools.run_tool('listar_tareas', {}, {}))
print(tools.run_tool('crear_tarea', {'titulo': 'Prueba Laura tareas', 'prioridad': 4}, {}))
print(tools.run_tool('cambiar_estado', {'tarea': 'prueba laura', 'estado': 'hecha'}, {}))
print(tools.run_tool('cambiar_estado', {'tarea': 'rediseño', 'estado': 'hecha'}, {}))
"
```

Esperado: la primera devuelve `{'ok': True, 'tareas': [...], 'total': N}`; la segunda `{'ok': True, 'tarea': 'Prueba Laura tareas'}`; la tercera `{'ok': True, ...}`; la cuarta (ambigua, hay varios «Rediseño…») `{'ok': False, 'error': 'nota no encontrada o ambigua', 'candidatos': [...]}` **sin modificar ninguna nota**. Borrar la nota de prueba (`rm ~/LinuxRicing/vault/Backlog/"Prueba Laura tareas.md"` y `tasks-index scan`). Después, `systemctl --user restart laura` y probar por voz: «Laura, ¿qué tengo pendiente?», «Laura, apunta que hay que revisar la batería», «Laura, marca como hecha la de prueba».

- [ ] **Step 5: Commit**

```bash
cd ~/LinuxRicing-tareas
git add assistant/tools.py
git commit -m "feat(laura): tools listar_tareas, crear_tarea y cambiar_estado sobre tasks-index

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Cierre

**Files:**
- Modify: `vault/Backlog/Sistema unificado de tareas.md`, `vault/Backlog/Laura gestiona las tareas (crear y modificar).md`, `vault/🎯 Hoy.md` (en el árbol donde estén esas notas)
- Modify: `CLAUDE.md` del proyecto (una línea nueva en «Backlog de tareas»)

- [ ] **Step 1:** Actualizar `CLAUDE.md`: el backlog ahora se agrupa con `tasks-index`; registrar repos nuevos en `~/.config/caelestia/task-repos.json` y mantener la convención de `Backlog/` + frontmatter.
- [ ] **Step 2:** Marcar `estado: hecha` en las dos notas del backlog y añadir una línea en la Bitácora de `🎯 Hoy.md`.
- [ ] **Step 3:** Invocar `superpowers:finishing-a-development-branch` y mergear `feat/sistema-tareas` a `main` (CLAUDE.md: feature → rama → merge de vuelta).

---

## Autorrevisión del plan frente a la spec

- Formato de nota + registro → Task 1 (plantilla y `install.sh`).
- Indexador scan/set/add, JSON, `hecha`/`idea` como contadores, orden, atómico, avisos → Task 1.
- Sin demonio, `Timer` de 30 s y refresco tras `set` → Task 2.
- Cometa sobre todos los repos, incluyendo `en-curso` → Task 2.
- Widget abajo a la derecha con botón a Obsidian, casilla, abrir nota, «+N más» → Task 4.
- Clic en el cometa con panel, chips por repo y prioridad → Task 4.
- Maqueta antes del QML → Task 3.
- Laura: tres tools, búsqueda aproximada que pregunta en ambigüedad (la hace `tasks-index set` devolviendo `candidatos`), solo `estado` y creación → Tasks 1 y 5.
- Reglas de CLAUDE.md (restart completo, sin animaciones permanentes, ruta absoluta) → Constraints y pasos de verificación.
- Fuera de alcance respetado: no hay edición de contenido, borrado ni Google Tasks.

Nota de integración: el botón «Abrir en Obsidian» del widget usa la nota `🎯 Hoy` del vault de LinuxRicing; si Alberto prefiere una nota central distinta, es una constante en `TasksWidget.qml`.
