pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

// Agujero blanco: llegadas del móvil (puente de Olimpo). El puente añade una línea JSON por archivo a
// $XDG_RUNTIME_DIR/olimpo-puente/llegadas.jsonl ({"ruta","nombre","tamano","mime","ts"}). `tail -F` las
// recibe (cero coste en reposo); un agujero blanco aparece en el borde superior, escupe el archivo en
// arco y se posa como tarjeta (clic: abrir · botón derecho: mostrar en carpeta · ~8 s o al pasar el ratón
// la retiene). Varias llegadas seguidas: ráfaga escalonada. Sin FrameAnimation: solo animaciones de
// duración finita mientras ocurre algo.
Scope {
    id: scope

    readonly property string file: `${Quickshell.env("XDG_RUNTIME_DIR")}/olimpo-puente/llegadas.jsonl`

    signal arrived(var entry)

    // Prueba sin puente: qs -c caelestia ipc call whitehole demo <ruta>
    IpcHandler {
        function demo(path: string): void {
            const name = path.split("/").pop();
            scope.arrived({
                ruta: path,
                nombre: name,
                tamano: 1234567,
                mime: name.match(/\.(png|jpe?g|webp|gif)$/i) ? "image/" + name.split(".").pop() : "application/octet-stream",
                ts: Date.now() / 1000
            });
        }

        target: "whitehole"
    }

    Process {
        command: ["tail", "-n", "0", "-F", scope.file]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    if (d.ruta)
                        scope.arrived(d);
                } catch (e) {}
            }
        }
    }

    Variants {
        model: Screens.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            property var pending: []
            property real show: 0          // presencia del agujero 0..1
            property real en: 0            // envolvente de energía
            property real phase: 0
            property real pulse: 0
            property bool holeOn: false
            readonly property real u: width / 1280
            readonly property var cards: [c0, c1, c2, c3, c4]
            readonly property real holeR: 40 * u

            function fmtSize(b: real): string {
                if (b >= 1073741824)
                    return (b / 1073741824).toFixed(1).replace(".", ",") + " GB";
                if (b >= 1048576)
                    return (b / 1048576).toFixed(b >= 10485760 ? 0 : 1).replace(".", ",") + " MB";
                return Math.max(1, Math.round(b / 1024)) + " KB";
            }

            function trySpit(): void {
                if (pending.length === 0)
                    return;
                const free = cards.find(c => !c.active);
                if (!free)
                    return;
                const e = pending.shift();
                pending = pending;
                free.launch(e);
                holeOn = true;
                holeHold.restart();
                enAnim.restart();
                pulseAnim.restart();
                if (pending.length > 0)
                    spitTimer.start();
            }

            screen: modelData
            name: "whitehole"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            mask: Region {
            Region {
                item: c0
            }
            Region {
                item: c1
            }
            Region {
                item: c2
            }
            Region {
                item: c3
            }
            Region {
                item: c4
            }
            }

            Connections {
                target: scope

                function onArrived(entry) {
                    win.pending.push(entry);
                    if (!spitTimer.running)
                        win.trySpit();
                }
            }

            Timer {
                id: spitTimer

                interval: 520
                onTriggered: win.trySpit()
            }

            // El agujero se retira poco después de la última expulsión
            Timer {
                id: holeHold

                interval: 1500
                onTriggered: {
                    if (win.pending.length === 0)
                        win.holeOn = false;
                    else
                        holeHold.restart();
                }
            }

            Behavior on show {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            onHoleOnChanged: show = holeOn ? 1 : 0

            SequentialAnimation {
                id: enAnim

                Anim {
                    target: win
                    property: "en"
                    to: 1
                    type: Anim.FastEffects
                }
                Anim {
                    target: win
                    property: "en"
                    to: 0.3
                    type: Anim.SlowEffects
                }
            }
            NumberAnimation {
                id: pulseAnim

                target: win
                property: "pulse"
                from: 1
                to: 0
                duration: PowerSaving.active ? 0 : 520
                easing.type: Easing.OutCubic
            }
            // Solo corre mientras el agujero está presente
            NumberAnimation {
                target: win
                property: "phase"
                from: 0
                to: 1
                duration: 1800
                loops: Animation.Infinite
                running: win.show > 0.01 && !PowerSaving.active
            }

            ShaderEffect {
                id: fx

                readonly property real half: 9 * win.holeR
                x: win.width / 2 - half
                y: -half
                width: half * 2
                height: half * 2
                visible: win.show > 0.01

                property vector2d size: Qt.vector2d(width, height)
                property color tint: Qt.rgba(Colours.palette.m3primary.r, Colours.palette.m3primary.g, Colours.palette.m3primary.b, 0.25)
                property real rad: win.holeR * (0.5 + 0.5 * win.show)
                property real upx: win.u
                property real en: win.en
                property real vis: win.show
                property real phase: win.phase
                property real pulse: win.pulse

                fragmentShader: Qt.resolvedUrl("shaders/whitehole.frag.qsb")
            }

            Card {
                id: c0

                slot: 0
                win: win
            }
            Card {
                id: c1

                slot: 1
                win: win
            }
            Card {
                id: c2

                slot: 2
                win: win
            }
            Card {
                id: c3

                slot: 3
                win: win
            }
            Card {
                id: c4

                slot: 4
                win: win
            }

            component Card: Item {
                id: card

                required property int slot
                required property var win
                property bool active: false
                property bool settled: false
                property var entry: null
                property real t: 0
                property real sx: win.width / 2
                property real sy: win.holeR
                readonly property real lx: win.width - width - 28 * win.u
                readonly property real ly: 110 * win.u + slot * (height + 14)
                readonly property bool isImage: (entry?.mime ?? "").startsWith("image/")

                function launch(e: var): void {
                    entry = e;
                    t = 0;
                    settled = false;
                    opacity = 1;
                    active = true;
                    flight.restart();
                }
                function dismiss(): void {
                    fadeOut.restart();
                }

                width: 320
                height: 88
                // Trayectoria: sale por el chorro (hacia abajo) y se curva hacia su sitio
                readonly property real p1x: sx
                readonly property real p1y: ly * 0.85
                x: (1 - t) * (1 - t) * sx + 2 * (1 - t) * t * p1x + t * t * lx - (1 - t) * width / 2 * (1 - t)
                y: (1 - t) * (1 - t) * sy + 2 * (1 - t) * t * p1y + t * t * ly
                scale: 0.2 + 0.8 * Math.min(1, t * 1.4)
                rotation: (1 - t) * (1 - t) * (slot % 2 ? 28 : -28)
                visible: active
                opacity: 0

                NumberAnimation {
                    id: flight

                    target: card
                    property: "t"
                    from: 0
                    to: 1
                    duration: PowerSaving.active ? 0 : 760
                    easing.type: Easing.OutCubic
                    onStarted: fadeIn.restart()
                    onFinished: {
                        card.settled = true;
                        life.restart();
                    }
                }
                NumberAnimation {
                    id: fadeIn

                    target: card
                    property: "opacity"
                    to: 1
                    duration: 140
                }
                NumberAnimation {
                    id: fadeOut

                    target: card
                    property: "opacity"
                    to: 0
                    duration: PowerSaving.active ? 0 : 260
                    onFinished: {
                        card.active = false;
                        card.settled = false;
                        win.trySpit();
                    }
                }
                Timer {
                    id: life

                    interval: 8000
                    onTriggered: card.dismiss()
                }

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.large
                    color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.96)
                    border.width: 1.5
                    border.color: Qt.alpha(Colours.palette.m3primary, 0.7)

                    Item {
                        id: thumbBox

                        x: 6
                        y: 6
                        width: parent.height - 12
                        height: width

                        Image {
                            anchors.fill: parent
                            visible: card.isImage && status === Image.Ready
                            source: card.isImage ? "file://" + card.entry.ruta : ""
                            sourceSize: Qt.size(256, 256)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        StyledRect {
                            anchors.fill: parent
                            visible: !card.isImage
                            radius: Tokens.rounding.medium
                            color: Colours.palette.m3secondaryContainer

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: {
                                    const m = card.entry?.mime ?? "";
                                    if (m.startsWith("video/"))
                                        return "movie";
                                    if (m.startsWith("audio/"))
                                        return "music_note";
                                    if (m.includes("pdf"))
                                        return "picture_as_pdf";
                                    if (m.includes("zip") || m.includes("compressed"))
                                        return "folder_zip";
                                    return "description";
                                }
                                color: Colours.palette.m3onSecondaryContainer
                                fontStyle: Tokens.font.icon.extraLarge
                            }
                        }
                    }

                    Column {
                        anchors.left: thumbBox.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: card.entry?.nombre ?? ""
                            elide: Text.ElideMiddle
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            color: Colours.palette.m3onSurface
                        }
                        Text {
                            width: parent.width
                            text: "Desde el móvil · " + win.fmtSize(card.entry?.tamano ?? 0)
                            font.family: "JetBrainsMono Nerd Font Mono"
                            font.pixelSize: 11
                            color: Colours.palette.m3onSurfaceVariant
                        }
                        Text {
                            width: parent.width
                            text: "clic: abrir · derecho: mostrar en carpeta"
                            font.pixelSize: 11
                            color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.7)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: card.settled
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: life.stop()
                        onExited: if (card.settled && fadeOut.running === false)
                            life.restart()
                        onClicked: ev => {
                            const path = card.entry.ruta;
                            if (ev.button === Qt.RightButton) {
                                Quickshell.execDetached(["sh", "-c", "dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:\"file://$1\" string:\"\" >/dev/null 2>&1 || xdg-open \"$(dirname \"$1\")\"", "sh", path]);
                            } else {
                                Quickshell.execDetached(["xdg-open", path]);
                            }
                            card.dismiss();
                        }
                    }
                }
            }
        }
    }
}
