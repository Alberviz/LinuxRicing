pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: `${Quickshell.env("HOME")}/.local/bin/tele`
    readonly property string statePath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/" + Quickshell.env("UID")}/tele/state.json`

    property string transport: "off"      // off | hdmi | wifi
    property string mode: "off"           // off | personal | agents | gaming
    property string monitor: ""
    property string laptopMonitor: "eDP-2"
    property bool hdmiConnected: false
    property string hdmiName: ""
    property bool hdmiActive: false
    property bool chromecastOnline: false
    property string chromecastName: "Гостиная"
    property bool interacting: false
    property int agentsWindows: 0
    property bool hdmiLostPrompt: false
    property bool busy: false

    readonly property bool available: hdmiConnected || chromecastOnline
    readonly property bool active: transport !== "off" && mode !== "off"

    function refresh(): void {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function applyState(d): void {
        if (!d)
            return;
        transport = d.transport ?? "off";
        mode = d.mode ?? "off";
        monitor = d.monitor ?? "";
        laptopMonitor = d.laptop_monitor ?? "eDP-2";
        hdmiConnected = !!d.hdmi_connected;
        hdmiName = d.hdmi_name ?? "";
        hdmiActive = !!d.hdmi_active;
        chromecastOnline = !!d.chromecast_online;
        chromecastName = d.chromecast_name ?? "Гостиная";
        interacting = !!d.interacting;
        agentsWindows = d.agents_windows ?? 0;
        hdmiLostPrompt = !!d.hdmi_lost_prompt;
    }

    function run(args: var, onDone: var): void {
        busy = true;
        const p = procComp.createObject(root, {
            command: [root.helper, ...args]
        });
        p.done = onDone ?? null;
        p.running = true;
    }

    function setMode(m: string, allowWifiGaming: bool): void {
        const a = ["mode", m];
        if (allowWifiGaming)
            a.push("--wifi");
        run(a);
    }

    function toggleInteract(): void {
        run(["interact", "toggle"]);
    }

    function openTarget(target: string): void {
        if (!target)
            return;
        run(["open", target]);
    }

    function answerHdmiLost(useWifi: bool): void {
        hdmiLostPrompt = false;
        run(["answer-hdmi-lost", useWifi ? "wifi" : "laptop"]);
    }

    Component.onCompleted: refresh()

    FileView {
        id: stateView

        path: root.statePath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.applyState(JSON.parse(text()));
            } catch (e) {}
        }
    }

    Process {
        id: statusProc

        command: [root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyState(JSON.parse(text));
                } catch (e) {}
            }
        }
    }

    Component {
        id: procComp

        Process {
            id: p

            property var done: null

            stdout: StdioCollector {
                onStreamFinished: {
                    root.busy = false;
                    let parsed = null;
                    try {
                        parsed = JSON.parse(text);
                        if (parsed && parsed.transport !== undefined)
                            root.applyState(parsed);
                    } catch (e) {}
                    if (p.done)
                        p.done(parsed);
                }
            }
            onExited: (code, status) => {
                root.busy = false;
                p.destroy();
            }
        }
    }
}
