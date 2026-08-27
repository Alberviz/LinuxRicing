pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Compact, non-interactive mock of the Akko 5075B used to show what a given
// battery lighting effect looks like. Purely decorative - it does not talk to
// the keyboard. `mode` picks the backlight animation, `sidestripMode` the
// lateral strip; both accept the effect keys stored in BatteryLightingConfig.
Item {
    id: root

    // theme | fill | breathing | stream | red_breathing | red_static | none
    property string mode: "fill"
    property string sidestripMode: "stream_battery"

    readonly property bool modeIsRed: mode === "red_breathing" || mode === "red_static"
    property color accent: Colours.palette.m3primary
    property color lowColour: Colours.palette.m3error

    readonly property int cols: 15
    readonly property int rows: 5

    // Master 0..1 phase driving every animation.
    property real phase: 0

    implicitHeight: 132

    NumberAnimation on phase {
        running: root.visible
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: (root.mode === "breathing" || root.mode === "red_breathing") ? 2600 : (root.mode === "stream" ? 2200 : 4200)
    }

    // Battery-level colour: red <=15 %, then a hue ramp up to green at 100 %.
    function batteryColour(level: real): color {
        if (level <= 0.15)
            return root.lowColour;
        const h = ((level - 0.15) / 0.85) * (120 / 360);
        return Qt.hsva(h, 0.85, 1, 1);
    }

    // Alpha for one backlight key given its column/row (row 0 = top).
    function keyAlpha(c: int, r: int): real {
        if (root.mode === "theme")
            return 1;
        if (root.mode === "none")
            return 0.12;
        if (root.mode === "red_static")
            return root.phase % 0.5 < 0.25 ? 1 : 0.18;
        if (root.mode === "breathing" || root.mode === "red_breathing") {
            const t = 0.5 - 0.5 * Math.cos(root.phase * 2 * Math.PI);
            return 0.22 + 0.78 * t;
        }
        if (root.mode === "stream") {
            const head = root.phase * (root.cols + 4) - 2;
            const d = Math.abs(c - head);
            return d < 3 ? (1 - d / 3) * 0.9 + 0.1 : 0.14;
        }
        // fill: a level rising from the bottom row to the top
        const fromBottom = (root.rows - 1 - r + 0.5) / root.rows;
        return Math.max(0.12, Math.min(1, (root.phase - fromBottom) * root.rows + 0.5));
    }

    function keyColour(c: int, r: int): color {
        if (root.modeIsRed)
            return root.lowColour;
        // Keep the demo in the amber->green range; a full-red keyboard would
        // read as an alarm, not "charging".
        if (root.mode === "fill")
            return root.batteryColour(0.25 + root.phase * 0.75);
        if (root.mode === "stream")
            return root.batteryColour(0.7);
        return root.accent;
    }

    Row {
        anchors.fill: parent
        spacing: 6

        // ---- Backlight key grid ----
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

        // ---- Side-strip ----
        StyledRect {
            id: sideStrip

            width: 12
            height: parent.height
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerLowest
            clip: true

            readonly property bool isLow: root.sidestripMode === "red_breathing" || root.sidestripMode === "red_static"
            readonly property color stripColour: isLow ? root.lowColour : ((root.sidestripMode === "breathing" || root.sidestripMode === "solid") ? root.accent : root.batteryColour(0.7))

            // Solid / breathing / low states
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: sideStrip.stripColour
                visible: root.sidestripMode !== "none" && root.sidestripMode !== "stream_battery"
                opacity: {
                    if (root.sidestripMode === "solid")
                        return 1;
                    if (root.sidestripMode === "red_static")
                        return root.phase % 0.5 < 0.25 ? 1 : 0.2;
                    // breathing / red_breathing
                    return 0.25 + 0.75 * (0.5 - 0.5 * Math.cos(root.phase * 2 * Math.PI));
                }
            }

            // Stream states: a travelling dot
            Rectangle {
                width: parent.width
                height: parent.height * 0.34
                radius: width / 2
                color: sideStrip.stripColour
                visible: root.sidestripMode === "stream_battery"
                y: (parent.height + height) * (1 - root.phase) - height
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                visible: root.sidestripMode === "none"
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
            }
        }
    }
}
