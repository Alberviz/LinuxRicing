pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia

// Estado del daemon de Laura con fases y progreso, para dar referencias visuales
// al encenderla/apagarla (arrancar lleva ~10 s: Whisper, voz, modelo).
//   state: "off" | "starting" | "on" | "stopping" | "error"
//   phase: texto de la fase actual · progress: 0..1 · eta: segundos estimados restantes
Singleton {
    id: root

    property string state: "off"
    property string phase: ""
    property real progress: 0
    property int eta: 0
    readonly property bool busy: state === "starting" || state === "stopping"
    readonly property bool on: state === "on"

    // Duración típica medida del arranque (s); se recalcula con cada arranque real.
    property real typicalStart: 10
    property real _t0: 0

    signal ready

    function start(): void {
        if (state === "on" || state === "starting")
            return;
        state = "starting";
        _setPhase(qsTr("Arrancando el servicio"), 0.05);
        _t0 = Date.now();
        follower.running = false;
        follower.running = true;
        startProc.running = true;
        Toaster.toast(qsTr("Encendiendo Laura"), qsTr("Cargando voz y modelos (~%1 s)").arg(Math.round(typicalStart)), "hourglass_top");
        watchdog.restart();
    }

    function stop(): void {
        if (state === "off" || state === "stopping")
            return;
        state = "stopping";
        follower.running = false;
        _setPhase(qsTr("Liberando la memoria de la gráfica"), 0.3);
        Toaster.toast(qsTr("Apagando Laura"), qsTr("Liberando la memoria de la gráfica"), "voice_over_off");
        _t0 = Date.now();
        stopProc.running = true;
    }

    function toggle(): void {
        if (state === "on" || state === "starting")
            stop();
        else
            start();
    }

    function _setPhase(text: string, p: real): void {
        phase = text;
        progress = p;
    }

    // Arranque iniciado por otro (GameMode, laura-toggle, terminal): seguirlo.
    function _adoptStart(): void {
        state = "starting";
        _setPhase(qsTr("Arrancando el servicio"), 0.05);
        _t0 = Date.now();
        follower.running = false;
        follower.running = true;
        watchdog.restart();
    }

    // Fases del arranque según el log del daemon.
    readonly property var _steps: [
        ["cargando Whisper", qsTr("Cargando el reconocimiento de voz"), 0.25],
        ["cargando Kokoro", qsTr("Cargando la voz"), 0.55],
        ["TTS listo", qsTr("Conectando el modelo de lenguaje"), 0.8],
        ["listo. control", qsTr("Lista"), 1]
    ]

    Process {
        id: follower

        command: ["journalctl", "--user", "-u", "laura.service", "-f", "-n", "0", "-o", "cat"]
        stdout: SplitParser {
            onRead: line => {
                if (root.state !== "starting")
                    return;
                for (const [key, text, p] of root._steps) {
                    if (line.includes(key)) {
                        root._setPhase(text, p);
                        if (p >= 1) {
                            root.typicalStart = (Date.now() - root._t0) / 1000;
                            root.state = "on";
                            follower.running = false;
                            watchdog.stop();
                            root.ready();
                            Toaster.toast(qsTr("Laura lista"), qsTr("Encendida en %1 s").arg(Math.round(root.typicalStart)), "graphic_eq");
                        }
                    }
                }
            }
        }
    }

    Process {
        id: startProc

        command: ["systemctl", "--user", "start", "laura.service"]
        onExited: code => {
            if (code !== 0) {
                root.state = "error";
                root.phase = qsTr("No arrancó (mira journalctl --user -u laura)");
                follower.running = false;
            }
        }
    }

    Process {
        id: stopProc

        command: ["systemctl", "--user", "stop", "laura.service"]
        onExited: {
            Toaster.toast(qsTr("Laura apagada"), qsTr("Gráfica y micro liberados"), "voice_over_off");
            root.state = "off";
            root.phase = "";
            root.progress = 0;
        }
    }

    // Si en 45 s no llega «listo», algo va mal.
    Timer {
        id: watchdog

        interval: 45000
        onTriggered: if (root.state === "starting") {
            root.state = "error";
            root.phase = qsTr("Tarda demasiado (mira journalctl --user -u laura)");
            follower.running = false;
        }
    }

    // ETA visible mientras arranca/para.
    Timer {
        interval: 500
        repeat: true
        running: root.busy
        onTriggered: {
            const el = (Date.now() - root._t0) / 1000;
            root.eta = Math.max(0, Math.round((root.state === "stopping" ? 2 : root.typicalStart) - el));
            // Avance suave entre fases (sin pasar de la siguiente fase real).
            if (root.state === "stopping")
                root.progress = Math.min(0.95, 0.3 + el / 2.5);
            else {
                const next = root._steps.map(x => x[2]).find(p => p > root.progress) ?? 1;
                root.progress = Math.max(root.progress, Math.min(next - 0.03, el / root.typicalStart));
            }
        }
    }

    // Estado real del servicio (por si se enciende/apaga desde fuera: GameMode,
    // ahorro de batería, la terminal…). Solo corrige si no hay transición nuestra.
    Process {
        id: poll

        // Línea 1: estado; línea 2 (si activo): cuántos «listo» hay desde que arrancó.
        command: ["sh", "-c", "s=$(systemctl --user is-active laura.service); echo $s; [ \"$s\" = active ] && journalctl --user -u laura.service --since \"$(systemctl --user show laura.service -p ActiveEnterTimestamp --value)\" -o cat | grep -c 'listo. control'"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.busy)
                    return;
                const [s, n] = text.trim().split("\n");
                if (s === "active" && parseInt(n) > 0)
                    root.state = "on";
                else if (s === "active" || s === "activating")
                    root._adoptStart();
                else if (root.state !== "error")
                    root.state = "off";
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: poll.running = true
    }
}
