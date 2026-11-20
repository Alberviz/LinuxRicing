pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    signal close
    signal show(string id)
    signal off

    required property var items
    required property var currentInfo

    property int selectedIndex: 0

    implicitWidth: 500
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.palette.m3surfaceContainer
    border.width: 1
    border.color: Colours.palette.m3outlineVariant

    // Swallow clicks inside dialog
    MouseArea {
        anchors.fill: parent
    }

    focus: true
    Component.onCompleted: forceActiveFocus()

    Keys.onEscapePressed: root.close()
    Keys.onUpPressed: {
        if (root.items.length > 0)
            root.selectedIndex = (root.selectedIndex - 1 + root.items.length) % root.items.length;
    }
    Keys.onDownPressed: {
        if (root.items.length > 0)
            root.selectedIndex = (root.selectedIndex + 1) % root.items.length;
    }
    Keys.onReturnPressed: root.activateSelected()
    Keys.onEnterPressed: root.activateSelected()

    Keys.onPressed: event => {
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            const idx = event.key - Qt.Key_1;
            if (idx < root.items.length) {
                root.show(root.items[idx].id);
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_O || event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            root.off();
            event.accepted = true;
        }
    }

    function activateSelected(): void {
        if (root.items.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.items.length) {
            root.show(root.items[root.selectedIndex].id);
        }
    }

    readonly property var cardColors: [
        Colours.palette.m3primary,
        Colours.palette.m3secondary,
        Colours.palette.m3tertiary,
        Colours.palette.m3primaryContainer,
        Colours.palette.m3secondaryContainer
    ]

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: Tokens.rounding.medium
                color: Qt.alpha(Colours.palette.m3primary, 0.2)
                border.width: 1.5
                border.color: Colours.palette.m3primary

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "tv"
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.2).weight(Font.Bold).build()
                    color: Colours.palette.m3primary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Escaparate de la Tele")
                    font: Tokens.font.title.medium
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Elige qué proyectar en el salón a pantalla completa")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            StyledRect {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: Tokens.rounding.full
                color: closeLayer.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent"

                StateLayer {
                    id: closeLayer
                    radius: Tokens.rounding.full
                    onClicked: root.close()
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "close"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Divider
        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            color: Colours.palette.m3outlineVariant
        }

        // Cards list
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: root.items

                delegate: EscaparateCard {
                    id: card
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    icon: modelData.icon || "desktop_windows"
                    title: modelData.name || modelData.id
                    description: modelData.kind === "video" ? qsTr("Vídeo en bucle · %1").arg(modelData.target) : (modelData.kind === "web" ? qsTr("Web · %1").arg(modelData.target) : qsTr("Comando · %1").arg(modelData.target))
                    shortcutKey: (index + 1) <= 9 ? String(index + 1) : ""
                    current: root.currentInfo.active && root.currentInfo.id === modelData.id
                    selected: root.selectedIndex === index
                    iconColor: root.cardColors[index % root.cardColors.length]
                    iconBgColor: Qt.alpha(iconColor, 0.18)
                    onClicked: {
                        root.selectedIndex = index;
                        root.show(modelData.id);
                    }
                }
            }
        }

        // Empty state if no items
        StyledText {
            visible: root.items.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("No hay escaparates definidos en ~/.config/caelestia/escaparate.json")
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurfaceVariant
        }

        // Footer / Actions
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: Tokens.spacing.medium

            // Apagar escaparate button
            StyledRect {
                id: offBtn
                implicitWidth: offRow.implicitWidth + 24
                implicitHeight: 36
                radius: Tokens.rounding.medium
                color: offLayer.containsMouse ? Colours.palette.m3errorContainer : Qt.alpha(Colours.palette.m3error, 0.12)
                border.width: 1
                border.color: Colours.palette.m3error

                StateLayer {
                    id: offLayer
                    radius: Tokens.rounding.medium
                    onClicked: root.off()
                }

                RowLayout {
                    id: offRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialIcon {
                        text: "power_settings_new"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3error
                    }

                    StyledText {
                        text: qsTr("Apagar escaparate (O)")
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3error
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // Close button
            StyledRect {
                id: cancelBtn
                implicitWidth: cancelRow.implicitWidth + 24
                implicitHeight: 36
                radius: Tokens.rounding.medium
                color: cancelLayer.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainerHigh
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                StateLayer {
                    id: cancelLayer
                    radius: Tokens.rounding.medium
                    onClicked: root.close()
                }

                RowLayout {
                    id: cancelRow
                    anchors.centerIn: parent
                    spacing: 6

                    StyledText {
                        text: qsTr("Cerrar (Esc)")
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurface
                    }
                }
            }
        }
    }
}
