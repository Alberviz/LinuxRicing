pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Modo centro (conversación): la forma de Aurora nace como un punto en el
// borde inferior y se abre hacia arriba. Se queda mientras dura la charla.
// Layershell a pantalla completa, transparente y click-through.
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

        readonly property real box: 340
        // Fracción de la forma que asoma sobre el borde inferior.
        readonly property real revealFrac: 0.58

        // Se "abre" de punto a tamaño completo al aparecer.
        property real bloom: 0
        state: win.visible ? "open" : "closed"
        states: [
            State {
                name: "open"
                PropertyChanges {
                    root.bloom: 1
                }
            },
            State {
                name: "closed"
                PropertyChanges {
                    root.bloom: 0
                }
            }
        ]
        transitions: Transition {
            NumberAnimation {
                property: "bloom"
                duration: 460
                easing.type: Easing.OutBack
                easing.overshoot: 1.1
            }
        }

        // Resplandor mínimo, pegado al borde inferior (a revisar en los mockups).
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: root.box * 2.2
            height: width
            anchors.bottomMargin: -height * 0.62
            radius: width / 2
            opacity: root.bloom
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0
                    color: "transparent"
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Aurora.accent, 0.16)
                }
            }
            scale: 0.85 + 0.2 * Aurora.amplitude
            Behavior on scale {
                NumberAnimation {
                    duration: 160
                }
            }
        }

        // Caja anclada abajo; la forma nace de su base y crece hacia arriba.
        Item {
            id: orbBox

            width: root.box
            height: root.box
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -height * (1 - root.revealFrac)

            transform: Scale {
                origin.x: orbBox.width / 2
                origin.y: orbBox.height * root.revealFrac
                xScale: root.bloom
                yScale: root.bloom
            }

            Orb {
                anchors.centerIn: parent
                baseSize: root.box
                state: Aurora.state
                level: Aurora.amplitude
            }
        }

        // Bocadillo sobre la forma. Prioriza la RESPUESTA de Aurora al
        // completo; mientras piensa, muestra lo que ha entendido.
        Rectangle {
            id: bubble

            readonly property string body: Aurora.reply || Aurora.transcript

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.box * root.revealFrac + 20

            visible: bubble.body.length > 0 && Aurora.state !== "idle" && Aurora.state !== "listening"
            opacity: (visible ? 1 : 0) * root.bloom
            width: Math.min(Math.max(label.implicitWidth + Tokens.padding.large * 2, 220), parent.width * 0.62)
            height: label.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Qt.alpha(Aurora.surface, 0.92)

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
                wrapMode: Text.WordWrap
                maximumLineCount: 8
                elide: Text.ElideRight
                text: bubble.body
                color: Aurora.onSurface
                opacity: Aurora.reply ? 1 : 0.6
                font: Tokens.font.body.medium
            }
        }
    }
}
