pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    implicitHeight: col.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.large
    color: Colours.palette.m3surfaceContainerHigh

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledText {
            text: qsTr("Estado en reposo")
            font: Tokens.font.title.small
            color: Colours.palette.m3onSurface
        }
        StyledText {
            Layout.fillWidth: true
            text: qsTr("El color base cuando no hay ningún evento activo.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            Chip {
                Layout.fillWidth: true
                implicitHeight: 36
                label: qsTr("Seguir el tema")
                selected: RgbConfig.source === "theme"
                onClicked: RgbConfig.setSource("theme")
            }
            Chip {
                Layout.fillWidth: true
                implicitHeight: 36
                label: qsTr("Color fijo")
                selected: RgbConfig.source === "fixed"
                onClicked: RgbConfig.setSource("fixed")
            }
        }

        ColourPicker {
            id: picker

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: RgbConfig.source === "fixed"
            selectedColour: RgbConfig.fixedColour
            onPicked: hex => RgbConfig.setFixedColour(hex)
        }

        StyledText {
            Layout.fillWidth: true
            visible: RgbConfig.source === "fixed"
            text: qsTr("El color fijo se envía tal cual, sin realce de saturación.")
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
            wrapMode: Text.WordWrap
        }
    }
}
