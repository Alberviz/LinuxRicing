pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string path: `${home}/.config/caelestia/rgb-config.json`
    readonly property string syncScript: `${home}/.config/caelestia/sync-rgb.py`

    // Mirrors ~/.config/caelestia/rgb-config.json (see docs/CENTRO_ILUMINACION_RGB_PLAN.md).
    property string source: "theme"                    // "theme" | "fixed"
    property string fixedColour: "d8bde7"              // hex, no leading '#'
    property var devices: ({
            openrgb: true,
            magichome: true,
            mchose_base: true,
            akko_keyboard: true,
            spicetify: true
        })
    property bool openrgbArgbZones: false
    property bool flashEnabled: false
    property string flashMode: "accent"               // "red" | "accent" | "complementary"
    property int flashPulses: 2
    property var flashDevices: ["mchose_base", "akko_keyboard"]

    property bool loaded: false

    function toJson(): string {
        return JSON.stringify({
            source: root.source,
            fixed_color: root.fixedColour,
            devices: root.devices,
            devices_extra: {
                openrgb: {
                    argb_zones: root.openrgbArgbZones
                }
            },
            notification_flash: {
                enabled: root.flashEnabled,
                mode: root.flashMode,
                pulses: root.flashPulses,
                devices: root.flashDevices
            }
        }, null, 2) + "\n";
    }

    function save(): void {
        if (root.loaded)
            saveTimer.restart();
    }

    // Re-run sync-rgb.py so the change reaches the LEDs without a button press.
    function apply(): void {
        applyTimer.restart();
    }

    function change(): void {
        save();
        apply();
    }

    function setSource(s: string): void {
        root.source = s;
        change();
    }

    function setFixedColour(hex: string): void {
        root.fixedColour = hex.replace(/^#/, "").toLowerCase();
        change();
    }

    function setDevice(key: string, on: bool): void {
        const d = Object.assign({}, root.devices);
        d[key] = on;
        root.devices = d;
        change();
    }

    function setOpenrgbArgbZones(on: bool): void {
        root.openrgbArgbZones = on;
        // The animated wave over the RAM + fan headers is a systemd --user
        // daemon (argb-wave.service). Toggle it and persist across reboots.
        Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "--now", "argb-wave.service"]);
        change();
    }

    function setFlashEnabled(on: bool): void {
        root.flashEnabled = on;
        save();
    }

    function setFlashMode(m: string): void {
        root.flashMode = m;
        save();
    }

    function setFlashPulses(n: int): void {
        root.flashPulses = Math.max(1, Math.min(5, n));
        save();
    }

    function setFlashDevice(key: string, on: bool): void {
        const s = new Set(root.flashDevices);
        if (on)
            s.add(key);
        else
            s.delete(key);
        root.flashDevices = [...s];
        save();
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: view.setText(root.toJson())
    }

    Timer {
        id: applyTimer
        interval: 500
        onTriggered: Quickshell.execDetached(["/usr/bin/python3", root.syncScript])
    }

    FileView {
        id: view

        path: root.path
        printErrors: false

        onLoaded: {
            try {
                const c = JSON.parse(view.text());
                if (c.source === "theme" || c.source === "fixed")
                    root.source = c.source;
                if (typeof c.fixed_color === "string")
                    root.fixedColour = c.fixed_color.replace(/^#/, "").toLowerCase();
                if (c.devices && typeof c.devices === "object")
                    root.devices = Object.assign({}, root.devices, c.devices);
                if (c.devices_extra && c.devices_extra.openrgb && c.devices_extra.openrgb.argb_zones !== undefined)
                    root.openrgbArgbZones = !!c.devices_extra.openrgb.argb_zones;
                const f = c.notification_flash ?? {};
                if (f.enabled !== undefined)
                    root.flashEnabled = !!f.enabled;
                if (typeof f.mode === "string")
                    root.flashMode = f.mode;
                if (typeof f.pulses === "number")
                    root.flashPulses = f.pulses;
                if (Array.isArray(f.devices))
                    root.flashDevices = f.devices;
            } catch (e) {
                console.warn("RgbConfig: bad rgb-config.json:", e);
            }
            root.loaded = true;
        }

        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => view.setText(root.toJson()));
        }
    }
}
