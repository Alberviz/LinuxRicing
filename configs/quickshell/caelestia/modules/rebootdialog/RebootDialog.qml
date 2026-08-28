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

    property bool shown

    function open(): void {
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

    Timer {
        id: unloadTimer
        interval: 250
        onTriggered: loader.activeAsync = false
    }

    Binding {
        target: ShellState
        property: "rebootMenu"
        value: scope
    }

    LazyLoader {
        id: loader

        Variants {
            model: Screens.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "reboot-dialog"

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
                    visible: Hypr.monitorFor(win.modelData) === Hypr.focusedMonitor

                    opacity: scope.shown ? 1 : 0
                    scale: scope.shown ? 1 : 0.92

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.15
                        }
                    }

                    onClose: scope.close()
                }
            }
        }
    }

    IpcHandler {
        target: "rebootMenu"

        function open(): void {
            scope.open();
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
        name: "rebootMenu"
        description: "Open the reboot selection dialog"
        onPressed: scope.toggle()
    }
}
