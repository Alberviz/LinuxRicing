pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Perfiles A2DP / códec de las tarjetas bluez de PipeWire, vía pactl.
// Quickshell.Services.Pipewire no expone perfiles de tarjeta.
Singleton {
    id: root

    // { "bluez_card.84_AC_...": { active: "a2dp-sink", profiles: [{ name, description, codec }] } }
    property var cards: ({})
    // Mientras sea true, se refresca cada 5 s (sin animaciones, solo un Timer).
    property int watchers: 0
    property string lastError: ""

    function cardName(address: string): string {
        return address ? "bluez_card." + address.replace(/:/g, "_") : "";
    }

    function cardFor(address: string): var {
        return cards[cardName(address)] ?? null;
    }

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    function setProfile(address: string, profile: string): void {
        const card = cardName(address);
        if (!card || !profile || setProc.running)
            return;
        setProc.command = ["pactl", "set-card-profile", card, profile];
        setProc.running = true;
    }

    function codecOf(description: string): string {
        const m = /codec ([^)]+)/.exec(description ?? "");
        return m ? m[1] : "";
    }

    function parse(text: string): void {
        let list;
        try {
            list = JSON.parse(text);
        } catch (e) {
            lastError = "pactl: salida no válida";
            cards = ({});
            return;
        }
        const out = {};
        for (const c of list) {
            if (!c.name || !c.name.startsWith("bluez_card."))
                continue;
            const profiles = [];
            for (const [name, p] of Object.entries(c.profiles ?? {})) {
                if (!name.startsWith("a2dp-sink") || p.available === false || (p.sinks ?? 0) < 1)
                    continue;
                profiles.push({
                    name,
                    description: p.description ?? name,
                    codec: codecOf(p.description),
                    priority: p.priority ?? 0
                });
            }
            profiles.sort((a, b) => b.priority - a.priority);
            out[c.name] = {
                active: c.active_profile ?? "",
                profiles
            };
        }
        lastError = "";
        cards = out;
    }

    Process {
        id: listProc

        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            id: listOut
        }
        onExited: code => {
            if (code === 0)
                root.parse(listOut.text);
            else {
                root.lastError = "pactl falló (" + code + ")";
                root.cards = ({});
            }
        }
    }

    Process {
        id: setProc

        onExited: code => {
            if (code !== 0)
                root.lastError = "set-card-profile falló (" + code + ")";
            root.refresh();
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.watchers > 0
        onTriggered: root.refresh()
    }
}
