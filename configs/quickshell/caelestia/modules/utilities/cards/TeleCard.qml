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

    readonly property real nonAnimHeight: col.implicitHeight + Tokens.padding.large * 2

    implicitHeight: nonAnimHeight
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    readonly property string statusText: {
        if (Tele.transport === "hdmi")
            return qsTr("HDMI conectado (%1)").arg(Tele.hdmiName || "SyncMaster");
        if (Tele.transport === "wifi")
            return qsTr("Wi-Fi activo (%1)").arg(Tele.chromecastName);
        if (Tele.hdmiConnected)
            return qsTr("HDMI listo · en espera");
        if (Tele.chromecastOnline)
            return qsTr("Chromecast listo (%1)").arg(Tele.chromecastName);
        return qsTr("Sin tele ni Chromecast");
    }

    ColumnLayout {
        id: col

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: tvIcon.implicitHeight + Tokens.padding.medium

                radius: Tokens.rounding.full
                color: Tele.active ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: tvIcon

                    anchors.centerIn: parent
                    text: Tele.mode === "agents" ? "smart_toy" : (Tele.mode === "gaming" ? "sports_esports" : "tv")
                    color: Tele.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.medium
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Tele")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    font: Tokens.font.label.small
                    color: Tele.transport === "hdmi" ? Colours.palette.m3primary : (Tele.transport === "wifi" ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant)
                    elide: Text.ElideRight
                }
            }

            // Botón rápido para apagar si está activa
            StyledRect {
                visible: Tele.active
                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: offLayer.containsMouse ? Colours.palette.m3errorContainer : Colours.tPalette.m3surfaceContainerHigh

                StateLayer {
                    id: offLayer
                    radius: Tokens.rounding.full
                    onClicked: Tele.setMode("off", false)
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "power_settings_new"
                    fontStyle: Tokens.font.icon.small
                    color: offLayer.containsMouse ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Selector de los 3 modos: Personal | Agentes | Juegos
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: [
                    { id: "personal", label: qsTr("Personal"), icon: "desktop_windows" },
                    { id: "agents", label: qsTr("Agentes"), icon: "smart_toy" },
                    { id: "gaming", label: qsTr("Juegos"), icon: "sports_esports" }
                ]

                StyledRect {
                    id: modeBtn
                    required property var modelData

                    readonly property bool selected: Tele.mode === modelData.id
                    readonly property bool enabledBtn: Tele.available

                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Tokens.rounding.medium
                    color: selected ? Colours.palette.m3primaryContainer : (btnLayer.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerHigh)
                    border.width: selected ? 1.5 : 0
                    border.color: Colours.palette.m3primary
                    opacity: enabledBtn ? 1 : 0.45

                    StateLayer {
                        id: btnLayer
                        radius: parent.radius
                        disabled: !modeBtn.enabledBtn || Tele.busy
                        onClicked: {
                            if (modeBtn.modelData.id === "gaming") {
                                // Abre Elysium (si no hay HDMI, Elysium permite elegir Wi-Fi)
                                Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "elysium", "enter"]);
                            } else {
                                Tele.setMode(modeBtn.modelData.id, false);
                            }
                        }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: modeBtn.modelData.icon
                            fontStyle: Tokens.font.icon.small
                            color: modeBtn.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            text: modeBtn.modelData.label
                            font: Tokens.font.label.small
                            color: modeBtn.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        }
                    }
                }
            }
        }

        // Acciones contextuales: Interactuar + Escaparate
        RowLayout {
            Layout.fillWidth: true
            visible: Tele.active || Tele.available
            spacing: Tokens.spacing.extraSmall

            StyledRect {
                visible: Tele.active && (Tele.mode === "agents" || Tele.transport === "wifi")
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Tokens.rounding.medium
                color: Tele.interacting ? Colours.palette.m3tertiaryContainer : Colours.tPalette.m3surfaceContainerHigh

                StateLayer {
                    radius: parent.radius
                    onClicked: Tele.toggleInteract()
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        text: Tele.interacting ? "keyboard_return" : "touch_app"
                        fontStyle: Tokens.font.icon.small
                        color: Tele.interacting ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        text: Tele.interacting ? qsTr("Devolver a Tele") : qsTr("Interactuar")
                        font: Tokens.font.label.small
                        color: Tele.interacting ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                    }
                }
            }

            StyledRect {
                visible: Tele.available
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainerHigh

                StateLayer {
                    radius: parent.radius
                    onClicked: Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "escaparate", "toggle"])
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        text: "slideshow"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        text: qsTr("Escaparate")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurface
                    }
                }
            }
        }
    }
}
