pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

// Portales de arrastre: al arrastrar un archivo (lo detecta `drag-watch`, ver DragWatch.qml)
// aparecen dos agujeros negros en los bordes: DERECHO -> Chromecast (Cast), SUPERIOR -> móvil
// vía Olimpo (`olimpo enviar`). Fuera del arrastre: ventana sin input, nada visible, ningún
// temporizador ni animación en marcha. Wayland solo entrega el DnD a la superficie bajo el
// cursor, por eso las bandas de input (~140 px) existen únicamente mientras se arrastra.
Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        readonly property bool busy: pRight.phase !== "idle" || pTop.phase !== "idle"
        readonly property bool active: DragWatch.dragging || grace.running || busy
        // Cursor en coordenadas locales de esta pantalla (el de drag-watch es global).
        readonly property real lx: DragWatch.cx - screen.x
        readonly property real ly: DragWatch.cy - screen.y
        readonly property bool here: lx >= 0 && ly >= 0 && lx <= width && ly <= height
        readonly property real band: 140
        property string olimpo: ""
        property string dropTarget: ""

        function prox(px: real, py: real): real {
            if (!here || !DragWatch.dragging)
                return 0;
            return Math.max(0, Math.min(1, 1 - Math.hypot(lx - px, ly - py) / 520));
        }

        function fall(portal, fromX: real, fromY: real): void {
            icon.x = fromX;
            icon.y = fromY;
            icon.scale = 1;
            icon.rotation = 0;
            icon.opacity = 1;
            icon.tx = portal.cx;
            icon.ty = portal.cy;
            fallAnim.restart();
        }

        function finish(portal, ok: bool, msg: string): void {
            portal.phase = ok ? "ok" : "error";
            portal.status = msg;
            retract.restart();
        }

        function sendTele(t: string): void {
            pRight.phase = "sending";
            pRight.status = "Enviando a la tele…";
            if (!Cast.selectedDevice) {
                finish(pRight, false, "Sin Chromecast disponible");
                return;
            }
            Cast.cmdError = "";
            Cast.run(["cast", Cast.selectedDevice.uuid, t], code => {
                win.finish(pRight, code === 0 && !Cast.cmdError, code === 0 && !Cast.cmdError ? "Enviado a la tele" : (Cast.cmdError || "Error al enviar"));
            });
        }

        function sendMovil(t: string): void {
            if (!olimpo) {
                pTop.phase = "unavail";
                pTop.status = "Envío al móvil aún no disponible";
                retract.restart();
                return;
            }
            pTop.phase = "sending";
            pTop.status = "Enviando al móvil…";
            olimpoProc.command = [olimpo, "enviar", t];
            olimpoProc.running = true;
        }

        screen: modelData
        name: "portals"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        mask: Region {
            Region {
                item: rBand
            }
            Region {
                item: tBand
            }
        }

        onActiveChanged: {
            if (active && !olimpoCheck.running && olimpo === "")
                olimpoCheck.running = true;
        }

        Connections {
            target: DragWatch

            function onDraggingChanged() {
                if (!DragWatch.dragging && !win.busy)
                    grace.restart();
            }
        }

        // Margen tras soltar: el fin del arrastre (evdev) puede llegar antes que el drop.
        Timer {
            id: grace

            interval: 700
        }

        Timer {
            id: retract

            interval: 2200
            onTriggered: {
                pRight.phase = "idle";
                pTop.phase = "idle";
            }
        }

        // ¿Existe la CLI de Olimpo? Solo se comprueba al empezar un arrastre.
        Process {
            id: olimpoCheck

            command: ["sh", "-c", "for p in \"$HOME/proyectos/olimpo/cli/olimpo\" \"$HOME/.local/bin/olimpo\"; do [ -x \"$p\" ] && echo \"$p\" && exit; done"]
            stdout: StdioCollector {
                onStreamFinished: win.olimpo = text.trim()
            }
        }

        Process {
            id: olimpoProc

            stdout: StdioCollector {
                id: olimpoOut
            }
            onExited: code => {
                let ok = false, msg = "";
                try {
                    const r = JSON.parse(olimpoOut.text.trim().split("\n").pop());
                    ok = r.ok === true;
                    msg = ok ? "Enviado al móvil" : (r.error ?? "Error al enviar");
                } catch (e) {
                    msg = "Olimpo no responde";
                }
                win.finish(pTop, ok, msg);
            }
        }

        Item {
            anchors.fill: parent
            visible: win.active

            // Bandas de input (y de drop) reales; vacías si no hay arrastre.
            Item {
                id: rBand

                anchors.right: parent.right
                y: parent.height * 0.25
                width: win.active ? win.band : 0
                height: win.active ? parent.height * 0.5 : 0

                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list", "text/plain"]
                    onDropped: drop => {
                        const t = win.targetOf(drop);
                        if (!t || pRight.phase !== "idle") {
                            return;
                        }
                        win.fall(pRight, win.lx, win.ly);
                        win.sendTele(t);
                    }
                }
            }

            Item {
                id: tBand

                anchors.top: parent.top
                x: parent.width * 0.3
                width: win.active ? parent.width * 0.4 : 0
                height: win.active ? win.band : 0

                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list", "text/plain"]
                    onDropped: drop => {
                        const t = win.targetOf(drop);
                        if (!t || pTop.phase !== "idle") {
                            return;
                        }
                        win.fall(pTop, win.lx, win.ly);
                        win.sendMovil(t);
                    }
                }
            }

            Portal {
                id: pRight

                anchors.fill: parent
                edge: "right"
                winW: win.width
                winH: win.height
                t: win.prox(win.width, win.height / 2)
                hot: DragWatch.dragging && win.here && win.lx > win.width - win.band && win.ly > win.height * 0.25 && win.ly < win.height * 0.75
                label: Cast.selectedDevice ? "Tele · " + Cast.selectedDevice.name : "Tele · sin Chromecast"
                visible: pTop.phase === "idle" || pRight.phase !== "idle"
            }

            Portal {
                id: pTop

                anchors.fill: parent
                edge: "top"
                winW: win.width
                winH: win.height
                t: win.prox(win.width / 2, 0)
                hot: DragWatch.dragging && win.here && win.ly < win.band && win.lx > win.width * 0.3 && win.lx < win.width * 0.7
                label: win.olimpo ? "Móvil" : "Móvil · no disponible"
                visible: pRight.phase === "idle" || pTop.phase !== "idle"
            }

            // Archivo cayendo en espiral hacia el agujero
            MaterialIcon {
                id: icon

                property real tx
                property real ty

                text: "description"
                color: Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.large
                opacity: 0
            }

            ParallelAnimation {
                id: fallAnim

                Anim {
                    target: icon
                    property: "x"
                    to: icon.tx
                    type: Anim.Emphasized
                }
                Anim {
                    target: icon
                    property: "y"
                    to: icon.ty
                    type: Anim.Emphasized
                }
                Anim {
                    target: icon
                    property: "rotation"
                    to: 540
                    type: Anim.Emphasized
                }
                Anim {
                    target: icon
                    property: "scale"
                    to: 0
                    type: Anim.Emphasized
                }
            }
        }

        function targetOf(drop): string {
            if (drop.hasUrls && drop.urls.length > 0)
                return Cast.normalizeTarget(drop.urls[0].toString());
            if (drop.hasText)
                return Cast.normalizeTarget(drop.text);
            return "";
        }
    }
}
