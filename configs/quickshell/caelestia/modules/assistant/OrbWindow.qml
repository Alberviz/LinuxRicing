pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Modo centro: la forma de Aurora emerge del borde inferior de la pantalla
// (queda medio oculta), con un resplandor suave detrás para darle cuerpo sin
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

    mask: Region {}

    visible: Aurora.active && Aurora.mode === "centro"

    Item {
        id: root

        anchors.fill: parent
        opacity: win.visible ? 1 : 0

        readonly property real box: 360
        // Cuánto asoma la forma por encima del borde inferior.
        readonly property real reveal: Aurora.active ? box * 0.62 : box * 0.42

        Behavior on opacity {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutQuad
            }
        }

        // Resplandor detrás de la forma, anclado abajo. No oscurece nada;
        // solo un halo que sube desde el borde.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: root.box * 3
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
                    color: Qt.alpha(Aurora.accent, 0.10)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Aurora.accent, 0.20)
                }
            }
            scale: 0.9 + 0.15 * Aurora.amplitude
            Behavior on scale {
                NumberAnimation {
                    duration: 160
                }
            }
        }

        // Caja fija que emerge; la forma va centrada dentro.
        Item {
            id: orbBox

            width: root.box
            height: root.box
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.reveal - height

            Behavior on anchors.bottomMargin {
                NumberAnimation {
                    duration: 340
                    easing.type: Easing.OutCubic
                }
            }

            Orb {
                anchors.centerIn: parent
                baseSize: root.box
                state: Aurora.state
                level: Aurora.amplitude
            }
        }

        // Bocadillo con lo último que dijo Alberto, sobre la forma.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.reveal + 24

            visible: label.text.length > 0 && Aurora.state !== "idle"
            opacity: visible ? 1 : 0
            width: Math.min(label.implicitWidth + Tokens.padding.large * 2, parent.width * 0.5)
            height: label.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.full
            color: Qt.alpha(Aurora.surface, 0.9)

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }

            StyledText {
                id: label

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.large * 2
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                text: Aurora.transcript
                color: Aurora.onSurface
                font: Tokens.font.body.medium
            }
        }
    }
}
