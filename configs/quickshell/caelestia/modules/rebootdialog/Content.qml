pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    signal close

    implicitWidth: 480
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.palette.m3surfaceContainer
    border.width: 1
    border.color: Colours.palette.m3outlineVariant

    // Swallow clicks inside the dialog so it doesn't dismiss
    MouseArea {
        anchors.fill: parent
    }

    focus: true
    Component.onCompleted: forceActiveFocus()

    Keys.onEscapePressed: root.close()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_1) {
            root.rebootLinux();
            event.accepted = true;
        } else if (event.key === Qt.Key_2) {
            root.rebootWindows();
            event.accepted = true;
        } else if (event.key === Qt.Key_3) {
            root.rebootBios();
            event.accepted = true;
        }
    }

    function rebootLinux(): void {
        root.close();
        Quickshell.execDetached(["systemctl", "reboot"]);
    }

    function rebootWindows(): void {
        root.close();
        Quickshell.execDetached(["/home/alberviz/.local/bin/reboot-to-windows"]);
    }

    function rebootBios(): void {
        root.close();
        Quickshell.execDetached(["systemctl", "reboot", "--firmware-setup"]);
    }

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
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: Tokens.rounding.medium
                color: Qt.alpha(Colours.palette.m3primary, 0.2)
                border.width: 1.5
                border.color: Colours.palette.m3primary

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "restart_alt"
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.2).weight(Font.Bold).build()
                    color: Colours.palette.m3primary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Reiniciar equipo")
                    font: Tokens.font.title.medium
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Selecciona el sistema operativo o modo")
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
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            color: Colours.palette.m3outlineVariant
        }

        // Option 1: Linux
        RebootCard {
            Layout.fillWidth: true
            icon: "computer"
            title: qsTr("Linux (CachyOS)")
            description: qsTr("Arranque principal del sistema")
            shortcutKey: "1"
            iconColor: Colours.palette.m3primary
            iconBgColor: Qt.alpha(Colours.palette.m3primary, 0.2)
            onClicked: root.rebootLinux()
        }

        // Option 2: Windows
        RebootCard {
            Layout.fillWidth: true
            icon: "desktop_windows"
            title: qsTr("Windows")
            description: qsTr("Arranque directo UEFI a Windows")
            shortcutKey: "2"
            iconColor: "#00a4ef"
            iconBgColor: Qt.alpha("#00a4ef", 0.2)
            onClicked: root.rebootWindows()
        }

        // Option 3: BIOS
        RebootCard {
            Layout.fillWidth: true
            icon: "settings"
            title: qsTr("Configuración BIOS / UEFI")
            description: qsTr("Acceder a los ajustes del firmware")
            shortcutKey: "3"
            iconColor: "#f59e0b"
            iconBgColor: Qt.alpha("#f59e0b", 0.2)
            onClicked: root.rebootBios()
        }

        // Footer / Cancel button
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6

            Item {
                Layout.fillWidth: true
            }

            StyledRect {
                id: cancelBtn
                implicitWidth: cancelRow.implicitWidth + 36
                implicitHeight: 38
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                radius: Tokens.rounding.full
                color: cancelLayer.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainerHigh
                border.width: 1
                border.color: cancelLayer.containsMouse ? Colours.palette.m3outline : Colours.palette.m3outlineVariant

                StateLayer {
                    id: cancelLayer
                    radius: Tokens.rounding.full
                    onClicked: root.close()
                }

                RowLayout {
                    id: cancelRow
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialIcon {
                        text: "close"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        text: qsTr("Cancelar")
                        font: Tokens.font.label.large
                        color: Colours.palette.m3onSurface
                    }

                    StyledRect {
                        implicitHeight: 20
                        implicitWidth: 32
                        radius: Tokens.rounding.extraSmall
                        color: Colours.palette.m3surfaceContainerLowest
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant

                        StyledText {
                            anchors.centerIn: parent
                            text: "Esc"
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
