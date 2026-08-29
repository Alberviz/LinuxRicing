pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    readonly property bool hasAgents: Agents.completedAgents.length > 0

    visible: height > 0
    opacity: hasAgents ? 1 : 0
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: hasAgents ? col.implicitHeight : 0

    Behavior on implicitHeight {
        Anim {
            easing: Tokens.anim.emphasizedDecel
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: ScriptModel {
                values: Agents.completedAgents
            }

            delegate: AgentPillItem {}
        }
    }

    component AgentPillItem: StyledRect {
        id: pill

        required property var modelData
        required property int index

        implicitWidth: Tokens.sizes.bar.innerWidth
        implicitHeight: Tokens.sizes.bar.innerWidth
        radius: Tokens.rounding.full
        color: Colours.palette.m3primaryContainer

        // Pulsing glow border
        border.width: 1
        border.color: Colours.palette.m3primary

        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: pill.visible

            NumberAnimation {
                to: 1.05
                duration: 900
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 1.0
                duration: 900
                easing.type: Easing.InOutSine
            }
        }

        Item {
            anchors.fill: parent

            MaterialIcon {
                id: botIcon

                anchors.centerIn: parent
                anchors.verticalCenterOffset: pill.modelData.num ? -2 : 0

                text: "smart_toy"
                color: Colours.palette.m3onPrimaryContainer
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                id: badge

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                visible: !!pill.modelData.num

                text: pill.modelData.num
                color: Colours.palette.m3primary
                font: Tokens.font.label.small
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    Agents.focus(pill.modelData.address);
                } else {
                    Agents.dismiss(pill.modelData.id);
                }
            }
        }

        // Animated entry and removal
        ListView.onAdd: SequentialAnimation {
            PropertyAction { target: pill; property: "scale"; value: 0 }
            NumberAnimation { target: pill; property: "scale"; to: 1; duration: Tokens.anim.durations.normal; easing.type: Easing.OutBack }
        }
    }
}
