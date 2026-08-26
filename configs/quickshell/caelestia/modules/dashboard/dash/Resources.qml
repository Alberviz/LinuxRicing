import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    anchors.top: parent.top
    anchors.bottom: parent.bottom

    implicitWidth: layout.implicitWidth + Tokens.padding.large * 2

    property int headsetBat: 0
    property string headsetStatus: "Desconectado"
    property bool headsetCharging: false
    property bool headsetConnected: false

    property int mouseBat: 0
    property string mouseStatus: "Desconectado"
    property bool mouseCharging: false
    property bool mouseConnected: false

    Process {
        id: batteryProc

        command: ["/home/alberviz/.local/bin/mchose-battery", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.headset) {
                        root.headsetBat = data.headset.battery ?? 0;
                        root.headsetStatus = data.headset.status ?? "Desconectado";
                        root.headsetCharging = data.headset.charging ?? false;
                        root.headsetConnected = data.headset.connected ?? false;
                    }
                    if (data.mouse) {
                        root.mouseBat = data.mouse.battery ?? 0;
                        root.mouseStatus = data.mouse.status ?? "Desconectado";
                        root.mouseCharging = data.mouse.charging ?? false;
                        root.mouseConnected = data.mouse.connected ?? false;
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!batteryProc.running)
                batteryProc.running = true;
        }
    }

    ColumnLayout {
        id: layout

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Auriculares V9 Pro
        PeripheralGauge {
            icon: root.headsetCharging ? "bolt" : "headphones"
            value: root.headsetConnected ? (root.headsetBat / 100) : 0
            wavy: root.headsetCharging
            fgColour: root.headsetConnected ? (root.headsetCharging ? Colours.palette.m3primary : Colours.palette.m3secondary) : Colours.palette.m3outline
        }

        // Ratón K7 Ultra
        PeripheralGauge {
            icon: root.mouseCharging ? "bolt" : "mouse"
            value: root.mouseConnected ? (root.mouseBat / 100) : 0
            wavy: root.mouseCharging
            fgColour: root.mouseConnected ? (root.mouseCharging ? Colours.palette.m3primary : Colours.palette.m3tertiary) : Colours.palette.m3outline
        }

        // Estado Global / Icono Periféricos
        PeripheralGauge {
            icon: "devices"
            value: root.headsetConnected && root.mouseConnected ? ((root.headsetBat + root.mouseBat) / 200) : (root.mouseConnected ? root.mouseBat / 100 : (root.headsetConnected ? root.headsetBat / 100 : 0))
            fgColour: Colours.palette.m3primary
        }
    }

    component PeripheralGauge: CircularProgress {
        id: gauge

        required property string icon

        Layout.fillHeight: true
        implicitSize: height
        strokeWidth: Tokens.sizes.dashboard.resourceProgressThickness

        Behavior on clampedVal {
            Anim {}
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: gauge.icon
            fontStyle: Tokens.font.icon.large
            color: gauge.fgColour
        }
    }
}
