import QtQuick
import Caelestia.Config
import qs.components
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
    property real r: 30 * u
    property real vis: 0
    property real dim: 0
    property real pulse: 0
    property real spinPhase: 0
    property real pullPhase: 0
    property real cx: edge === "right" ? winW + 2 * r : winW / 2
    property real cy: edge === "right" ? winH / 2 : -2 * r
    property bool armed: false
    property string phase: "idle"      // idle | sending | ok | error | unavail
    property string status: ""

    readonly property bool hot: armed || phase !== "idle"
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
        }
    }

    ShaderEffect {
        x: root.cx - root.half
        y: root.cy - root.half
        width: root.half * 2
        height: root.half * 2

        property vector2d size: Qt.vector2d(width, height)
        property vector2d outward: root.edge === "right" ? Qt.vector2d(1, 0) : Qt.vector2d(0, -1)
        property color tint: Qt.rgba(Colours.palette.m3primary.r, Colours.palette.m3primary.g, Colours.palette.m3primary.b, 0.18)
        property real rad: root.r
        property real upx: root.u
        property real en: root.e
        property real vis: root.vis
        property real armed: root.armed ? 1 : 0
        property real pulse: root.pulse
        property real spin: root.spinPhase
        property real pull: root.pullPhase

        fragmentShader: Qt.resolvedUrl("shaders/portal.frag.qsb")
    }

    // Etiqueta HUD
    Column {
        id: hud

        readonly property real fs: 11 * root.u
        x: root.edge === "right" ? root.winW - root.r * 1.6 - width : root.cx + root.r * 4.6
        y: root.edge === "right" ? root.cy - root.r * 2.3 - height : root.r * 0.6
        spacing: fs * 0.25
        opacity: root.vis > 0.05 && root.e > 0.35 ? Math.min(1, (root.e - 0.35) / 0.3) * (1 - 0.6 * root.dim) : 0

        Text {
            x: root.edge === "right" ? hud.width - width : 0
            text: root.kicker
            font.family: "JetBrainsMono Nerd Font Mono"
            font.pixelSize: hud.fs * 0.8
            font.weight: Font.Medium
            font.letterSpacing: hud.fs * 0.8 * 0.22
            color: Colours.palette.m3tertiary
        }
        Text {
            x: root.edge === "right" ? hud.width - width : 0
            text: root.title
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
        Item {
            x: root.edge === "right" ? hud.width - width : 0
            width: ctaText.implicitWidth + hud.fs * 1.6
            height: ctaText.implicitHeight + hud.fs + 6

            Rectangle {
                id: pill

                width: parent.width
                height: parent.height - 6
                y: root.hot ? 6 : 10
                radius: height / 2
                color: root.phase === "error" ? Colours.palette.m3error : root.warm
                opacity: root.hot ? 1 : 0

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
                text: root.phase === "idle" ? root.cta : root.status
                font.family: "JetBrainsMono Nerd Font Mono"
                font.pixelSize: hud.fs * 0.85
                font.weight: Font.Medium
                color: root.phase === "error" ? Colours.palette.m3onError : "#05060a"
            }
        }
    }
}
