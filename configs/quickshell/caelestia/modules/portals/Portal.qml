import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Un portal-agujero negro pegado a un borde (estilo Gargantua del escritorio, sin shaders:
// solo rectángulos redondeados — disco de acreción inclinado, horizonte y anillo de fotones).
// Latente y pequeño mientras se arrastra; crece según se acerca el cursor (t) y se abre del
// todo (hot). Nada se anima fuera de los cambios de estado: no hay bucles.
Item {
    id: root

    required property string edge      // "right" | "top"
    required property real winW
    required property real winH
    property real t: 0                 // 0..1, cercanía del cursor
    property bool hot: false           // cursor dentro de la banda
    property string phase: "idle"      // idle | sending | ok | error | unavail
    property string label: ""
    property string hotLabel: "Suelta para enviar…"
    property string status: ""

    readonly property real r: 56
    readonly property bool open: hot || phase !== "idle"
    property real k: open ? 1.35 : 0.5 + 0.55 * t
    readonly property real inset: r * k * (open ? 1.25 : 0.55 + 0.5 * t)
    readonly property real cx: edge === "right" ? winW - inset : winW / 2
    readonly property real cy: edge === "right" ? winH / 2 : inset
    readonly property color ring: phase === "error" ? Colours.palette.m3error : Colours.palette.m3tertiary

    Behavior on k {
        Anim {
            type: Anim.FastSpatial
        }
    }

    opacity: open ? 1 : 0.55 + 0.45 * t
    Behavior on opacity {
        Anim {
            type: Anim.FastEffects
        }
    }

    Item {
        id: bh

        x: root.cx
        y: root.cy
        scale: root.k

        // Disco de acreción (inclinado como el del fondo, -0.30 rad)
        Rectangle {
            width: root.r * 4.4
            height: root.r * 0.78
            x: -width / 2
            y: -height / 2
            radius: height / 2
            rotation: -17
            color: Qt.alpha(Colours.palette.m3primaryContainer, 0.6)
        }
        Rectangle {
            width: root.r * 3.4
            height: root.r * 0.34
            x: -width / 2
            y: -height / 2
            radius: height / 2
            rotation: -17
            color: Qt.alpha(Colours.palette.m3primary, 0.9)
        }
        // Horizonte de sucesos + anillo de fotones
        Rectangle {
            width: root.r * 2
            height: width
            x: -width / 2
            y: -height / 2
            radius: width / 2
            color: Qt.darker(Colours.palette.m3surface, 3)
            border.width: 2.5
            border.color: root.ring
        }
        // Cara delantera del disco, cruzando por delante de la sombra
        Rectangle {
            width: root.r * 3.4
            height: root.r * 0.2
            x: -width / 2
            y: root.r * 0.06
            radius: height / 2
            rotation: -17
            color: Qt.alpha(Colours.palette.m3primary, 0.75)
        }
    }

    // Etiqueta (fuera de la escala del agujero)
    StyledRect {
        id: tag

        readonly property real gap: root.r * root.k + 14
        x: root.edge === "right" ? root.cx - gap - width : root.cx - width / 2
        y: root.edge === "right" ? root.cy - height / 2 : root.cy + gap
        implicitWidth: lbl.implicitWidth + Tokens.padding.large * 2
        implicitHeight: lbl.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.92)
        opacity: root.open || root.t > 0.15 ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        StyledText {
            id: lbl

            anchors.centerIn: parent
            text: root.phase === "idle" ? (root.hot ? root.hotLabel : root.label) : root.status
            color: root.phase === "error" ? Colours.palette.m3error : Colours.palette.m3onSurface
            font: Tokens.font.body.small
        }
    }
}
