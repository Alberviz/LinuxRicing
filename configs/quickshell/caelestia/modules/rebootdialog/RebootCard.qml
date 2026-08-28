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
    required property string shortcutKey
    property color iconColor: Colours.palette.m3primary
    property color iconBgColor: Colours.palette.m3primaryContainer

    signal clicked

    implicitWidth: 420
    implicitHeight: 70
    radius: Tokens.rounding.large
    color: stateLayer.containsMouse || activeFocus ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainerHigh
    border.width: 1
    border.color: stateLayer.containsMouse || activeFocus ? Colours.palette.m3outline : Colours.palette.m3outlineVariant

    scale: stateLayer.pressed ? 0.98 : (stateLayer.containsMouse || activeFocus) ? 1.01 : 1.0

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
        onClicked: root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        // Icon badge
        StyledRect {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: Tokens.rounding.medium
            color: root.iconBgColor

            MaterialIcon {
                anchors.centerIn: parent
                text: root.icon
                fontStyle: Tokens.font.icon.medium
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

        // Shortcut pill
        StyledRect {
            Layout.preferredHeight: 28
            Layout.preferredWidth: 32
            radius: Tokens.rounding.small
            color: stateLayer.containsMouse || root.activeFocus ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerLowest
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            StyledText {
                anchors.centerIn: parent
                text: root.shortcutKey
                font: Tokens.font.label.medium
                color: stateLayer.containsMouse || root.activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
