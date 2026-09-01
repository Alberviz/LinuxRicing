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
    property list<var> runningAgents: []
    readonly property int count: completedAgents.length

    // Un pulso "en curso" caduca si nadie lo refresca. Los hooks per-turno de
    // Claude Code mandan `start` en cada prompt (refresca startTime) y `complete`
    // al terminar; si un `complete` se pierde (terminal ya cerrado -> address
    // vacío, SIGKILL, crash) esto evita que el halo parpadee para siempre.
    readonly property int runningTtlMs: 20 * 60 * 1000

    // Estilo visual (config: ~/.config/caelestia/agents-config.json)
    property string runningStyle: "blink"   // blink | breathe | arc
    property string unseenMarker: "badge"   // badge | wedge

    // Sonidos de notificación (config: ~/.config/caelestia/agents-config.json)
    property bool soundEnabled: true
    property real soundVolume: 0.6
    property string soundStart: "/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga"
    property string soundComplete: "/usr/share/sounds/freedesktop/stereo/complete.oga"
    property string soundError: "/usr/share/sounds/freedesktop/stereo/dialog-error.oga"

    signal agentAdded(var agent)
    signal agentRemoved(string id)

    // Nudge para recomputar los mapas cuando cambia el foco o el nº de ventanas.
    readonly property var wsMap: {
        const _deps = [Hypr.activeWsId, Hyprland.toplevels.values.length, completedAgents.length];
        const m = ({});
        for (const a of root.completedAgents) {
            const w = root.liveWs(a.address, a.ws);
            (m[w] = m[w] || []).push(a);
        }
        return m;
    }

    readonly property var runningWsMap: {
        const _deps = [Hypr.activeWsId, Hyprland.toplevels.values.length, runningAgents.length];
        const now = Date.now();
        const m = ({});
        for (const a of root.runningAgents) {
            if (a.startTime && (now - a.startTime) > root.runningTtlMs)
                continue; // pulso caducado: no lo pintamos
            const w = root.liveWs(a.address, a.ws);
            (m[w] = m[w] || []).push(a);
        }
        return m;
    }

    // Poda periódica de pulsos "en curso" caducados (respaldo del filtro de
    // runningWsMap, para que la lista no crezca sin límite).
    Timer {
        interval: 60000
        running: root.runningAgents.length > 0
        repeat: true
        onTriggered: {
            const now = Date.now();
            const fresh = root.runningAgents.filter(a => a.startTime && (now - a.startTime) <= root.runningTtlMs);
            if (fresh.length !== root.runningAgents.length)
                root.runningAgents = fresh;
        }
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

    function runningForWs(n: int): var {
        return root.runningWsMap[n] || [];
    }

    function hasCompletedForWs(n: int): bool {
        return (root.wsMap[n] || []).length > 0;
    }

    function hasRunningForWs(n: int): bool {
        return (root.runningWsMap[n] || []).length > 0;
    }

    function hasUnseenForWs(n: int): bool {
        return (root.wsMap[n] || []).some(a => !a.seen);
    }

    function unseenCountForWs(n: int): int {
        return (root.wsMap[n] || []).filter(a => !a.seen).length;
    }

    function _parse(dataStr) {
        try {
            return typeof dataStr === "string" ? JSON.parse(dataStr) : dataStr;
        } catch (e) {
            console.warn("Agents: JSON inválido:", e, dataStr);
            return null;
        }
    }

    // Alta / actualización de un agente en ejecución (una entrada por terminal).
    function start(dataStr: string): void {
        const data = root._parse(dataStr);
        if (!data || typeof data !== "object")
            return;

        const address = data.address || "";
        const na = root._normAddr(address);
        const entry = {
            id: data.id || `agent-${Date.now()}`,
            name: data.name || "Agente",
            task: data.task || "Trabajando…",
            status: "running",
            dir: data.dir || "",
            ws: data.ws || 1,
            address: address,
            startTime: data.startTime || Date.now(),
            time: new Date()
        };

        root.runningAgents = [
            ...root.runningAgents.filter(a => na === "" || root._normAddr(a.address) !== na),
            entry
        ];

        root._playSound(root.soundStart);
    }

    // El agente terminó: pasa de runningAgents a completedAgents.
    function complete(dataStr: string): void {
        const data = root._parse(dataStr);
        if (!data || typeof data !== "object")
            return;
        root._addCompleted(data);
    }

    // Compat: interceptación de notificaciones nativas (Antigravity).
    function notify(dataStr: string): void {
        const data = root._parse(dataStr);
        if (!data || typeof data !== "object")
            return;
        root._addCompleted(data);
    }

    function _addCompleted(data): void {
        const address = data.address || "";
        const na = root._normAddr(address);
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

        // Sale de la lista de "en curso". Con address, filtramos por address.
        // Sin address (el terminal ya se cerró y `finish` no pudo resolverlo):
        // solo limpiamos por nombre si hay UNA única entrada con ese nombre, para
        // no apagar el pulso de otra sesión del mismo agente que sí siga viva.
        // El resto lo recoge el TTL de runningTtlMs.
        if (na) {
            root.runningAgents = root.runningAgents.filter(a => root._normAddr(a.address) !== na);
        } else {
            const sameName = root.runningAgents.filter(a => a.name === entry.name);
            if (sameName.length === 1)
                root.runningAgents = root.runningAgents.filter(a => a.name !== entry.name);
        }
        // …y entra en "completado" (una entrada por terminal).
        root.completedAgents = [
            ...root.completedAgents.filter(a => a.id !== entry.id && (na === "" || root._normAddr(a.address) !== na)),
            entry
        ];

        const isError = /error|cancel|fall/i.test(String(entry.status));
        root._playSound(isError ? root.soundError : root.soundComplete);

        root.agentAdded(entry);
    }

    // Reproduce un sonido de notificación (fire-and-forget, no bloqueante).
    // Se salta si los sonidos están desactivados o si el modo No Molestar está activo.
    function _playSound(path: string): void {
        if (!root.soundEnabled || !path || path.length === 0)
            return;
        if (Notifs.dnd)
            return;
        soundProcComp.createObject(root, {
            command: ["pw-play", `--volume=${root.soundVolume}`, path],
            running: true
        });
    }

    Component {
        id: soundProcComp

        Process {
            onExited: destroy()
        }
    }

    function markSeen(wsOrId): void {
        const target = wsOrId;
        root.completedAgents = root.completedAgents.map(a => {
            const match = (typeof target === "number")
                ? root.liveWs(a.address, a.ws) === target
                : a.id === target;
            if (match && !a.seen)
                return Object.assign(({}), a, { seen: true });
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
        root.runningAgents = root.runningAgents.filter(a => a.id !== id);
        root.agentRemoved(id);
    }

    function dismissByAddress(address: string): void {
        const norm = root._normAddr(address);
        root.completedAgents = root.completedAgents.filter(a => root._normAddr(a.address) !== norm);
        root.runningAgents = root.runningAgents.filter(a => root._normAddr(a.address) !== norm);
    }

    // Apaga solo el pulso "en curso" de una ventana, sin tocar lo completado.
    // Lo usa el wrapper `agent-notify run` al salir, para barrer un pulso que
    // dejara un turno interrumpido (el terminal aún vivo -> address fiable).
    function clearRunningByAddress(dataStr: string): void {
        const data = root._parse(dataStr);
        const norm = root._normAddr((data && data.address) || dataStr || "");
        if (!norm)
            return;
        root.runningAgents = root.runningAgents.filter(a => root._normAddr(a.address) !== norm);
    }

    function clearAll(): void {
        root.completedAgents = [];
        root.runningAgents = [];
    }

    // Al enfocar la ventana del agente -> descartar (solo lo completado; el pulso
    // "en curso" se mantiene aunque mires la ventana, hasta que el agente termine).
    Connections {
        target: Hyprland

        function onActiveToplevelChanged(): void {
            const active = Hyprland.activeToplevel;
            if (active && active.address) {
                const norm = root._normAddr(active.address);
                root.completedAgents = root.completedAgents.filter(a => root._normAddr(a.address) !== norm);
            }
        }

        // Al entrar a un workspace cuya ventana de agente ya no existe -> descartar.
        function onFocusedWorkspaceChanged(): void {
            const wsId = Hyprland.focusedWorkspace?.id;
            if (!wsId)
                return;
            const gone = a => {
                const onThisWs = root.liveWs(a.address, a.ws) === wsId;
                const stillOpen = Hyprland.toplevels.values.some(t => root._normAddr(t.address) === root._normAddr(a.address));
                return onThisWs && !stillOpen;
            };
            root.completedAgents = root.completedAgents.filter(a => !gone(a));
            root.runningAgents = root.runningAgents.filter(a => !gone(a));
        }
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.config/caelestia/agents-config.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const cfg = JSON.parse(text());
                if (cfg.runningStyle)
                    root.runningStyle = cfg.runningStyle;
                if (cfg.unseenMarker)
                    root.unseenMarker = cfg.unseenMarker;
                if (cfg.soundEnabled !== undefined)
                    root.soundEnabled = cfg.soundEnabled;
                if (cfg.soundVolume !== undefined)
                    root.soundVolume = cfg.soundVolume;
                if (cfg.soundStart)
                    root.soundStart = cfg.soundStart;
                if (cfg.soundComplete)
                    root.soundComplete = cfg.soundComplete;
                if (cfg.soundError)
                    root.soundError = cfg.soundError;
            } catch (e) {
                // valores por defecto
            }
        }
    }

    IpcHandler {
        target: "agents"

        function start(data: string): void { root.start(data); }
        function complete(data: string): void { root.complete(data); }
        function notify(data: string): void { root.notify(data); }
        function clearRunning(data: string): void { root.clearRunningByAddress(data); }
        function focus(address: string): void { root.focus(address); }
        function dismiss(id: string): void { root.dismiss(id); }
        function markSeen(ws: int): void { root.markSeen(ws); }
        function clearAll(): void { root.clearAll(); }
        function list(): string { return JSON.stringify(root.completedAgents); }
        function listRunning(): string { return JSON.stringify(root.runningAgents); }
    }
}
