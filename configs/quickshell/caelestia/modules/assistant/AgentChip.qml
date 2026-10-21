pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Caelestia.Config
import qs.components
import qs.services

// Chip de agente del tablero: glifo (o anillo de actividad), nombre y estado en
// una línea. Pulsarlo filtra la rejilla; volver a pulsarlo quita el filtro.
Rectangle {
    id: chip

    required property string agent
    property bool selected: false
    // Reloj del cajón (s); solo avanza con el cajón visible
    property real clock: 0
    signal clicked

    readonly property color ac: Laura.agentColor(agent)
    readonly property var mine: Laura.jobs.filter(j => agent === "laura" ? (j.origen === "laura") || (j.destino === "laura" && j.origen !== "laura") : (j.destino === agent && j.origen !== "laura"))
    readonly property int nConfirm: mine.filter(j => j.kind === "confirm").length
    readonly property int nRun: mine.filter(j => j.kind === "running").length
    readonly property int nWait: mine.filter(j => j.kind === "agent").length
    readonly property int nFail: mine.filter(j => j.kind === "fail" && !j.leido).length
    readonly property int nOwn: agent === "laura" ? Laura.jobs.filter(j => j.origen === "laura" && !j.leido).length : 0
    readonly property bool busy: nRun + nWait > 0 && nConfirm === 0

    readonly property string tone: nConfirm > 0 ? "cfm" : (nRun + nWait) > 0 ? "act" : nOwn > 0 ? "own" : nFail > 0 ? "bad" : ""
    readonly property string txt: {
        if (nConfirm > 0)
            return nConfirm + (nConfirm > 1 ? " esperan tu OK" : " espera tu OK");
        if (nRun > 0)
            return nRun === 1 ? "Trabajando" : nRun + " en curso";
        if (nWait > 0)
            return nWait + " en cola";
        if (agent === "laura")
            return nOwn > 0 ? nOwn + " avisos suyos" : "Vigía en guardia";
        if (nFail > 0)
            return nFail + " fallo";
        return "Libre";
    }
    readonly property color txtCol: tone === "cfm" ? Laura.cWait : tone === "bad" ? Laura.cFail : tone === "act" ? Colours.palette.m3onSurface : tone === "own" ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant

    implicitHeight: 56
    radius: 16
    color: selected ? Qt.tint(Colours.palette.m3surfaceContainer, Qt.alpha(ac, 0.13)) : (ma.containsMouse ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainer)
    border.width: 1.5
    border.color: selected ? ac : (tone === "cfm" ? Qt.alpha(Laura.cWait, 0.6) : "transparent")
    Behavior on color {
        ColorAnimation {
            duration: 200
        }
    }
    Behavior on border.color {
        ColorAnimation {
            duration: 200
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 11
        anchors.rightMargin: 8
        spacing: 5

        Row {
            spacing: 7
            height: 22

            Item {
                width: 22
                height: 22

                AgentGlyph {
                    anchors.centerIn: parent
                    agent: chip.agent
                    color: chip.ac
                    size: 16
                    visible: !chip.busy
                }
                // anillo de actividad (solo con trabajo en marcha): arco que gira
                Shape {
                    anchors.fill: parent
                    visible: chip.busy
                    rotation: (chip.clock * 240) % 360
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.alpha(Colours.palette.m3onSurface, 0.14)
                        strokeWidth: 3
                        PathAngleArc {
                            centerX: 11
                            centerY: 11
                            radiusX: 9
                            radiusY: 9
                            startAngle: 0
                            sweepAngle: 360
                        }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: chip.ac
                        strokeWidth: 3
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 11
                            centerY: 11
                            radiusX: 9
                            radiusY: 9
                            startAngle: 0
                            sweepAngle: 100
                        }
                    }
                }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Laura.agentName(chip.agent)
                font.pixelSize: 13
                font.bold: true
            }
        }
        Row {
            spacing: 5
            height: 14

            Rectangle {
                width: 6
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: chip.tone === "" ? Colours.palette.m3onSurfaceVariant : chip.txtCol === Colours.palette.m3onSurface ? chip.ac : chip.txtCol
                opacity: chip.tone === "" ? 0.5 : 1
            }
            StyledText {
                width: chip.width - 11 - 8 - 11
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: chip.txt
                color: chip.txtCol
                font.pixelSize: 11.5
                font.bold: chip.tone === "cfm"
            }
        }
    }

    MouseArea {
        id: ma

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
