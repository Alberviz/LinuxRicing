pragma Singleton
pragma ComponentBehavior: Bound

// Cast — interfaz con `cast-helper` (daemon Chromecast, ver widgets/cast-helper).
// Lee $XDG_RUNTIME_DIR/cast-helper/state.json (lo reescribe el daemon de forma atómica:
// tmp + rename, por eso además del watch hay un sondeo de 1 s mientras haya alguna tarjeta
// observando) y lanza `cast-helper <cmd>` para las órdenes. Quickshell no tiene
// ~/.local/bin en el PATH, de ahí la ruta absoluta.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: `${Quickshell.env("HOME")}/.local/bin/cast-helper`
    readonly property string statePath: `${Quickshell.env("XDG_RUNTIME_DIR")}/cast-helper/state.json`

    // Estado publicado por el daemon.
    property var devices: []
    property var active: null
    property string error: ""
    // Error local de la última orden (daemon no activo, etc.).
    property string cmdError: ""
    readonly property string shownError: cmdError || error
    readonly property bool preparing: active?.preparing ?? false
    readonly property bool hasActive: active !== null
    // El selector de archivos está abierto: el drawer de utilities no debe cerrarse.
    property bool picking: false
    property var monitors: []
    readonly property bool mirroring: active?.mode === "mirror"
    // Cuántas tarjetas están mirando; el sondeo solo corre si hay alguna.
    property int observers: 0

    // Dispositivo elegido en el selector (uuid). Vacío = el activo o el primero.
    property string selectedUuid: ""
    readonly property var selectedDevice: {
        const byUuid = devices.find(d => d.uuid === selectedUuid);
        if (byUuid)
            return byUuid;
        if (active) {
            const a = devices.find(d => d.uuid === active.device_uuid);
            if (a)
                return a;
        }
        return devices[0] ?? null;
    }

    function refresh(): void {
        stateView.reload();
    }

    function run(args: var, onDone: var): void {
        const p = procComp.createObject(root, {
            command: [root.helper, ...args]
        });
        p.done = onDone ?? null;
        p.running = true;
    }

    function scan(): void {
        run(["devices"]);
    }

    function castTo(uuid: string, target: string): void {
        if (!uuid || !target)
            return;
        run(["cast", uuid, target]);
    }

    function castSelected(target: string): void {
        if (!selectedDevice) {
            cmdError = "No hay ningún Chromecast";
            return;
        }
        castTo(selectedDevice.uuid, target);
    }

    function mirrorStart(uuid: string, monitor: string, audio: bool): void {
        cmdError = "";
        const a = ["mirror", "start", "--device", uuid];
        if (monitor)
            a.push("--monitor", monitor);
        if (!audio)
            a.push("--no-audio");
        run(a);
    }
    function mirrorAudio(on: bool): void {
        run(["mirror", "audio", on ? "on" : "off"]);
    }
    function scanMonitors(): void {
        run(["mirror", "monitors"]);
    }

    function setSub(n: int): void {
        run(["subs", n < 0 ? "off" : String(n)]);
    }
    function setAudioTrack(n: int): void {
        run(["audio", String(n)]);
    }

    function toggle(): void {
        run(["toggle"]);
    }
    function stop(): void {
        run(["stop"]);
    }
    function seek(seconds: real): void {
        run(["seek", String(Math.max(0, Math.round(seconds)))]);
    }
    function setVolume(percent: real): void {
        run(["volume", String(Math.max(0, Math.min(100, Math.round(percent))))]);
    }
    function mute(): void {
        run(["mute"]);
    }

    // "file:///a%20b.mkv" -> "/a b.mkv"; las URL http(s) pasan tal cual.
    function normalizeTarget(raw: string): string {
        let s = (raw ?? "").trim().split("\n")[0].trim();
        if (s.startsWith("file://"))
            return decodeURIComponent(s.substring(7));
        return s;
    }

    function fmtTime(sec: real): string {
        const t = Math.max(0, Math.floor(sec));
        const h = Math.floor(t / 3600);
        const m = Math.floor((t % 3600) / 60);
        const s = t % 60;
        const mm = (h > 0 && m < 10 ? "0" : "") + m;
        return (h > 0 ? h + ":" : "") + mm + ":" + (s < 10 ? "0" : "") + s;
    }

    Component {
        id: procComp

        Process {
            property var done: null

            stdout: StdioCollector {
                id: out
            }

            onExited: code => {
                try {
                    const r = JSON.parse(out.text.trim().split("\n").pop());
                    root.cmdError = r.ok === false ? (r.error ?? "") : "";
                } catch (e) {
                    root.cmdError = code === 0 ? "" : "cast-helper no responde";
                }
                if (done)
                    done(code);
                destroy();
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.observers > 0
        onTriggered: stateView.reload()
    }

    FileView {
        id: stateView

        path: root.statePath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.devices = d.devices ?? [];
                root.active = d.active ?? null;
                root.error = d.error ?? "";
                root.monitors = d.monitors ?? [];
            } catch (e) {}
        }
        onLoadFailed: {
            root.devices = [];
            root.active = null;
        }
    }
}
