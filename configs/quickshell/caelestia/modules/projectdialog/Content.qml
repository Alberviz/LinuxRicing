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

    implicitWidth: 500
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.palette.m3surfaceContainer
    border.width: 1
    border.color: Colours.palette.m3outlineVariant

    // Swallow clicks inside the dialog
    MouseArea {
        anchors.fill: parent
    }

    focus: true
    Component.onCompleted: forceActiveFocus()

    Keys.onEscapePressed: root.close()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_1) {
            root.modeExternalOnly();
            event.accepted = true;
        } else if (event.key === Qt.Key_2) {
            root.modeExtend();
            event.accepted = true;
        } else if (event.key === Qt.Key_3) {
            root.modeMirror();
            event.accepted = true;
        } else if (event.key === Qt.Key_4) {
            root.modeLaptopOnly();
            event.accepted = true;
        }
    }

    function modeExternalOnly(): void {
        root.close();
        Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = 'eDP-2', disabled = true }); hl.monitor({ output = 'HDMI-A-1', mode = '1920x1080@144', position = '0x0', scale = 1, disabled = false })"]);
        Quickshell.execDetached(["notify-send", "-a", "Pantalla", "-i", "video-display", "Modo: Solo Monitor Externo", "Pantalla integrada apagada (0 consumo).\nMonitor externo activo a 144Hz."]);
    }

    function modeExtend(): void {
        root.close();
        Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = 'HDMI-A-1', mode = '1920x1080@144', position = '1920x0', scale = 1, disabled = false }); hl.monitor({ output = 'eDP-2', mode = '1920x1080@144', position = '0x0', scale = 1, disabled = false })"]);
        Quickshell.execDetached(["notify-send", "-a", "Pantalla", "-i", "video-display", "Modo: Pantallas Extendidas", "Doble monitor activo a 144Hz."]);
    }

    function modeMirror(): void {
        root.close();
        Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = 'eDP-2', mode = '1920x1080@144', position = 'auto', scale = 1, disabled = false }); hl.monitor({ output = 'HDMI-A-1', mode = '1920x1080@144', position = 'auto', scale = 1, mirror = 'eDP-2', disabled = false })"]);
        Quickshell.execDetached(["notify-send", "-a", "Pantalla", "-i", "video-display", "Modo: Duplicado / Espejo", "Ambas pantallas en espejo a 144Hz."]);
    }

    function modeLaptopOnly(): void {
        root.close();
        Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = 'HDMI-A-1', disabled = true }); hl.monitor({ output = 'eDP-2', mode = '1920x1080@144', position = '0x0', scale = 1, disabled = false })"]);
        Quickshell.execDetached(["notify-send", "-a", "Pantalla", "-i", "video-display", "Modo: Solo Portátil", "Monitor externo deshabilitado.\nPanel integrado a 144Hz."]);
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
                    text: "cast"
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.2).weight(Font.Bold).build()
                    color: Colours.palette.m3primary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Proyectar pantalla")
                    font: Tokens.font.title.medium
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Selecciona el modo de distribución de pantallas")
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

        // Option 1: Solo monitor externo (Apagar portátil)
        ProjectCard {
            Layout.fillWidth: true
            icon: "desktop_windows"
            title: qsTr("Solo monitor externo")
            description: qsTr("Apaga la pantalla del portátil para ahorro y 0 consumo")
            shortcutKey: "1"
            iconColor: Colours.palette.m3primary
            iconBgColor: Qt.alpha(Colours.palette.m3primary, 0.2)
            onClicked: root.modeExternalOnly()
        }

        // Option 2: Extender
        ProjectCard {
            Layout.fillWidth: true
            icon: "splitscreen"
            title: qsTr("Extender pantallas")
            description: qsTr("Doble monitor activo a 144Hz en paralelo")
            shortcutKey: "2"
            iconColor: Colours.palette.m3secondary
            iconBgColor: Qt.alpha(Colours.palette.m3secondary, 0.2)
            onClicked: root.modeExtend()
        }

        // Option 3: Duplicar
        ProjectCard {
            Layout.fillWidth: true
            icon: "flip_to_front"
            title: qsTr("Duplicar / Espejo")
            description: qsTr("Muestra el mismo contenido en ambas pantallas a 144Hz")
            shortcutKey: "3"
            iconColor: Colours.palette.m3tertiary
            iconBgColor: Qt.alpha(Colours.palette.m3tertiary, 0.2)
            onClicked: root.modeMirror()
        }

        // Option 4: Solo portátil
        ProjectCard {
            Layout.fillWidth: true
            icon: "laptop"
            title: qsTr("Solo pantalla del portátil")
            description: qsTr("Deshabilita el monitor externo y deja solo el portátil")
            shortcutKey: "4"
            iconColor: Colours.palette.m3outline
            iconBgColor: Qt.alpha(Colours.palette.m3outline, 0.2)
            onClicked: root.modeLaptopOnly()
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
