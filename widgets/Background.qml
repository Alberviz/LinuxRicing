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
            id: tasksLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled
            sourceComponent: DesktopTasks {}

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

            anchors.top: tasksLoader.bottom
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

        implicitHeight: itemCol.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: win.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh

        Behavior on color {
            CAnim {}
        }

        ColumnLayout {
            id: itemCol

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: devItem.icon
                    fontStyle: Tokens.font.icon.medium
                    color: devItem.connected ? (devItem.charging ? Colours.palette.m3primary : devItem.accentColor) : Colours.palette.m3outline
                }

                StyledText {
                    text: devItem.connected ? `${devItem.battery}%` : "Off"
                    color: devItem.connected ? (devItem.battery <= 20 && !devItem.charging ? Colours.palette.m3error : Colours.palette.m3onSurface) : Colours.palette.m3outline
                    font: Tokens.font.title.medium
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: devItem.name
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: devItem.connected ? devItem.status : "Desconectado"
                color: devItem.charging ? Colours.palette.m3primary : Colours.palette.m3outline
                font: Tokens.font.label.small
            }
        }
    }

    component DesktopTasks: StyledClippingRect {
        id: tasksRoot

        implicitWidth: 320
        implicitHeight: tasksLayout.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: win.transparentWidgets ? "transparent" : Colours.tPalette.m3surfaceContainer

        Behavior on color {
            CAnim {}
        }

        property var taskItems: []
        property var pendingToggles: ({})
        property string listTitle: "Google Tasks"
        property bool isAuthenticated: false
        property bool isSyncing: false

        function toggleLocalTask(taskId) {
            let current = tasksRoot.taskItems || [];
            let items = [];
            for (let i = 0; i < current.length; i++) {
                let t = Object.assign({}, current[i]);
                if (t.id === taskId) {
                    t.completed = !t.completed;
                }
                items.push(t);
            }
            tasksRoot.taskItems = items;

            // Track queued changes
            let q = Object.assign({}, tasksRoot.pendingToggles);
            if (q[taskId]) {
                delete q[taskId];
            } else {
                q[taskId] = true;
            }
            tasksRoot.pendingToggles = q;

            // Restart debounce timer (1.2s delay before sending to Google API)
            debouncePushTimer.restart();
        }

        Timer {
            id: debouncePushTimer
            interval: 1200
            repeat: false
            onTriggered: {
                const ids = Object.keys(tasksRoot.pendingToggles);
                if (ids.length > 0) {
                    tasksRoot.isSyncing = true;
                    for (let i = 0; i < ids.length; i++) {
                        Quickshell.execDetached(["/home/alberviz/.local/bin/gtasks", "--toggle", ids[i]]);
                    }
                    tasksRoot.pendingToggles = ({});
                    syncCompleteTimer.start();
                }
            }
        }

        Timer {
            id: syncCompleteTimer
            interval: 1500
            repeat: false
            onTriggered: {
                tasksRoot.isSyncing = false;
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
                        tasksRoot.isAuthenticated = data.authenticated ?? false;
                        tasksRoot.listTitle = data.listName ?? "Google Tasks";
                        if (Object.keys(tasksRoot.pendingToggles).length === 0) {
                            tasksRoot.taskItems = data.tasks ?? [];
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
                if (!gtasksProc.running && Object.keys(tasksRoot.pendingToggles).length === 0)
                    gtasksProc.running = true;
            }
        }

        ColumnLayout {
            id: tasksLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "task_alt"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3primary
                }

                StyledText {
                    text: tasksRoot.listTitle
                    color: Colours.palette.m3primary
                    font: Tokens.font.title.small
                    Layout.fillWidth: true
                    elide: Text.ElideRight
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
                            if (!gtasksProc.running)
                                gtasksProc.running = true;
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: (gtasksProc.running || tasksRoot.isSyncing) ? "sync" : "refresh"
                        fontStyle: Tokens.font.icon.small
                        color: (gtasksProc.running || tasksRoot.isSyncing) ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

                        Behavior on color {
                            CAnim {}
                        }
                    }
                }
            }

            StyledText {
                visible: (tasksRoot.taskItems?.length ?? 0) === 0
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                Layout.bottomMargin: Tokens.spacing.small
                text: tasksRoot.isAuthenticated ? qsTr("No hay tareas pendientes ✨") : qsTr("Cargando tareas...")
                color: Colours.palette.m3onSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                font: Tokens.font.body.medium
            }

            Repeater {
                model: tasksRoot.taskItems

                TaskRow {
                    Layout.fillWidth: true
                    onToggled: tasksRoot.toggleLocalTask(modelData.id)
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
                        ledRoot.isPowered = data.is_on ?? false;
                        ledRoot.currentHex = data.color ?? "#ffffff";
                        ledRoot.isConnecting = false;
                    } catch (e) {}
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
            interval: 5000
            running: true
            repeat: true
            onTriggered: {
                if (!ledStatusProc.running && !ledRoot.isConnecting && !ledRoot.isSyncing)
                    ledStatusProc.running = true;
            }
        }

        function togglePower() {
            ledRoot.isPowered = !ledRoot.isPowered;
            ledRoot.isConnecting = true;
            Quickshell.execDetached(["/home/alberviz/.local/bin/magichome-control", "--toggle"]);
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
