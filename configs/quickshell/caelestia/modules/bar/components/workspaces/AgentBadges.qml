pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

// Marcador de "sin ver" (badge con contador / cuña) dibujado FUERA del recorte
// del contenedor de workspaces, para que no se corte al sobresalir del pip.
Item {
    id: root

    required property Item workspacesItem

    Repeater {
        model: ScriptModel {
            // workspaces (int) con al menos un agente completado sin ver
            values: {
                const _deps = [Agents.completedAgents.length, Hypr.activeWsId];
                const out = [];
                for (const k of Object.keys(Agents.wsMap)) {
                    const n = parseInt(k, 10);
                    if (Agents.unseenCountForWs(n) > 0)
                        out.push(n);
                }
                return out;
            }
        }

        Item {
            id: slot

            required property int modelData

            readonly property Item pip: root.workspacesItem.pipFor(modelData)
            readonly property int cnt: Agents.unseenCountForWs(modelData)
            readonly property point corner: pip ? pip.mapToItem(root, pip.width, 0) : Qt.point(0, 0)

            visible: !!pip

            // Badge (contador) — por defecto
            Item {
                id: badge

                visible: Agents.unseenMarker !== "wedge"

                width: chip.width
                height: chip.height
                x: slot.corner.x - width / 2 + 3
                y: slot.corner.y - height / 2 + 2

                scale: slot.visible ? pulse : 0
                property real pulse: 1
                Behavior on scale {
                    Anim { easing: Tokens.anim.standardDecel }
                }
                SequentialAnimation on pulse {
                    running: badge.visible && slot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.14; duration: 850; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 850; easing.type: Easing.InOutSine }
                }

                // Resplandor
                Rectangle {
                    anchors.centerIn: chip
                    width: chip.width + 6
                    height: chip.height + 6
                    radius: height / 2
                    color: Colours.palette.m3primary
                    opacity: 0.35
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 0.9
                        blurMax: 14
                    }
                }

                Rectangle {
                    id: chip

                    implicitWidth: Math.max(14, label.implicitWidth + 8)
                    implicitHeight: 14
                    radius: height / 2
                    color: Colours.palette.m3primary
                    border.width: 1
                    border.color: Colours.palette.m3surfaceContainer

                    StyledText {
                        id: label

                        anchors.centerIn: parent
                        text: slot.cnt > 1 ? String(slot.cnt) : ""
                        color: Colours.palette.m3onPrimary
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            // Cuña lateral — alternativa (config unseenMarker = "wedge")
            MaterialIcon {
                visible: Agents.unseenMarker === "wedge"

                x: slot.corner.x - implicitWidth / 2
                y: (slot.pip?.mapToItem(root, 0, slot.pip.height / 2).y ?? 0) - implicitHeight / 2

                rotation: 180
                text: "play_arrow"
                color: Colours.palette.m3tertiary
                fontStyle: Tokens.font.icon.small

                scale: slot.visible ? 1 : 0
                Behavior on scale {
                    Anim { easing: Tokens.anim.standardDecel }
                }
            }
        }
    }
}
