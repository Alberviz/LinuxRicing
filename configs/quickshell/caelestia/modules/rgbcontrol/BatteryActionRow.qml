pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    required property string ruleId
    required property int index
    required property var modelData
    property var action: modelData

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Tokens.padding.medium * 2
    radius: Tokens.rounding.medium
    color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.6)
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

    function previewMode(zone: var, effect: string): string {
        if (zone === "sidestrip")
            return "none";
        switch (effect) {
        case "theme":
            return "theme";
        case "wave":
        case "wave_battery":
            return "wave";
        case "breathing_battery":
        case "breathing":
            return "breathing";
        case "red_breathing":
            return "red_breathing";
        case "red_static":
            return "red_static";
        case "none":
            return "none";
        default:
            return "breathing";
        }
    }

    function previewSidestripMode(zone: var, effect: string): string {
        if (zone === "keys")
            return "none";
        switch (effect) {
        case "stream_battery":
            return "stream_battery";
        case "solid_theme":
            return "solid";
        case "breathing":
            return "breathing";
        case "red_breathing":
            return "red_breathing";
        case "red_static":
            return "red_static";
        case "none":
            return "none";
        default:
            return "stream_battery";
        }
    }

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        // Header with Action # and Remove button
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "tune"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3primary
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Acción %1").arg(root.index + 1)
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurface
            }

            StyledRect {
                implicitWidth: 26
                implicitHeight: 26
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.6)

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: BatteryLightingConfig.removeAction(root.ruleId, root.index)
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "close"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Section: Destino
        StyledText {
            text: qsTr("Destino")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: BatteryLightingConfig.targets

                Chip {
                    id: targetChip

                    required property var modelData

                    implicitWidth: targetLabel.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 30
                    label: modelData.label
                    selected: root.action.target === modelData.key
                    onClicked: BatteryLightingConfig.updateAction(root.ruleId, root.index, {
                        target: modelData.key
                    })

                    StyledText {
                        id: targetLabel

                        visible: false
                        text: targetChip.modelData.label
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        // Section: Zona (Akko only)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            visible: root.action.target === "akko_keyboard"

            StyledText {
                text: qsTr("Zona")
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: BatteryLightingConfig.zones

                    Chip {
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: 30
                        label: modelData.label
                        selected: (root.action.zone ?? "keys") === modelData.key
                        onClicked: BatteryLightingConfig.updateAction(root.ruleId, root.index, {
                            zone: modelData.key
                        })
                    }
                }
            }
        }

        // Section: Efecto
        StyledText {
            text: qsTr("Efecto")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: BatteryLightingConfig.effectsFor(root.action.target, root.action.zone)

                Chip {
                    id: effectChip

                    required property var modelData
                    readonly property bool isDanger: modelData.key.startsWith("red")

                    implicitWidth: effectLabel.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 30
                    label: modelData.label
                    selected: root.action.effect === modelData.key
                    activeColour: isDanger ? Colours.palette.m3errorContainer : Colours.palette.m3primary
                    activeText: isDanger ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimary
                    onClicked: BatteryLightingConfig.updateAction(root.ruleId, root.index, {
                        effect: modelData.key
                    })

                    StyledText {
                        id: effectLabel

                        visible: false
                        text: effectChip.modelData.label
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        // Akko live preview
        KeyboardPreview {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            visible: root.action.target === "akko_keyboard"
            mode: root.previewMode(root.action.zone, root.action.effect)
            sidestripMode: root.previewSidestripMode(root.action.zone, root.action.effect)
            lowColour: Colours.palette.m3error
        }
    }
}
