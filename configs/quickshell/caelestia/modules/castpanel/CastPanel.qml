pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.components.misc
import qs.services

// «Proyectar» (Super+K, como Win+K): panel abajo a la derecha cuyo único objetivo es enviar la
// pantalla a una tele. Esc o clic fuera lo cierra. Atajo: global caelestia:castPanel
// (Hyprland: hl.dsp.global) o `qs -c caelestia ipc call castPanel toggle`.
Scope {
    id: scope

    property bool shown

    function open(): void {
        unloadTimer.stop();
        loader.activeAsync = true;
        shown = true;
        Cast.scan();
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

        interval: 300
        onTriggered: loader.activeAsync = false
    }

    LazyLoader {
        id: loader

        Variants {
            model: Screens.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "cast-panel"

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

                // Clic fuera = cerrar
                MouseArea {
                    anchors.fill: parent
                    onClicked: scope.close()
                }

                CastPanelContent {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 24
                    anchors.bottomMargin: 24
                    visible: Hypr.monitorFor(win.modelData) === Hypr.focusedMonitor
                    shown: scope.shown
                    onClose: scope.close()
                }
            }
        }
    }

    IpcHandler {
        function open(): void {
            scope.open();
        }
        function close(): void {
            scope.close();
        }
        function toggle(): void {
            scope.toggle();
        }

        target: "castPanel"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "castPanel"
        description: "Proyectar la pantalla en una tele (Super+K)"
        onPressed: scope.toggle()
    }
}
