pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    required property var rule

    property bool expanded: true

    readonly property string sourceIcon: {
        const s = BatteryLightingConfig.sources.find(src => src.key === root.rule.source);
        return s ? s.icon : "devices";
    }

    readonly property string headerTitle: {
        let t = `${BatteryLightingConfig.sourceLabel(root.rule.source)} · ${BatteryLightingConfig.triggerLabel(root.rule.trigger)}`;
        if (root.rule.trigger === "low") {
            t += ` ≤ ${root.rule.threshold ?? 20} %`;
        } else if (root.rule.trigger === "critical") {
            t += ` ≤ ${BatteryLightingConfig.criticalThreshold} %`;
        }
        return t;
    }

    readonly property string actionsSummary: {
        const acts = root.rule.actions ?? [];
        if (acts.length === 0)
            return qsTr("Sin acciones asignadas");
        return acts.map(a => {
            const tgt = BatteryLightingConfig.targetLabel(a.target);
            const eff = BatteryLightingConfig.effectLabels[a.effect] ?? a.effect;
            return `${tgt} → ${eff}`;
        }).join(" · ");
    }

    readonly property real headerBand: Tokens.padding.large * 2 + header.implicitHeight

    Layout.fillWidth: true
    implicitHeight: headerBand + (root.expanded ? Tokens.spacing.medium * 2 + 1 + bodyCol.implicitHeight : 0)
    radius: Tokens.rounding.large
    color: Colours.palette.m3surfaceContainerHigh
    clip: true

    Behavior on implicitHeight {
        Anim {}
    }

    // Header click area for collapsing
    StateLayer {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.headerBand

        topLeftRadius: root.radius
        topRightRadius: root.radius
        bottomLeftRadius: root.expanded ? 0 : root.radius
        bottomRightRadius: root.expanded ? 0 : root.radius

        onClicked: root.expanded = !root.expanded

        Behavior on bottomLeftRadius {
            Anim {}
        }
        Behavior on bottomRightRadius {
            Anim {}
        }
    }

    // ---- Header content ----
    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        implicitHeight: 38
        height: 38

        RowLayout {
            anchors.fill: parent
            spacing: Tokens.spacing.small

            StyledRect {
                implicitWidth: 36
                implicitHeight: 36
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.7)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.sourceIcon
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.small
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.headerTitle
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.actionsSummary
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            // Remove rule button
            StyledRect {
                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.6)

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: BatteryLightingConfig.removeRule(root.rule.id)
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "delete"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3error
                }
            }

            // Collapse/expand chevron
            MaterialIcon {
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

    // ---- Divider between header and body (only while expanded) ----
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.topMargin: Tokens.spacing.medium
        height: 1
        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
        opacity: root.expanded ? 1 : 0

        Behavior on opacity {
            Anim {}
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
        anchors.topMargin: root.expanded ? Tokens.spacing.medium * 2 + 1 : 0
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

            // Low battery threshold slider (only if trigger is low)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall
                visible: root.rule.trigger === "low"

                StyledText {
                    text: qsTr("Umbral de aviso: ≤ %1 %").arg(root.rule.threshold ?? 20)
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledSlider {
                    Layout.fillWidth: true
                    implicitHeight: 14
                    value: ((root.rule.threshold ?? 20) - 5) / 35
                    onInteraction: v => BatteryLightingConfig.setRuleThreshold(root.rule.id, Math.min(40, Math.max(5, Math.round((5 + v * 35) / 5) * 5)))
                }
            }

            // Actions list
            Repeater {
                model: root.rule.actions

                BatteryActionRow {
                    ruleId: root.rule.id
                }
            }

            // Empty state placeholder
            StyledText {
                Layout.fillWidth: true
                visible: (!root.rule.actions || root.rule.actions.length === 0)
                text: qsTr("No hay acciones configuradas para esta regla.")
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
                horizontalAlignment: Text.AlignHCenter
            }

            // Bottom buttons: Add Action & Probe
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                // Add action button
                StyledRect {
                    Layout.alignment: Qt.AlignLeft
                    implicitWidth: addRow.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: 1
                    border.color: Colours.palette.m3outline

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: BatteryLightingConfig.addAction(root.rule.id, "mchose_base", null, "red_breathing")
                    }

                    RowLayout {
                        id: addRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "add"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: qsTr("Añadir acción")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onSurface
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Probe button
                StyledRect {
                    Layout.alignment: Qt.AlignRight
                    implicitWidth: probeRow.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: 1
                    border.color: Colours.palette.m3primary

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: BatteryLightingConfig.probe(root.rule.id)
                    }

                    RowLayout {
                        id: probeRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "bolt"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: qsTr("Probar")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3primary
                        }
                    }
                }
            }
        }
    }
}
