pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import qs.services

Singleton {
    id: root

    readonly property bool onBattery: UPower.onBattery
    readonly property bool isSaverProfile: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property bool isLowBattery: UPower.displayDevice.isLaptopBattery && UPower.displayDevice.percentage <= 0.20

    // Modo activo: en batería, perfil power-saver o batería crítica
    readonly property bool active: onBattery || isSaverProfile || isLowBattery

    property int previousProfile: PowerProfile.Balanced
    property bool autoSwitchedProfile: false

    function applyHyprlandConfs(): void {
        Quickshell.execDetached([
            "hyprctl", "eval",
            "hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false }, shadow = { enabled = false } } })"
        ]);
    }

    function restoreHyprlandConfs(): void {
        if (GameMode.enabled) {
            GameMode.setDynamicConfs();
        } else {
            Quickshell.execDetached([
                "hyprctl", "eval",
                "hl.config({ animations = { enabled = true }, decoration = { blur = { enabled = true }, shadow = { enabled = true } } })"
            ]);
        }
    }

    function checkState(): void {
        if (active) {
            if (UPower.onBattery && PowerProfiles.profile !== PowerProfile.PowerSaver) {
                previousProfile = PowerProfiles.profile;
                autoSwitchedProfile = true;
                PowerProfiles.profile = PowerProfile.PowerSaver;
            }
            applyHyprlandConfs();
        } else {
            if (autoSwitchedProfile && PowerProfiles.profile === PowerProfile.PowerSaver) {
                PowerProfiles.profile = previousProfile;
                autoSwitchedProfile = false;
            }
            restoreHyprlandConfs();
        }
    }

    onActiveChanged: checkState()
    Component.onCompleted: checkState()

    Connections {
        function onConfigReloaded(): void {
            if (root.active)
                root.applyHyprlandConfs();
        }

        target: Hypr
    }

    IpcHandler {
        function isActive(): bool {
            return root.active;
        }

        target: "powerSaving"
    }
}
