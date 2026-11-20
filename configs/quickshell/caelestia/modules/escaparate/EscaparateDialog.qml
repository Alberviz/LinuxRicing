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

    property bool shown: false

    property var items: []
    property var currentInfo: ({ "active": false })

    readonly property string helper: `${Quickshell.env("HOME")}/.local/bin/escaparate`
    readonly property string configPath: `${Quickshell.env("HOME")}/.config/caelestia/escaparate.json`
    readonly property string statePath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/" + Quickshell.env("UID")}/escaparate/state.json`

    function open(): void {
        reloadConfig();
        reloadState();
        unloadTimer.stop();
        loader.activeAsync = true;
        shown = true;
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

    function showItem(id: string): void {
        close();
        Quickshell.execDetached([scope.helper, "show", id]);
        reloadTimer.restart();
    }

    function turnOff(): void {
        close();
        Quickshell.execDetached([scope.helper, "off"]);
        reloadTimer.restart();
    }

    function reloadConfig(): void {
        configFile.reload();
    }

    function reloadState(): void {
        stateFile.reload();
    }

    Timer {
        id: unloadTimer
        interval: 250
        onTriggered: loader.activeAsync = false
    }

    Timer {
        id: reloadTimer
        interval: 500
        onTriggered: {
            scope.reloadState();
        }
    }

    FileView {
        id: configFile
        path: scope.configPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                scope.items = JSON.parse(text());
            } catch (e) {
                scope.items = [];
            }
        }
    }

    FileView {
        id: stateFile
        path: scope.statePath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                scope.currentInfo = JSON.parse(text());
            } catch (e) {
                scope.currentInfo = { "active": false };
            }
        }
        onLoadFailed: {
            scope.currentInfo = { "active": false };
        }
    }

    LazyLoader {
        id: loader

        Variants {
            model: Screens.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "escaparate-dialog"

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

                // Dimmed backdrop; click outside to dismiss
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.55)
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

                    anchors.centerIn: parent
                    visible: Hypr.monitorFor(win.modelData) === Hypr.focusedMonitor || win.modelData.name.startsWith("eDP")

                    items: scope.items
                    currentInfo: scope.currentInfo

                    opacity: scope.shown ? 1 : 0
                    scale: scope.shown ? 1 : 0.94

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.05
                        }
                    }

                    onClose: scope.close()
                    onShow: id => scope.showItem(id)
                    onOff: scope.turnOff()
                }
            }
        }
    }

    IpcHandler {
        target: "escaparate"

        function open(): void {
            scope.open();
        }

        function close(): void {
            scope.close();
        }

        function toggle(): void {
            scope.toggle();
        }

        function show(id: string): void {
            scope.showItem(id);
        }

        function off(): void {
            scope.turnOff();
        }

        function list(): string {
            return JSON.stringify(scope.items);
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "escaparate"
        description: "Open the TV escaparate dialog"
        onPressed: scope.toggle()
    }
}
