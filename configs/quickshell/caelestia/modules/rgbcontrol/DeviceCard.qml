pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    property string icon
    property string name
    property string subtitle
    property string deviceKey          // key in RgbConfig.devices; "" hides the switch
    property bool expandable: true
    property bool expanded
    default property alias content: bodyCol.data

    Layout.fillWidth: true
    implicitHeight: Tokens.padding.large * 2 + header.implicitHeight + (root.expanded ? Tokens.spacing.medium + bodyCol.implicitHeight : 0)
    radius: Tokens.rounding.large
    color: Colours.palette.m3surfaceContainerHigh
    clip: true

    Behavior on implicitHeight {
        Anim {}
    }

    // ---- Header (click toggles expansion) ----
    // A bare Item does not adopt implicitHeight as height, which left the
    // StateLayer below sized 0px tall and swallowing no clicks. Give the
    // header a real height and let the ripple bleed into the card padding.
    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        implicitHeight: 36
        height: 36

        StateLayer {
            anchors.fill: parent
            radius: Tokens.rounding.normal
            disabled: !root.expandable
            onClicked: root.expanded = !root.expanded
        }

        RowLayout {
            anchors.fill: parent
            spacing: Tokens.spacing.small

            StyledRect {
                implicitWidth: 34
                implicitHeight: 34
                radius: Tokens.rounding.normal
                color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.7)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.icon
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.small
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: root.name
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }
                StyledText {
                    visible: !!root.subtitle
                    text: root.subtitle
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            StyledSwitch {
                visible: !!root.deviceKey
                checked: RgbConfig.devices[root.deviceKey] ?? true
                onToggled: RgbConfig.setDevice(root.deviceKey, checked)
            }

            MaterialIcon {
                visible: root.expandable
                text: "expand_more"
                rotation: root.expanded ? 180 : 0
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small

                Behavior on rotation {
                    Anim {}
                }
            }
        }
    }

    // ---- Body (animated collapse) ----
    Item {
        id: bodyClip

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.topMargin: root.expanded ? Tokens.spacing.medium : 0
        clip: true
        height: root.expanded ? bodyCol.implicitHeight : 0

        Behavior on height {
            Anim {}
        }

        ColumnLayout {
            id: bodyCol

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Tokens.spacing.medium
            opacity: root.expanded ? 1 : 0

            Behavior on opacity {
                Anim {}
            }
        }
    }
}
