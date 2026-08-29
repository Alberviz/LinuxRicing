pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property int index
    required property int activeWsId
    required property var occupied
    required property int groupOffset

    readonly property bool isWorkspace: true // Flag for finding workspace children
    // Unanimated prop for others to use as reference
    readonly property int size: implicitHeight + (hasWindows ? Tokens.padding.extraSmall : 0)

    readonly property int ws: groupOffset + index + 1
    readonly property bool isOccupied: occupied[ws] ?? false
    readonly property bool hasWindows: isOccupied && Config.bar.workspaces.showWindows
    readonly property bool hasAgent: Agents.agentsForWs(ws).length > 0
    readonly property bool agentUnseen: Agents.hasUnseenForWs(ws)

    Layout.alignment: Qt.AlignHCenter
    Layout.preferredHeight: size

    spacing: 0

    StyledText {
        id: indicator

        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
        Layout.preferredHeight: Tokens.sizes.bar.innerWidth - Tokens.padding.small

        animate: true
        text: {
            const ws = Hypr.workspaces.values.find(w => w.id === root.ws);
            const wsName = !ws || ws.name == root.ws ? root.ws : ws.name[0];
            let displayName = wsName.toString();
            if (Config.bar.workspaces.capitalisation.toLowerCase() === "upper") {
                displayName = displayName.toUpperCase();
            } else if (Config.bar.workspaces.capitalisation.toLowerCase() === "lower") {
                displayName = displayName.toLowerCase();
            }
            const label = Config.bar.workspaces.label || displayName;
            const occupiedLabel = Config.bar.workspaces.occupiedLabel || label;
            const activeLabel = Config.bar.workspaces.activeLabel || (root.isOccupied ? occupiedLabel : label);
            return root.activeWsId === root.ws ? activeLabel : root.isOccupied ? occupiedLabel : label;
        }
        color: root.hasAgent
            ? Colours.palette.m3onPrimaryContainer
            : (Config.bar.workspaces.occupiedBg || root.isOccupied || root.activeWsId === root.ws
               ? Colours.palette.m3onSurface
               : Colours.layer(Colours.palette.m3outlineVariant, 2))
        verticalAlignment: Qt.AlignVCenter
        font.family: Tokens.font.workspaces

        // Marcador de "sin ver": badge con contador (por defecto) o cuña lateral.
        Item {
            id: marker

            anchors.centerIn: parent
            width: Tokens.sizes.bar.innerWidth - Tokens.padding.small
            height: parent.height
            opacity: root.agentUnseen ? 1 : 0
            Behavior on opacity {
                Anim { easing: Tokens.anim.standardDecel }
            }

            readonly property int cnt: Agents.unseenCountForWs(root.ws)

            Rectangle {
                id: badge

                visible: Agents.unseenMarker !== "wedge"
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -3
                anchors.topMargin: -1

                implicitWidth: Math.max(11, badgeTxt.implicitWidth + 5)
                height: 11
                radius: height / 2
                color: Colours.palette.m3primary
                border.width: 1.5
                border.color: Colours.palette.m3surface

                SequentialAnimation on scale {
                    running: marker.opacity > 0 && badge.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.18; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                }

                StyledText {
                    id: badgeTxt

                    anchors.centerIn: parent
                    text: marker.cnt > 1 ? String(marker.cnt) : ""
                    color: Colours.palette.m3onPrimary
                    font.pixelSize: 8
                    font.bold: true
                }
            }

            MaterialIcon {
                visible: Agents.unseenMarker === "wedge"
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.left
                anchors.rightMargin: 1
                rotation: 180
                text: "play_arrow"
                color: Colours.palette.m3tertiary
                fontStyle: Tokens.font.icon.small
            }
        }
    }

    Loader {
        id: windows

        asynchronous: true

        Layout.alignment: Qt.AlignHCenter
        Layout.fillHeight: true
        Layout.topMargin: -Tokens.sizes.bar.innerWidth / 10

        visible: active
        active: root.hasWindows

        sourceComponent: Column {
            spacing: 0

            add: Transition {
                Anim {
                    properties: "scale"
                    from: 0
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
            }

            move: Transition {
                Anim {
                    properties: "scale"
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    properties: "x,y"
                }
            }

            Repeater {
                model: ScriptModel {
                    values: {
                        const ws = root.ws;
                        const windows = Hypr.toplevels.values.filter(c => c.workspace?.id === ws);
                        const maxIcons = root.Config.bar.workspaces.maxWindowIcons;
                        return maxIcons > 0 ? windows.slice(0, maxIcons) : windows;
                    }
                }

                MaterialIcon {
                    required property var modelData

                    grade: 0
                    text: Icons.getAppCategoryIcon(modelData.lastIpcObject.class, "terminal")
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }

    Behavior on Layout.preferredHeight {
        Anim {}
    }
}
