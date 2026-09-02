pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Services
import Caelestia.Components
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services

StyledRect {
    id: taskItem

    required property var modelData
    // Se propaga desde la ventana: fondos translúcidos vs. sólidos.
    property bool transparentWidgets: true
    signal toggled()

    readonly property bool completed: modelData?.completed ?? false
    readonly property string titleText: modelData?.title ?? ""
    readonly property string dueText: modelData?.due ?? ""

    implicitHeight: rowContent.implicitHeight + Tokens.padding.medium * 2
    radius: Tokens.rounding.medium
    color: completed ? "transparent" : (taskItem.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

    Behavior on color {
        CAnim {}
    }

    StateLayer {
        radius: Tokens.rounding.medium
        onClicked: taskItem.toggled()
    }

    RowLayout {
        id: rowContent

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: taskItem.completed ? "check_box" : "check_box_outline_blank"
            fontStyle: Tokens.font.icon.small
            color: taskItem.completed ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

            Behavior on color {
                CAnim {}
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: taskItem.titleText
            color: taskItem.completed ? Colours.palette.m3outline : Colours.palette.m3onSurface
            font: Tokens.font.body.medium
            elide: Text.ElideRight
            opacity: taskItem.completed ? 0.5 : 1.0

            Behavior on opacity {
                Anim {}
            }
            Behavior on color {
                CAnim {}
            }
        }

        StyledRect {
            visible: taskItem.dueText !== ""
            radius: Tokens.rounding.full
            color: taskItem.completed ? Colours.palette.m3surfaceContainerLowest : Colours.palette.m3primaryContainer
            implicitWidth: dueLabel.implicitWidth + Tokens.padding.small * 2
            implicitHeight: dueLabel.implicitHeight + Tokens.padding.extraSmall
            opacity: taskItem.completed ? 0.5 : 1.0

            StyledText {
                id: dueLabel
                anchors.centerIn: parent
                text: taskItem.dueText
                color: taskItem.completed ? Colours.palette.m3outline : Colours.palette.m3onPrimaryContainer
                font: Tokens.font.label.small
            }
        }
    }
}
