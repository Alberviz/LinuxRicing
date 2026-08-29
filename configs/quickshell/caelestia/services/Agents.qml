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
