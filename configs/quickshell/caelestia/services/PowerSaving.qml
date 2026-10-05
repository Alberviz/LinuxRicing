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

    // Modo activo (60 Hz, turbo off, servicios/LEDs fuera): power-saver elegido a mano
    // (con o sin AC), o batería / batería baja salvo anulación manual.
    // La dGPU NO depende de esto: siempre queda en runtime PM `auto` (ver caelestia-power-root).
    readonly property bool active: isSaverProfile || (!manualOverride && (onBattery || isLowBattery))

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

    // Aplica la matriz completa de forma idempotente según `active`.
    function checkState(): void {
        wasActive = active;
        if (active) {
            applyHyprlandConfs();
            applyPowerTweaks();
            applyLauraPowerSaving();
        } else {
            restoreHyprlandConfs();
            restorePowerTweaks();
            restoreLauraPowerSaving();
        }
    }

    // Transición de corriente: en batería fuerza power-saver (recordando el perfil);
    // al enchufar lo restaura. Es independiente de `active` para que también funcione
    // cuando el saver ya era el perfil activo (active no cambia en el enchufe).
    property bool wasOnBattery: onBattery
    function handleAcChange(): void {
        if (onBattery) {
            if (!manualOverride && PowerProfiles.profile !== PowerProfile.PowerSaver) {
                previousProfile = PowerProfiles.profile;
                autoSwitchedProfile = true;
                PowerProfiles.profile = PowerProfile.PowerSaver;
            }
        } else if (wasOnBattery && PowerProfiles.profile === PowerProfile.PowerSaver) {
            PowerProfiles.profile = previousProfile;
            autoSwitchedProfile = false;
        }
        wasOnBattery = onBattery;
        stateTimer.restart();
    }

    // Agrupa eventos casi simultáneos (enchufe + cambio de perfil + active) en una sola aplicación.
    Timer {
        id: stateTimer

        interval: 400
        onTriggered: root.checkState()
    }

    onOnBatteryChanged: handleAcChange()
    onIsLowBatteryChanged: stateTimer.restart()
    onActiveChanged: stateTimer.restart()
    Component.onCompleted: {
        // Arrancar en batería sin saver: forzarlo. Arrancar con AC no toca el perfil.
        if (onBattery && !manualOverride && PowerProfiles.profile !== PowerProfile.PowerSaver) {
            previousProfile = PowerProfiles.profile;
            autoSwitchedProfile = true;
            PowerProfiles.profile = PowerProfile.PowerSaver;
        }
        checkState();
    }

    // Cambio de perfil (también estando enchufado): reaplicar la matriz.
    Connections {
        function onProfileChanged(): void {
            stateTimer.restart();
        }

        target: PowerProfiles
    }

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
