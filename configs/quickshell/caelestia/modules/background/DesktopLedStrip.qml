pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Services
import Caelestia.Components
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services

StyledClippingRect {
    id: ledRoot

    // Se propaga desde la ventana: fondos translúcidos vs. sólidos.
    property bool transparentWidgets: true

    implicitWidth: 320
    implicitHeight: ledLayout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: ledRoot.transparentWidgets ? "transparent" : Colours.tPalette.m3surfaceContainer

    Behavior on color {
        CAnim {}
    }

    property bool isPowered: false
    property string currentHex: "#ffffff"
    property bool isConnecting: false
    property bool isSyncing: false

    Process {
        id: ledStatusProc
        command: ["/home/alberviz/.local/bin/magichome-control", "--status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data && data.success) {
                        ledRoot.isPowered = data.is_on ?? false;
                        ledRoot.currentHex = data.color ?? "#ffffff";
                    }
                } catch (e) {}
                ledRoot.isConnecting = false;
            }
        }
    }

    Process {
        id: ledToggleProc
        command: ["/home/alberviz/.local/bin/magichome-control", "--toggle"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data && data.success) {
                        ledRoot.isPowered = data.is_on ?? !ledRoot.isPowered;
                    }
                } catch (e) {}
                ledRoot.isConnecting = false;
                if (!ledStatusProc.running)
                    ledStatusProc.running = true;
            }
        }
    }

    Process {
        id: syncProc
        command: ["/home/alberviz/.config/caelestia/sync-rgb.py"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                ledRoot.isSyncing = false;
                if (!ledStatusProc.running)
                    ledStatusProc.running = true;
            }
        }
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: {
            if (!ledStatusProc.running && !ledToggleProc.running && !ledRoot.isSyncing)
                ledStatusProc.running = true;
        }
    }

    function togglePower() {
        ledRoot.isConnecting = true;
        if (!ledToggleProc.running)
            ledToggleProc.running = true;
    }

    function syncColors() {
        ledRoot.isSyncing = true;
        if (!syncProc.running)
            syncProc.running = true;
    }

    ColumnLayout {
        id: ledLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Iluminación Ambiente")
                color: Colours.palette.m3primary
                font: Tokens.font.title.small
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // Open the full lighting control center
            StyledRect {
                implicitWidth: 28
                implicitHeight: 28
                radius: Tokens.rounding.full
                color: ledRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5)

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: ShellState.rgbControl?.open()
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "tune"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            MaterialIcon {
                text: ledRoot.isConnecting ? "sync" : "lightbulb"
                fontStyle: Tokens.font.icon.small
                color: ledRoot.isPowered ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                opacity: 0.6
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            // Card 1: Toggle & Power State
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: card1Col.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.large
                color: ledRoot.isPowered ? Qt.alpha(Colours.palette.m3primary, 0.18) : (ledRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

                Behavior on color {
                    CAnim {}
                }

                StateLayer {
                    radius: Tokens.rounding.large
                    onClicked: ledRoot.togglePower()
                }

                ColumnLayout {
                    id: card1Col
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: ledRoot.isPowered ? "lightbulb" : "lightbulb_outline"
                            fontStyle: Tokens.font.icon.medium
                            color: ledRoot.isPowered ? Colours.palette.m3primary : Colours.palette.m3outline

                            Behavior on color {
                                CAnim {}
                            }
                        }

                        StyledText {
                            text: ledRoot.isPowered ? qsTr("ON") : qsTr("OFF")
                            color: ledRoot.isPowered ? Colours.palette.m3primary : Colours.palette.m3outline
                            font: Tokens.font.title.medium
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Tira LED")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: ledRoot.isPowered ? qsTr("Encendida") : qsTr("Apagada")
                        color: ledRoot.isPowered ? Colours.palette.m3primary : Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }
            }

            // Card 2: Color Palette & Resync Action
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: card2Col.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.large
                color: ledRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh

                Behavior on color {
                    CAnim {}
                }

                StateLayer {
                    radius: Tokens.rounding.large
                    onClicked: ledRoot.syncColors()
                }

                ColumnLayout {
                    id: card2Col
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Tokens.spacing.small

                        StyledRect {
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: Tokens.rounding.full
                            color: ledRoot.currentHex
                        }

                        StyledText {
                            text: ledRoot.currentHex.toUpperCase()
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.title.medium
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Sincronizar")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: ledRoot.isSyncing ? "sync" : "refresh"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3secondary
                            opacity: 0.85
                        }

                        StyledText {
                            text: ledRoot.isSyncing ? qsTr("Sincronizando...") : qsTr("Re-sincronizar")
                            color: Colours.palette.m3secondary
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }
    }
}
