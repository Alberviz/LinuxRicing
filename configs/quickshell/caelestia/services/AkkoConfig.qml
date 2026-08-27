pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors ~/.config/caelestia/akko-config.json.
//
// FRONTEND ONLY for now: this singleton just persists the user's preferences.
// There is no reactive engine behind it yet because the Akko 5075B does not
// report its battery / charging state over the 2.4 GHz link (the official
// Windows driver uses a proprietary RF transport we have not reverse-engineered
// - see docs/HARDWARE_PROTOCOLS.md §1.B). Once battery telemetry exists, a
// backend (mchose-battery / sync-rgb.py) can read this same file and drive the
// two Akko light zones. Until then, changing anything here is a no-op on the
// hardware - it only records intent.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string path: `${home}/.config/caelestia/akko-config.json`

    // Master toggle: should the keyboard react to battery events at all, or
    // just always follow the global theme colour.
    property bool reactiveEnabled: true

    // --- Al cargar ---
    // backlight: "theme" | "fill" | "breathing" | "stream"
    property string chargingBacklight: "fill"
    // sidestrip: "stream_battery" | "breathing" | "solid" | "none"
    property string chargingSidestrip: "stream_battery"

    // --- Batería baja ---
    // backlight / sidestrip: "none" | "red_breathing" | "red_static"
    property string lowBatBacklight: "red_breathing"
    property string lowBatSidestrip: "red_breathing"

    property int lowBatThreshold: 20

    property bool loaded: false

    readonly property var chargingBacklightOptions: [
        { key: "theme", label: qsTr("Tema") },
        { key: "fill", label: qsTr("Barra de carga") },
        { key: "breathing", label: qsTr("Respiración") },
        { key: "stream", label: qsTr("Flujo") }
    ]
    readonly property var chargingSidestripOptions: [
        { key: "stream_battery", label: qsTr("Flujo") },
        { key: "breathing", label: qsTr("Respiración") },
        { key: "solid", label: qsTr("Fijo") },
        { key: "none", label: qsTr("Ninguno") }
    ]
    readonly property var lowBatOptions: [
        { key: "red_breathing", label: qsTr("Respiración roja") },
        { key: "red_static", label: qsTr("Roja fija") },
        { key: "none", label: qsTr("Ninguna") }
    ]

    function toJson(): string {
        return JSON.stringify({
            reactive_enabled: root.reactiveEnabled,
            charging: {
                backlight: root.chargingBacklight,
                sidestrip: root.chargingSidestrip
            },
            low_battery: {
                backlight: root.lowBatBacklight,
                sidestrip: root.lowBatSidestrip
            },
            low_battery_threshold: root.lowBatThreshold
        }, null, 2) + "\n";
    }

    function save(): void {
        if (root.loaded)
            saveTimer.restart();
    }

    function setReactiveEnabled(on: bool): void {
        root.reactiveEnabled = on;
        save();
    }

    function setChargingBacklight(key: string): void {
        root.chargingBacklight = key;
        save();
    }

    function setChargingSidestrip(key: string): void {
        root.chargingSidestrip = key;
        save();
    }

    function setLowBatBacklight(key: string): void {
        root.lowBatBacklight = key;
        save();
    }

    function setLowBatSidestrip(key: string): void {
        root.lowBatSidestrip = key;
        save();
    }

    function setThreshold(n: int): void {
        const v = Math.min(40, Math.max(5, n));
        if (v === root.lowBatThreshold)
            return;
        root.lowBatThreshold = v;
        save();
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: view.setText(root.toJson())
    }

    FileView {
        id: view

        path: root.path
        printErrors: false
        watchChanges: true

        onFileChanged: reload()

        onLoaded: {
            try {
                const c = JSON.parse(view.text());
                if (c.reactive_enabled !== undefined)
                    root.reactiveEnabled = !!c.reactive_enabled;

                const ch = c.charging ?? {};
                if (typeof ch.backlight === "string")
                    root.chargingBacklight = ch.backlight;
                if (typeof ch.sidestrip === "string")
                    root.chargingSidestrip = ch.sidestrip;

                const lb = c.low_battery ?? {};
                if (typeof lb.backlight === "string")
                    root.lowBatBacklight = lb.backlight;
                if (typeof lb.sidestrip === "string")
                    root.lowBatSidestrip = lb.sidestrip;

                if (typeof c.low_battery_threshold === "number")
                    root.lowBatThreshold = c.low_battery_threshold;
            } catch (e) {
                console.warn("AkkoConfig: bad akko-config.json:", e);
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
