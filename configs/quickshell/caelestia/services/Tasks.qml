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
    property string hoyUri: ""

    // El widget sin tarjeta de fondo (solo texto sobre el escritorio). Se persiste en un
    // fichero propio (tasks-widget.json): desktop-state.json lo comparten otros servicios
    // y varias instancias de Quickshell, y un snapshot viejo pisaba estas claves.
    property bool widgetTransparente: false
    // Desplegado (lista) o plegado (solo «TAREAS» y el recuento). Persistido igual.
    property bool widgetExpandido: false
    property bool _stateLoaded: false

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

    function abrirHoy(): void {
        if (root.hoyUri !== "")
            Quickshell.execDetached(["xdg-open", root.hoyUri]);
    }

    // pendiente -> en-curso -> hecha
    function siguienteEstado(estado: string): string {
        return estado === "pendiente" ? "en-curso" : "hecha";
    }

    function etiquetaEstado(estado: string): string {
        return estado === "en-curso" ? "en curso" : estado;
    }

    function cambiarEstado(t, estado: string): void {
        setProc.command = ["sh", "-c", "\"$HOME/.local/bin/tasks-index\" set \"$1\" \"$2\" \"$3\"", "sh", t.repo, t.titulo, estado];
        setProc.running = true;
    }

    function marcarHecha(t): void {
        root.cambiarEstado(t, "hecha");
    }

    function setWidgetTransparente(v: bool): void {
        root.widgetTransparente = v;
        root._guardar("transparente", v);
    }

    function setWidgetExpandido(v: bool): void {
        root.widgetExpandido = v;
        root._guardar("expandido", v);
    }

    function _guardar(clave: string, valor): void {
        if (!root._stateLoaded)
            return;
        // Read-modify-write: conservar las claves ajenas del fichero.
        let cur = {};
        try {
            const parsed = JSON.parse(stateView.text());
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
                cur = parsed;
        } catch (e) {}
        cur[clave] = valor;
        stateView.setText(JSON.stringify(cur, null, 2) + "\n");
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
                    root.hoyUri = d.hoy || "";
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

    FileView {
        id: stateView

        path: `${Quickshell.env("HOME")}/.config/caelestia/tasks-widget.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (typeof d.transparente === "boolean")
                    root.widgetTransparente = d.transparente;
                if (typeof d.expandido === "boolean")
                    root.widgetExpandido = d.expandido;
            } catch (e) {
                console.warn("Tasks: tasks-widget.json inválido:", e);
            }
            root._stateLoaded = true;
        }
        onLoadFailed: root._stateLoaded = true
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
