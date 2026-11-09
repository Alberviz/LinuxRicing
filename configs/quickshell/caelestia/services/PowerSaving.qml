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

    // Último modo aplicado (on/off), en $XDG_RUNTIME_DIR: sobrevive a reinicios del shell. Al arrancar solo se
    // reaplica si no coincide (así un reinicio con AC no vuelve a encender el Bluetooth ni toca la tasa de refresco).
    readonly property string appliedMark: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-power-applied`

    function runTweaks(mode: string, onlyIfChanged: bool): void {
        const guard = onlyIfChanged ? `[ "$(cat '${appliedMark}' 2>/dev/null)" = ${mode} ] && exit 0; ` : "";
        Quickshell.execDetached(["sh", "-c", `${guard}echo ${mode} > '${appliedMark}'; exec '${tweaksScript}' ${mode}`]);
    }

    function applyPowerTweaks(): void {
        runTweaks("on", false);
    }

    function restorePowerTweaks(): void {
        runTweaks("off", false);
    }

    // La marca de «Laura parada por el ahorro» vive en un fichero de $XDG_RUNTIME_DIR, no en memoria:
    // si el shell se reinicia (o se cuelga) estando en batería, al enchufar se sigue sabiendo que hay
    // que volver a arrancarla. Antes era una propiedad y tras un reinicio Laura se quedaba parada.
    readonly property string lauraMark: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-laura-autostopped`

    function applyLauraPowerSaving(): void {
        Quickshell.execDetached(["sh", "-c", `systemctl --user is-active --quiet laura && touch '${lauraMark}'; systemctl --user stop laura`]);
    }

    function restoreLauraPowerSaving(): void {
        Quickshell.execDetached(["sh", "-c", `[ -e '${lauraMark}' ] && rm -f '${lauraMark}' && systemctl --user start laura`]);
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

    Timer {
        id: reconcileTimer

        interval: 1500
        onTriggered: {
            root.wasActive = root.active;
            if (root.active) {
                root.applyHyprlandConfs();
                root.runTweaks("on", true);
                root.applyLauraPowerSaving();
            } else {
                root.runTweaks("off", true);
                root.restoreLauraPowerSaving();
            }
        }
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
        // Reconciliar al arrancar: si el enchufe/desenchufe ocurrió con el shell caído o reiniciándose, el
        // evento se perdió y Ollama/Laura se quedaban parados aunque ya hubiera corriente.
        reconcileTimer.start();
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
            if (root.active) {
                root.applyHyprlandConfs();
                root.applyPowerTweaks();
            }
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
