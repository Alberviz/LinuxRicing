pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Modo centro: orbe grande centrado en pantalla. Layershell a pantalla
// completa, transparente y click-through (no captura ratón ni teclado).
StyledWindow {
    id: win

    required property ShellScreen modelData

    screen: modelData
    name: "aurora-orb"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    // Click-through total: máscara de entrada vacía.
    mask: Region {}

    visible: Aurora.active && Aurora.mode === "centro"

    Item {
        anchors.fill: parent
        opacity: win.visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutQuad
            }
        }

        Orb {
            id: orb

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: 360
            height: 360

            state: Aurora.state
            level: Aurora.amplitude
        }

        // Bocadillo con lo último que dijo Alberto
        Rectangle {
            id: bubble

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: orb.bottom
            anchors.topMargin: 24

            visible: text.text.length > 0 && Aurora.state !== "idle"
            opacity: visible ? 1 : 0
            width: Math.min(text.implicitWidth + 36, parent.width * 0.5)
            height: text.implicitHeight + 24
            radius: height / 2
            color: Qt.alpha(Aurora.surface, 0.85)

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }

            StyledText {
                id: text

                anchors.centerIn: parent
                width: parent.width - 36
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                text: Aurora.transcript
                color: Aurora.onSurface
            }
        }
    }
}
