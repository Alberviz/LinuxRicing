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

    // Permite desactivar manualmente el modo ahorro (ej: demostración o máximo rendimiento en batería)
    property bool manualOverride: false

    // Modo activo: en batería o batería crítica, salvo anulación manual.
    // Elegir power-saver a mano con AC NO activa el ahorro extremo (solo cambia el perfil).
    readonly property bool active: !manualOverride && (onBattery || isLowBattery)

    FileView {
        id: stateView

        path: `${Quickshell.env("HOME")}/.config/caelestia/desktop-state.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (typeof d.powerSavingOverride === "boolean")
                    root.manualOverride = d.powerSavingOverride;
            } catch (e) {}
        }
    }

    function setManualOverride(v: bool): void {
        manualOverride = v;
        try {
            let d = {};
            try { d = JSON.parse(stateView.text()); } catch (e) {}
            d.powerSavingOverride = v;
            stateView.setText(JSON.stringify(d, null, 2) + "\n");
        } catch (e) {}
    }

    property int previousProfile: PowerProfile.Balanced
    property bool autoSwitchedProfile: false
    // Estado de `active` en la comprobación anterior (para detectar batería -> AC)
    property bool wasActive: false
    property bool lauraAutoStopped: false
    readonly property string tweaksScript: Quickshell.env("HOME") + "/.local/bin/caelestia-power-tweaks"

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

    function applyPowerTweaks(): void {
        Quickshell.execDetached([tweaksScript, "on"]);
    }

    function restorePowerTweaks(): void {
        Quickshell.execDetached([tweaksScript, "off"]);
    }

    function applyLauraPowerSaving(): void {
        Quickshell.execDetached(["systemctl", "--user", "stop", "laura"]);
        lauraAutoStopped = true;
    }

    function restoreLauraPowerSaving(): void {
        if (lauraAutoStopped) {
            Quickshell.execDetached(["systemctl", "--user", "start", "laura"]);
            lauraAutoStopped = false;
        }
    }

    function checkState(): void {
        const prevActive = wasActive;
        wasActive = active;
        if (active) {
            if (UPower.onBattery && PowerProfiles.profile !== PowerProfile.PowerSaver) {
                previousProfile = PowerProfiles.profile;
                autoSwitchedProfile = true;
                PowerProfiles.profile = PowerProfile.PowerSaver;
            }
            applyHyprlandConfs();
            applyPowerTweaks();
            applyLauraPowerSaving();
        } else {
            // Al salir del ahorro: restaurar el perfil si lo pusimos nosotros, o si venimos
            // de estar activos y ya hay AC (autoSwitchedProfile se pierde al reiniciar el shell).
            // Al arrancar enchufado (prevActive=false) no se toca el perfil.
            if (PowerProfiles.profile === PowerProfile.PowerSaver && (autoSwitchedProfile || (prevActive && !onBattery)))
                PowerProfiles.profile = previousProfile;
            autoSwitchedProfile = false;
            restoreHyprlandConfs();
            restorePowerTweaks();
            restoreLauraPowerSaving();
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

        function isOverride(): bool {
            return root.manualOverride;
        }

        function setOverride(v: bool): void {
            root.setManualOverride(v);
        }

        function toggleOverride(): bool {
            root.setManualOverride(!root.manualOverride);
            return root.manualOverride;
        }

        target: "powerSaving"
    }
}
