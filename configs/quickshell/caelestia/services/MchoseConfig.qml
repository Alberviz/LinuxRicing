pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors ~/.config/caelestia/mchose-config.json. Writes go through the
// `mchose-config` CLI so it also fires `mchose-battery --trigger-lighting`.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string path: `${home}/.config/caelestia/mchose-config.json`
    readonly property string cli: `${home}/.local/bin/mchose-config`

    property string chargingEffect: "theme_breathing"
    property string lowBatEffect: "red_breathing"
    property int lowBatThreshold: 20

    // chip label -> CLI argument
    readonly property var chargingArgs: ({
            theme_breathing: "theme",
            battery_breathing: "battery",
            hardware_battery: "hardware",
            wave: "wave"
        })
    readonly property var lowBatArgs: ({
            red_breathing: "red",
            wave: "wave",
            none: "none",
            red_static: "static"
        })

    function setCharging(effectKey: string): void {
        chargingEffect = effectKey;
        Quickshell.execDetached([root.cli, "charge", chargingArgs[effectKey] ?? "theme"]);
    }

    function setLowBat(effectKey: string): void {
        lowBatEffect = effectKey;
        Quickshell.execDetached([root.cli, "lowbat", lowBatArgs[effectKey] ?? "red"]);
    }

    function setThreshold(n: int): void {
        lowBatThreshold = n;
        Quickshell.execDetached([root.cli, "threshold", String(n)]);
    }

    function previewCharging(): void {
        const map = ({
                theme_breathing: "breathing",
                battery_breathing: "battery",
                hardware_battery: "hardware",
                wave: "wave"
            });
        Quickshell.execDetached([`${root.home}/.local/bin/mchose-lighting`, map[chargingEffect] ?? "breathing"]);
    }

    FileView {
        path: root.path
        printErrors: false
        watchChanges: true

        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (typeof c.charging_effect === "string")
                    root.chargingEffect = c.charging_effect;
                if (typeof c.low_battery_effect === "string")
                    root.lowBatEffect = c.low_battery_effect;
                if (typeof c.low_battery_threshold === "number")
                    root.lowBatThreshold = c.low_battery_threshold;
            } catch (e) {
            }
        }
    }
}
