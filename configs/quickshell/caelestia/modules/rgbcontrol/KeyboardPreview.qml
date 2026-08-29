pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Maqueta compacta y no interactiva del Akko 5075B para previsualizar un efecto.
// Puramente decorativa: no habla con el teclado. Toma los objetos de efecto
// {animation, colour, speed, direction} de las dos zonas.
Item {
    id: root

    property var keysEffect: DeviceEffects.defaultEffect
    property var sidestripEffect: DeviceEffects.defaultEffect

    readonly property var _k: DeviceEffects.normalize(root.keysEffect)
    readonly property var _s: DeviceEffects.normalize(root.sidestripEffect)

    property color accent: Colours.palette.m3primary

    readonly property int cols: 15
    readonly property int rows: 5

    property real phase: 0
    implicitHeight: 132

    NumberAnimation on phase {
        running: root.visible
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: {
            const sp = root._k.speed;
            return 4600 - sp * 700;   // 1 -> 3900ms, 5 -> 1100ms
        }
    }

    function _srcColour(eff: var, lvl: real): color {
        if (eff.colour.source === "fixed")
            return "#" + eff.colour.hex;
        if (eff.colour.source === "battery") {
            if (lvl <= 0.15)
                return Colours.palette.m3error;
            const h = ((lvl - 0.15) / 0.85) * (120 / 360);
            return Qt.hsva(h, 0.85, 1, 1);
        }
        return root.accent;
    }

    function keyAlpha(c: int, r: int): real {
        const a = root._k.animation;
        if (a === "off")
            return 0.1;
        if (a === "solid" || a === "press_action" || a === "ripple")
            return 1;
        if (a === "breathing")
            return 0.22 + 0.78 * (0.5 - 0.5 * Math.cos(root.phase * 2 * Math.PI));
        if (a === "wave" || a === "line_wave") {
            const dir = root._k.direction;
            const vertical = dir === "down" || dir === "up";
            const rev = dir === "left" || dir === "up";
            const span = vertical ? root.rows : root.cols;
            let p = rev ? (1 - root.phase) : root.phase;
            const pos = vertical ? r : c;
            const head = p * (span + 4) - 2;
            const d = Math.abs(pos - head);
            return d < 2.5 ? (1 - d / 2.5) * 0.85 + 0.15 : 0.14;
        }
        if (a === "sine_wave" || a === "kaleidoscope" || a === "circle_wave") {
            const dx = c - (root.cols - 1) / 2;
            const dy = (r - (root.rows - 1) / 2) * 2;
            const dist = Math.sqrt(dx * dx + dy * dy);
            return 0.15 + 0.8 * (0.5 + 0.5 * Math.sin(dist * 0.6 - root.phase * 6.28));
        }
        if (a === "snake") {
            const idx = r % 2 === 0 ? c : (root.cols - 1 - c);
            const lin = (r * root.cols + idx) / (root.cols * root.rows);
            const d = Math.abs(((lin - root.phase % 1) + 1) % 1);
            return d < 0.12 ? 1 : 0.14;
        }
        // neon / meteor / laser / etc.: parpadeo suave
        return 0.3 + 0.6 * (0.5 + 0.5 * Math.sin(root.phase * 6.28 + (c + r) * 0.5));
    }

    function keyColour(c: int, r: int): color {
        if (root._k.animation === "neon")
            return Qt.hsva((root.phase + (c + r) / 40) % 1, 0.8, 1, 1);
        return root._srcColour(root._k, 0.2 + root.phase * 0.7);
    }

    Row {
        anchors.fill: parent
        spacing: 6

        StyledRect {
            width: parent.width - sideStrip.width - parent.spacing
            height: parent.height
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.6)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

            Grid {
                anchors.centerIn: parent
                columns: root.cols
                rowSpacing: 4
                columnSpacing: 4

                Repeater {
                    model: root.cols * root.rows

                    Rectangle {
                        required property int index
                        readonly property int col: index % root.cols
                        readonly property int row: Math.floor(index / root.cols)

                        width: 12
                        height: 12
                        radius: 3
                        color: Colours.palette.m3surfaceContainerHighest
                        antialiasing: true

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: root.keyColour(parent.col, parent.row)
                            opacity: root.keyAlpha(parent.col, parent.row)
                        }
                    }
                }
            }
        }

        StyledRect {
            id: sideStrip

            width: 12
            height: parent.height
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerLowest
            clip: true

            readonly property color stripColour: root._s.animation === "neon"
                ? Qt.hsva(root.phase, 0.8, 1, 1)
                : root._srcColour(root._s, 0.7)

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: sideStrip.stripColour
                visible: root._s.animation !== "off" && root._s.animation !== "snake" && root._s.animation !== "wave"
                opacity: root._s.animation === "solid" ? 1
                    : (0.25 + 0.75 * (0.5 - 0.5 * Math.cos(root.phase * 2 * Math.PI)))
            }

            Rectangle {
                width: parent.width
                height: parent.height * 0.34
                radius: width / 2
                color: sideStrip.stripColour
                visible: root._s.animation === "snake" || root._s.animation === "wave"
                y: (parent.height + height) * (1 - root.phase) - height
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                visible: root._s.animation === "off"
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
            }
        }
    }
}
