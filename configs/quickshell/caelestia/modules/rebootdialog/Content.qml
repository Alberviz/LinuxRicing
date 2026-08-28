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

    implicitWidth: 460
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
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: Tokens.rounding.medium
                color: Colours.palette.m3primaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "restart_alt"
                    fontStyle: Tokens.font.icon.medium
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

        // Options
        RebootCard {
            Layout.fillWidth: true
            icon: "computer"
            title: qsTr("Linux (CachyOS)")
            description: qsTr("Arranque predeterminado del sistema")
            shortcutKey: "1"
            iconColor: Colours.palette.m3primary
            iconBgColor: Colours.palette.m3primaryContainer
            onClicked: root.rebootLinux()
        }

        RebootCard {
            Layout.fillWidth: true
            icon: "desktop_windows"
            title: qsTr("Windows")
            description: qsTr("Arranque directo UEFI a Windows")
            shortcutKey: "2"
            iconColor: Colours.palette.m3tertiary
            iconBgColor: Colours.palette.m3tertiaryContainer
            onClicked: root.rebootWindows()
        }

        RebootCard {
            Layout.fillWidth: true
            icon: "settings"
            title: qsTr("Configuración BIOS / UEFI")
            description: qsTr("Acceder a los ajustes del firmware")
            shortcutKey: "3"
            iconColor: Colours.palette.m3secondary
            iconBgColor: Colours.palette.m3secondaryContainer
            onClicked: root.rebootBios()
        }

        // Footer / Cancel button
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4

            Item {
                Layout.fillWidth: true
            }

            StyledRect {
                Layout.preferredHeight: 36
                Layout.preferredWidth: 110
                radius: Tokens.rounding.full
                color: cancelLayer.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent"
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                StateLayer {
                    id: cancelLayer
                    radius: Tokens.rounding.full
                    onClicked: root.close()
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    StyledText {
                        text: qsTr("Cancelar")
                        font: Tokens.font.label.large
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        text: "(Esc)"
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
