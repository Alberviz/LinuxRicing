import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// «Hay una versión nueva de Hookshot»: A actualiza · B juega con la actual · Y más tarde.
Item {
    id: root

    required property var elysium
    readonly property var c: elysium.hsCheck
    readonly property bool shown: elysium.updAsk
    readonly property color accent: Colours.palette.m3primary

    visible: opacity > 0.01
    opacity: shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 220
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.62)
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: 680
        height: col.implicitHeight + 80
        radius: 30
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(root.accent, 0.4)
        scale: root.shown ? 1 : 0.92
        clip: true

        Behavior on scale {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.4
            }
        }

        // Brillo del acento en la esquina.
        Rectangle {
            x: -140
            y: -160
            width: 420
            height: 420
            radius: 210
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(root.accent, 0.20)
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
            anchors.margins: 40
            spacing: 14

            RowLayout {
                spacing: 16

                Rectangle {
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: 28
                    color: Qt.alpha(root.accent, 0.16)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.5)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "system_update_alt"
                        color: root.accent
                        fill: 1
                        fontStyle: Tokens.font.icon.builders.medium.scale(1.6).build()
                    }
                }

                ColumnLayout {
                    spacing: 2

                    StyledText {
                        text: qsTr("NUEVA VERSIÓN")
                        color: root.accent
                        font.family: Tokens.font.label.small.family
                        font.pointSize: 9
                        font.weight: Font.DemiBold
                        font.letterSpacing: 2.6
                    }

                    StyledText {
                        text: qsTr("Hookshot %1").arg(root.c.latest ?? "")
                        color: Colours.palette.m3onSurface
                        font.family: Tokens.font.title.large.family
                        font.pointSize: 26
                        font.weight: Font.Light
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: [qsTr("Tienes %1").arg(root.c.current ?? "?"), root.c.published ? qsTr("publicada el %1").arg(root.c.published) : "", root.c.sizeMB ? qsTr("%1 MB").arg(root.c.sizeMB) : ""].filter(x => x).join("  ·  ")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.large
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 6
                wrapMode: Text.WordWrap
                text: qsTr("Se descarga, se recompila el juego%1 y se precompilan los shaders. Va en segundo plano: puedes seguir usando el PC o salir de Elysium, y te aviso al terminar.").arg(root.c.lastUpdateMin ? qsTr(" (la última vez, ~%1 min)").arg(root.c.lastUpdateMin) : "")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.large
            }

            Item {
                implicitHeight: 12
            }

            RowLayout {
                spacing: 14

                Btn {
                    letter: "A"
                    label: qsTr("Actualizar")
                    primary: true
                }

                Btn {
                    letter: "B"
                    label: qsTr("Jugar con la actual")
                }

                Btn {
                    letter: "Y"
                    label: qsTr("Más tarde")
                }
            }
        }
    }

    component Btn: Rectangle {
        id: b

        property string letter
        property string label
        property bool primary

        implicitHeight: 50
        implicitWidth: r.implicitWidth + 36
        radius: 25
        color: primary ? root.accent : Qt.alpha(Colours.palette.m3onSurface, 0.08)

        Row {
            id: r

            anchors.centerIn: parent
            spacing: 12

            PadGlyph {
                anchors.verticalCenter: parent.verticalCenter
                letter: b.letter
                tone: b.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: b.label
                color: b.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                font: Tokens.font.title.small
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.elysium.handle(b.letter.toLowerCase())
        }
    }
}
