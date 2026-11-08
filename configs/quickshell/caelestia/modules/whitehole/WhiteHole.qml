pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Llegadas del móvil (puente de Olimpo): el MISMO agujero negro de los portales (variante B, clavado en
// el borde superior (agujero del móvil); shader ../portals/shaders/portal.frag) se abre y el archivo emerge del horizonte y se
// queda aparcado en una tarjeta junto al agujero (se apilan mientras el agujero sigue abierto en latente).
// Se va (cae de vuelta al agujero y este se retrae) al abrirlo, con la X o tras ~60 s sin interacción.
// Clic: abrir · botón derecho: mostrar en carpeta · arrastrar la tarjeta: soltar en otra app.
// El puente añade una línea JSON por archivo a $XDG_RUNTIME_DIR/olimpo-puente/llegadas.jsonl
// ({"ruta","nombre","tamano","mime","ts"}); `tail -F` las recibe (cero coste en reposo).
Scope {
    id: scope

    readonly property string file: `${Quickshell.env("XDG_RUNTIME_DIR")}/olimpo-puente/llegadas.jsonl`

    signal arrived(var entry)

    // Prueba sin puente: qs -c caelestia ipc call whitehole demo <ruta>
    IpcHandler {
        function demo(path: string): void {
            const name = path.split("/").pop();
            scope.arrived({
                ruta: path,
                nombre: name,
                tamano: 1234567,
                mime: name.match(/\.(png|jpe?g|webp|gif)$/i) ? "image/" + name.split(".").pop() : "application/octet-stream",
                ts: Date.now() / 1000
            });
        }

        target: "whitehole"
    }

    Process {
        command: ["tail", "-n", "0", "-F", scope.file]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    if (d.ruta)
                        scope.arrived(d);
                } catch (e) {}
            }
        }
    }

    Variants {
        model: Screens.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            property var pending: []
            property real show: 0          // presencia del agujero 0..1 (entra con muelle, sale acelerando)
            property real spin: 0
            property real pull: 0
            property real pulse: 0
            property bool holeOn: false
            readonly property real u: width / 1280
            readonly property real holeR: 46 * u
            readonly property real holeCx: width / 2                          // el «agujero del móvil»: borde superior, centrado
            readonly property real holeCy: -(1 - show) * 1.4 * holeR          // centro EXACTAMENTE sobre el borde
            readonly property var cards: [c0, c1, c2, c3, c4]

            function fmtSize(b: real): string {
                if (b >= 1073741824)
                    return (b / 1073741824).toFixed(1).replace(".", ",") + " GB";
                if (b >= 1048576)
                    return (b / 1048576).toFixed(b >= 10485760 ? 0 : 1).replace(".", ",") + " MB";
                return Math.max(1, Math.round(b / 1024)) + " KB";
            }

            function trySpit(): void {
                if (pending.length === 0)
                    return;
                const free = cards.find(c => !c.active);
                if (!free)
                    return;
                const e = pending.shift();
                pending = pending;
                holeOn = true;
                closeTimer.stop();
                free.launch(e);
                pulseAnim.restart();
                if (pending.length > 0)
                    spitTimer.start();
            }

            // Si no queda ninguna tarjeta ni pendiente, el agujero se retrae
            function checkEmpty(): void {
                if (pending.length === 0 && !cards.some(c => c.active))
                    closeTimer.restart();
            }

            screen: modelData
            name: "arrivals"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            mask: Region {
            Region {
                item: c0
            }
            Region {
                item: c1
            }
            Region {
                item: c2
            }
            Region {
                item: c3
            }
            Region {
                item: c4
            }
            }

            Connections {
                target: scope

                function onArrived(entry) {
                    win.pending.push(entry);
                    if (!spitTimer.running)
                        win.trySpit();
                }
            }

            Timer {
                id: spitTimer

                interval: 650
                onTriggered: win.trySpit()
            }

            Timer {
                id: closeTimer

                interval: 500
                onTriggered: win.holeOn = false
            }

            // Entrada con muelle; salida acelerando (~380 ms), igual que los portales
            NumberAnimation {
                id: showAnim

                target: win
                property: "show"
                duration: PowerSaving.active ? 0 : (win.holeOn ? 420 : 380)
                easing.type: win.holeOn ? Easing.OutCubic : Easing.InCubic
            }
            onHoleOnChanged: {
                showAnim.stop();
                showAnim.to = holeOn ? 1 : 0;
                showAnim.start();
            }

            NumberAnimation {
                id: pulseAnim

                target: win
                property: "pulse"
                from: 1
                to: 0
                duration: PowerSaving.active ? 0 : 520
                easing.type: Easing.OutCubic
            }
            // Giro del disco y succión: solo corren mientras el agujero está presente
            NumberAnimation {
                target: win
                property: "spin"
                from: 0
                to: 6.2831853
                duration: 14000
                loops: Animation.Infinite
                running: win.show > 0.01 && !PowerSaving.active
            }
            NumberAnimation {
                target: win
                property: "pull"
                from: 0
                to: 40
                duration: 40000
                loops: Animation.Infinite
                running: win.show > 0.01 && !PowerSaving.active
            }

            ShaderEffect {
                readonly property real half: 7.5 * win.holeR
                x: win.holeCx - half
                y: win.holeCy - half
                width: half * 2
                height: half * 2
                // durante un arrastre el portal del móvil (Portals) pinta ese mismo agujero: no se duplica
                visible: win.show > 0.01 && !DragWatch.dragging

                property vector2d size: Qt.vector2d(width, height)
                property vector2d outward: Qt.vector2d(0, -1)
                property color tint: Qt.rgba(Colours.palette.m3primary.r, Colours.palette.m3primary.g, Colours.palette.m3primary.b, 0.18)
                property real rad: win.holeR
                property real upx: win.u
                property real en: 0.45 + 0.3 * win.pulse
                property real vis: win.show
                property real armed: win.pulse > 0.2 ? 1 : 0
                property real pulse: win.pulse
                property real spin: win.spin
                property real pull: win.pull

                fragmentShader: Qt.resolvedUrl("../portals/shaders/portal.frag.qsb")
            }

            Card {
                id: c0

                slot: 0
                win: win
            }
            Card {
                id: c1

                slot: 1
                win: win
            }
            Card {
                id: c2

                slot: 2
                win: win
            }
            Card {
                id: c3

                slot: 3
                win: win
            }
            Card {
                id: c4

                slot: 4
                win: win
            }

            component Card: Item {
                id: card

                required property int slot
                required property var win
                property bool active: false
                property bool parked: false
                property var entry: null
                property real t: 0           // 0 = dentro del agujero, 1 = aparcada
                readonly property real lx: win.width / 2 - width - 24 * win.u       // a la izquierda del eje: el HUD del portal queda a la derecha
                readonly property real ly: win.holeR * 1.9 + slot * (height + 12)
                readonly property bool isImage: (entry?.mime ?? "").startsWith("image/")
                readonly property string fileUrl: "file://" + (entry?.ruta ?? "")

                function launch(e: var): void {
                    entry = e;
                    t = 0;
                    parked = false;
                    opacity = 0;
                    active = true;
                    emerge.restart();
                }
                // Vuelve a caer al agujero
                function dismiss(): void {
                    life.stop();
                    parked = false;
                    emerge.stop();
                    back.restart();
                }

                width: 320
                height: 88
                x: win.holeCx - width / 2 + (lx - (win.holeCx - width / 2)) * t
                y: win.holeCy - height / 2 + (ly - (win.holeCy - height / 2)) * t
                visible: active
                opacity: 0
                // Emerge del horizonte: pequeña y estirada hasta su tamaño
                transform: Scale {
                    origin.x: card.width
                    origin.y: card.height / 2
                    xScale: 0.15 + 0.85 * Math.min(1, card.t * 1.15)
                    yScale: 0.08 + 0.92 * card.t
                }

                NumberAnimation {
                    id: emerge

                    target: card
                    property: "t"
                    from: 0
                    to: 1
                    duration: PowerSaving.active ? 0 : 750
                    easing.type: Easing.OutCubic
                    onStarted: {
                        fadeIn.restart();
                        win.pulse = 1;
                    }
                    onFinished: {
                        card.parked = true;
                        life.restart();
                    }
                }
                NumberAnimation {
                    id: fadeIn

                    target: card
                    property: "opacity"
                    to: 1
                    duration: 220
                }
                NumberAnimation {
                    id: back

                    target: card
                    property: "t"
                    to: 0
                    duration: PowerSaving.active ? 0 : 450
                    easing.type: Easing.InCubic
                    onFinished: {
                        card.active = false;
                        card.opacity = 0;
                        win.trySpit();
                        win.checkEmpty();
                    }
                }
                // Sin interacción durante ~60 s: se va sola
                Timer {
                    id: life

                    interval: 60000
                    onTriggered: card.dismiss()
                }

                StyledRect {
                    id: body

                    anchors.fill: parent
                    radius: Tokens.rounding.large
                    color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.96)
                    border.width: 1.5
                    border.color: Qt.alpha(Colours.palette.m3primary, 0.7)

                    Item {
                        id: thumbBox

                        x: 6
                        y: 6
                        width: parent.height - 12
                        height: width

                        Image {
                            anchors.fill: parent
                            visible: card.isImage && status === Image.Ready
                            source: card.isImage ? card.fileUrl : ""
                            sourceSize: Qt.size(256, 256)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        StyledRect {
                            anchors.fill: parent
                            visible: !card.isImage
                            radius: Tokens.rounding.medium
                            color: Colours.palette.m3secondaryContainer

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: {
                                    const m = card.entry?.mime ?? "";
                                    if (m.startsWith("video/"))
                                        return "movie";
                                    if (m.startsWith("audio/"))
                                        return "music_note";
                                    if (m.includes("pdf"))
                                        return "picture_as_pdf";
                                    if (m.includes("zip") || m.includes("compressed"))
                                        return "folder_zip";
                                    return "description";
                                }
                                color: Colours.palette.m3onSecondaryContainer
                                fontStyle: Tokens.font.icon.extraLarge
                            }
                        }
                    }

                    Column {
                        anchors.left: thumbBox.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 36
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: card.entry?.nombre ?? ""
                            elide: Text.ElideMiddle
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            color: Colours.palette.m3onSurface
                        }
                        Text {
                            width: parent.width
                            text: "Desde el móvil · " + win.fmtSize(card.entry?.tamano ?? 0)
                            font.family: "JetBrainsMono Nerd Font Mono"
                            font.pixelSize: 11
                            color: Colours.palette.m3onSurfaceVariant
                        }
                        Text {
                            width: parent.width
                            text: "clic: abrir · derecho: carpeta · arrastra"
                            font.pixelSize: 11
                            color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.7)
                        }
                    }

                    // Arrastrar la tarjeta a otra aplicación (text/uri-list)
                    Item {
                        id: dragProxy

                        anchors.fill: parent
                        Drag.dragType: Drag.Automatic
                        Drag.supportedActions: Qt.CopyAction
                        Drag.mimeData: {
                            "text/uri-list": card.fileUrl + "\r\n",
                            "text/plain": card.entry?.ruta ?? ""
                        }
                        Drag.active: dragHandler.active

                        DragHandler {
                            id: dragHandler

                            target: null
                            enabled: card.parked
                            onActiveChanged: if (active)
                                life.stop()
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: card.parked
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        propagateComposedEvents: true
                        onEntered: life.stop()
                        onExited: if (card.parked)
                            life.restart()
                        onClicked: ev => {
                            const path = card.entry.ruta;
                            if (ev.button === Qt.RightButton) {
                                Quickshell.execDetached(["sh", "-c", "dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:\"file://$1\" string:\"\" >/dev/null 2>&1 || xdg-open \"$(dirname \"$1\")\"", "sh", path]);
                            } else {
                                Quickshell.execDetached(["xdg-open", path]);
                                card.dismiss();
                            }
                        }
                    }

                    IconButton {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 2
                        icon: "close"
                        type: IconButton.Text
                        visible: card.parked
                        onClicked: card.dismiss()
                    }
                }
            }
        }
    }
}
