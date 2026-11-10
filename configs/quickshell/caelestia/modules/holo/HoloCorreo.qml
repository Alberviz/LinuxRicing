pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Correos en holograma: remitente con inicial, asunto y la frase-resumen de Laura.
// Los importantes llevan barra de acento y van con más peso.
Item {
    id: root

    required property var panel
    readonly property var items: panel?.payload?.items ?? []
    readonly property color acc: Colours.palette.m3primary

    ListView {
        id: lista
        anchors.fill: parent
        anchors.margins: 10
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: root.items

        delegate: Rectangle {
            id: fila
            required property var modelData
            required property int index
            readonly property bool imp: modelData.importante ?? false
            width: lista.width
            height: 66
            radius: 14
            color: imp ? Qt.alpha(root.acc, 0.12) : (hov.hovered ? Qt.alpha(Colours.palette.m3onSurface, 0.06) : "transparent")
            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }

            property real t: 0
            opacity: t
            transform: Translate {
                x: (1 - fila.t) * 24
            }
            NumberAnimation on t {
                from: 0
                to: 1
                duration: 360 + fila.index * 60
                easing.type: Easing.OutCubic
            }
            HoverHandler {
                id: hov
            }

            Rectangle {
                visible: fila.imp
                x: 0
                width: 3
                height: parent.height - 22
                anchors.verticalCenter: parent.verticalCenter
                radius: 1.5
                color: root.acc
            }

            Rectangle {
                id: avatar
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 38
                radius: 19
                color: fila.imp ? root.acc : Qt.alpha(root.acc, 0.18)
                StyledText {
                    anchors.centerIn: parent
                    text: (fila.modelData.de || "?").charAt(0).toUpperCase()
                    color: fila.imp ? Colours.palette.m3onPrimary : root.acc
                    font.pointSize: 13
                    font.weight: Font.DemiBold
                }
            }

            Column {
                anchors.left: avatar.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Item {
                    width: parent.width
                    height: de.implicitHeight
                    StyledText {
                        id: de
                        anchors.left: parent.left
                        anchors.right: hora.left
                        anchors.rightMargin: 8
                        text: fila.modelData.de
                        elide: Text.ElideRight
                        color: Colours.palette.m3onSurface
                        font.pointSize: 10.5
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        id: hora
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: fila.modelData.hora ?? ""
                        color: fila.imp ? root.acc : Colours.palette.m3onSurfaceVariant
                        font.pointSize: 8.5
                        font.features: {
                            "tnum": 1
                        }
                    }
                }
                StyledText {
                    width: parent.width
                    text: fila.modelData.asunto
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurface
                    font.pointSize: 9.5
                }
                StyledText {
                    width: parent.width
                    text: fila.modelData.frase
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: 9
                }
            }
        }
    }
}
