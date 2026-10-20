pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Un orbe de cristal (forma «i» del mockup): esfera con núcleo, reflejo
// especular y halo, todo gradientes en GPU. El estado se lee por el movimiento
// interior; el reloj `clock` lo da el dock (un solo Timer, parado si nada se
// mueve), así que aquí no hay animaciones infinitas.
Item {
    id: orb

    property var job: ({})
    property bool isMain: true
    // Segundos; solo avanza mientras haya un trabajo activo.
    property real clock: 0
    property bool gone: false
    // Progreso 0..1 del pulso de una sola vez (al terminar).
    property real pulseP: 1

    readonly property string kind: job.kind ?? "running"
    readonly property string destino: job.destino ?? "laura"
    readonly property color agentCol: Laura.agentColor(destino)
    // «k» del mockup: color del movimiento interior.
    readonly property color kCol: kind === "confirm" ? Laura.cWait : kind === "fail" ? Laura.cFail : agentCol
    readonly property bool unseen: Laura.isUnseen(job)

    property real d: isMain ? 46 : 20
    Behavior on d {
        NumberAnimation {
            duration: 450
            easing.type: Easing.OutCubic
        }
    }

    width: d
    height: d

    // Nacimiento / disolución
    property real appear: 0
    opacity: gone ? 0 : appear
    scale: gone ? 0.3 : (0.2 + 0.8 * appear)
    transformOrigin: Item.Right
    Behavior on opacity {
        NumberAnimation {
            duration: 700
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 700
            easing.type: Easing.InOutQuad
        }
    }
    NumberAnimation on appear {
        from: 0
        to: 1
        duration: 900
        easing.type: Easing.OutBack
        easing.overshoot: 0.6
    }

    // Pulso al pasar a done / fail (no al cargar)
    property string prevKind: ""
    Component.onCompleted: prevKind = kind
    onKindChanged: {
        if ((kind === "done" || kind === "fail") && prevKind !== "" && prevKind !== kind)
            pulseAnim.restart();
        prevKind = kind;
    }
    NumberAnimation {
        id: pulseAnim

        target: orb
        property: "pulseP"
        from: 0
        to: 1
        duration: 1500
    }

    // Fases derivadas del reloj compartido
    readonly property real spinAngle: ((clock / 3.4) % 1) * 360
    readonly property real sparkAngle: ((clock / 5.6) % 1) * 360
    readonly property real breath: 0.675 + 0.325 * Math.cos(clock / 3.4 * 2 * Math.PI)
    readonly property real rippleP: (clock % 2.8) / 2.8

    // --- Halo (sustituto del box-shadow) --------------------------------
    OrbDisc {
        anchors.centerIn: parent
        width: orb.d + 22
        height: orb.d + 22
        fillGradient: RadialGradient {
            centerX: (orb.d + 22) / 2
            centerY: (orb.d + 22) / 2
            centerRadius: (orb.d + 22) / 2
            focalX: centerX
            focalY: centerY
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 0.62
                color: Qt.alpha(orb.kCol, orb.kind === "confirm" ? 0.3 : 0.2)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    // --- Cuerpo de cristal ----------------------------------------------
    OrbDisc {
        id: body

        anchors.fill: parent
        strokeColor: Qt.alpha(orb.agentCol, 0.55)
        strokeWidth: 1
        strokeStyle: orb.kind === "fail" ? ShapePath.DashLine : ShapePath.SolidLine
        dashPattern: [3, 2]
        fillGradient: RadialGradient {
            centerX: body.width / 2
            centerY: body.height * 0.7
            centerRadius: body.width * 0.62
            focalX: centerX
            focalY: centerY
            GradientStop {
                position: 0
                color: Qt.tint("#171421", Qt.alpha(orb.agentCol, 0.26))
            }
            GradientStop {
                position: 1
                color: "#12101a"
            }
        }
    }

    // Movimiento interior ------------------------------------------------
    // trabajando: barrido cónico que gira
    OrbDisc {
        anchors.fill: parent
        visible: orb.kind === "running"
        rotation: orb.spinAngle
        fillGradient: ConicalGradient {
            centerX: orb.d / 2
            centerY: orb.d / 2
            angle: 0
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 0.48
                color: "transparent"
            }
            GradientStop {
                position: 0.84
                color: Qt.alpha(orb.kCol, 0.7)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    // esperando / confirmar / terminado / fallido: núcleo radial
    OrbDisc {
        anchors.fill: parent
        visible: orb.kind !== "running" && orb.kind !== "cancel"
        // agent respira; fail queda quieto (la imagen no se mueve al terminar)
        opacity: orb.kind === "agent" ? orb.breath : 1
        fillGradient: RadialGradient {
            centerX: orb.d / 2
            centerY: orb.d / 2
            centerRadius: orb.d / 2
            focalX: centerX
            focalY: centerY
            GradientStop {
                position: 0
                color: Qt.alpha(orb.kCol, orb.kind === "confirm" ? 0.62 : orb.kind === "done" ? 0.5 : orb.kind === "fail" ? 0.45 : 0.55)
            }
            GradientStop {
                position: orb.kind === "confirm" ? 0.85 : orb.kind === "done" ? 0.78 : orb.kind === "fail" ? 0.75 : 0.72
                color: Qt.alpha(orb.kCol, orb.kind === "confirm" ? 0.2 : 0)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(orb.kCol, orb.kind === "confirm" ? 0.2 : 0)
            }
        }
    }

    // sombra interior inferior
    OrbDisc {
        anchors.fill: parent
        fillGradient: RadialGradient {
            centerX: orb.d / 2
            centerY: orb.d * 0.4
            centerRadius: orb.d * 0.62
            focalX: centerX
            focalY: centerY
            GradientStop {
                position: 0.55
                color: "transparent"
            }
            GradientStop {
                position: 1
                color: "#59000000"
            }
        }
    }

    // reflejo especular
    OrbDisc {
        id: spec

        anchors.fill: parent
        fillGradient: RadialGradient {
            centerX: spec.width * 0.34
            centerY: spec.height * 0.26
            centerRadius: spec.width * 0.99
            focalX: centerX
            focalY: centerY
            GradientStop {
                position: 0
                color: "#80ffffff"
            }
            GradientStop {
                position: 0.3
                color: "#0fffffff"
            }
            GradientStop {
                position: 0.46
                color: "transparent"
            }
        }
    }

    // punto que orbita (esperando a un agente externo)
    Item {
        anchors.fill: parent
        visible: orb.kind === "agent"
        rotation: orb.sparkAngle
        Rectangle {
            readonly property real s: Math.max(3, orb.d * 0.1)
            width: s
            height: s
            radius: s / 2
            x: parent.width / 2 - s / 2
            y: 3
            color: "#ffffff"
            opacity: 0.8
        }
    }

    AgentGlyph {
        anchors.centerIn: parent
        agent: orb.destino
        size: orb.d * 0.4
        color: Qt.tint(orb.agentCol, "#b3ffffff")
    }

    // Onda: confirm (continua) o pulso al terminar
    OrbDisc {
        id: ring

        readonly property bool confirmRing: orb.kind === "confirm"
        readonly property bool pulsing: orb.pulseP < 1
        readonly property real p: pulsing ? orb.pulseP : orb.rippleP
        readonly property real pe: 1 - (1 - p) * (1 - p)

        anchors.fill: parent
        visible: confirmRing || pulsing
        scale: 1 + 0.75 * pe
        opacity: 0.6 * (1 - p)
        transformOrigin: Item.Center
        strokeColor: orb.kCol
        strokeWidth: 1.5
    }

    // Insignia (solo el orbe principal): ! ✓ ×
    Rectangle {
        visible: orb.isMain && (orb.kind === "confirm" || orb.kind === "done" || orb.kind === "fail")
        x: -4
        y: orb.d - width + 4
        width: orb.d * 0.38
        height: width
        radius: width / 2
        color: orb.kCol

        Text {
            anchors.centerIn: parent
            text: orb.kind === "confirm" ? "!" : orb.kind === "done" ? "✓" : "×"
            color: "#14111d"
            font.pixelSize: 10
            font.bold: true
        }
    }

    // Punto blanco de «sin leer»
    Rectangle {
        visible: orb.unseen
        x: -2
        y: -2
        width: orb.d * 0.3
        height: width
        radius: width / 2
        color: "#ffffff"
        border.width: 2
        border.color: "#14111d"
    }

    // --- Ratón: etiqueta y pulsar -----------------------------------------
    property bool hovered: mouse.containsMouse
    signal clicked

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !orb.gone
        onClicked: orb.clicked()
    }

    property real nowSec: Date.now() / 1000
    Timer {
        interval: 1000
        repeat: true
        running: orb.hovered
        onTriggered: orb.nowSec = Date.now() / 1000
    }
    onHoveredChanged: if (hovered)
        nowSec = Date.now() / 1000

    function _elapsed(): string {
        const end = orb.job.fin ?? orb.nowSec;
        const s = Math.max(0, Math.round(end - (orb.job.inicio ?? orb.nowSec)));
        return s < 60 ? s + " s" : Math.round(s / 60) + " min";
    }

    Rectangle {
        id: lbl

        anchors.right: parent.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(380, lblText.implicitWidth + 20)
        height: lblText.implicitHeight + 12
        radius: 10
        color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.97)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.12)
        opacity: orb.hovered ? 1 : 0
        visible: opacity > 0.01
        transform: Translate {
            x: orb.hovered ? 0 : 6
            Behavior on x {
                NumberAnimation {
                    duration: 180
                }
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }
        }

        StyledText {
            id: lblText

            anchors.centerIn: parent
            width: lbl.width - 20
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: `<b><font color="${orb.agentCol}">${Laura.agentName(orb.destino)}</font></b> · ${orb.job.titulo ?? ""} · ${orb._elapsed()}`
            font: Tokens.font.body.small
        }
    }
}
