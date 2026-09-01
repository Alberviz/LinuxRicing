pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Modo barra: un punto anclado al borde derecho de la barra de Caelestia (que
// NO se toca). Al activarse, un conector con forma de píldora se estira sin
// cortarse hasta la forma de Aurora; al terminar, cuelgan las pastillas de
// acción. Capa propia click-through por encima de la barra.
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

    // Linger: tras terminar, deja las pastillas ~3 s antes de recogerse.
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

        // El ancla vive en el borde derecho de la barra de Caelestia (aquí sí
        // hay contexto de pantalla para leer Tokens/Config).
        readonly property real barWidth: Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness) * 2
        readonly property real anchorX: barWidth + 4
        readonly property real anchorY: height / 2
        readonly property real shapeSize: Aurora.state === "idle" ? 12 : 30 + 14 * Aurora.amplitude
        property real shapeX: win.engaged ? anchorX + 66 : anchorX

        Behavior on shapeX {
            Anim {
                type: Anim.Emphasized
            }
        }

        // Punto ancla, siempre pegado al borde de la barra
        Rectangle {
            width: 9
            height: 9
            radius: 4.5
            x: canvas.anchorX - width / 2
            y: canvas.anchorY - height / 2
            color: Aurora.accent
            opacity: win.engaged ? 1 : 0
        }

        // Conector: píldora que se estira del ancla a la forma. Nunca se corta.
        Rectangle {
            height: 4 + 3 * Aurora.amplitude
            radius: height / 2
            x: canvas.anchorX
            y: canvas.anchorY - height / 2
            width: Math.max(0, canvas.shapeX - canvas.anchorX)
            color: Aurora.accent
            opacity: win.engaged ? 1 : 0
        }

        // La forma de Aurora
        Orb {
            id: drop

            baseSize: canvas.shapeSize
            state: Aurora.state
            level: Aurora.amplitude
            x: canvas.shapeX - implicitSize / 2
            y: canvas.anchorY - implicitSize / 2
        }

        // Tallo + una pastilla por acción, colgando de la forma
        Column {
            id: stem

            x: canvas.shapeX + 24
            y: canvas.anchorY - height / 2
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
                            easing.type: Easing.OutQuad
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
