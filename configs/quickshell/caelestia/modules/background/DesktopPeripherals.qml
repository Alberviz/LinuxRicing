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
    id: periphRoot

    // Se propaga desde la ventana: fondos translúcidos vs. sólidos.
    property bool transparentWidgets: true
    // La ventana es la dueña del estado de transparencia; el botón de blur
    // sólo pide el cambio y ella lo persiste.
    signal toggleTransparencyRequested()

    implicitWidth: 640
    implicitHeight: periphLayout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: periphRoot.transparentWidgets ? "transparent" : Colours.tPalette.m3surfaceContainer

    Behavior on color {
        CAnim {}
    }

    property int headsetBat: 0
    property bool headsetBatteryKnown: false
    property string headsetStatus: "Desconectado"
    property string headsetMode: "Desconectado"
    property bool headsetCharging: false
    property bool headsetConnected: false

    property int mouseBat: 0
    property bool mouseBatteryKnown: false
    property string mouseStatus: "Desconectado"
    property string mouseMode: "Desconectado"
    property bool mouseCharging: false
    property bool mouseConnected: false

    property int kbBat: 0
    property bool kbBatteryKnown: false
    property string kbStatus: "Desconectado"
    property string kbMode: "Desconectado"
    property bool kbCharging: false
    property bool kbConnected: false

    Process {
        id: proc
        command: ["/home/alberviz/.local/bin/mchose-battery", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.headset) {
                        periphRoot.headsetBatteryKnown = data.headset.battery !== null && data.headset.battery !== undefined;
                        periphRoot.headsetBat = data.headset.battery ?? 0;
                        periphRoot.headsetStatus = data.headset.status ?? "Desconectado";
                        periphRoot.headsetMode = data.headset.mode ?? (data.headset.connected ? "2.4G Inalámbrico" : "Desconectado");
                        periphRoot.headsetCharging = data.headset.charging ?? false;
                        periphRoot.headsetConnected = data.headset.connected ?? false;
                    }
                    if (data.mouse) {
                        periphRoot.mouseBatteryKnown = data.mouse.battery !== null && data.mouse.battery !== undefined;
                        periphRoot.mouseBat = data.mouse.battery ?? 0;
                        periphRoot.mouseStatus = data.mouse.status ?? "Desconectado";
                        periphRoot.mouseMode = data.mouse.mode ?? (data.mouse.connected ? "2.4G Inalámbrico" : "Desconectado");
                        periphRoot.mouseCharging = data.mouse.charging ?? false;
                        periphRoot.mouseConnected = data.mouse.connected ?? false;
                    }
                    if (data.keyboard) {
                        periphRoot.kbBatteryKnown = data.keyboard.battery !== null && data.keyboard.battery !== undefined;
                        periphRoot.kbBat = data.keyboard.battery ?? 0;
                        periphRoot.kbStatus = data.keyboard.status ?? "Desconectado";
                        periphRoot.kbMode = data.keyboard.mode ?? (data.keyboard.connected ? "2.4G Inalámbrico" : "Desconectado");
                        periphRoot.kbCharging = data.keyboard.charging ?? false;
                        periphRoot.kbConnected = data.keyboard.connected ?? false;
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!proc.running)
                proc.running = true;
        }
    }

    StateLayer {
        radius: Tokens.rounding.extraLarge
        onClicked: {
            if (!proc.running)
                proc.running = true;
        }
    }

    ColumnLayout {
        id: periphLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Periféricos")
                color: Colours.palette.m3primary
                font: Tokens.font.title.small
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // Open Lighting Center Button
            StyledRect {
                implicitWidth: 28
                implicitHeight: 28
                radius: Tokens.rounding.full
                color: periphRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5)

                Behavior on color {
                    CAnim {}
                }

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: ShellState.rgbControl?.open()
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "tune"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3primary

                    Behavior on color {
                        CAnim {}
                    }
                }
            }

            // Toggle Transparency Button
            StyledRect {
                implicitWidth: 28
                implicitHeight: 28
                radius: Tokens.rounding.full
                color: periphRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5)

                Behavior on color {
                    CAnim {}
                }

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: periphRoot.toggleTransparencyRequested()
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: periphRoot.transparentWidgets ? "blur_on" : "blur_off"
                    fontStyle: Tokens.font.icon.small
                    color: periphRoot.transparentWidgets ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

                    Behavior on color {
                        CAnim {}
                    }
                }
            }

            // Reload Button
            StyledRect {
                implicitWidth: 28
                implicitHeight: 28
                radius: Tokens.rounding.full
                color: periphRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5)

                Behavior on color {
                    CAnim {}
                }

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: {
                        if (!proc.running)
                            proc.running = true;
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: proc.running ? "sync" : "refresh"
                    fontStyle: Tokens.font.icon.small
                    color: proc.running ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

                    Behavior on color {
                        CAnim {}
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            DeviceItem {
                Layout.fillWidth: true
                transparentWidgets: periphRoot.transparentWidgets
                name: "V9 Pro"
                icon: periphRoot.headsetCharging ? "battery_charging_full" : "headphones"
                battery: periphRoot.headsetBat
                batteryKnown: periphRoot.headsetBatteryKnown
                status: periphRoot.headsetStatus
                mode: periphRoot.headsetMode
                charging: periphRoot.headsetCharging
                connected: periphRoot.headsetConnected
                accentColor: Colours.palette.m3primary
            }

            DeviceItem {
                Layout.fillWidth: true
                transparentWidgets: periphRoot.transparentWidgets
                name: "K7 Ultra"
                icon: periphRoot.mouseCharging ? "battery_charging_full" : "mouse"
                battery: periphRoot.mouseBat
                batteryKnown: periphRoot.mouseBatteryKnown
                status: periphRoot.mouseStatus
                mode: periphRoot.mouseMode
                charging: periphRoot.mouseCharging
                connected: periphRoot.mouseConnected
                accentColor: Colours.palette.m3primary
            }

            DeviceItem {
                Layout.fillWidth: true
                transparentWidgets: periphRoot.transparentWidgets
                name: "Akko 5075B"
                icon: periphRoot.kbCharging ? "battery_charging_full" : "keyboard"
                battery: periphRoot.kbBat
                batteryKnown: periphRoot.kbBatteryKnown
                status: periphRoot.kbStatus
                mode: periphRoot.kbMode
                charging: periphRoot.kbCharging
                connected: periphRoot.kbConnected
                accentColor: Colours.palette.m3primary
            }
        }

    }
}
