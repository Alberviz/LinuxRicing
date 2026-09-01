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

// Modo barra: "punto con cordón". Capa propia anclada al borde izquierdo, por
// encima de la barra de Caelestia (que NO se toca). En reposo es un punto; al
// activarse se despega en un cordón que nunca se corta y hace de gota reactiva.
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

    implicitWidth: 260
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

        // Geometría
        readonly property real anchorX: 10
        readonly property real anchorY: height / 2
        readonly property real dropX: win.engaged ? 74 : anchorX
        readonly property real dropR: (Aurora.state === "idle" ? 5 : 15 + 10 * Aurora.amplitude)

        Behavior on dropX {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
            }
        }

        // Punto ancla, siempre pegado al borde
        Rectangle {
            x: canvas.anchorX - 4
            y: canvas.anchorY - 4
            width: 8
            height: 8
            radius: 4
            color: Aurora.accent
        }

        // Cordón: curva del ancla a la gota. Nunca se corta.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            asynchronous: true

            ShapePath {
                fillColor: "transparent"
                strokeColor: Aurora.accent
                strokeWidth: 2 + 2 * Aurora.amplitude
                capStyle: ShapePath.RoundCap

                startX: canvas.anchorX
                startY: canvas.anchorY

                PathQuad {
                    x: canvas.dropX - canvas.dropR
                    y: canvas.anchorY
                    controlX: (canvas.anchorX + canvas.dropX) / 2
                    controlY: canvas.anchorY - 6 * Aurora.amplitude
                }
            }
        }

        // La gota
        Item {
            id: drop

            x: canvas.dropX - canvas.dropR
            y: canvas.anchorY - canvas.dropR
            width: canvas.dropR * 2
            height: canvas.dropR * 2

            transform: Scale {
                origin.x: drop.width / 2
                origin.y: drop.height / 2
                xScale: 1 + 0.12 * Aurora.amplitude
                yScale: 1 - 0.08 * Aurora.amplitude
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop {
                        position: 0
                        color: Qt.lighter(Aurora.accentAlt, 1.2)
                    }
                    GradientStop {
                        position: 1
                        color: Aurora.accent
                    }
                }
            }
        }

        // Aro "pensando" alrededor de la gota
        Shape {
            id: bring

            width: canvas.dropR * 3
            height: width
            x: canvas.dropX - width / 2
            y: canvas.anchorY - width / 2
            visible: Aurora.state === "thinking"
            preferredRendererType: Shape.CurveRenderer

            NumberAnimation on rotation {
                running: bring.visible
                from: 0
                to: 360
                duration: 1000
                loops: Animation.Infinite
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Aurora.accentAlt
                strokeWidth: 2
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: bring.width / 2
                    centerY: bring.height / 2
                    radiusX: bring.width / 2 - 1
                    radiusY: bring.height / 2 - 1
                    startAngle: 0
                    sweepAngle: 260
                }
            }
        }

        // Tallo + una pastilla por acción, colgando de la gota
        Column {
            id: stem

            x: canvas.dropX + 26
            y: canvas.anchorY - height / 2
            spacing: 6
            visible: (Aurora.state === "speaking" || win.linger) && Aurora.actions.length > 0
            opacity: visible ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }

            Repeater {
                model: Aurora.actions

                Rectangle {
                    id: pill

                    required property var modelData
                    required property int index

                    width: pillRow.implicitWidth + 20
                    height: pillRow.implicitHeight + 12
                    radius: height / 2
                    color: Qt.alpha(Aurora.surface, 0.9)

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
                        NumberAnimation {
                            target: pill
                            property: "x"
                            to: 0
                            duration: 260
                            easing.type: Easing.OutBack
                        }
                    }

                    Row {
                        id: pillRow

                        anchors.centerIn: parent
                        spacing: 6

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pill.modelData.icon ?? "bolt"
                            color: Aurora.accent
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pill.modelData.text ?? ""
                            color: Aurora.onSurface
                        }
                    }
                }
            }
        }
    }
}
