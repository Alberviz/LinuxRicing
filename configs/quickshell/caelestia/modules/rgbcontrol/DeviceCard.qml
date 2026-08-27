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
    default property alias content: body.data

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.large
    color: Colours.palette.m3surfaceContainerHigh

    Behavior on implicitHeight {
        CAnim {}
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Header
        Item {
            Layout.fillWidth: true
            implicitHeight: 36

            StateLayer {
                radius: Tokens.rounding.small
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
                    text: root.expanded ? "expand_less" : "expand_more"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }
        }

        // Expandable body
        ColumnLayout {
            id: body

            Layout.fillWidth: true
            Layout.topMargin: root.expanded ? 0 : -layout.spacing
            visible: root.expanded
            spacing: Tokens.spacing.medium
        }
    }
}
