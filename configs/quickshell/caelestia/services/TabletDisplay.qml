pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.local/bin/caelestia-tablet-display"

    // Es activo si el monitor Tablet está presente en las pantallas de Quickshell
    readonly property bool active: Quickshell.screens.some(s => s.name === "Tablet")

    function toggle(): void {
        Quickshell.execDetached([root.script, "toggle"]);
    }

    function enable(): void {
        Quickshell.execDetached([root.script, "on"]);
    }

    function disable(): void {
        Quickshell.execDetached([root.script, "off"]);
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        function enable(): void {
            root.enable();
        }

        function disable(): void {
            root.disable();
        }

        function isActive(): bool {
            return root.active;
        }

        target: "tabletDisplay"
    }
}
