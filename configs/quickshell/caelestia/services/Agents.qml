pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property list<var> completedAgents: []
    readonly property int count: completedAgents.length

    signal agentAdded(var agent)
    signal agentRemoved(string id)

    function notify(dataStr: string): void {
        try {
            let data = typeof dataStr === "string" ? JSON.parse(dataStr) : dataStr;
            if (!data || typeof data !== "object")
                return;

            const id = data.id || `agent-${Date.now()}`;
            const address = data.address || "";
            const ws = data.ws || 1;
            const name = data.name || "Agente";
            const dir = data.dir || "";
            const num = data.num || (root.completedAgents.length + 1);
            const status = data.status || "Completado";

            const newAgent = {
                id: id,
                num: num,
                name: name,
                ws: ws,
                address: address,
                dir: dir,
                status: status,
                time: new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
            };

            // Filtrar duplicados con mismo address o id
            const remaining = root.completedAgents.filter(a => a.id !== id && (address === "" || a.address !== address));
            root.completedAgents = [...remaining, newAgent];
            root.agentAdded(newAgent);
        } catch (e) {
            console.warn("Agents.notify: Error parsing data:", e, dataStr);
        }
    }

    function focus(address: string): void {
        if (!address || address.length === 0)
            return;

        const target = address.startsWith("0x") ? address : `0x${address}`;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:${target}" })` : `focuswindow address:${target}`);

        // Descartar de la lista de pendientes
        dismissByAddress(target);
    }

    function dismiss(id: string): void {
        root.completedAgents = root.completedAgents.filter(a => a.id !== id);
        root.agentRemoved(id);
    }

    function dismissByAddress(address: string): void {
        const norm = address.toLowerCase();
        root.completedAgents = root.completedAgents.filter(a => {
            const aAddr = (a.address || "").toLowerCase();
            return aAddr !== norm && (norm.startsWith("0x") ? aAddr !== norm.slice(2) : `0x${aAddr}` !== norm);
        });
    }

    function clearAll(): void {
        root.completedAgents = [];
    }

    // Auto-descartar píldora cuando el usuario entra activamente a esa ventana
    Connections {
        target: Hyprland

        function onActiveToplevelChanged(): void {
            const active = Hyprland.activeToplevel;
            if (active && active.address) {
                root.dismissByAddress(active.address);
            }
        }
    }

    IpcHandler {
        target: "agents"

        function notify(data: string): void {
            root.notify(data);
        }

        function focus(address: string): void {
            root.focus(address);
        }

        function dismiss(id: string): void {
            root.dismiss(id);
        }

        function clearAll(): void {
            root.clearAll();
        }

        function list(): string {
            return JSON.stringify(root.completedAgents);
        }
    }
}
