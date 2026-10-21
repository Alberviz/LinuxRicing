pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Overlay único de Laura — borde «Gemini» (propuesta E del mockup-barra).
//
// Al levantarla Alberto, la luz nace con un destello en el centro del borde
// inferior, se abre a los dos lados, sube por los laterales y cierra el
// contorno arriba (progress 0..1, 1,9 s). Estable: gradiente multicolor que
// fluye despacio, respira y su profundidad sigue la voz. Pensando y delegando
// un «cometa» recorre el contorno; al delegar la paleta pasa al color del
// agente. Al terminar se recoge al centro (el mismo progress al revés, 1,3 s).
// Subtítulos: píldora con fila de estado, lo que dijo Alberto en pequeño y la
// respuesta de Laura en grande.
//
// Todo es UN ShaderEffect a pantalla completa (shaders/laura_edge.frag.qsb), sin
// shadowBlur. El reloj corre a ~30 fps SOLO con el overlay visible; en reposo la
// ventana está oculta y no hay nada en marcha. Click-through total.
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

    readonly property bool lit: Laura.borderActive
    // Frente de entrada / salida
    property real progress: 0
    NumberAnimation {
        id: front

        target: win
        property: "progress"
        easing.type: Easing.InOutCubic
    }
    onLitChanged: {
        front.stop();
        front.to = lit ? 1 : 0;
        front.duration = Math.max(1, Math.round((lit ? 1900 : 1300) * Math.abs(front.to - progress)));
        front.start();
    }

    visible: lit || progress > 0.001

    // --- Estado de la presentación ---
    readonly property string phase: Laura.state
    readonly property bool listening: phase === "listening"
    readonly property bool thinking: phase === "thinking"
    readonly property bool speaking: phase === "speaking"

    // Agente al que se delega (Gemini / Claude): trabajo activo recién lanzado por Alberto
    readonly property string delegAgent: {
        const lim = Date.now() / 1000 - 25;
        for (const j of Laura.jobs)
            if ((j.destino === "gemini" || j.destino === "claude") && j.origen !== "laura" && Laura.isActive(j) && j.inicio > lim)
                return j.destino;
        return "";
    }
    readonly property bool deleg: delegAgent !== "" && (thinking || speaking)

    // --- Reloj (solo con el overlay visible) ---
    property real time: 0
    property real flow: 0
    property real comet: 0
    Timer {
        interval: 33
        repeat: true
        running: win.visible
        property real last: 0
        onRunningChanged: last = Date.now()
        onTriggered: {
            const now = Date.now();
            const dt = Math.min(0.1, (now - last) / 1000);
            last = now;
            win.time += dt;
            win.flow += dt * (win.deleg ? 0.2 : win.thinking ? 0.16 : 0.07);
            win.comet = (win.comet + dt * (win.deleg ? 0.5 : win.thinking ? 0.3 : 0)) % 1;
        }
    }

    // --- Paleta (transiciones suaves al cambiar de estado) ---
    readonly property color gb: "#7db4ff"
    readonly property color gp: "#b69cff"
    readonly property color co: "#ee9a6e"
    readonly property color ca: "#f6c58a"
    readonly property color tert: Colours.palette.m3tertiary
    readonly property color prim: Colours.palette.m3primary
    function _lt(c, t): color {
        return Qt.tint(c, Qt.rgba(1, 1, 1, t));
    }
    readonly property var pal: {
        if (deleg && delegAgent === "gemini")
            return [gb, gp, _lt(gb, 0.35), gp];
        if (deleg)
            return [co, ca, _lt(co, 0.3), ca];
        if (thinking)
            return [gp, tert, gb, prim];
        return [gb, gp, tert, prim];
    }
    property color c0: pal[0]
    property color c1: pal[1]
    property color c2: pal[2]
    property color c3: pal[3]
    Behavior on c0 {
        ColorAnimation {
            duration: 500
        }
    }
    Behavior on c1 {
        ColorAnimation {
            duration: 500
        }
    }
    Behavior on c2 {
        ColorAnimation {
            duration: 500
        }
    }
    Behavior on c3 {
        ColorAnimation {
            duration: 500
        }
    }

    // Intensidad: sigue la voz al escuchar / hablar; constante al pensar
    property real glowVal: (listening || speaking) ? Laura.amplitude : 0.22
    Behavior on glowVal {
        NumberAnimation {
            duration: 120
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: win.progress > 0.001
        blending: true
        fragmentShader: Qt.resolvedUrl("shaders/laura_edge.frag.qsb")

        property real progress: win.progress
        property real time: win.time
        property real flow: win.flow
        property real glow: win.glowVal
        property real depth: 0
        property real comet: win.comet
        property real cometOn: (win.thinking || win.deleg) ? 1 : 0
        property size res: Qt.size(width, height)
        property color c0: win.c0
        property color c1: win.c1
        property color c2: win.c2
        property color c3: win.c3
    }

    // --- Píldora de subtítulos ----------------------------------------------
    Rectangle {
        id: pill

        readonly property real pad: Tokens.padding.large
        readonly property string youText: Laura.transcript
        readonly property string herText: Laura.reply
        readonly property color cc: win.deleg ? (win.delegAgent === "gemini" ? win.gb : win.co) : win.thinking ? win.tert : win.prim
        readonly property string label: win.deleg ? "Delegando en " + (win.delegAgent === "gemini" ? "Gemini" : "Claude") : win.listening ? "Escuchando" : win.thinking ? "Pensando" : "Laura"
        readonly property bool showHer: (win.speaking || win.deleg) && herText.length > 0

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.extraLarge * 2

        readonly property bool hasContent: win.lit && (youText.length > 0 || showHer)
        visible: opacity > 0.001
        opacity: hasContent ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 280
            }
        }

        width: Math.min(Math.max(col.implicitWidth + pad * 2, 380), parent.width * 0.68)
        height: col.implicitHeight + pad * 1.4 + 6
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

        radius: 22
        color: Qt.alpha(Colours.palette.m3surface, 0.82)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.11)
        clip: true

        // reflejo superior suave
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colours.palette.m3onSurface, 0.07)
                }
                GradientStop {
                    position: 0.4
                    color: "transparent"
                }
            }
        }

        Column {
            id: col

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: pill.pad * 0.7
            width: parent.width - pill.pad * 2
            spacing: 6

            // Fila de estado: punto + etiqueta + ecualizador
            Item {
                width: parent.width
                height: 14

                Rectangle {
                    id: dot

                    width: 8
                    height: 8
                    radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: pill.cc
                }
                StyledText {
                    anchors.left: dot.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.label.toUpperCase()
                    color: Colours.palette.m3onSurfaceVariant
                    font.pixelSize: 11
                    font.letterSpacing: 1.3
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index

                            readonly property real ph: [0, 0.9, 1.9, 0.35][index]
                            readonly property bool moving: win.listening || win.speaking
                            width: 2.5
                            height: moving ? 3 + 9 * (0.25 + 0.75 * Laura.amplitude) * (0.5 + 0.5 * Math.sin(win.time * 9 + ph * 3)) : 3
                            radius: 1.5
                            anchors.verticalCenter: parent.verticalCenter
                            color: pill.cc
                            opacity: moving ? 1 : 0.5
                        }
                    }
                }
            }

            StyledText {
                width: parent.width
                visible: pill.youText.length > 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                text: "“" + pill.youText + "”"
                color: Colours.palette.m3onSurfaceVariant
                opacity: pill.showHer ? 0.55 : 0.9
                font.pixelSize: pill.showHer ? 13.5 : 15
            }

            StyledText {
                width: parent.width
                visible: pill.showHer
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 8
                elide: Text.ElideRight
                text: pill.herText
                color: Colours.palette.m3onSurface
                font.pixelSize: 21
                font.weight: Font.Medium
            }
        }

        // Barra de progreso inferior al delegar
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2.5
            visible: win.deleg

            Rectangle {
                width: parent.width / 2
                height: parent.height
                x: -width + (parent.width + width) * ((win.time / 1.6) % 1)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 0.35
                        color: win.deleg ? (win.delegAgent === "gemini" ? win.gb : win.co) : "transparent"
                    }
                    GradientStop {
                        position: 0.65
                        color: win.deleg ? (win.delegAgent === "gemini" ? win.gp : win.ca) : "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }
        }
    }
}
