pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

Scope {
    id: scope

    property bool active: false
    property bool hasProgress: false
    property string statusTitle: qsTr("Hookshot · Iniciando juego")
    property string statusDetail: qsTr("Cargando recursos y shaders...")
    property int donePipelines: 0
    property int totalPipelines: 0
    property int etaSeconds: -1
    property int elapsedSeconds: 0

    readonly property real progress: totalPipelines > 0 ? Math.min(1, Math.max(0, donePipelines / totalPipelines)) : 0
    readonly property int percent: Math.round(progress * 100)

    function formatEta(secs: int): string {
        if (secs < 0)
            return qsTr("Preparando...");
        if (secs < 60)
            return qsTr("~%1 s restantes").arg(secs);
        const mins = Math.floor(secs / 60);
        const rem = secs % 60;
        if (mins >= 60) {
            const hrs = Math.floor(mins / 60);
            const remMins = mins % 60;
            return qsTr("~%1 h %2 min restantes").arg(hrs).arg(remMins);
        }
        return rem > 0 ? qsTr("~%1 min %2 s restantes").arg(mins).arg(rem) : qsTr("~%1 min restantes").arg(mins);
    }

    function formatElapsed(secs: int): string {
        if (secs <= 0)
            return "";
        if (secs < 60)
            return `${secs} s`;
        const mins = Math.floor(secs / 60);
        const rem = secs % 60;
        return `${mins} min ${rem} s`;
    }

    function formatCount(n: int): string {
        return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
    }

    Timer {
        id: pollTimer
        interval: 1500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!statusProc.running)
                statusProc.running = true;
        }
    }

    Process {
        id: statusProc
        command: [
            "python3",
            "-c",
            `
import json, os, re, subprocess, time

log_path = os.path.expanduser("~/Games/Hookshot/logs/hookshot_log.txt")
res = {"active": False, "hasProgress": False, "title": "Hookshot · Iniciando juego", "detail": "Cargando recursos...", "done": 0, "total": 0, "eta": -1, "elapsed": 0}

try:
    p = subprocess.run(["pgrep", "-f", "/Games/Hookshot/bin/hookshot"], capture_output=True, text=True)
    if p.returncode != 0:
        print(json.dumps(res))
        raise SystemExit(0)
    pids = {int(x) for x in p.stdout.split() if x.isdigit()}
except Exception:
    print(json.dumps(res))
    raise SystemExit(0)

has_window = False
try:
    hc = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=1.5)
    if hc.returncode == 0 and hc.stdout:
        for c in json.loads(hc.stdout):
            cls = (c.get("class") or "").lower()
            title = (c.get("title") or "").lower()
            pid = c.get("pid")
            if pid in pids or "hookshot" in cls or "ocarina" in title:
                has_window = True
                break
except Exception:
    pass

done = 0
total = 0
eta = -1
elapsed = 0
detail = "Inicializando motor..."

if os.path.exists(log_path):
    try:
        with open(log_path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 32768))
            tail = f.read().decode("utf-8", errors="ignore")

        startup_matches = re.findall(r"vk:\\s*start-up:\\s*(\\d+)\\s+of\\s+(\\d+)", tail)
        noted_matches = re.findall(r"vk:\\s*noted pipelines:\\s*(\\d+)\\s+of\\s+(\\d+)\\s+pipelines in\\s+(\\d+)\\s+s,\\s+about\\s+(\\d+)\\s+s left", tail)

        if noted_matches:
            d, t, el, lf = noted_matches[-1]
            done, total, elapsed, eta = int(d), int(t), int(el), int(lf)

        if startup_matches:
            sd, st = startup_matches[-1]
            sd, st = int(sd), int(st)
            if sd >= done:
                done = sd
                total = st

        if "vk: mesh" in tail:
            detail = "Compilando mesh shaders..."
        elif "precompile:" in tail:
            detail = "Cargando caché de pipelines..."
    except Exception:
        pass

if total > 0 and done < total:
    res = {
        "active": True,
        "hasProgress": True,
        "title": "Hookshot · Compilando shaders",
        "detail": detail,
        "done": done,
        "total": total,
        "eta": eta,
        "elapsed": elapsed,
    }
elif not has_window:
    try:
        # Tiempo transcurrido desde que arrancó el proceso
        if pids:
            proc_stat = f"/proc/{min(pids)}"
            elapsed = max(0, int(time.time() - os.path.getctime(proc_stat)))
    except Exception:
        elapsed = 0
    res = {
        "active": True,
        "hasProgress": False,
        "title": "Hookshot · Iniciando juego",
        "detail": detail,
        "done": 0,
        "total": 0,
        "eta": -1,
        "elapsed": elapsed,
    }

print(json.dumps(res))
            `
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw)
                    return;
                try {
                    const data = JSON.parse(raw);
                    scope.active = !!data.active;
                    scope.hasProgress = !!data.hasProgress;
                    scope.statusTitle = data.title || qsTr("Hookshot · Iniciando juego");
                    scope.statusDetail = data.detail || qsTr("Cargando...");
                    scope.donePipelines = data.done || 0;
                    scope.totalPipelines = data.total || 0;
                    scope.etaSeconds = data.eta !== undefined ? data.eta : -1;
                    scope.elapsedSeconds = data.elapsed || 0;
                } catch (e) {}
            }
        }
    }

    LazyLoader {
        id: loader
        activeAsync: scope.active

        Variants {
            model: Screens.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "hookshot-warmup"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: empty

                anchors.bottom: true
                anchors.right: true
                margins.bottom: Tokens.padding.large * 2
                margins.right: Tokens.padding.large * 2

                implicitWidth: 360
                implicitHeight: Math.max(88, layout.implicitHeight + Tokens.padding.normal * 2)
                visible: scope.active && Hypr.monitorFor(win.modelData) === Hypr.focusedMonitor

                Region {
                    id: empty
                }

                StyledRect {
                    id: card

                    anchors.fill: parent
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    ColumnLayout {
                        id: layout

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.normal
                        spacing: Tokens.spacing.small

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: scope.hasProgress ? "local_fire_department" : "sports_esports"
                                color: Colours.palette.m3primary
                                font.pointSize: Tokens.font.size.large
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: scope.statusTitle
                                color: Colours.palette.m3onSurface
                                font.pointSize: Tokens.font.size.normal
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            StyledText {
                                text: scope.hasProgress ? `${scope.percent}%` : scope.formatElapsed(scope.elapsedSeconds)
                                color: Colours.palette.m3primary
                                font.pointSize: Tokens.font.size.normal
                                font.weight: Font.Bold
                            }
                        }

                        StyledRect {
                            id: track
                            Layout.fillWidth: true
                            implicitHeight: 6
                            radius: 3
                            clip: true
                            color: Colours.palette.m3surfaceContainerHighest

                            StyledRect {
                                visible: scope.hasProgress
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Math.max(radius * 2, parent.width * scope.progress)
                                radius: 3
                                color: Colours.palette.m3primary

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 350
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            StyledRect {
                                id: indeterminateBar
                                visible: !scope.hasProgress
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * 0.35
                                radius: 3
                                color: Colours.palette.m3primary

                                SequentialAnimation on x {
                                    running: !scope.hasProgress && scope.active
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        from: -indeterminateBar.width
                                        to: track.width
                                        duration: 1300
                                        easing.type: Easing.InOutQuad
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: scope.hasProgress
                                    ? `${scope.formatCount(scope.donePipelines)} / ${scope.formatCount(scope.totalPipelines)} pipelines`
                                    : scope.statusDetail
                                color: Colours.palette.m3onSurfaceVariant
                                font.pointSize: Tokens.font.size.smaller
                                elide: Text.ElideRight
                            }

                            StyledText {
                                visible: scope.hasProgress
                                text: scope.formatEta(scope.etaSeconds)
                                color: Colours.palette.m3onSurfaceVariant
                                font.pointSize: Tokens.font.size.smaller
                            }
                        }
                    }
                }
            }
        }
    }
}
