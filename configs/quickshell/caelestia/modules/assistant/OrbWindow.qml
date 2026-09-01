pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Modo centro: el orbe emerge del borde inferior de la pantalla (queda
// medio oculto), con un resplandor suave detrás para darle cuerpo sin
// oscurecer el resto. Layershell a pantalla completa, click-through.
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
        id: root

        anchors.fill: parent
        opacity: win.visible ? 1 : 0

        readonly property real orbSize: 420
        // Cuánto asoma el orbe por encima del borde inferior.
        readonly property real reveal: Aurora.active ? orbSize * 0.6 : orbSize * 0.42

        Behavior on opacity {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutQuad
            }
        }

        // Resplandor detrás del orbe, anclado abajo. Nada de oscurecer;
        // solo un halo cálido que sube desde el borde.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: root.orbSize * 3.2
            height: width
            anchors.bottomMargin: -height / 2 + root.reveal * 0.7
            radius: width / 2
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0
                    color: "transparent"
                }
                GradientStop {
                    position: 0.5
                    color: Qt.alpha(Aurora.accent, 0.12)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Aurora.accent, 0.22)
                }
            }
            scale: 0.9 + 0.15 * Aurora.amplitude

            Behavior on scale {
                NumberAnimation {
                    duration: 160
                }
            }
        }

        Orb {
            id: orb

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.reveal - height
            width: root.orbSize
            height: root.orbSize

            state: Aurora.state
            level: Aurora.amplitude

            Behavior on anchors.bottomMargin {
                NumberAnimation {
                    duration: 320
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Bocadillo con lo último que dijo Alberto, sobre el orbe.
        Rectangle {
            id: bubble

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.reveal + 20

            visible: label.text.length > 0 && Aurora.state !== "idle"
            opacity: visible ? 1 : 0
            width: Math.min(label.implicitWidth + 36, parent.width * 0.5)
            height: label.implicitHeight + 24
            radius: height / 2
            color: Qt.alpha(Aurora.surface, 0.85)

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }

            StyledText {
                id: label

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
