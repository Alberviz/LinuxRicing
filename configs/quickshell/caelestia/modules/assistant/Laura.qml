pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Servicio del asistente de voz Laura.
//
// Lee el bus de eventos del daemon (`$XDG_RUNTIME_DIR/laura-events.sock`,
// JSON por líneas — ver assistant/events.py) y lo expone como propiedades
// reactivas para el overlay. Si el daemon aún no está, reintenta la conexión.
Singleton {
    id: root

    // Rutas de los sockets. Sobrescribibles con LAURA_EVENTS_SOCK / LAURA_CTRL_SOCK
    // para probar con un servidor simulado (assistant/dev/mock_events.py).
    readonly property string socketPath: Quickshell.env("LAURA_EVENTS_SOCK") || `${Quickshell.env("XDG_RUNTIME_DIR")}/laura-events.sock`
    readonly property string ctrlPath: Quickshell.env("LAURA_CTRL_SOCK") || `${Quickshell.env("XDG_RUNTIME_DIR")}/laura.sock`

    // Estado del ciclo: idle | listening | thinking | speaking
    property string state: "idle"
    // Modo de invocación del ciclo en curso: centro | barra
    property string mode: "centro"
    // Último texto transcrito de Alberto
    property string transcript: ""
    // Última respuesta de Laura, al completo (para el bocadillo del modo principal)
    property string reply: ""
    // Acciones ejecutadas en el ciclo: [{icon, text}, ...]
    property var actions: []
    // Nivel de voz 0..1 (grabando y hablando), ya suavizado
    property real amplitude: 0

    readonly property bool active: state !== "idle"

    // --- Trabajos en segundo plano ---------------------------------------
    // Lista de jobs normalizados (ver PLAN-ORBE.md, evento `job`). Se reasigna
    // entera en cada cambio para que los bindings se reevalúen.
    property var jobs: []
    // Estado de UI compartido entre el orbe y el cajón.
    property bool drawerOpen: false
    property string drawerFocusId: ""
    // Pantalla donde vive el orbe (la enfocada al nacer); el cajón la sigue.
    property string dockScreen: ""
    // Trabajos que ya se leyeron con el cajón abierto: siguen en el orbe hasta cerrarlo.
    property var keepIds: ({})

    function openDrawer(id: string): void {
        const keep = Object.assign({}, root.keepIds);
        for (const j of root.jobs)
            if (root.isUnseen(j)) {
                keep[j.id] = true;
                root.read(j.id);
            }
        root.keepIds = keep;
        root.drawerFocusId = id ?? "";
        root.drawerOpen = true;
    }
    function closeDrawer(): void {
        root.drawerOpen = false;
        root.keepIds = ({});
        root.drawerFocusId = "";
    }

    // SUPER+I (hypr-user.lua): `qs -c caelestia ipc call laura toggleDrawer`.
    IpcHandler {
        target: "laura"
        function toggleDrawer(): void {
            if (root.drawerOpen) {
                root.closeDrawer();
                return;
            }
            const f = Hypr.focusedMonitor;
            if (f)
                root.dockScreen = f.name;
            root.openDrawer("");
        }
    }
    // Un trabajo NUEVO ha arrancado en vivo (no viene de la sincronización).
    signal jobStarted(var job)
    // Un trabajo ha pasado a done / failed en vivo.
    signal jobFinished(var job)

    // started|waiting|confirm|done|failed|cancelled -> running|agent|confirm|done|fail|cancel
    function kindOf(estado: string): string {
        switch (estado) {
        case "started":
            return "running";
        case "waiting":
            return "agent";
        case "confirm":
            return "confirm";
        case "done":
            return "done";
        case "failed":
            return "fail";
        case "cancelled":
            return "cancel";
        }
        return "running";
    }

    // Colores por agente (los del mockup aprobado) y de estado.
    readonly property color cWait: "#ffc65c"
    readonly property color cFail: "#ff8a9c"
    function agentColor(destino: string): color {
        switch (destino) {
        case "gemini":
            return "#7db4ff";
        case "claude":
            return "#ee9a6e";
        case "aurora":
            return "#6fdcb4";
        }
        return "#bfb0ff";
    }
    function agentName(destino: string): string {
        switch (destino) {
        case "gemini":
            return "Gemini";
        case "claude":
            return "Claude";
        case "aurora":
            return "Aurora";
        }
        return "Laura";
    }

    function isActive(j): bool {
        return j.kind === "running" || j.kind === "agent" || j.kind === "confirm";
    }

    function isUnseen(j): bool {
        return (j.kind === "done" || j.kind === "fail") && !j.leido;
    }

    function _norm(ev, prev) {
        const p = prev ?? {};
        const estado = ev.value ?? ev.estado ?? p.estado ?? "started";
        return {
            id: String(ev.id ?? p.id),
            estado: estado,
            kind: kindOf(estado),
            destino: ev.destino ?? p.destino ?? "laura",
            titulo: ev.titulo ?? p.titulo ?? "",
            resumen: ev.resumen ?? p.resumen ?? "",
            pregunta: ev.pregunta ?? p.pregunta ?? "",
            nota: ev.nota ?? p.nota ?? "",
            fuentes: ev.fuentes ?? p.fuentes ?? [],
            inicio: ev.inicio ?? p.inicio ?? Date.now() / 1000,
            fin: ev.fin !== undefined ? ev.fin : (p.fin ?? null),
            leido: ev.leido !== undefined ? !!ev.leido : (p.leido ?? false)
        };
    }

    function _upsert(ev, live: bool): void {
        if (ev.id === undefined || ev.id === null)
            return;
        const id = String(ev.id);
        const cut = Date.now() / 1000 - 86400;
        const list = root.jobs.filter(j => (j.fin ?? j.inicio) > cut || root.isActive(j));
        const idx = list.findIndex(j => j.id === id);
        const prev = idx >= 0 ? list[idx] : null;
        const j = _norm(ev, prev);
        if (idx >= 0)
            list[idx] = j;
        else
            list.push(j);
        // El aviso de «nuevo» va ANTES de publicar la lista: así el orbe puede
        // retener el dock y lanzar la convergencia antes de pintar nada.
        if (live && !prev && j.kind === "running")
            root.jobStarted(j);
        root.jobs = list;
        if (live && (!prev || prev.kind !== j.kind) && (j.kind === "done" || j.kind === "fail")) {
            if (root.drawerOpen) {
                const keep = Object.assign({}, root.keepIds);
                keep[j.id] = true;
                root.keepIds = keep;
                root.read(j.id);
            }
            root.jobFinished(j);
        }
    }

    function _syncJobs(arr): void {
        // La lista del daemon manda: lo que ya no está (p. ej. daemon reiniciado) se va.
        const ids = arr.map(e => String(e.id));
        root.jobs = root.jobs.filter(j => ids.indexOf(j.id) >= 0);
        for (const e of arr)
            _upsert(e, false);
    }

    function refreshJobs(): void {
        _ctrl("jobs", line => {
            try {
                const r = JSON.parse(line);
                if (r.jobs)
                    root._syncJobs(r.jobs);
            } catch (e) {}
        });
    }

    function cancel(id: string): void {
        _ctrl("job-cancel " + id, null);
    }
    function confirm(id: string, yes: bool): void {
        _ctrl("job-confirm " + id + " " + (yes ? "yes" : "no"), null);
    }
    function read(id: string): void {
        const j = root.jobs.find(x => x.id === id);
        if (j && !j.leido) {
            const l = root.jobs.slice();
            l[root.jobs.indexOf(j)] = Object.assign({}, j, {
                leido: true
            });
            root.jobs = l;
        }
        _ctrl("job-read " + id, null);
    }
    function follow(id: string): void {
        _ctrl("job-follow " + id, null);
    }

    // Un comando de control = una conexión corta: manda la línea, lee la
    // respuesta JSON (si hay), cierra. `cb` recibe la línea de respuesta.
    function _ctrl(cmd: string, cb): void {
        const s = ctrlComp.createObject(root, {
            cmd: cmd,
            cb: cb
        });
        if (!s)
            console.warn("Laura: no se pudo crear el socket de control");
    }

    Component {
        id: ctrlComp

        Socket {
            id: cs

            property string cmd
            property var cb
            property bool done: false

            path: root.ctrlPath
            connected: true
            onConnectedChanged: {
                if (connected) {
                    write(cmd + "\n");
                    flush();
                    if (!cb)
                        cs.dieT.interval = 600;
                } else if (!done) {
                    done = true;
                    cs.destroy();
                }
            }
            onError: {
                if (!done) {
                    done = true;
                    cs.destroy();
                }
            }
            parser: SplitParser {
                onRead: line => {
                    if (cs.done)
                        return;
                    cs.done = true;
                    if (cs.cb)
                        cs.cb(line);
                    cs.destroy();
                }
            }

            property Timer dieT: Timer {
                interval: 4000
                running: true
                onTriggered: {
                    if (!cs.done) {
                        cs.done = true;
                        cs.destroy();
                    }
                }
            }
        }
    }

    // --- Colores del theming dinámico de Caelestia (nunca hardcodear) ---
    readonly property color accent: Colours.palette.m3primary
    readonly property color accentAlt: Colours.palette.m3tertiary
    readonly property color onAccent: Colours.palette.m3onPrimary
    readonly property color surface: Colours.palette.m3surfaceContainer
    readonly property color onSurface: Colours.palette.m3onSurface

    Behavior on amplitude {
        NumberAnimation {
            duration: 90
            easing.type: Easing.OutQuad
        }
    }

    function _handle(line: string): void {
        if (!line)
            return;
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        // Cualquier línea (incluido el ping) prueba que el enlace sigue vivo.
        linkWatch.restart();
        if (ev.type === "ping")
            return;
        // Los eventos de "progreso" reinician el guardián de estado atascado;
        // amplitude no cuenta (fluye sin que el ciclo avance).
        if (ev.type !== "amplitude")
            stuckWatch.restart();
        switch (ev.type) {
        case "state":
            root.state = ev.value;
            if (ev.mode)
                root.mode = ev.mode;
            if (ev.value === "listening") {
                root.transcript = "";
                root.reply = "";
                root.actions = [];
            }
            if (ev.value === "idle")
                root.amplitude = 0;
            break;
        case "amplitude":
            root.amplitude = ev.value;
            break;
        case "transcript":
            root.transcript = ev.value;
            break;
        case "reply":
            root.reply = ev.value;
            break;
        case "result":
            root.actions = ev.actions ?? [];
            break;
        case "job":
            root._upsert(ev, true);
            break;
        }
    }

    // Quickshell no reconecta un Socket que ya erró: reasignar `connected` no
    // basta. Hay que recrear el objeto. El Socket vive en un Loader y lo
    // reciclamos cuando el enlace lleva demasiado tiempo mudo.
    Component {
        id: socketComp

        Socket {
            path: root.socketPath
            connected: true
            // Al (re)conectar, pedir la lista viva de trabajos: así no se
            // pierde el estado tras reiniciar el shell.
            onConnectedChanged: if (connected)
                root.refreshJobs()
            parser: SplitParser {
                onRead: line => root._handle(line)
            }
        }
    }

    Loader {
        id: sockLoader
        active: true
        sourceComponent: socketComp
    }

    // El daemon manda un "ping" cada 5 s; cada línea reinicia este timer. Si
    // pasan 9 s sin recibir NADA, el enlace está muerto (o el daemon aún no
    // estaba) -> recrear el Socket.
    Timer {
        id: linkWatch
        interval: 9000
        repeat: true
        running: true
        onTriggered: {
            sockLoader.active = false;
            sockLoader.active = true;
        }
    }

    // Si el ciclo se atasca (p. ej. Ollama no responde) y el estado no avanza
    // en 75 s, devolver el overlay a idle para no quedarse en "pensando".
    Timer {
        id: stuckWatch
        interval: 75000
        onTriggered: {
            root.state = "idle";
            root.amplitude = 0;
        }
    }
}
