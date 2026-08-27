pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.components.misc
import qs.services

Scope {
    id: scope

    // true while the panel should be on screen; false triggers the close animation
    property bool shown
    // which tab to show (0 Inicio, 1 Dispositivos, 2 Notificaciones)
    property int startTab: 0

    function open(): void {
        unloadTimer.stop();
        loader.activeAsync = true;
        shown = true;
    }

    function openTab(i: int): void {
        startTab = i;
        open();
    }

    function close(): void {
        shown = false;
        unloadTimer.restart();
    }

    function toggle(): void {
        if (shown)
            close();
        else
            open();
    }

    // Keep the window alive through the close animation, then drop it.
    Timer {
        id: unloadTimer
        interval: 250
        onTriggered: loader.activeAsync = false
    }

    // Let the desktop widget (and anything else in-process) reach the panel.
    Binding {
        target: ShellState
        property: "rgbControl"
        value: scope
    }

    // ---- Notification flash ----------------------------------------------
    // Lives in the Scope (not the LazyLoader) so it works even if the panel
    // has never been opened. See docs/CENTRO_ILUMINACION_RGB_HANDOFF.md §Fase 4.
    property string lastFlashedId: ""

    Connections {
        target: Notifs

        function onListChanged(): void {
            if (!RgbConfig.flashEnabled || Notifs.dnd)
                return;

            const n = Notifs.list[0]; // newest notification is prepended
            if (!n || String(n.notificationId) === scope.lastFlashedId)
                return;
            scope.lastFlashedId = String(n.notificationId);

            // Ignore stale entries restored from disk on shell start.
            if (Date.now() - n.time.getTime() > 10000)
                return;

            // Never flash for our own battery / lighting notifications.
            const app = (n.appName || "").toLowerCase();
            if (app.includes("mchose") || app.includes("battery") || app.includes("iluminaci"))
                return;

            flashDebounce.restart();
        }
    }

    Timer {
        id: flashDebounce
        interval: 400
        onTriggered: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.local/bin/rgb-notify-flash",
            "--mode", RgbConfig.flashMode,
            "--pulses", String(RgbConfig.flashPulses)
        ])
    }

    LazyLoader {
        id: loader

        Variants {
            model: Screens.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "rgb-control"

                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: scope.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                mask: scope.shown ? null : empty

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Region {
                    id: empty
                }

                // Dimmed backdrop; click outside the card to dismiss.
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.5)
                    opacity: scope.shown ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: scope.close()
                    }
                }

                Content {
                    id: content

                    tab: scope.startTab
                    anchors.centerIn: parent
                    // Only render the card on the monitor Hypr currently focuses.
                    visible: Hypr.monitorFor(win.modelData) === Hypr.focusedMonitor

                    opacity: scope.shown ? 1 : 0
                    scale: scope.shown ? 1 : 0.94

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }
                    }

                    onClose: scope.close()
                }
            }
        }
    }

    IpcHandler {
        target: "rgb"

        function open(): void {
            scope.open();
        }

        function openTab(tab: int): void {
            scope.openTab(tab);
        }

        function close(): void {
            scope.close();
        }

        function toggle(): void {
            scope.toggle();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "rgbControl"
        description: "Open the lighting control center"
        onPressed: scope.toggle()
    }
}
