pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Chasis provisional del panel holográfico (la Task 5 implementará el chasis definitivo con shaders y animaciones).
Rectangle {
    id: root

    required property var panel
    property var holoLayer
    property real targetX: 0
    property real targetY: 0
    property real targetRot: 0
    property point origin: Qt.point(holoLayer ? holoLayer.width / 2 : 0, holoLayer ? holoLayer.height - 0.06 * holoLayer.height : 0)

    function sendAway(): void {}
    function closeAway(): void {}

    x: targetX
    y: targetY
    rotation: targetRot

    width: holoLayer && holoLayer.posiciones && holoLayer.posiciones[panel.id] ? holoLayer.posiciones[panel.id].w : 400
    height: holoLayer && holoLayer.posiciones && holoLayer.posiciones[panel.id] ? holoLayer.posiciones[panel.id].h : 300

    Behavior on x {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutCubic
        }
    }
    Behavior on y {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutCubic
        }
    }

    radius: Tokens.rounding.large
    color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.86)
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3primary, 0.55)
    clip: true

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 44

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: (root.panel && root.panel.titulo ? root.panel.titulo : "").toUpperCase()
            color: Colours.palette.m3primary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            elide: Text.ElideRight
            width: parent.width - 64
        }

        // Botón de cerrar
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: 14
            color: closeMouse.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.12) : "transparent"

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: Colours.palette.m3onSurfaceVariant
                font.pixelSize: 14
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: HoloState.cerrar(root.panel.id)
            }
        }
    }

    // Contenido del panel
    Loader {
        id: contentLoader
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 8
        sourceComponent: fallbackComp
    }

    Component {
        id: fallbackComp

        Item {
            anchors.fill: parent

            Text {
                anchors.centerIn: parent
                text: root.panel ? (root.panel.titulo ?? "") : ""
                color: Colours.palette.m3onSurface
                font.pixelSize: 15
            }
        }
    }
}
