pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Modo barra (un input): SOLO un cordón que brota del borde derecho de la
// barra de Caelestia, se estira y late con la voz, y cuelga una pastilla por
// acción. Sin esfera ni forma. Un input -> respuesta -> se recoge.
StyledWindow {
    id: win

    required property ShellScreen modelData

    screen: modelData
    name: "aurora-bar"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true

    implicitWidth: 380
    mask: Region {}

    // Linger: deja las pastillas ~3 s tras terminar antes de recogerse.
    property bool linger: false
    Timer {
        id: lingerTimer
        interval: 3000
        onTriggered: win.linger = false
    }
    Connections {
        target: Aurora
        function onStateChanged(): void {
            if (Aurora.state === "idle" && Aurora.actions.length > 0) {
                win.linger = true;
                lingerTimer.restart();
            } else if (Aurora.state === "listening") {
                win.linger = false;
                lingerTimer.stop();
            }
        }
    }

    readonly property bool engaged: Aurora.mode === "barra" && (Aurora.active || linger)
    visible: engaged

    Item {
        id: canvas

        anchors.fill: parent
        opacity: win.engaged ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }

        // El cordón arranca en el borde derecho de la barra de Caelestia.
        readonly property real originX: Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness) * 2
        readonly property real midY: height / 2
        // Longitud del cordón: 0 recogido, se estira al activarse.
        property real len: win.engaged ? (Aurora.state === "idle" ? 34 : 90) : 0

        Behavior on len {
            Anim {
                type: Anim.Emphasized
            }
        }

        // El cordón: una curva que sale de la barra, con grosor y onda que
        // laten con la voz. Nunca se corta.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            asynchronous: true

            ShapePath {
                fillColor: "transparent"
                strokeColor: Aurora.accent
                strokeWidth: 3 + 4 * Aurora.amplitude
                capStyle: ShapePath.RoundCap

                startX: canvas.originX
                startY: canvas.midY

                PathQuad {
                    x: canvas.originX + canvas.len
                    y: canvas.midY
                    controlX: canvas.originX + canvas.len * 0.5
                    controlY: canvas.midY - (6 + 22 * Aurora.amplitude)
                }
            }
        }

        // Punta del cordón
        Rectangle {
            width: 8 + 6 * Aurora.amplitude
            height: width
            radius: width / 2
            x: canvas.originX + canvas.len - width / 2
            y: canvas.midY - height / 2
            color: Aurora.accent
            opacity: win.engaged ? 1 : 0
        }

        // Tallo con una pastilla por acción, colgando de la punta.
        Column {
            x: canvas.originX + canvas.len + 20
            y: canvas.midY - height / 2
            spacing: Tokens.spacing.small
            visible: (Aurora.state === "speaking" || win.linger) && Aurora.actions.length > 0
            opacity: visible ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }

            Repeater {
                model: Aurora.actions

                StyledRect {
                    id: pill

                    required property var modelData
                    required property int index

                    implicitWidth: pillRow.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: pillRow.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainer

                    opacity: 0
                    x: -12
                    Component.onCompleted: appear.start()
                    ParallelAnimation {
                        id: appear
                        NumberAnimation {
                            target: pill
                            property: "opacity"
                            to: 1
                            duration: 220
                        }
                        Anim {
                            target: pill
                            property: "x"
                            to: 0
                            type: Anim.Emphasized
                        }
                    }

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pill.modelData.icon ?? "bolt"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pill.modelData.text ?? ""
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.label.large
                        }
                    }
                }
            }
        }
    }
}
