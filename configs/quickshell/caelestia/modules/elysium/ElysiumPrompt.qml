pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Tarjeta discreta arriba a la derecha: «Mando conectado · Elysium en N s».
StyledRect {
    id: card

    required property var elysium
    readonly property bool shown: elysium.prompt

    implicitWidth: 452
    implicitHeight: col.implicitHeight + 36
    radius: Tokens.rounding.large
    color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.96)
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3primary, 0.35)
    clip: true

    opacity: shown ? 1 : 0
    transform: Translate {
        x: card.shown ? 0 : 60
        Behavior on x {
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutExpo
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 260
        }
    }

    // Halo del acento detrás del icono.
    Rectangle {
        x: -60
        y: -60
        width: 200
        height: 200
        radius: 100
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(Colours.palette.m3primary, 0.22)
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }
    }

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 14

        RowLayout {
            spacing: 14

            Rectangle {
                implicitWidth: 48
                implicitHeight: 48
                radius: 24
                color: Qt.alpha(Colours.palette.m3primary, 0.16)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3primary, 0.5)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "stadia_controller"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.5).build()
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: qsTr("MANDO CONECTADO")
                    color: Colours.palette.m3primary
                    font.family: Tokens.font.label.small.family
                    font.pointSize: 8
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2.4
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("¿Entrar en Elysium?")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.title.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.elysium.padName
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            // Cuenta atrás grande.
            StyledText {
                text: card.elysium.countdown
                color: Colours.palette.m3primary
                font.family: Tokens.font.title.large.family
                font.pointSize: 26
                font.weight: Font.Light
            }
        }

        RowLayout {
            spacing: 8

            PadButton {
                glyph: "A"
                label: qsTr("Elysium")
                primary: true
                onClicked: card.elysium.enter()
            }

            PadButton {
                glyph: "Y"
                label: qsTr("Solo modo juego")
                onClicked: card.elysium.enterNormal()
            }

            PadButton {
                glyph: "B"
                label: qsTr("Ahora no")
                onClicked: card.elysium.prompt = false
            }
        }
    }

    // Barra que se consume en 6 s.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        height: 3
        color: Colours.palette.m3primary
        width: card.shown ? 0 : parent.width

        Behavior on width {
            enabled: card.shown
            NumberAnimation {
                duration: 6000
            }
        }
    }

    component PadButton: Rectangle {
        id: btn

        property string glyph
        property string label
        property bool primary

        signal clicked

        implicitHeight: 34
        implicitWidth: row.implicitWidth + 20
        radius: 17
        color: primary ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurface, ma.containsMouse ? 0.12 : 0.06)

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        RowLayout {
            id: row

            anchors.centerIn: parent
            spacing: 7

            Rectangle {
                implicitWidth: 20
                implicitHeight: 20
                radius: 10
                color: "transparent"
                border.width: 1.5
                border.color: btn.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant

                StyledText {
                    anchors.centerIn: parent
                    text: btn.glyph
                    font.pointSize: 7.5
                    font.weight: Font.Bold
                    color: btn.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                }
            }

            StyledText {
                text: btn.label
                font: Tokens.font.label.medium
                color: btn.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            }
        }

        MouseArea {
            id: ma

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
