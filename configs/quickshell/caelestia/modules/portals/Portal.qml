import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Un portal Gargantua clavado en el borde (variante B del mockup). La física/animación de
// estado la hace Portals.qml en un único tick y escribe aquí; este item solo pinta:
// un ShaderEffect (portal.frag) centrado en el agujero, las rectas del borde de pantalla y
// las etiquetas HUD. Nada corre por su cuenta: sin bucles ni temporizadores.
Item {
    id: root

    required property string edge      // "right" | "top"
    required property real winW
    required property real winH
    required property real u           // px por px de mockup (ancho/1280)
    required property string kicker    // TELE / MÓVIL
    required property string title
    required property string detail
    required property string cta

    // Estado (lo escribe Portals.tick)
    property real e: 0
    // Lente (Fase 5): textura de la captura de la pantalla, si está lista, y fuerza 0..1 según el tamaño de la pantalla.
    property var captura: null
    property bool capturaLista: false
    property real lenteK: 1
    // El otro agujero del mismo borde (móvil y tablet a la vez): las dos lentes se componen en vez de taparse.
    property Item vecino: null
    readonly property real fuerza: Math.max(0, Math.min(1, (winW - 1280) / 640))
    property real r: 30 * u
    property real vis: 0
    property real dim: 0
    property real pulse: 0
    property real spinPhase: 0
    property real pullPhase: 0
    // v2.17 (Olimpo): varios portales en el borde superior, uno por dispositivo
    property real posX: 0.5
    property string destino: ""
    property real cx: edge === "right" ? winW + 2 * r : winW * posX
    property real cy: edge === "right" ? winH / 2 : -2 * r
    property bool armed: false
    property string phase: "idle"      // idle | sending | ok | error | unavail
    property string status: ""
    // Aviso previo a soltar (lo rellena Portals al entrar el DnD en la banda)
    property bool over: false
    property string bad: ""            // motivo por el que NO se puede enviar («» = ok)
    property string fileLine: ""       // nombre · tamaño del archivo arrastrado
    property string fileName: ""
    // Transferencia (tarjeta persistente)
    property string tName: ""
    property real tProgress: -1        // -1 indeterminado, 0..1
    property string tText: ""
    property string tSub: ""
    property string tIcon: ""
    property string customKicker: ""
    property string customTitle: ""
    property real phaseT: 0
    // v2.19.1: «a los dos». Mientras dura la fusión el agujero lo pinta Portals.qml (shader BINARIO) y aquí solo quedan
    // las etiquetas y la tarjeta; el borde recto y el agujero propio se apagan.
    property bool fundido: false
    readonly property Item maskItem: maskBox
    signal cancel

    readonly property bool hot: armed || phase === "ok" || phase === "error"
    readonly property bool showPill: armed || (over && bad !== "")
    readonly property real half: 7.5 * r
    readonly property color warm: Qt.rgba(1, 0.871, 0.725, 1)

    anchors.fill: parent
    visible: vis > 0.01

    // Tramos rectos del borde de pantalla (el arco que rodea el agujero lo pinta el shader)
    Repeater {
        model: 4

        Rectangle {
            required property int index
            readonly property bool glow: index < 2
            readonly property bool second: index % 2 === 1
            readonly property real rr: root.r * (1.45 + 0.25 * root.e) * root.vis
            readonly property real th: Math.max(0.6, (glow ? 5 : 1.4) * root.u)
            readonly property real a: (glow ? 0.06 : 0.45) * root.vis * (0.35 + 0.65 * root.e)

            color: Qt.rgba(1, 0.871, 0.725, a)
            x: root.edge === "right" ? root.winW - th - 0 : (second ? root.cx + rr : 0)
            y: root.edge === "right" ? (second ? root.cy + rr : 0) : 0
            width: root.edge === "right" ? th : (second ? root.winW - (root.cx + rr) : root.cx - rr)
            height: root.edge === "right" ? (second ? root.winH - (root.cy + rr) : root.cy - rr) : th
            visible: width > 0 && height > 0
            opacity: root.fundido ? 0 : 1

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }
    }

    ShaderEffect {
        visible: !root.fundido
        x: root.cx - root.half
        y: root.cy - root.half
        width: root.half * 2
        height: root.half * 2

        property vector2d size: Qt.vector2d(width, height)
        property vector2d outward: root.edge === "right" ? Qt.vector2d(1, 0) : Qt.vector2d(0, -1)
        property color tint: root.bad !== "" && root.over ? Qt.rgba(1, 0.3, 0.2, 0.8) : (root.tIcon === "music_note" ? Qt.rgba(0.11, 0.73, 0.33, 0.28) : Qt.rgba(Colours.palette.m3primary.r, Colours.palette.m3primary.g, Colours.palette.m3primary.b, 0.18))
        property real rad: root.r * (0.15 + 0.85 * Math.min(1, root.vis))  // v2.16: crece desde un punto
        property real upx: root.u
        property real en: root.e
        property real vis: root.vis
        property real armed: root.armed ? 1 : 0
        property real pulse: root.pulse
        property real spin: root.spinPhase
        property real pull: root.pullPhase
        // v2.19.1 (Olimpo, AE1): reloj del cielo y del gas; reposo 1 = disco y halo casi apagados (fuera de alcance)
        property real time: root.phaseT
        readonly property real et: Math.max(0, Math.min(1, (root.e - 0.05) / 0.55))
        property real reposo: root.phase === "idle" ? 1 - et * et * (3 - 2 * et) : 0
        // Modo 0 = AE1. Los campos del binario no se usan aquí, pero el bloque de uniforms los pide.
        property real mode: 0
        property vector2d ctr1: Qt.vector2d(0, 0)
        property vector2d ctr2: Qt.vector2d(0, 0)
        property real fase: 0
        property real uno: 0
        property real onda: 0
        property real oval: 0
        // Lente real (diseño: LinuxRicing/docs/plans/warp-teclado-portales.md, Fase 5): captura congelada de la pantalla
        // y fuerza del PC. Sin captura (`lente` 0) el shader cae al cielo sintético.
        property var bg: root.captura
        property vector2d quadPos: Qt.vector2d(x, y)
        property vector2d scrSize: Qt.vector2d(root.winW, root.winH)
        property real lente: root.captura && root.capturaLista ? root.lenteK : 0
        property real fuerza: root.fuerza
        property vector4d vecino: root.vecino && root.vecino.visible && root.vecino.vis > 0.01 ? Qt.vector4d(root.vecino.cx - root.cx, root.vecino.cy - root.cy, root.vecino.r * (0.15 + 0.85 * Math.min(1, root.vecino.vis)), root.vecino.vis) : Qt.vector4d(0, 0, 0, 0)

        fragmentShader: Qt.resolvedUrl("shaders/portal.frag.qsb")
    }

    // Etiquetas y tarjeta en una capa por encima de TODOS los agujeros (cuelga del padre): así el quad del agujero vecino
    // no pinta encima de los textos de este.
    Item {
        parent: root.parent
        anchors.fill: parent
        z: 3
        visible: root.visible

        // Placa de la etiqueta: cristal oscuro con filo cálido, para que se lea encima de cualquier ventana (y de la lente).
        Rectangle {
            readonly property real px: hud.fs * 1.1
            readonly property real py: hud.fs * 0.9
            x: hud.x - px
            y: hud.y - py
            width: hud.width + px * 2
            // Sin píldora («Suelta para enviar») la placa se recoge: no deja un hueco vacío debajo del detalle.
            height: hud.height + py * 2 - (root.showPill ? 0 : pildora.height + hud.spacing)
            radius: hud.fs * 1.3
            visible: hud.opacity > 0.01
            opacity: hud.opacity
            color: Qt.rgba(0.02, 0.024, 0.04, 0.86)
            border.width: 1
            border.color: Qt.rgba(1, 0.871, 0.725, root.showPill ? 0.5 : 0.2)

            Behavior on border.color {
                ColorAnimation {
                    duration: 160
                }
            }
            Behavior on height {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }

        // Etiqueta HUD
        Column {
            id: hud

            readonly property real fs: 11 * root.u
            // Derecho: arriba-izquierda del agujero (margen respecto a la sombra), dentro de pantalla.
            // Superior: a la derecha del agujero. Siempre sin salirse de la ventana.
            x: root.edge === "right" ? Math.max(8, root.cx - root.r * 1.5 - width) : Math.min(root.winW - width - 8, root.cx + root.r * 1.7)
            y: root.edge === "right" ? Math.max(24 * root.u, root.cy - root.r * 1.4 - height) : root.r * 0.5 + 10
            spacing: fs * 0.55
            opacity: root.phase === "idle" && root.vis > 0.05 && root.e > 0.35 ? Math.min(1, (root.e - 0.35) / 0.3) * (1 - 0.6 * root.dim) * Math.max(0, Math.min(1, (root.vis - 0.55) / 0.35)) : 0

            Text {
                x: root.edge === "right" ? hud.width - width : 0
                text: root.customKicker || root.kicker
                font.family: "JetBrainsMono Nerd Font Mono"
                font.pixelSize: hud.fs * 0.8
                font.weight: Font.Medium
                font.letterSpacing: hud.fs * 0.8 * 0.22
                color: Colours.palette.m3tertiary
            }
            Text {
                x: root.edge === "right" ? hud.width - width : 0
                text: root.customTitle || root.title
                font.pixelSize: hud.fs * 1.5
                font.weight: Font.Medium
                color: Colours.palette.m3onSurface
            }
            Text {
                x: root.edge === "right" ? hud.width - width : 0
                text: root.detail
                font.family: "JetBrainsMono Nerd Font Mono"
                font.pixelSize: hud.fs * 0.8
                color: Colours.palette.m3onSurfaceVariant
            }
            Text {
                x: root.edge === "right" ? hud.width - width : 0
                visible: root.fileLine !== ""
                text: root.fileLine
                font.family: "JetBrainsMono Nerd Font Mono"
                font.pixelSize: hud.fs * 0.85
                color: Colours.palette.m3onSurface
            }
            Item {
                id: pildora

                x: root.edge === "right" ? hud.width - width : 0
                width: ctaText.implicitWidth + hud.fs * 1.6
                height: ctaText.implicitHeight + hud.fs

                Rectangle {
                    id: pill

                    width: parent.width
                    height: parent.height
                    y: root.showPill ? 0 : 4
                    radius: height / 2
                    color: root.bad !== "" ? "#d63a33" : root.warm
                    opacity: root.showPill ? 1 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }
                    Behavior on y {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }
                }

                Text {
                    id: ctaText

                    anchors.centerIn: pill
                    opacity: pill.opacity
                    text: root.bad !== "" ? root.bad : root.cta
                    font.family: "JetBrainsMono Nerd Font Mono"
                    font.pixelSize: hud.fs * 0.85
                    font.weight: Font.Medium
                    color: root.bad !== "" ? "#ffffff" : "#05060a"
                }
            }
        }

        // Tarjeta de transferencia persistente (progreso / resultado), cerca del agujero
        Item {
            id: maskBox

            x: card.x
            y: card.y
            width: card.visible ? card.width : 0
            height: card.visible ? card.height : 0
        }

        Rectangle {
            id: card

            readonly property real pad: 14 * root.u
            readonly property bool failed: root.phase === "error"
            width: 340 * root.u
            height: col.implicitHeight + pad * 2
            x: root.edge === "right" ? root.winW - width - 28 * root.u : Math.min(root.winW - width - 8, root.cx + root.r * 1.7)
            y: root.edge === "right" ? Math.min(root.winH - height - 8, root.cy + root.r * 1.7) : 40 * root.u
            visible: root.vis > 0.01 && (root.phase === "sending" || root.phase === "ok" || root.phase === "error")
            radius: Tokens.rounding.large
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.96)
            border.width: 1.5
            border.color: failed ? Colours.palette.m3error : root.phase === "ok" ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.5)

            Column {
                id: col

                x: card.pad
                y: card.pad
                width: card.width - card.pad * 2
                spacing: 9 * root.u

                Row {
                    width: parent.width
                    spacing: 8 * root.u

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.failed ? "error" : root.phase === "ok" ? "check_circle" : (root.tIcon ? root.tIcon : (root.edge === "right" ? "cast" : "smartphone"))
                        color: card.failed ? Colours.palette.m3error : (root.tIcon === "music_note" && root.phase === "sending" ? "#1db954" : Colours.palette.m3primary)
                        fontStyle: Tokens.font.icon.medium
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 80 * root.u
                        text: root.tName
                        elide: Text.ElideMiddle
                        font.pixelSize: 13 * root.u
                        font.weight: Font.Medium
                        color: Colours.palette.m3onSurface
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.phase === "sending"
                        icon: "close"
                        type: IconButton.Text
                        onClicked: root.cancel()
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 6 * root.u
                    radius: height / 2
                    color: Colours.palette.m3surfaceContainerHighest
                    clip: true

                    Rectangle {
                        readonly property bool indet: root.tProgress < 0 && root.phase === "sending"
                        height: parent.height
                        radius: height / 2
                        width: indet ? parent.width * 0.3 : parent.width * (root.phase === "ok" ? 1 : Math.max(0, root.tProgress))
                        x: indet ? ((root.phaseT * 0.7) % 1.3 - 0.3) * parent.width : 0
                        color: card.failed ? Colours.palette.m3error : Colours.palette.m3primary
                    }
                }

                Row {
                    width: parent.width

                    Text {
                        width: parent.width * 0.55
                        text: root.tText
                        elide: Text.ElideRight
                        font.pixelSize: 11.5 * root.u
                        color: card.failed ? Colours.palette.m3error : Colours.palette.m3onSurface
                    }
                    Text {
                        width: parent.width * 0.45
                        horizontalAlignment: Text.AlignRight
                        text: root.tSub
                        elide: Text.ElideLeft
                        font.family: "JetBrainsMono Nerd Font Mono"
                        font.pixelSize: 10.5 * root.u
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
