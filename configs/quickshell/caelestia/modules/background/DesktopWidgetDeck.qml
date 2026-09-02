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
    id: deckRoot

    // Se propaga desde la ventana: fondos translúcidos vs. sólidos.
    property bool transparentWidgets: true

    implicitWidth: 640
    implicitHeight: deckLayout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: deckRoot.transparentWidgets ? "transparent" : Colours.tPalette.m3surfaceContainer

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

    // Forzar un refresco manual de la lista (botón de refrescar de la tarjeta).
    function refreshTasks() {
        if (!gtasksProc.running)
            gtasksProc.running = true;
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
                color: deckRoot.currentTab === 0 ? Colours.palette.m3primaryContainer : (deckRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

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
                color: deckRoot.currentTab === 1 ? Colours.palette.m3primaryContainer : (deckRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

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
                color: deckRoot.currentTab === 2 ? Colours.palette.m3primaryContainer : (deckRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

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
                color: deckRoot.currentTab === 3 ? Colours.palette.m3primaryContainer : (deckRoot.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

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
        DeckTasksCard {
            visible: deckRoot.currentTab === 0
            Layout.fillWidth: true
            deck: deckRoot
        }

        // --- CARD 1: WEATHER & CURVE ---
        DeckWeatherCard {
            visible: deckRoot.currentTab === 1
            Layout.fillWidth: true
            deck: deckRoot
        }

        // --- CARD 2: HARDWARE HUD ---
        DeckHardwareCard {
            visible: deckRoot.currentTab === 2
            Layout.fillWidth: true
            deck: deckRoot
        }

        // --- CARD 3: FOCUS POMODORO ---
        DeckFocusCard {
            visible: deckRoot.currentTab === 3
            Layout.fillWidth: true
            deck: deckRoot
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
