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
