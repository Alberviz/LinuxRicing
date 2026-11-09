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

// Warp — llegadas del móvil (puente de Olimpo). Lo que se envía cae por el agujero NEGRO (Portals); lo que llega sale
// por el agujero BLANCO, en el mismo sitio (borde superior, centrado), como en Outer Wilds. Shader shaders/whitehole.frag:
// núcleo incandescente, disco fino frío con Doppler, chorro hacia la pantalla y onda de destello en cada expulsión.
// Cada llegada sale despedida y queda aparcada en una tarjeta (se apilan, máx. 5); se va (cae de vuelta) al usarla,
// con la X o tras ~60 s sin interacción. Durante un arrastre (el portal negro ocupa ese sitio) las llegadas esperan.
//   archivo: clic abrir · derecho mostrar en carpeta · arrastrar a otra app
//   texto:   el puente ya lo copió al portapapeles; clic lo vuelve a copiar · arrastrar como texto
// El puente añade una línea JSON por llegada a $XDG_RUNTIME_DIR/olimpo-puente/llegadas.jsonl: archivo
// {"ruta","nombre","tamano","mime","ts"} o texto {"tipo":"texto","texto","caracteres","copiado","ts"}; `tail -F` las
// recibe (cero coste en reposo). Diseño: docs/WARP.md.
Scope {
    id: scope

    readonly property string file: `${Quickshell.env("XDG_RUNTIME_DIR")}/olimpo-puente/llegadas.jsonl`

    signal arrived(var entry)

    // Prueba sin puente: qs -c caelestia ipc call whitehole demo <ruta> · … demoTexto <texto>
    IpcHandler {
        function demoTexto(texto: string): void {
            scope.arrived({
                tipo: "texto",
                texto: texto,
                caracteres: texto.length,
                copiado: true,
                ts: Date.now() / 1000
            });
        }

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
                    if (d.ruta || (d.tipo === "texto" && typeof d.texto === "string"))
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
            property real phase: 0
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
                if (pending.length === 0 || DragWatch.dragging)   // el portal negro está en ese sitio: esperar
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

            function flash(): void {
                pulseAnim.restart();
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
                target: DragWatch

                function onDraggingChanged() {
                    if (!DragWatch.dragging)
                        spitTimer.restart();
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
            // Pulsos del chorro y giro del disco: solo mientras el agujero está presente
            NumberAnimation {
                target: win
                property: "phase"
                from: 0
                to: 1
                duration: 1800
                loops: Animation.Infinite
                running: win.show > 0.01 && !PowerSaving.active
            }

            ShaderEffect {
                readonly property real half: 9 * win.holeR
                x: win.holeCx - half
                y: win.holeCy - half
                width: half * 2
                height: half * 2
                // durante un arrastre el portal del móvil (Portals) pinta el agujero negro en ese sitio: no se mezclan
                visible: win.show > 0.01 && !DragWatch.dragging

                property vector2d size: Qt.vector2d(width, height)
                property color tint: Qt.rgba(Colours.palette.m3primary.r, Colours.palette.m3primary.g, Colours.palette.m3primary.b, 0.25)
                property real rad: win.holeR * (0.5 + 0.5 * win.show)
                property real upx: win.u
                property real en: 0.35 + 0.65 * win.pulse
                property real vis: win.show
                property real phase: win.phase
                property real pulse: win.pulse

                fragmentShader: Qt.resolvedUrl("shaders/whitehole.frag.qsb")
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
                readonly property bool isText: entry?.tipo === "texto"
                readonly property bool isImage: !isText && (entry?.mime ?? "").startsWith("image/")
                property bool recopied: false
                readonly property string fileUrl: "file://" + (entry?.ruta ?? "")

                function launch(e: var): void {
                    entry = e;
                    recopied = false;
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
                Process {
                    id: copyProc

                    command: ["wl-copy"]
                    stdinEnabled: true
                    onStarted: {
                        write(card.entry?.texto ?? "");
                        stdinEnabled = false;
                    }
                    onExited: code => {
                        stdinEnabled = true;
                        if (code === 0) {
                            card.recopied = true;
                            win.flash();
                            dismissSoon.restart();
                        }
                    }
                }
                Timer {
                    id: dismissSoon

                    interval: 900
                    onTriggered: card.dismiss()
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
                    // borde blanco-azulado: viene del agujero blanco
                    border.color: Qt.alpha(Qt.tint(Colours.palette.m3primary, Qt.rgba(0.9, 0.95, 1, 0.6)), 0.8)

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
                                    if (card.isText)
                                        return card.entry?.copiado === false && !card.recopied ? "content_paste_off" : "content_paste";
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
                            text: card.isText ? (card.recopied ? "Copiado otra vez" : card.entry?.copiado === false ? "No se pudo copiar · clic para copiar" : "Copiado al portapapeles") : (card.entry?.nombre ?? "")
                            elide: Text.ElideMiddle
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            color: Colours.palette.m3onSurface
                        }
                        Text {
                            width: parent.width
                            visible: card.isText
                            text: (card.entry?.texto ?? "").replace(/\s+/g, " ").trim()
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: "JetBrainsMono Nerd Font Mono"
                            font.pixelSize: 12
                            color: Colours.palette.m3onSurfaceVariant
                        }
                        Text {
                            width: parent.width
                            visible: !card.isText
                            text: "Desde el móvil · " + win.fmtSize(card.entry?.tamano ?? 0)
                            font.family: "JetBrainsMono Nerd Font Mono"
                            font.pixelSize: 11
                            color: Colours.palette.m3onSurfaceVariant
                        }
                        Text {
                            width: parent.width
                            text: card.isText ? "Desde el móvil · " + (card.entry?.caracteres ?? 0) + " caracteres · clic: copiar" : "clic: abrir · derecho: carpeta · arrastra"
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
                        Drag.mimeData: card.isText ? {
                            "text/plain": card.entry?.texto ?? ""
                        } : {
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
                            if (card.isText) {
                                copyProc.running = true;   // wl-copy lee el texto por stdin (nunca en la línea de órdenes)
                                return;
                            }
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
