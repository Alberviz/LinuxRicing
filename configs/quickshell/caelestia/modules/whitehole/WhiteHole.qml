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
// Gargantua inversa, el gemelo del negro (núcleo incandescente, disco frío con Doppler, halo lensado, corrientes que salen).
// Coreografía: se abre (0,65 s), escupe la tarjeta con ondas y chispas, respira 3,5 s y colapsa con un último destello.
// La tarjeta queda aparcada bajo el borde (se apilan, máx. 5). Si no la tocas, se va con el agujero; si la tocas (ratón
// encima o arrastre) se queda y se desvanece al usarla,
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
            property real show: 0          // presencia del agujero 0..1 (se abre con rebote, colapsa hacia el borde)
            property real pulse: 0         // 1 -> 0: expulsión
            property real en: 0.35         // energía (respira mientras está abierto)
            property real closing: 0       // 1 -> 0: destello de colapso
            property real spin: 0
            property real pull: 0
            property real tsec: 0
            property bool holeOn: false
            readonly property int holdMs: 3500                                // tiempo abierto tras la última expulsión
            readonly property real u: width / 1280
            readonly property real holeR: 30 * u                              // mismo tamaño que el negro
            readonly property real holeCx: width / 2                          // el «agujero del móvil»: borde superior, centrado
            readonly property real holeCy: -(1 - show) * 1.2 * holeR          // centro EXACTAMENTE sobre el borde
            readonly property var cards: [c0, c1, c2, c3, c4]

            function fmtSize(b: real): string {
                if (b >= 1073741824)
                    return (b / 1073741824).toFixed(1).replace(".", ",") + " GB";
                if (b >= 1048576)
                    return (b / 1048576).toFixed(b >= 10485760 ? 0 : 1).replace(".", ",") + " MB";
                return Math.max(1, Math.round(b / 1024)) + " KB";
            }

            // Coreografía (mockup aprobado, variante A): se abre 0,65 s → escupe (onda, chispas) → respira holdMs →
            // se aviva 0,25 s → colapsa 0,8 s con un último destello. Si llega otra cosa mientras, la escupe y vuelve a esperar.
            function trySpit(): void {
                if (pending.length === 0 || DragWatch.dragging)   // el portal negro está en ese sitio: esperar
                    return;
                const free = cards.find(c => !c.active);
                if (!free)
                    return;
                holdTimer.stop();
                preCloseTimer.stop();
                if (!holeOn) {                        // primero se abre; escupe cuando ya está abierto (una sola espera)
                    holeOn = true;
                    openTimer.restart();
                    return;
                }
                const e = pending.shift();
                pending = pending;
                free.launch(e);
                flash();
                if (pending.length > 0)
                    spitTimer.restart();
                else
                    holdTimer.restart();
            }

            function flash(): void {
                pulseAnim.restart();
                enAnim.stop();
                en = 1;
                enAnim.to = 0.5;
                enAnim.duration = PowerSaving.active ? 0 : 1400;
                enAnim.start();
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

                interval: 900
                onTriggered: win.trySpit()
            }

            Timer {
                id: openTimer

                interval: PowerSaving.active ? 1 : 650
                onTriggered: win.trySpit()
            }

            Timer {
                id: holdTimer

                interval: win.holdMs
                onTriggered: {
                    if (win.cards.some(c => c.active && c.hovered)) {   // ratón encima: el agujero espera
                        restart();
                        return;
                    }
                    enAnim.stop();
                    enAnim.to = 0.9;
                    enAnim.duration = PowerSaving.active ? 0 : 250;
                    enAnim.start();
                    preCloseTimer.restart();
                }
            }

            Timer {
                id: preCloseTimer

                interval: PowerSaving.active ? 1 : 250
                onTriggered: {
                    win.holeOn = false;
                    collapseTimer.restart();
                    // las tarjetas que no has tocado se van con el agujero; las que has tocado se quedan (X o 60 s)
                    for (const c of win.cards)
                        if (c.active && !c.kept)
                            c.dismiss(true);
                }
            }

            Timer {
                id: collapseTimer

                interval: PowerSaving.active ? 1 : 650
                onTriggered: if (!win.holeOn)
                    collapseAnim.restart()
            }

            NumberAnimation {
                id: showAnim

                target: win
                property: "show"
                duration: PowerSaving.active ? 0 : (win.holeOn ? 650 : 800)
                easing.type: win.holeOn ? Easing.OutBack : Easing.InBack
                easing.overshoot: win.holeOn ? 1.5 : 1.7
            }
            onHoleOnChanged: {
                showAnim.stop();
                showAnim.to = holeOn ? 1 : 0;
                showAnim.start();
                enAnim.stop();
                enAnim.to = holeOn ? 0.55 : 0.3;
                enAnim.duration = PowerSaving.active ? 0 : (holeOn ? 650 : 800);
                enAnim.start();
                if (holeOn) {
                    collapseTimer.stop();
                    closing = 0;
                }
            }

            NumberAnimation {
                id: enAnim

                target: win
                property: "en"
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                id: pulseAnim

                target: win
                property: "pulse"
                from: 1
                to: 0
                duration: PowerSaving.active ? 0 : 1100
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                id: collapseAnim

                target: win
                property: "closing"
                from: 1
                to: 0
                duration: PowerSaving.active ? 0 : 450
                easing.type: Easing.OutCubic
            }

            // Giro del disco, eyección y respiración: solo mientras el agujero está presente (CLAUDE.md: running gateado)
            FrameAnimation {
                running: (win.show > 0.003 || win.closing > 0) && !PowerSaving.active
                onTriggered: {
                    const dt = Math.min(0.05, frameTime);
                    win.tsec += dt;
                    win.spin += 0.25 * (0.3 + 0.7 * win.show) * (1 + 1.4 * win.en) * dt;
                    win.pull += (0.35 + 1.5 * win.en) * (0.2 + 0.8 * win.show) * dt;
                    if (win.holeOn && !enAnim.running)
                        win.en = 0.5 + 0.06 * Math.sin(win.tsec * 2.2);
                }
            }

            ShaderEffect {
                readonly property real half: 9 * win.holeR
                x: win.holeCx - half
                y: win.holeCy - half
                width: half * 2
                height: half * 2
                // durante un arrastre el portal del móvil (Portals) pinta el agujero negro en ese sitio: no se mezclan
                visible: (win.show > 0.003 || win.closing > 0) && !DragWatch.dragging

                property vector2d size: Qt.vector2d(width, height)
                property real rad: win.holeR * (0.25 + 0.75 * Math.max(0, win.show))
                property real upx: win.u
                property real en: win.en
                property real vis: Math.min(1, Math.max(0, win.show))
                property real pulse: win.pulse
                property real spin: win.spin
                property real pull: win.pull
                property real tsec: win.tsec
                property real closing: win.closing

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
                property bool hovered: false
                property bool kept: false    // la has tocado: ya no se va con el agujero
                property var entry: null
                property real t: 0           // 0 = dentro del agujero, 1 = aparcada
                property real out: 0         // 0 -> 1: se desvanece (salida)
                readonly property real lx: win.holeCx - width / 2                   // centrada bajo el agujero
                readonly property real ly: win.holeR * 3.1 + slot * (height + 12)   // por debajo del agujero, sin taparlo
                readonly property bool isText: entry?.tipo === "texto"
                readonly property bool isImage: !isText && (entry?.mime ?? "").startsWith("image/")
                property bool recopied: false
                readonly property string fileUrl: "file://" + (entry?.ruta ?? "")

                function launch(e: var): void {
                    entry = e;
                    recopied = false;
                    hovered = false;
                    kept = false;
                    t = 0;
                    out = 0;
                    parked = false;
                    opacity = 0;
                    active = true;
                    emerge.restart();
                }
                // Salida: se encoge un poco, sube y se desvanece en su sitio (el agujero ya está cerrado)
                function dismiss(withHole: bool): void {
                    if (!active || leave.running)
                        return;
                    leaveOut.duration = PowerSaving.active ? 0 : (withHole ? 700 : 260);
                    leaveFade.duration = PowerSaving.active ? 0 : (withHole ? 650 : 240);
                    life.stop();
                    parked = false;
                    emerge.stop();
                    fadeIn.stop();
                    leave.restart();
                }

                width: 320
                height: 88
                x: lx
                y: -40 * win.u + (ly + 40 * win.u) * t - 18 * win.u * out
                visible: active
                opacity: 0
                // Sale disparada del agujero: diminuta y estirada en vertical hasta su tamaño (con un leve rebote)
                transform: Scale {
                    origin.x: card.width / 2
                    origin.y: 0
                    xScale: (0.12 + 0.88 * card.t) * (1 - 0.08 * card.out)
                    yScale: (0.25 + 0.75 * card.t) * (1 - 0.08 * card.out)
                }

                NumberAnimation {
                    id: emerge

                    target: card
                    property: "t"
                    from: 0
                    to: 1
                    duration: PowerSaving.active ? 0 : 760
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.1
                    onStarted: fadeIn.restart()
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
                ParallelAnimation {
                    id: leave

                    NumberAnimation {
                        id: leaveOut

                        target: card
                        property: "out"
                        to: 1
                        duration: PowerSaving.active ? 0 : 260
                        easing.type: Easing.InCubic
                    }
                    NumberAnimation {
                        id: leaveFade

                        target: card
                        property: "opacity"
                        to: 0
                        duration: PowerSaving.active ? 0 : 240
                        easing.type: Easing.InQuad
                    }
                    onFinished: {
                        card.active = false;
                        card.opacity = 0;
                        win.trySpit();
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
                    onTriggered: card.dismiss(false)
                }

                // Sin interacción durante ~60 s: se va sola
                Timer {
                    id: life

                    interval: 60000
                    onTriggered: card.dismiss(false)
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
                            onActiveChanged: if (active) {
                                card.kept = true;
                                life.stop();
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: card.parked
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        propagateComposedEvents: true
                        onEntered: {
                            card.hovered = true;
                            card.kept = true;
                            life.stop();
                        }
                        onExited: {
                            card.hovered = false;
                            if (card.parked)
                                life.restart();
                        }
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
                                card.dismiss(false);
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
                        onClicked: card.dismiss(false)
                    }
                }
            }
        }
    }
}
