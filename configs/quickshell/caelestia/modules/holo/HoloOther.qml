pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Visor de archivo genérico u otro formato no previsualizable directamente.
// Muestra icono grande de Material Symbols, nombre del archivo, aviso de error
// o estado si lo hay, y botón para abrir con la aplicación del sistema (xdg-open).
Item {
    id: root

    required property var panel

    readonly property var payload: panel && panel.payload ? panel.payload : ({})

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, 280)
        spacing: 12

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (root.payload && root.payload.icono) ? root.payload.icono : "draft"
            fontStyle: Tokens.font.icon.size(48).build()
            color: (root.payload && root.payload.icono === "error") ? Colours.palette.m3error : Colours.palette.m3secondary
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: root.panel ? (root.panel.titulo ?? "") : ""
            color: Colours.palette.m3onSurface
            font.family: Tokens.font.title.small.family
            font.pixelSize: 14
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            elide: Text.ElideMiddle
            maximumLineCount: 2
        }

        // Aviso opcional (p. ej. «Ya no existe» o «Demasiado grande para previsualizar»)
        Rectangle {
            id: avisoBox
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !!(root.payload && root.payload.aviso)
            width: Math.min(parent.width, avisoText.implicitWidth + 20)
            height: avisoText.implicitHeight + 10
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3errorContainer, 0.45)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3error, 0.4)

            Text {
                id: avisoText
                anchors.centerIn: parent
                text: (root.payload && root.payload.aviso) ? root.payload.aviso : ""
                color: Colours.palette.m3onErrorContainer
                font.family: Tokens.font.label.small.family
                font.pixelSize: 11
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Botón «Abrir con su programa»
        Rectangle {
            id: btnOpen
            anchors.horizontalCenter: parent.horizontalCenter
            width: btnContent.implicitWidth + 24
            height: 32
            radius: 16
            color: Qt.alpha(Colours.palette.m3primary, btnMouse.pressed ? 0.32 : btnMouse.containsMouse ? 0.24 : 0.12)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3primary, 0.5)
            scale: btnMouse.pressed ? 0.96 : 1

            Behavior on color {
                ColorAnimation {
                    duration: HoloGeo.tMicro
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: HoloGeo.tMicro
                    easing.type: HoloGeo.curvaEntra
                }
            }

            Row {
                id: btnContent
                anchors.centerIn: parent
                spacing: 6

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "open_in_new"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3primary
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Abrir con su programa"
                    color: Colours.palette.m3primary
                    font.family: Tokens.font.label.small.family
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.panel && root.panel.item_n !== undefined && root.panel.item_n !== null) {
                        HoloState.externo(root.panel.item_n);
                    }
                }
            }
        }
    }
}
