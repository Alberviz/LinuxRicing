pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant
import "HoloPlacer.js" as HoloPlacer

// Ventana a pantalla completa en la capa Overlay para presentar los hologramas de Laura.
// Se visualiza exclusivamente en la pantalla enfocada y captura la tecla Escape para cerrar.
PanelWindow {
    id: root

    required property ShellScreen modelData
    screen: modelData

    WlrLayershell.namespace: "caelestia-holo"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    contentItem.Config.screen: screen ? screen.name : ""
    contentItem.Tokens.screen: screen ? screen.name : ""

    property bool cerrando: false

    Timer {
        id: closeTimer
        interval: 450
        repeat: false
        onTriggered: {
            root.cerrando = false;
            root.posiciones = ({});
        }
    }

    Connections {
        target: HoloState
        function onCleared(): void {
            root.cerrando = true;
            closeTimer.restart();
        }
    }

    visible: (HoloState.activo && (Hypr.focusedMonitor?.name === modelData.name)) || cerrando

    // Gestión de colocaciones (calculadas una sola vez por id de panel)
    property var posiciones: ({})
    readonly property bool hasVisores: (HoloState.paneles || []).some(p => p && p.kind === "visor")

    function getPos(panel) {
        if (!panel || !panel.id)
            return { x: 0, y: 0, w: 400, h: 300, rot: 0 };

        if (posiciones[panel.id])
            return posiciones[panel.id];

        const newPos = Object.assign({}, posiciones);
        let p;

        if (panel.kind === "lista" || panel.id === "lista") {
            const sz = HoloPlacer.size(panel, root.width, root.height);
            const lx = root.hasVisores ? Math.round(0.08 * root.width) : Math.round((root.width - sz.w) / 2);
            const ly = Math.round((root.height - sz.h) / 2);
            p = { x: lx, y: ly, w: sz.w, h: sz.h, rot: 0 };
        } else {
            const sz = HoloPlacer.size(panel, root.width, root.height);
            const ocupados = [];
            const keys = Object.keys(posiciones);
            for (let i = 0; i < keys.length; i++) {
                ocupados.push(posiciones[keys[i]]);
            }
            const pt = HoloPlacer.place(root.width, root.height, ocupados, sz.w, sz.h);
            p = { x: pt.x, y: pt.y, w: sz.w, h: sz.h, rot: pt.rot };
        }

        newPos[panel.id] = p;
        posiciones = newPos;
        return p;
    }

    // Contenedor principal con captura de foco y tecla Escape
    Item {
        id: container
        anchors.fill: parent

        focus: root.visible
        Keys.onEscapePressed: HoloState.cerrarTodo()

        // 1. Velo de oscurecimiento y ambientación
        Item {
            id: veil
            anchors.fill: parent

            // Fondo oscuro
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.62
            }

            // Resplandor que sube desde la píldora de Laura en el 45 % inferior
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * 0.45
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.alpha(Colours.palette.m3primary, 0.18)
                    }
                }
            }

            // Malla de puntos sutil en mosaico
            Image {
                anchors.fill: parent
                fillMode: Image.Tile
                source: Qt.resolvedUrl("assets/dots.png")
                opacity: 0.25
            }

            // Bloqueo de clics hacia el fondo (solo botones o Escape cierran)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {}
            }
        }

        // 2. Hilos de conexión entre lista y visores
        HoloLinks {
            id: links
            anchors.fill: parent
            holoLayer: root
        }

        // 3. Paneles holográficos
        Repeater {
            model: HoloState.paneles

            HoloPanel {
                id: panelComp

                required property var modelData

                panel: modelData
                holoLayer: root

                targetX: {
                    if (panel.kind === "lista" || panel.id === "lista") {
                        const w = root.posiciones["lista"]?.w ?? HoloPlacer.size(panel, root.width, root.height).w;
                        return root.hasVisores ? Math.round(0.08 * root.width) : Math.round((root.width - w) / 2);
                    }
                    return root.getPos(panel).x;
                }
                targetY: root.getPos(panel).y
                targetRot: root.getPos(panel).rot
            }
        }
    }
}
