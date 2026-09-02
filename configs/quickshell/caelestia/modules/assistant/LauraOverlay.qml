pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Overlay único de Laura. Un solo modo: mientras el ciclo está activo el
// BORDE INFERIOR de la pantalla se ilumina como una barra de luz que sigue el
// estado (escucha / piensa / habla), y una PÍLDORA translúcida centrada abajo
// muestra los subtítulos: lo que dijo Alberto y, al responder, la respuesta
// completa de Laura.
//
// Layershell a pantalla completa, transparente y click-through total
// (`mask: Region {}`). La luz son gradientes, sin shader. Todos los colores
// salen de `Colours.palette` (tema dinámico de Caelestia).
StyledWindow {
    id: win

    required property ShellScreen modelData

    screen: modelData
    name: "laura"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    // Sin zona de input: todo lo que hay debajo se sigue pudiendo clicar.
    mask: Region {}

    // Fundido global del overlay al entrar / salir de reposo.
    property real reveal: Laura.active ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutQuad
        }
    }

    visible: Laura.active || reveal > 0.001

    Item {
        id: root

        anchors.fill: parent
        opacity: win.reveal

        // Estado del ciclo: idle | listening | thinking | speaking
        readonly property string phase: Laura.state
        readonly property bool listening: phase === "listening"
        readonly property bool thinking: phase === "thinking"
        readonly property bool speaking: phase === "speaking"

        // --- Motor de la luz -------------------------------------------------

        // Vaivén sintético mientras "piensa" (no hay amplitud que seguir).
        property real thinkPulse: 0
        SequentialAnimation on thinkPulse {
            running: root.thinking && win.visible
            loops: Animation.Infinite
            NumberAnimation {
                to: 1
                duration: 1500
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 0
                duration: 1500
                easing.type: Easing.InOutSine
            }
        }

        // Intensidad objetivo 0..1 de la barra de luz según el estado.
        //  · escucha  → brillo estable que sigue la amplitud del micro
        //  · habla    → palpita con la envolvente del TTS (misma amplitud)
        //  · piensa   → deriva suave sin amplitud
        readonly property real targetGlow: {
            if (root.listening)
                return Math.min(1, 0.30 + 0.55 * Laura.amplitude);
            if (root.speaking)
                return Math.min(1, 0.38 + 0.60 * Laura.amplitude);
            if (root.thinking)
                return 0.34 + 0.13 * root.thinkPulse;
            return 0;
        }

        // Suavizado de los saltos de estado (la amplitud ya viene suavizada).
        property real glow: 0
        onTargetGlowChanged: glow = targetGlow
        Behavior on glow {
            NumberAnimation {
                duration: 130
                easing.type: Easing.OutQuad
            }
        }

        // Color de la luz: primario; al pensar deriva hacia terciario.
        function _lerp(a, b, t) {
            return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
        }
        // No `readonly`: el Behavior necesita poder escribir la propiedad al
        // reevaluarse el binding (transición de tono al entrar/salir de "piensa").
        property color lightColor: root.thinking ? root._lerp(Colours.palette.m3primary, Colours.palette.m3tertiary, root.thinkPulse) : Colours.palette.m3primary
        Behavior on lightColor {
            ColorAnimation {
                duration: 400
            }
        }

        // --- Barra de luz del borde inferior -------------------------------

        Item {
            id: lightBar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // La altura crece con la intensidad (decisión de Alberto).
            height: 80 + 260 * root.glow

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 0.62
                        color: Qt.alpha(root.lightColor, 0.14)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(root.lightColor, 0.72)
                    }
                }
            }

            // Línea nítida pegada al filo, como el borde de un tubo de luz.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                color: Qt.alpha(root.lightColor, 0.55 + 0.45 * root.glow)
            }
        }

        // --- Píldora de subtítulos ----------------------------------------

        Rectangle {
            id: pill

            readonly property real pad: Tokens.padding.large
            readonly property string youText: Laura.transcript
            readonly property string herText: Laura.reply

            // Qué enseñar:
            //  · piensa → solo lo que entendió (atenuado)
            //  · habla  → lo que entendió (fino) + la respuesta completa
            readonly property bool hasContent: (root.thinking && youText.length > 0) || (root.speaking && (herText.length > 0 || youText.length > 0))

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Tokens.padding.extraLarge * 2

            visible: opacity > 0.001
            opacity: (hasContent ? 1 : 0) * win.reveal
            Behavior on opacity {
                NumberAnimation {
                    duration: 220
                }
            }

            width: Math.min(Math.max(col.implicitWidth + pad * 2, 260), parent.width * 0.68)
            height: col.implicitHeight + pad * 2
            Behavior on width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutQuad
                }
            }

            radius: Tokens.rounding.large
            color: Qt.alpha(Colours.palette.m3surface, 0.82)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3onSurface, 0.1)

            Column {
                id: col

                anchors.centerIn: parent
                width: parent.width - pill.pad * 2
                spacing: Tokens.spacing.small

                StyledText {
                    width: parent.width
                    visible: pill.youText.length > 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    text: pill.youText
                    color: Colours.palette.m3onSurfaceVariant
                    opacity: root.speaking ? 0.55 : 0.85
                    font: Tokens.font.body.small
                }

                StyledText {
                    width: parent.width
                    visible: root.speaking && pill.herText.length > 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 8
                    elide: Text.ElideRight
                    text: pill.herText
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.medium
                }
            }
        }
    }
}
