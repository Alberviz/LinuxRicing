pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.utils

Column {
    id: root

    required property int ws
    readonly property var agents: Agents.agentsForWs(ws)

    spacing: Tokens.spacing.small

    function ago(t: var): string {
        const m = Math.floor((Date.now() - new Date(t).getTime()) / 60000);
        if (m < 1)
            return qsTr("ahora mismo");
        if (m < 60)
            return qsTr("hace %1 min").arg(m);
        const h = Math.floor(m / 60);
        return qsTr("hace %1 h").arg(h);
    }

    Repeater {
        model: ScriptModel {
            values: root.agents
        }

        StyledRect {
            id: card

            required property var modelData

            implicitWidth: Math.max(col.implicitWidth + Tokens.padding.large * 2, 200)
            implicitHeight: col.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: col

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.extraSmall

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "smart_toy"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        text: card.modelData.name
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.label.large
                    }
                }

                StyledText {
                    Layout.maximumWidth: 280
                    text: card.modelData.task
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                StyledText {
                    text: {
                        const parts = [];
                        if (card.modelData.dir)
                            parts.push(card.modelData.dir);
                        parts.push(root.ago(card.modelData.time));
                        if (card.modelData.duration)
                            parts.push(qsTr("en %1").arg(card.modelData.duration));
                        return parts.join(" • ");
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }

                StyledRect {
                    Layout.topMargin: Tokens.spacing.extraSmall
                    implicitWidth: stateRow.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: stateRow.implicitHeight + Tokens.padding.extraSmall * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primaryContainer

                    RowLayout {
                        id: stateRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "check_circle"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: card.modelData.status
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.label.small
                        }
                    }
                }

                StyledText {
                    Layout.topMargin: Tokens.spacing.extraSmall
                    text: qsTr("Clic en el workspace para saltar ahí")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.small
                }
            }
        }
    }
}
