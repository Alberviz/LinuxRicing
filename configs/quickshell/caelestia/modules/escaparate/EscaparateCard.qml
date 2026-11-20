pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property string icon
    required property string title
    required property string description
    property string shortcutKey: ""
    property color iconColor: Colours.palette.m3primary
    property color iconBgColor: Qt.alpha(Colours.palette.m3primary, 0.18)

    property bool current: false
    property bool selected: false

    signal clicked

    implicitWidth: 460
    implicitHeight: 74
    radius: Tokens.rounding.large
    color: stateLayer.containsMouse || root.selected ? Colours.palette.m3surfaceContainerHighest : root.current ? Qt.alpha(root.iconColor, 0.12) : Colours.palette.m3surfaceContainerHigh
    border.width: stateLayer.containsMouse || root.selected || root.current ? 1.5 : 1
    border.color: stateLayer.containsMouse || root.selected || root.current ? root.iconColor : Colours.palette.m3outlineVariant

    opacity: enabled ? 1 : 0.45
    scale: stateLayer.pressed ? 0.98 : (stateLayer.containsMouse || root.selected) ? 1.015 : 1.0

    Behavior on scale {
        Anim {
            duration: 150
        }
    }

    Behavior on color {
        CAnim {
            duration: 150
        }
    }

    Behavior on border.color {
        CAnim {
            duration: 150
        }
    }

    StateLayer {
        id: stateLayer

        anchors.fill: parent
        radius: root.radius
        disabled: !root.enabled
        onClicked: root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        // Icon badge with distinct vibrant container and crisp border
        StyledRect {
            Layout.preferredWidth: 46
            Layout.preferredHeight: 46
            radius: Tokens.rounding.medium
            color: root.iconBgColor
            border.width: 1.5
            border.color: root.iconColor

            MaterialIcon {
                anchors.centerIn: parent
                text: root.icon
                fontStyle: Tokens.font.icon.builders.medium.scale(1.2).weight(Font.Bold).build()
                color: root.iconColor
            }
        }

        // Texts
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.description
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }

        // Pill 'Activo'
        StyledRect {
            visible: root.current
            Layout.preferredHeight: 24
            Layout.preferredWidth: activoText.implicitWidth + 16
            radius: Tokens.rounding.full
            color: Qt.alpha(root.iconColor, 0.2)
            border.width: 1
            border.color: root.iconColor

            StyledText {
                id: activoText
                anchors.centerIn: parent
                text: qsTr("Activo")
                font: Tokens.font.label.small
                color: root.iconColor
            }
        }

        // Shortcut pill (if provided)
        StyledRect {
            visible: root.shortcutKey !== ""
            Layout.preferredHeight: 30
            Layout.preferredWidth: 32
            radius: Tokens.rounding.small
            color: stateLayer.containsMouse || root.selected ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerLowest
            border.width: 1
            border.color: stateLayer.containsMouse || root.selected ? Colours.palette.m3outline : Colours.palette.m3outlineVariant

            StyledText {
                anchors.centerIn: parent
                text: root.shortcutKey
                font: Tokens.font.label.medium
                color: stateLayer.containsMouse || root.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            }
        }
    }
}
