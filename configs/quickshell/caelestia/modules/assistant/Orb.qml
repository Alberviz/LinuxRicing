pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.assistant

// El orbe líquido del modo centro. Aislado a propósito: más adelante se puede
// sustituir su interior por un ShaderEffect GLSL sin tocar el resto del overlay.
Item {
    id: root

    // "idle" | "listening" | "thinking" | "speaking"
    property string state: "idle"
    // Nivel de voz 0..1 (ya suavizado por el servicio Aurora)
    property real level: 0

    readonly property color accent: Aurora.accent
    readonly property color accentAlt: Aurora.accentAlt

    readonly property real unit: Math.min(width, height) / 2

    // Respiración lenta permanente
    property real breath: 0
    SequentialAnimation on breath {
        running: true
        loops: Animation.Infinite
        NumberAnimation {
            to: 1
            duration: 2600
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0
            duration: 2600
            easing.type: Easing.InOutSine
        }
    }

    // Halo exterior
    Rectangle {
        anchors.centerIn: parent
        width: core.width * 1.9
        height: width
        radius: width / 2
        color: Qt.alpha(root.accent, 0.15)
        scale: 0.9 + 0.06 * root.breath + 0.35 * root.level

        Behavior on scale {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutQuad
            }
        }
    }

    // Esfera
    Item {
        id: core

        anchors.centerIn: parent

        readonly property real target: root.unit * (root.state === "idle" ? 0.45 : 0.78 + 0.06 * root.breath + 0.45 * root.level)
        property real d: target
        width: d * 2
        height: d * 2

        Behavior on d {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        // Wobble: deformación sutil y continua del contorno
        property real wob: 0
        SequentialAnimation on wob {
            running: root.state !== "idle"
            loops: Animation.Infinite
            NumberAnimation {
                to: 1
                duration: 1700
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: -1
                duration: 1900
                easing.type: Easing.InOutSine
            }
        }
        transform: Scale {
            origin.x: core.width / 2
            origin.y: core.height / 2
            xScale: 1 + 0.03 * core.wob + 0.04 * root.level
            yScale: 1 - 0.03 * core.wob
        }

        // Disco base
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0
                    color: Qt.lighter(root.accentAlt, 1.15)
                }
                GradientStop {
                    position: 1
                    color: Qt.darker(root.accent, 1.4)
                }
            }
        }

        // Brillo esférico (sheen) arriba-izquierda
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            asynchronous: true

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: core.width * 0.36
                    centerY: core.height * 0.30
                    focalX: centerX
                    focalY: centerY
                    centerRadius: core.width * 0.62

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Qt.lighter(root.accentAlt, 1.6), 0.9)
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.alpha(root.accent, 0.25)
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }

                startX: core.width
                startY: core.height / 2

                PathArc {
                    x: 0
                    y: core.height / 2
                    radiusX: core.width / 2
                    radiusY: core.height / 2
                    useLargeArc: true
                }
                PathArc {
                    x: core.width
                    y: core.height / 2
                    radiusX: core.width / 2
                    radiusY: core.height / 2
                    useLargeArc: true
                }
            }
        }
    }

    // Anillo "pensando"
    Shape {
        id: ring

        anchors.centerIn: parent
        width: core.width * 1.28
        height: width
        visible: root.state === "thinking"
        opacity: visible ? 1 : 0
        preferredRendererType: Shape.CurveRenderer

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }

        NumberAnimation on rotation {
            running: ring.visible
            from: 0
            to: 360
            duration: 1100
            loops: Animation.Infinite
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.accentAlt
            strokeWidth: 3
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.width / 2 - 2
                radiusY: ring.height / 2 - 2
                startAngle: 0
                sweepAngle: 270
            }
        }
    }

    // Anillos que emanan al "hablar"
    Repeater {
        model: 3

        Rectangle {
            id: wave

            required property int index

            anchors.centerIn: parent
            width: core.width
            height: width
            radius: width / 2
            color: "transparent"
            border.color: root.accent
            border.width: 2
            opacity: 0

            SequentialAnimation {
                running: root.state === "speaking"
                loops: Animation.Infinite

                PauseAnimation {
                    duration: wave.index * 550
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: wave
                        property: "scale"
                        from: 0.7
                        to: 1.8
                        duration: 1650
                        easing.type: Easing.OutQuad
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: wave
                            property: "opacity"
                            from: 0
                            to: 0.5
                            duration: 300
                        }
                        NumberAnimation {
                            target: wave
                            property: "opacity"
                            to: 0
                            duration: 1350
                        }
                    }
                }
            }
        }
    }
}
