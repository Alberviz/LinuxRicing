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

Variants {
    model: Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled)

    StyledWindow {
        id: win

        required property ShellScreen modelData
        property bool transparentWidgets: true

        screen: modelData
        name: "background"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: contentItem.Config.background.wallpaperEnabled ? WlrLayer.Background : WlrLayer.Bottom
        color: contentItem.Config.background.wallpaperEnabled ? "black" : "transparent"
        surfaceFormat.opaque: false

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        ShellState.ComponentRef {
            screen: win.screen
            slot: "background"
            component: win
        }

        Item {
            id: behindClock

            anchors.fill: parent

            Loader {
                id: wallpaper

                asynchronous: true

                anchors.fill: parent
                active: Config.background.wallpaperEnabled

                sourceComponent: Wallpaper {}
            }

            DesktopCircularMedia {
                anchors.right: parent.right
                anchors.rightMargin: Math.max(80, Math.round((parent.width - 640 - width) / 2))
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Loader {
            id: clockLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled
            width: item ? (item as Item).implicitWidth : implicitWidth
            height: item ? (item as Item).implicitHeight : implicitHeight

            anchors.margins: Tokens.padding.extraLargeIncreased
            anchors.leftMargin: Tokens.padding.extraLargeIncreased + Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness)

            state: Config.background.desktopClock.position
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }

            sourceComponent: DesktopClock {
                wallpaper: behindClock
                absX: clockLoader.x
                absY: clockLoader.y
            }
        }

        Loader {
            id: peripheralsLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled
            sourceComponent: DesktopPeripherals {}

            anchors.top: clockLoader.bottom
            anchors.topMargin: Tokens.spacing.extraLarge
            anchors.left: clockLoader.left
            width: clockLoader.width > 0 ? clockLoader.width : 640
        }

        Loader {
            id: deckLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled
            sourceComponent: DesktopWidgetDeck {}

            anchors.top: peripheralsLoader.bottom
            anchors.topMargin: Tokens.spacing.large
            anchors.left: clockLoader.left
            width: clockLoader.width > 0 ? clockLoader.width : 640
        }

        Loader {
            id: ledStripLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled
            sourceComponent: DesktopLedStrip {}

            anchors.top: deckLoader.bottom
            anchors.topMargin: Tokens.spacing.large
            anchors.left: clockLoader.left
            width: clockLoader.width > 0 ? clockLoader.width : 640
        }
    }

    component DesktopPeripherals: StyledClippingRect {
        id: periphRoot

        implicitWidth: 640
        implicitHeight: periphLayout.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: win.transparentWidgets ? "transparent" : Colours.tPalette.m3surfaceContainer

        Behavior on color {
            CAnim {}
        }

        property int headsetBat: 0
        property string headsetStatus: "Desconectado"
        property bool headsetCharging: false
        property bool headsetConnected: false

        property int mouseBat: 0
        property string mouseStatus: "Desconectado"
        property bool mouseCharging: false
        property bool mouseConnected: false

        property int kbBat: 0
        property string kbStatus: "Desconectado"
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
                            periphRoot.headsetBat = data.headset.battery ?? 0;
                            periphRoot.headsetStatus = data.headset.status ?? "Desconectado";
                            periphRoot.headsetCharging = data.headset.charging ?? false;
                            periphRoot.headsetConnected = data.headset.connected ?? false;
                        }
                        if (data.mouse) {
                            periphRoot.mouseBat = data.mouse.battery ?? 0;
                            periphRoot.mouseStatus = data.mouse.status ?? "Desconectado";
                            periphRoot.mouseCharging = data.mouse.charging ?? false;
                            periphRoot.mouseConnected = data.mouse.connected ?? false;
                        }
                        if (data.keyboard) {
                            periphRoot.kbBat = data.keyboard.battery ?? 0;
                            periphRoot.kbStatus = data.keyboard.status ?? "Desconectado";
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

        property bool showMchoseSettings: false
        property string chargingEffect: "theme_breathing"
        property string lowBatEffect: "red_breathing"
        property int lowBatThreshold: 20

        Process {
            id: configReadProc
            command: ["/usr/bin/cat", "/home/alberviz/.config/caelestia/mchose-config.json"]
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const c = JSON.parse(text);
                        if (c.charging_effect) periphRoot.chargingEffect = c.charging_effect;
                        if (c.low_battery_effect) periphRoot.lowBatEffect = c.low_battery_effect;
                        if (c.low_battery_threshold) periphRoot.lowBatThreshold = c.low_battery_threshold;
                    } catch (e) {}
                }
            }
        }

        Component.onCompleted: {
            if (!configReadProc.running)
                configReadProc.running = true;
        }

        Process {
            id: configSaveProc
            property var cmdArgs: []
            command: cmdArgs
            running: false
        }

        function saveCharging(opt) {
            chargingEffect = opt;
            configSaveProc.cmdArgs = ["/home/alberviz/.local/bin/mchose-config", "charge", opt];
            configSaveProc.running = true;
        }

        function saveLowBat(opt) {
            lowBatEffect = opt;
            configSaveProc.cmdArgs = ["/home/alberviz/.local/bin/mchose-config", "lowbat", opt];
            configSaveProc.running = true;
        }

        function saveThreshold(th) {
            lowBatThreshold = th;
            configSaveProc.cmdArgs = ["/home/alberviz/.local/bin/mchose-config", "threshold", String(th)];
            configSaveProc.running = true;
        }

        function previewEffect(mode) {
            configSaveProc.cmdArgs = ["/home/alberviz/.local/bin/mchose-lighting", mode];
            configSaveProc.running = true;
        }

        ColumnLayout {
            id: periphLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
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

                // Toggle Transparency Button
                StyledRect {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5)

                    Behavior on color {
                        CAnim {}
                    }

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: win.transparentWidgets = !win.transparentWidgets
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: win.transparentWidgets ? "blur_on" : "blur_off"
                        fontStyle: Tokens.font.icon.small
                        color: win.transparentWidgets ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

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
                    color: win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5)

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
                    name: "V9 Pro"
                    icon: periphRoot.headsetCharging ? "battery_charging_full" : "headphones"
                    battery: periphRoot.headsetBat
                    status: periphRoot.headsetStatus
                    charging: periphRoot.headsetCharging
                    connected: periphRoot.headsetConnected
                    accentColor: Colours.palette.m3secondary
                }

                DeviceItem {
                    Layout.fillWidth: true
                    name: "K7 Ultra"
                    icon: periphRoot.mouseCharging ? "battery_charging_full" : "mouse"
                    battery: periphRoot.mouseBat
                    status: periphRoot.mouseStatus
                    charging: periphRoot.mouseCharging
                    connected: periphRoot.mouseConnected
                    accentColor: Colours.palette.m3tertiary
                    isClickable: true
                    onClicked: {
                        periphRoot.showMchoseSettings = !periphRoot.showMchoseSettings;
                        if (periphRoot.showMchoseSettings && !configReadProc.running)
                            configReadProc.running = true;
                    }
                }

                DeviceItem {
                    Layout.fillWidth: true
                    name: "Akko B"
                    icon: periphRoot.kbCharging ? "battery_charging_full" : "keyboard"
                    battery: periphRoot.kbBat
                    status: periphRoot.kbStatus
                    charging: periphRoot.kbCharging
                    connected: periphRoot.kbConnected
                    accentColor: Colours.palette.m3primary
                }
            }

            // =========================================================================
            // MCHOSE 8K BASE LIGHTING SETTINGS CARD (Expandable on K7 Ultra Click)
            // =========================================================================
            StyledRect {
                id: mchoseSettingsCard
                Layout.fillWidth: true
                visible: periphRoot.showMchoseSettings
                clip: true
                radius: Tokens.rounding.large
                color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.6)
                Layout.preferredHeight: periphRoot.showMchoseSettings ? (settingsCol.implicitHeight + Tokens.padding.medium * 2) : 0
                implicitHeight: Layout.preferredHeight

                Behavior on Layout.preferredHeight {
                    CAnim {}
                }

                ColumnLayout {
                    id: settingsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "tune"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: "Ajustes de Iluminación Base 8K"
                            font: Tokens.font.title.small
                            color: Colours.palette.m3primary
                            Layout.fillWidth: true
                        }

                        StyledRect {
                            implicitWidth: 24
                            implicitHeight: 24
                            radius: Tokens.rounding.full
                            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.6)

                            StateLayer {
                                radius: Tokens.rounding.full
                                onClicked: periphRoot.showMchoseSettings = false
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "close"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    // Seccion 1: Efecto de Carga
                    StyledText {
                        text: "🔌 Efecto al Poner a Cargar:"
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        MchoseChip {
                            Layout.fillWidth: true
                            label: "🎨 Tema"
                            selected: periphRoot.chargingEffect === "theme_breathing"
                            onClicked: periphRoot.saveCharging("theme")
                        }
                        MchoseChip {
                            Layout.fillWidth: true
                            label: "🔋 Batería"
                            selected: periphRoot.chargingEffect === "battery_breathing"
                            onClicked: periphRoot.saveCharging("battery")
                        }
                        MchoseChip {
                            Layout.fillWidth: true
                            label: "⚡ Oficial"
                            selected: periphRoot.chargingEffect === "hardware_battery"
                            onClicked: periphRoot.saveCharging("hardware")
                        }
                        MchoseChip {
                            Layout.fillWidth: true
                            label: "🌊 Ola"
                            selected: periphRoot.chargingEffect === "wave"
                            onClicked: periphRoot.saveCharging("wave")
                        }
                    }

                    // Seccion 2: Alerta de Bateria Baja
                    StyledText {
                        text: "🪫 Alerta de Batería Baja:"
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        MchoseChip {
                            Layout.fillWidth: true
                            label: "🚨 Roja"
                            selected: periphRoot.lowBatEffect === "red_breathing"
                            onClicked: periphRoot.saveLowBat("red")
                        }
                        MchoseChip {
                            Layout.fillWidth: true
                            label: "🌊 Ola"
                            selected: periphRoot.lowBatEffect === "wave"
                            onClicked: periphRoot.saveLowBat("wave")
                        }
                        MchoseChip {
                            Layout.fillWidth: true
                            label: "⚪ Ninguna"
                            selected: periphRoot.lowBatEffect === "none"
                            onClicked: periphRoot.saveLowBat("none")
                        }
                        MchoseChip {
                            Layout.fillWidth: true
                            label: "🔴 Fijo"
                            selected: periphRoot.lowBatEffect === "red_static"
                            onClicked: periphRoot.saveLowBat("static")
                        }
                    }

                    // Seccion 3: Umbral y Boton de Prueba
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        StyledText {
                            text: `📊 Umbral: <= ${periphRoot.lowBatThreshold}%`
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        RowLayout {
                            spacing: 4
                            MchoseChip {
                                label: "15%"
                                selected: periphRoot.lowBatThreshold === 15
                                onClicked: periphRoot.saveThreshold(15)
                            }
                            MchoseChip {
                                label: "20%"
                                selected: periphRoot.lowBatThreshold === 20
                                onClicked: periphRoot.saveThreshold(20)
                            }
                            MchoseChip {
                                label: "30%"
                                selected: periphRoot.lowBatThreshold === 30
                                onClicked: periphRoot.saveThreshold(30)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Boton Probar en Vivo
                        StyledRect {
                            implicitWidth: 100
                            implicitHeight: 28
                            radius: Tokens.rounding.full
                            color: Qt.alpha(Colours.palette.m3primaryContainer, 0.7)

                            StateLayer {
                                radius: Tokens.rounding.full
                                onClicked: {
                                    if (periphRoot.chargingEffect === "wave")
                                        periphRoot.previewEffect("wave");
                                    else if (periphRoot.chargingEffect === "hardware_battery")
                                        periphRoot.previewEffect("hardware");
                                    else if (periphRoot.chargingEffect === "battery_breathing")
                                        periphRoot.previewEffect("battery");
                                    else
                                        periphRoot.previewEffect("breathing");
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: "🧪 Probar"
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onPrimaryContainer
                            }
                        }
                    }
                }
            }
        }
    }

    component MchoseChip: StyledRect {
        id: chipRoot
        required property string label
        required property bool selected
        signal clicked()

        implicitHeight: 28
        radius: Tokens.rounding.small
        color: selected ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5)

        Behavior on color {
            CAnim {}
        }

        StateLayer {
            radius: Tokens.rounding.small
            onClicked: chipRoot.clicked()
        }

        StyledText {
            anchors.centerIn: parent
            text: chipRoot.label
            font: Tokens.font.label.small
            color: chipRoot.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
        }
    }

    component DeviceItem: StyledRect {
        id: devItem

        required property string name
        required property string icon
        required property int battery
        required property string status
        required property bool charging
        required property bool connected
        required property color accentColor
        property bool isClickable: false
        signal clicked()

        readonly property bool isLowBattery: connected && battery <= 20 && !charging

        implicitHeight: itemCol.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: isLowBattery ? Qt.alpha(Colours.palette.m3errorContainer, 0.4) : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

        Behavior on color {
            CAnim {}
        }

        StateLayer {
            enabled: devItem.isClickable
            radius: Tokens.rounding.large
            onClicked: devItem.clicked()
        }

        MaterialIcon {
            visible: devItem.isClickable
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            text: "tune"
            fontStyle: Tokens.font.icon.small
            color: Qt.alpha(devItem.accentColor, 0.6)
        }

        ColumnLayout {
            id: itemCol

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: devItem.charging ? "battery_charging_full" : (devItem.isLowBattery ? "battery_alert" : devItem.icon)
                    fontStyle: Tokens.font.icon.medium
                    color: devItem.connected ? (devItem.isLowBattery ? Colours.palette.m3error : (devItem.charging ? Colours.palette.m3primary : devItem.accentColor)) : Colours.palette.m3outline
                }

                StyledText {
                    text: devItem.connected ? `${devItem.battery}%` : "Off"
                    color: devItem.connected ? (devItem.isLowBattery ? Colours.palette.m3error : Colours.palette.m3onSurface) : Colours.palette.m3outline
                    font: Tokens.font.title.medium
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: devItem.name
                color: devItem.isLowBattery ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: devItem.connected ? (devItem.isLowBattery ? "¡Batería Baja!" : devItem.status) : "Desconectado"
                color: devItem.isLowBattery ? Colours.palette.m3error : (devItem.charging ? Colours.palette.m3primary : Colours.palette.m3outline)
                font: Tokens.font.label.small
            }
        }
    }

    component DesktopWidgetDeck: StyledClippingRect {
        id: deckRoot

        implicitWidth: 640
        implicitHeight: deckLayout.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: win.transparentWidgets ? "transparent" : Colours.tPalette.m3surfaceContainer

        Behavior on color {
            CAnim {}
        }

        property int currentTab: 0 // 0: Tasks, 1: Weather, 2: Hardware, 3: Focus

        // Mouse Wheel Handler to smoothly cycle tabs when hovering the deck
        MouseArea {
            anchors.fill: parent
            z: 10
            propagateComposedEvents: true
            onWheel: function(wheel) {
                if (wheel.angleDelta.y < 0) {
                    deckRoot.currentTab = (deckRoot.currentTab + 1) % 4;
                } else if (wheel.angleDelta.y > 0) {
                    deckRoot.currentTab = (deckRoot.currentTab - 1 + 4) % 4;
                }
            }
            onPressed: function(mouse) { mouse.accepted = false; }
            onReleased: function(mouse) { mouse.accepted = false; }
            onClicked: function(mouse) { mouse.accepted = false; }
        }

        Component.onCompleted: {
            if (!gtasksProc.running) gtasksProc.running = true;
            if (!weatherProc.running) weatherProc.running = true;
            if (!hwProc.running) hwProc.running = true;
        }

        // --- GOOGLE TASKS DATA ---
        property var taskItems: []
        property var pendingToggles: ({})
        property string listTitle: "Google Tasks"
        property bool isAuthenticated: false
        property bool isSyncing: false

        function toggleLocalTask(taskId) {
            let current = deckRoot.taskItems || [];
            let items = [];
            for (let i = 0; i < current.length; i++) {
                let t = Object.assign({}, current[i]);
                if (t.id === taskId) {
                    t.completed = !t.completed;
                }
                items.push(t);
            }
            deckRoot.taskItems = items;
            let q = Object.assign({}, deckRoot.pendingToggles);
            if (q[taskId]) {
                delete q[taskId];
            } else {
                q[taskId] = true;
            }
            deckRoot.pendingToggles = q;
            debouncePushTimer.restart();
        }

        Timer {
            id: debouncePushTimer
            interval: 1200
            repeat: false
            onTriggered: {
                const ids = Object.keys(deckRoot.pendingToggles);
                if (ids.length > 0) {
                    deckRoot.isSyncing = true;
                    for (let i = 0; i < ids.length; i++) {
                        Quickshell.execDetached(["/home/alberviz/.local/bin/gtasks", "--toggle", ids[i]]);
                    }
                    deckRoot.pendingToggles = ({});
                    syncCompleteTimer.start();
                }
            }
        }

        Timer {
            id: syncCompleteTimer
            interval: 1500
            repeat: false
            onTriggered: {
                deckRoot.isSyncing = false;
                if (!gtasksProc.running)
                    gtasksProc.running = true;
            }
        }

        Process {
            id: gtasksProc
            command: ["/home/alberviz/.local/bin/gtasks", "--json"]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const data = JSON.parse(text);
                        deckRoot.isAuthenticated = data.authenticated ?? false;
                        deckRoot.listTitle = data.listName ?? "Google Tasks";
                        if (Object.keys(deckRoot.pendingToggles).length === 0) {
                            deckRoot.taskItems = data.tasks ?? [];
                        }
                    } catch (e) {}
                }
            }
        }

        Timer {
            interval: 20000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                if (!gtasksProc.running && Object.keys(deckRoot.pendingToggles).length === 0)
                    gtasksProc.running = true;
            }
        }

        // --- WEATHER DATA ---
        property string weatherTemp: "23°C"
        property string weatherDesc: "Despejado"
        property string weatherCity: "Local"
        property string weatherIcon: "wb_sunny"
        property string weatherHumidity: "45%"
        property string weatherWind: "9 km/h"
        property string weatherSunrise: "07:30 AM"
        property string weatherSunset: "08:45 PM"

        Process {
            id: weatherProc
            command: ["/home/alberviz/.local/bin/desktop-deck-helper", "--weather"]
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const w = JSON.parse(text);
                        deckRoot.weatherTemp = w.temp || "22°C";
                        deckRoot.weatherDesc = w.desc || "Despejado";
                        deckRoot.weatherCity = w.city || "Local";
                        deckRoot.weatherIcon = w.icon || "wb_sunny";
                        deckRoot.weatherHumidity = w.humidity || "45%";
                        deckRoot.weatherWind = w.wind || "10 km/h";
                        deckRoot.weatherSunrise = w.sunrise || "07:30 AM";
                        deckRoot.weatherSunset = w.sunset || "08:45 PM";
                    } catch (e) {}
                }
            }
        }

        Timer {
            interval: 60000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                if (!weatherProc.running)
                    weatherProc.running = true;
            }
        }

        // --- HARDWARE DATA ---
        property int cpuPct: 0
        property int ramPct: 0
        property string ramUsed: "0.0 GB"
        property string ramTotal: "16.0 GB"
        property int gpuTemp: 0
        property int gpuUtil: 0
        property int vramPct: 0
        property string vramUsed: "0.0 GB"
        property string vramTotal: "6.0 GB"

        Process {
            id: hwProc
            command: ["/home/alberviz/.local/bin/desktop-deck-helper", "--hardware"]
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const h = JSON.parse(text);
                        deckRoot.cpuPct = h.cpu_pct ?? 0;
                        deckRoot.ramPct = h.ram_pct ?? 0;
                        deckRoot.ramUsed = h.ram_used ?? "0 GB";
                        deckRoot.ramTotal = h.ram_total ?? "16 GB";
                        deckRoot.gpuTemp = h.gpu_temp ?? 0;
                        deckRoot.gpuUtil = h.gpu_util ?? 0;
                        deckRoot.vramPct = h.vram_pct ?? 0;
                        deckRoot.vramUsed = h.vram_used ?? "0 GB";
                        deckRoot.vramTotal = h.vram_total ?? "6 GB";
                    } catch (e) {}
                }
            }
        }

        Timer {
            interval: 2000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                if (!hwProc.running)
                    hwProc.running = true;
            }
        }

        // --- FOCUS POMODORO DATA ---
        property int focusSeconds: 1500 // 25 mins
        property int focusTotal: 1500
        property bool focusRunning: false
        property bool focusIsBreak: false
        property int focusSessions: 1
        property bool focusLightActive: false

        Process {
            id: focusLightProc
            property var cmdArgs: []
            command: cmdArgs
            running: false
        }

        function setFocusLight(active) {
            deckRoot.focusLightActive = active;
            if (active) {
                focusLightProc.cmdArgs = ["/home/alberviz/.local/bin/magichome-control", "--color", "#ff9800"];
            } else {
                focusLightProc.cmdArgs = ["/usr/bin/python3", "/home/alberviz/.config/caelestia/sync-rgb.py"];
            }
            focusLightProc.running = true;
        }

        function toggleFocus() {
            deckRoot.focusRunning = !deckRoot.focusRunning;
            if (deckRoot.focusRunning && deckRoot.focusLightActive) {
                deckRoot.setFocusLight(true);
            }
        }

        function resetFocus() {
            deckRoot.focusRunning = false;
            deckRoot.focusSeconds = deckRoot.focusIsBreak ? 300 : 1500;
            deckRoot.focusTotal = deckRoot.focusSeconds;
        }

        Timer {
            id: focusTimer
            interval: 1000
            running: deckRoot.focusRunning
            repeat: true
            onTriggered: {
                if (deckRoot.focusSeconds > 0) {
                    deckRoot.focusSeconds -= 1;
                } else {
                    deckRoot.focusRunning = false;
                    deckRoot.focusIsBreak = !deckRoot.focusIsBreak;
                    deckRoot.focusSeconds = deckRoot.focusIsBreak ? 300 : 1500;
                    deckRoot.focusTotal = deckRoot.focusSeconds;
                    if (!deckRoot.focusIsBreak) deckRoot.focusSessions += 1;
                    Quickshell.execDetached(["notify-send", "Focus Timer", deckRoot.focusIsBreak ? "¡Tiempo de descanso! (5 min)" : "¡A enfocarse! (25 min)", "-i", "timer"]);
                }
            }
        }

        ColumnLayout {
            id: deckLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            // --- DECK HEADER PILL TABS ---
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                // Tab 0: Tareas
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: deckRoot.currentTab === 0 ? Colours.palette.m3primaryContainer : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

                    Behavior on color { CAnim {} }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "checklist"
                            fontStyle: Tokens.font.icon.small
                            color: deckRoot.currentTab === 0 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                        StyledText {
                            text: "Tareas"
                            color: deckRoot.currentTab === 0 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.large
                        }
                    }

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: deckRoot.currentTab = 0
                    }
                }

                // Tab 1: Clima
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: deckRoot.currentTab === 1 ? Colours.palette.m3primaryContainer : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

                    Behavior on color { CAnim {} }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "partly_cloudy_day"
                            fontStyle: Tokens.font.icon.small
                            color: deckRoot.currentTab === 1 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                        StyledText {
                            text: "Clima"
                            color: deckRoot.currentTab === 1 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.large
                        }
                    }

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: deckRoot.currentTab = 1
                    }
                }

                // Tab 2: Hardware
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: deckRoot.currentTab === 2 ? Colours.palette.m3primaryContainer : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

                    Behavior on color { CAnim {} }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "speed"
                            fontStyle: Tokens.font.icon.small
                            color: deckRoot.currentTab === 2 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                        StyledText {
                            text: "Hardware"
                            color: deckRoot.currentTab === 2 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.large
                        }
                    }

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: deckRoot.currentTab = 2
                    }
                }

                // Tab 3: Focus
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: deckRoot.currentTab === 3 ? Colours.palette.m3primaryContainer : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

                    Behavior on color { CAnim {} }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "timer"
                            fontStyle: Tokens.font.icon.small
                            color: deckRoot.currentTab === 3 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                        StyledText {
                            text: "Focus"
                            color: deckRoot.currentTab === 3 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.large
                        }
                    }

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: deckRoot.currentTab = 3
                    }
                }
            }

            // --- CARD 0: GOOGLE TASKS ---
            ColumnLayout {
                visible: deckRoot.currentTab === 0
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: deckRoot.listTitle
                        color: Colours.palette.m3primary
                        font: Tokens.font.title.small
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    StyledRect {
                        readonly property int pendingCount: (deckRoot.taskItems || []).filter(t => !t.completed).length
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primaryContainer
                        implicitWidth: pendingLabel.implicitWidth + Tokens.padding.medium
                        implicitHeight: pendingLabel.implicitHeight + Tokens.padding.extraSmall

                        StyledText {
                            id: pendingLabel
                            anchors.centerIn: parent
                            text: `${parent.pendingCount} pendientes`
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.label.small
                        }
                    }

                    StyledRect {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "refresh"
                            fontStyle: Tokens.font.icon.small
                            color: deckRoot.isSyncing ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            rotation: deckRoot.isSyncing ? 360 : 0
                            Behavior on rotation { Anim { duration: 800; loops: Animation.Infinite } }
                        }

                        StateLayer {
                            radius: Tokens.rounding.full
                            onClicked: {
                                if (!gtasksProc.running)
                                    gtasksProc.running = true;
                            }
                        }
                    }
                }

                Repeater {
                    model: (deckRoot.taskItems || []).slice(0, 4)
                    TaskRow {
                        Layout.fillWidth: true
                        onToggled: deckRoot.toggleLocalTask(modelData.id)
                    }
                }

                StyledText {
                    visible: (deckRoot.taskItems?.length ?? 0) === 0
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    Layout.bottomMargin: Tokens.spacing.small
                    text: deckRoot.isAuthenticated ? "No hay tareas pendientes ✨" : "Cargando tareas..."
                    color: Colours.palette.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    font: Tokens.font.body.medium
                }
            }

            // --- CARD 1: WEATHER & CURVE ---
            RowLayout {
                visible: deckRoot.currentTab === 1
                Layout.fillWidth: true
                spacing: Tokens.spacing.large

                // Left: Big Temp & Icon
                RowLayout {
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: deckRoot.weatherIcon
                        fontStyle: Tokens.font.icon.large
                        color: Colours.palette.m3primary
                    }

                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            text: deckRoot.weatherTemp
                            font: Tokens.font.headline.large
                            color: Colours.palette.m3onSurface
                        }
                        StyledText {
                            text: `${deckRoot.weatherDesc} • ${deckRoot.weatherCity}`
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Right: 4 Metrics Grid
                GridLayout {
                    columns: 2
                    columnSpacing: Tokens.spacing.medium
                    rowSpacing: Tokens.spacing.small

                    RowLayout {
                        spacing: Tokens.spacing.extraSmall
                        MaterialIcon { text: "water_drop"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3secondary }
                        StyledText { text: `Humedad: ${deckRoot.weatherHumidity}`; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
                    }
                    RowLayout {
                        spacing: Tokens.spacing.extraSmall
                        MaterialIcon { text: "air"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3secondary }
                        StyledText { text: `Viento: ${deckRoot.weatherWind}`; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
                    }
                    RowLayout {
                        spacing: Tokens.spacing.extraSmall
                        MaterialIcon { text: "wb_twilight"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3tertiary }
                        StyledText { text: `Amanecer: ${deckRoot.weatherSunrise}`; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
                    }
                    RowLayout {
                        spacing: Tokens.spacing.extraSmall
                        MaterialIcon { text: "nights_stay"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3tertiary }
                        StyledText { text: `Atardecer: ${deckRoot.weatherSunset}`; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
                    }
                }
            }

            // --- CARD 2: HARDWARE HUD ---
            GridLayout {
                visible: deckRoot.currentTab === 2
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Tokens.spacing.large
                rowSpacing: Tokens.spacing.small

                // CPU
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall
                    RowLayout {
                        Layout.fillWidth: true
                        MaterialIcon { text: "memory"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
                        StyledText { text: "CPU"; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
                        Item { Layout.fillWidth: true }
                        StyledText { text: `${deckRoot.cpuPct}%`; font: Tokens.font.label.medium; color: Colours.palette.m3primary }
                    }
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: 4
                        color: (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5) : Colours.palette.m3surfaceContainerHigh)
                        StyledRect {
                            width: parent.width * (deckRoot.cpuPct / 100.0)
                            height: parent.height
                            radius: 4
                            color: Colours.palette.m3primary
                            Behavior on width { Anim { duration: 300 } }
                        }
                    }
                }

                // RAM
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall
                    RowLayout {
                        Layout.fillWidth: true
                        MaterialIcon { text: "straighten"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3secondary }
                        StyledText { text: "RAM"; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
                        Item { Layout.fillWidth: true }
                        StyledText { text: `${deckRoot.ramUsed} (${deckRoot.ramPct}%)`; font: Tokens.font.label.medium; color: Colours.palette.m3secondary }
                    }
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: 4
                        color: (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5) : Colours.palette.m3surfaceContainerHigh)
                        StyledRect {
                            width: parent.width * (deckRoot.ramPct / 100.0)
                            height: parent.height
                            radius: 4
                            color: Colours.palette.m3secondary
                            Behavior on width { Anim { duration: 300 } }
                        }
                    }
                }

                // GPU
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall
                    RowLayout {
                        Layout.fillWidth: true
                        MaterialIcon { text: "videogame_asset"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3tertiary }
                        StyledText { text: "GPU (Nvidia)"; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
                        Item { Layout.fillWidth: true }
                        StyledText { text: `${deckRoot.gpuTemp}°C (${deckRoot.gpuUtil}%)`; font: Tokens.font.label.medium; color: Colours.palette.m3tertiary }
                    }
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: 4
                        color: (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5) : Colours.palette.m3surfaceContainerHigh)
                        StyledRect {
                            width: parent.width * (Math.min(100, deckRoot.gpuTemp) / 100.0)
                            height: parent.height
                            radius: 4
                            color: Colours.palette.m3tertiary
                            Behavior on width { Anim { duration: 300 } }
                        }
                    }
                }

                // VRAM
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall
                    RowLayout {
                        Layout.fillWidth: true
                        MaterialIcon { text: "layers"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
                        StyledText { text: "VRAM"; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
                        Item { Layout.fillWidth: true }
                        StyledText { text: `${deckRoot.vramUsed} (${deckRoot.vramPct}%)`; font: Tokens.font.label.medium; color: Colours.palette.m3primary }
                    }
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: 4
                        color: (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5) : Colours.palette.m3surfaceContainerHigh)
                        StyledRect {
                            width: parent.width * (deckRoot.vramPct / 100.0)
                            height: parent.height
                            radius: 4
                            color: Colours.palette.m3primary
                            Behavior on width { Anim { duration: 300 } }
                        }
                    }
                }
            }

            // --- CARD 3: FOCUS POMODORO ---
            RowLayout {
                visible: deckRoot.currentTab === 3
                Layout.fillWidth: true
                spacing: Tokens.spacing.large

                // Left: Timer Display
                ColumnLayout {
                    spacing: 0
                    StyledText {
                        readonly property int mins: Math.floor(deckRoot.focusSeconds / 60)
                        readonly property int secs: deckRoot.focusSeconds % 60
                        text: `${mins < 10 ? '0' + mins : mins}:${secs < 10 ? '0' + secs : secs}`
                        font: Tokens.font.headline.large
                        color: Colours.palette.m3primary
                    }
                    StyledText {
                        text: deckRoot.focusIsBreak ? "Descanso" : `Sesión de enfoque #${deckRoot.focusSessions}`
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                Item { Layout.fillWidth: true }

                // Right: Controls
                RowLayout {
                    spacing: Tokens.spacing.small

                    // Play / Pause
                    StyledRect {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: deckRoot.focusRunning ? "pause" : "play_arrow"
                            fontStyle: Tokens.font.icon.medium
                            color: Colours.palette.m3onPrimaryContainer
                        }
                        StateLayer {
                            radius: Tokens.rounding.full
                            onClicked: deckRoot.toggleFocus()
                        }
                    }

                    // Reset
                    StyledRect {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: Tokens.rounding.full
                        color: (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "restart_alt"
                            fontStyle: Tokens.font.icon.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }
                        StateLayer {
                            radius: Tokens.rounding.full
                            onClicked: deckRoot.resetFocus()
                        }
                    }

                    // Focus Ambient Light Toggle
                    StyledRect {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: Tokens.rounding.full
                        color: deckRoot.focusLightActive ? Colours.palette.m3tertiaryContainer : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "wb_incandescent"
                            fontStyle: Tokens.font.icon.medium
                            color: deckRoot.focusLightActive ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                        StateLayer {
                            radius: Tokens.rounding.full
                            onClicked: deckRoot.setFocusLight(!deckRoot.focusLightActive)
                        }
                    }
                }
            }

            // --- BOTTOM DECK INDICATOR DOTS ---
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.small

                Repeater {
                    model: 4
                    StyledRect {
                        required property int index

                        implicitWidth: deckRoot.currentTab === index ? 24 : 8
                        implicitHeight: 8
                        radius: 4
                        color: deckRoot.currentTab === index ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.3)

                        Behavior on implicitWidth { Anim { duration: 250 } }
                        Behavior on color { CAnim {} }

                        StateLayer {
                            radius: 4
                            onClicked: deckRoot.currentTab = parent.index
                        }
                    }
                }
            }
        }
    }

    component TaskRow: StyledRect {
        id: taskItem

        required property var modelData
        signal toggled()

        readonly property bool completed: modelData?.completed ?? false
        readonly property string titleText: modelData?.title ?? ""
        readonly property string dueText: modelData?.due ?? ""

        implicitHeight: rowContent.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.medium
        color: completed ? "transparent" : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

        Behavior on color {
            CAnim {}
        }

        StateLayer {
            radius: Tokens.rounding.medium
            onClicked: taskItem.toggled()
        }

        RowLayout {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: taskItem.completed ? "check_box" : "check_box_outline_blank"
                fontStyle: Tokens.font.icon.small
                color: taskItem.completed ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

                Behavior on color {
                    CAnim {}
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: taskItem.titleText
                color: taskItem.completed ? Colours.palette.m3outline : Colours.palette.m3onSurface
                font: Tokens.font.body.medium
                elide: Text.ElideRight
                opacity: taskItem.completed ? 0.5 : 1.0

                Behavior on opacity {
                    Anim {}
                }
                Behavior on color {
                    CAnim {}
                }
            }

            StyledRect {
                visible: taskItem.dueText !== ""
                radius: Tokens.rounding.full
                color: taskItem.completed ? Colours.palette.m3surfaceContainerLowest : Colours.palette.m3primaryContainer
                implicitWidth: dueLabel.implicitWidth + Tokens.padding.small * 2
                implicitHeight: dueLabel.implicitHeight + Tokens.padding.extraSmall
                opacity: taskItem.completed ? 0.5 : 1.0

                StyledText {
                    id: dueLabel
                    anchors.centerIn: parent
                    text: taskItem.dueText
                    color: taskItem.completed ? Colours.palette.m3outline : Colours.palette.m3onPrimaryContainer
                    font: Tokens.font.label.small
                }
            }
        }
    }

    component DesktopLedStrip: StyledClippingRect {
        id: ledRoot

        implicitWidth: 320
        implicitHeight: ledLayout.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: win.transparentWidgets ? "transparent" : Colours.tPalette.m3surfaceContainer

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
                    color: ledRoot.isPowered ? Qt.alpha(Colours.palette.m3primary, 0.18) : (win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

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
                    color: win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh

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

    component DesktopCircularMedia: Item {
        id: mediaRoot

        implicitWidth: 460
        implicitHeight: contentCol.implicitHeight

        ServiceRef {
            service: Audio.cava
        }

        readonly property var cavaVals: Audio.cava.values || []
        property var smoothedVals: []
        property var smoothedVals2: []

        FrameAnimation {
            running: true
            onTriggered: {
                const vals = mediaRoot.cavaVals || [];
                const len = 48;
                if (!mediaRoot.smoothedVals || mediaRoot.smoothedVals.length !== len) {
                    mediaRoot.smoothedVals = new Array(len).fill(0.02);
                    mediaRoot.smoothedVals2 = new Array(len).fill(0.02);
                }
                const cur1 = mediaRoot.smoothedVals.slice();
                const cur2 = mediaRoot.smoothedVals2.slice();
                for (let i = 0; i < len; i++) {
                    const ratio = (i / (len - 1)) * (vals.length - 1);
                    const idx = Math.floor(ratio);
                    const frac = ratio - idx;
                    const v1 = vals[idx] || 0.0;
                    const v2 = vals[Math.min(idx + 1, vals.length - 1)] || 0.0;
                    const target = Math.max(0.02, v1 * (1 - frac) + v2 * frac);

                    cur1[i] += (target - cur1[i]) * 0.36;
                    cur2[i] += (target - cur2[i]) * 0.20;
                }
                mediaRoot.smoothedVals = cur1;
                mediaRoot.smoothedVals2 = cur2;
                radialCanvas.requestPaint();
            }
        }

        ColumnLayout {
            id: contentCol
            anchors.centerIn: parent
            spacing: Tokens.spacing.large

            // Visualizer and Circular Cover Area
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 380
                implicitHeight: 380

                // 360° Concentric Gravitational Resonance Rings Canvas
                Canvas {
                    id: radialCanvas
                    anchors.fill: parent
                    renderTarget: Canvas.FramebufferObject

                    property real orbitPhase: 0.0

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();

                        const cx = width / 2;
                        const cy = height / 2;
                        const vals = mediaRoot.smoothedVals;
                        if (!vals || vals.length < 8) return;

                        // Calculate Frequency Band Intensities
                        let bSum = 0, mSum = 0, tSum = 0;
                        for (let i = 0; i < 8; i++) bSum += (vals[i] || 0.0);
                        for (let i = 8; i < 24; i++) mSum += (vals[i] || 0.0);
                        for (let i = 24; i < vals.length; i++) tSum += (vals[i] || 0.0);

                        const bass = Math.min(1.0, (bSum / 8) * 1.4);
                        const mid = Math.min(1.0, (mSum / 16) * 1.5);
                        const treble = Math.min(1.0, (tSum / (vals.length - 24)) * 1.8);

                        // Base cover radius = 120px
                        // Ring 1: Bass Core Gravity Well (Thick, pulsating with kick drum)
                        const r1 = 128 + bass * 18;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r1, 0, 2 * Math.PI);
                        ctx.strokeStyle = Qt.alpha(Colours.palette.m3primary, 0.75 + bass * 0.25);
                        ctx.lineWidth = 2.5 + bass * 3.5;
                        ctx.stroke();

                        // Ring 2: Mid-Range Orbit (Dashed satellite ring reacting to vocals/melody)
                        const r2 = 150 + mid * 22;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r2, 0, 2 * Math.PI);
                        ctx.setLineDash([10, 6]);
                        ctx.strokeStyle = Qt.alpha(Colours.palette.m3secondary, 0.6 + mid * 0.4);
                        ctx.lineWidth = 2.0 + mid * 1.5;
                        ctx.stroke();
                        ctx.setLineDash([]); // Reset dash

                        // Ring 3: Treble Orbit (Outer delicate harmonic resonance)
                        const r3 = 172 + treble * 26;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r3, 0, 2 * Math.PI);
                        ctx.strokeStyle = Qt.alpha(Colours.palette.m3tertiary, 0.45 + treble * 0.55);
                        ctx.lineWidth = 1.5 + treble * 1.5;
                        ctx.stroke();

                        // Ring 4: Faint Cosmic Boundary
                        const r4 = 192 + (bass * 0.5 + treble * 0.5) * 16;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r4, 0, 2 * Math.PI);
                        ctx.setLineDash([4, 8]);
                        ctx.strokeStyle = Qt.alpha(Colours.palette.m3outlineVariant, 0.25 + bass * 0.3);
                        ctx.lineWidth = 1.0;
                        ctx.stroke();
                        ctx.setLineDash([]);

                        // Orbiting Photons / Satellites
                        const t = Date.now() / 1000;
                        const ang1 = (t * 1.2) % (2 * Math.PI);
                        const ang2 = (-t * 0.8) % (2 * Math.PI);
                        const ang3 = (t * 1.6 + Math.PI) % (2 * Math.PI);

                        // Photon 1 on Ring 1
                        ctx.beginPath();
                        ctx.fillStyle = Colours.palette.m3primary;
                        ctx.arc(cx + r1 * Math.cos(ang1), cy + r1 * Math.sin(ang1), 4.0 + bass * 3, 0, 2 * Math.PI);
                        ctx.fill();

                        // Photon 2 on Ring 2
                        ctx.beginPath();
                        ctx.fillStyle = Colours.palette.m3secondary;
                        ctx.arc(cx + r2 * Math.cos(ang2), cy + r2 * Math.sin(ang2), 3.5 + mid * 2.5, 0, 2 * Math.PI);
                        ctx.fill();

                        // Photon 3 on Ring 3
                        ctx.beginPath();
                        ctx.fillStyle = Colours.palette.m3tertiary;
                        ctx.arc(cx + r3 * Math.cos(ang3), cy + r3 * Math.sin(ang3), 3.0 + treble * 2.5, 0, 2 * Math.PI);
                        ctx.fill();

                        // Cardinal Coordinate Crosshair Accents
                        const crossLen = 6 + bass * 8;
                        ctx.strokeStyle = Qt.alpha(Colours.palette.m3primary, 0.6);
                        ctx.lineWidth = 1.5;
                        const angles = [0, Math.PI / 2, Math.PI, 3 * Math.PI / 2];
                        for (let a of angles) {
                            const x0 = cx + (r1 - 4) * Math.cos(a);
                            const y0 = cy + (r1 - 4) * Math.sin(a);
                            const x1 = cx + (r1 + crossLen) * Math.cos(a);
                            const y1 = cy + (r1 + crossLen) * Math.sin(a);
                            ctx.beginPath();
                            ctx.moveTo(x0, y0);
                            ctx.lineTo(x1, y1);
                            ctx.stroke();
                        }
                    }
                }

                // Large Circular Album Cover Art (240px)
                StyledClippingRect {
                    id: coverCircle
                    anchors.centerIn: parent
                    width: 240
                    height: 240
                    radius: width / 2
                    color: Colours.palette.m3surfaceVariant
                    border.color: Qt.alpha(Colours.palette.m3primary, 0.5)
                    border.width: 3

                    // Fallback Icon when no art is available
                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "album"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.size(72).build()
                        opacity: coverFadeImg.status === Image.Null || coverFadeImg.status === Image.Error || !coverFadeImg.source ? 0.7 : 0
                        animate: true

                        Behavior on opacity {
                            Anim { type: Anim.DefaultEffects }
                        }
                    }

                    FadeImage {
                        id: coverFadeImg
                        anchors.fill: parent
                        source: Players.getArtUrl(Players.active)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    // Inner soft dark vignette
                    StyledRect {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.color: Qt.alpha("#000000", 0.35)
                        border.width: 4
                    }

                    // Click to toggle play/pause
                    StateLayer {
                        radius: coverCircle.radius
                        onClicked: Players.active?.togglePlaying()
                    }
                }
            }

            // Track Details (Centered cleanly below)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Players.active?.trackTitle ?? qsTr("Sin reproducción")
                    color: Colours.palette.m3onSurface
                    horizontalAlignment: Text.AlignHCenter
                    font: Tokens.font.headline.small
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Players.active?.trackArtist ?? qsTr("Abre Spotify o YouTube para escuchar")
                    color: Colours.palette.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }
            }
        }
    }
}
