pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Column {
    id: root

    required property int ws
    readonly property var agents: Agents.agentsForWs(ws)
    readonly property var running: Agents.runningForWs(ws)

    spacing: Tokens.spacing.small

    function ago(t: var): string {
        if (!t || isNaN(new Date(t).getTime())) return qsTr("hace un momento");
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
            values: root.running
        }

        StyledRect {
            id: runCard

            required property var modelData

            implicitWidth: Math.max(runCol.implicitWidth + Tokens.padding.large * 2, 200)
            implicitHeight: runCol.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: runCol

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.extraSmall

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "sync"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small

                        RotationAnimation on rotation {
                            running: true
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1600
                        }
                    }

                    StyledText {
                        text: runCard.modelData.name
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.label.large
                    }
                }

                StyledText {
                    Layout.maximumWidth: 280
                    text: runCard.modelData.task
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                StyledText {
                    Layout.maximumWidth: 280
                    text: {
                        const parts = [];
                        if (runCard.modelData.dir)
                            parts.push(runCard.modelData.dir);
                        parts.push(qsTr("ejecutando %1").arg(root.ago(runCard.modelData.startTime ?? runCard.modelData.time)));
                        return parts.join(" • ");
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideLeft
                }

                StyledRect {
                    Layout.topMargin: Tokens.spacing.extraSmall
                    implicitWidth: runStateRow.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: runStateRow.implicitHeight + Tokens.padding.extraSmall * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primaryContainer

                    RowLayout {
                        id: runStateRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "pending"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: qsTr("En curso")
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }
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
                    Layout.maximumWidth: 280
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
                    elide: Text.ElideLeft
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
