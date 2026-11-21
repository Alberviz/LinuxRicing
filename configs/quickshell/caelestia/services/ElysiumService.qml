pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services

Singleton {
    id: root

    readonly property string updatePath: `${Quickshell.env("HOME")}/.cache/elysium/hookshot-update.json`

    property var upd: ({})
    property bool updAlive: false
    readonly property bool updating: ["downloading", "building", "shaders"].indexOf(upd.state ?? "") >= 0 && updAlive
    readonly property string state: upd.state ?? ""
    readonly property string stage: upd.stage ?? ""
    readonly property string text: upd.text ?? ""
    readonly property real pct: typeof upd.pct === "number" ? Math.max(0, Math.min(1, upd.pct)) : 0
    readonly property var files: upd.files ?? null
    readonly property int eta: typeof upd.eta === "number" ? upd.eta : 0
    readonly property string version: upd.latest ?? ""

    property string _lastStage: ""
    property string _lastState: ""

    FileView {
        id: updFile

        path: root.updatePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.upd = JSON.parse(text());
            } catch (e) {}
        }
    }

    Timer {
        id: updAliveTimer

        interval: 2500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: updAliveProc.running = true
    }

    Process {
        id: updAliveProc

        command: ["systemctl", "--user", "is-active", "-q", "elysium-hookshot-update"]
        onExited: code => root.updAlive = code === 0
    }

    onStateChanged: {
        if (!state || state === _lastState)
            return;
        const prev = _lastState;
        _lastState = state;
        if (!prev)
            return;

        if (state === "done") {
            Toaster.toast(
                qsTr("Hookshot actualizado"),
                qsTr("Versión %1 lista para jugar").arg(root.version || qsTr("nueva")),
                "check_circle"
            );
        } else if (state === "error") {
            Toaster.toast(
                qsTr("Error actualizando Hookshot"),
                upd.error || qsTr("Ocurrió un error durante la actualización"),
                "error"
            );
        }
    }

    onStageChanged: {
        if (!updating || !stage || stage === _lastStage)
            return;
        _lastStage = stage;

        if (stage === "shaders") {
            Toaster.toast(
                qsTr("Precompilando shaders"),
                qsTr("Hookshot continúa en segundo plano (puedes usar el escritorio normalmente)"),
                "deployed_code"
            );
        } else if (stage === "compile") {
            Toaster.toast(
                qsTr("Compilando Hookshot"),
                (root.text || qsTr("Compilación en segundo plano")) + (root.files ? ` (${root.files[0]}/${root.files[1]})` : ""),
                "build"
            );
        }
    }
}
