pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    // Selected colour as a 6-digit hex string, no leading '#'.
    property string selectedColour: "d8bde7"
    signal picked(string hex)

    function hex6(c: color): string {
        return c.toString().replace(/^#/, "").slice(0, 6).toLowerCase();
    }

    readonly property var themeSwatches: [
        Colours.palette.m3primary,
        Colours.palette.m3secondary,
        Colours.palette.m3tertiary,
        Colours.palette.m3primaryContainer,
        Colours.palette.m3error,
        Colours.palette.m3surfaceTint
    ]
    readonly property var fixedSwatches: ["#ffffff", "#ff3b30", "#34c759", "#0a84ff", "#ff9800", "#bf5af2", "#00e5c8"]

    spacing: Tokens.spacing.small

    component SwatchRow: Flow {
        id: rowRoot
        required property var swatches
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: rowRoot.swatches

            StyledRect {
                id: sw
                required property color modelData
                readonly property string hex: root.hex6(modelData)
                readonly property bool active: root.selectedColour.toLowerCase() === hex

                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: modelData

                StyledRect {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: sw.active ? 2 : 0
                    border.color: Colours.palette.m3primary
                }

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: {
                        root.selectedColour = sw.hex;
                        root.picked(sw.hex);
                    }
                }
            }
        }
    }

    StyledText {
        text: qsTr("Del tema")
        font: Tokens.font.label.small
        color: Colours.palette.m3onSurfaceVariant
    }
    SwatchRow {
        swatches: root.themeSwatches
    }

    StyledText {
        text: qsTr("Fijos")
        font: Tokens.font.label.small
        color: Colours.palette.m3onSurfaceVariant
        Layout.topMargin: Tokens.spacing.small
    }
    SwatchRow {
        swatches: root.fixedSwatches
    }

    StyledTextField {
        id: hexField

        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        type: StyledTextField.Filled
        leadingIcon: "tag"
        placeholderText: qsTr("Color hex")
        text: root.selectedColour.toUpperCase()
        validate: /^#?[0-9a-fA-F]{6}$/
        errorText: qsTr("Formato: RRGGBB")
        inputMethodHints: Qt.ImhNoAutoUppercase

        onEditingFinished: {
            if (valid && text) {
                const h = text.replace(/^#/, "").toLowerCase();
                root.selectedColour = h;
                root.picked(h);
            }
        }
    }
}
