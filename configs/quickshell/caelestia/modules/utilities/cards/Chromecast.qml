pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.cast

// Tarjeta «Chromecast» con dos estados:
//  · Reposo: una fila compacta (dispositivo + «Elegir»); toda la tarjeta acepta archivos/URLs soltados.
//  · Reproduciendo: mini-reproductor (fotograma, título, chips, progreso, controles). Sin zona de soltar
//    visible; si se arrastra algo encima, un velo ofrece reemplazar lo que suena.
// Estado: services/Cast.qml (state.json del daemon cast-helper).
StyledRect {
    id: root

    readonly property var act: Cast.active
    readonly property var tracks: Cast.active?.tracks ?? null
    readonly property string audioLabel: {
        const t = tracks;
        if (!t)
            return "";
        const a = t.audio.find(x => x.n === t.audio_active);
        return a ? a.label : "Audio";
    }
    readonly property bool hasAct: act !== null
    readonly property bool playing: act?.state === "PLAYING" || act?.state === "BUFFERING"
    readonly property bool busy: Cast.preparing || act?.state === "BUFFERING"
    readonly property real duration: act?.duration ?? 0
    readonly property real position: act?.position ?? 0
    readonly property string deviceName: act?.device_name ?? Cast.selectedDevice?.name ?? ""
    readonly property bool mirroring: act?.mode === "mirror"
    readonly property real nonAnimHeight: (mirroring ? mirrorCol.implicitHeight : hasAct ? playerCol.implicitHeight : idleCol.implicitHeight) + Tokens.padding.large * 2

    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    color: Colours.palette.m3surfaceContainer
    clip: true

    // Sin animar la altura al crearse (el panel se construye al abrirlo): si no, la tarjeta crece desde 0
    // y empuja los quick toggles de debajo con un «pop». Solo anima los cambios posteriores (reposo ↔ reproducir).
    property bool settled: false

    Timer {
        interval: 400
        running: true
        onTriggered: root.settled = true
    }

    Behavior on implicitHeight {
        enabled: root.settled

        Anim {}
    }

    Component.onCompleted: {
        Cast.observers++;
        Cast.refresh();
        if (mirroring)
            Cast.mirrorOptions();
    }
    onMirroringChanged: if (mirroring)
        Cast.mirrorOptions()
    Component.onDestruction: Cast.observers--

    function dropTarget(drop): string {
        if (drop.hasUrls && drop.urls.length > 0)
            return Cast.normalizeTarget(drop.urls[0].toString());
        if (drop.hasText) {
            const t = Cast.normalizeTarget(drop.text);
            if (t.startsWith("http://") || t.startsWith("https://") || t.startsWith("magnet:") || t.startsWith("/"))
                return t;
        }
        return "";
    }

    function pick(): void {
        if (Cast.selectedDevice && Cast.selectedDevice.online === false) {
            Cast.cmdError = "La tele está desconectada (enciéndela primero)";
            return;
        }
        if (zenityProc.running)
            return;
        Cast.picking = true;
        zenityProc.running = true;
    }

    function pickLink(): void {
        if (Cast.selectedDevice && Cast.selectedDevice.online === false) {
            Cast.cmdError = "La tele está desconectada (enciéndela primero)";
            return;
        }
        if (zenityLinkProc.running)
            return;
        Cast.picking = true;
        zenityLinkProc.running = true;
    }

    Process {
        id: zenityLinkProc

        command: [
            "sh", "-c",
            "clip=$(wl-paste -n 2>/dev/null | head -n1); case \"$clip\" in magnet:*|http://*|https://*) ;; *) clip='' ;; esac; exec zenity --entry --title='Enviar enlace o magnet a Chromecast' --text='Pega un enlace magnet:, URL o ruta:' --entry-text=\"$clip\""
        ]

        stdout: StdioCollector {
            id: zenityLinkOut
        }

        onExited: code => {
            Cast.picking = false;
            if (code === 0) {
                const p = zenityLinkOut.text.trim().split("\n")[0].trim();
                if (p)
                    Cast.castSelected(Cast.normalizeTarget(p));
            }
        }
    }

    Process {
        id: zenityProc

        command: [
            "zenity",
            "--file-selection",
            "--title=Elegir vídeo para Chromecast",
            "--file-filter=Vídeos, torrents y música (*.mp4, *.mkv, *.torrent, ...) | *.mp4 *.m4v *.mkv *.webm *.avi *.mov *.ts *.torrent *.mp3 *.flac *.wav *.ogg *.m4a",
            "--file-filter=Todos los archivos | *"
        ]

        stdout: StdioCollector {
            id: zenityOut
        }

        onExited: code => {
            Cast.picking = false;
            if (code === 0) {
                const p = zenityOut.text.trim().split("\n")[0].trim();
                if (p)
                    Cast.castSelected(Cast.normalizeTarget(p));
            }
        }
    }

    DropArea {
        id: dropArea

        anchors.fill: parent
        keys: ["text/uri-list", "text/plain"]
        onDropped: drop => {
            if (Cast.selectedDevice && Cast.selectedDevice.online === false) {
                Cast.cmdError = "La tele está desconectada (enciéndela primero)";
                return;
            }
            const t = root.dropTarget(drop);
            if (t)
                Cast.castSelected(t);
            else
                Cast.cmdError = "Lo soltado no es un archivo ni una URL";
        }
    }

    // ───────────── Reposo ─────────────
    ColumnLayout {
        id: idleCol

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        visible: !root.hasAct
        opacity: visible ? 1 : 0

        Behavior on opacity {
            Anim {}
        }

        RowLayout {
            id: idleRow

            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            readonly property bool isOffline: Cast.selectedDevice && Cast.selectedDevice.online === false

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: idleIcon.implicitHeight + Tokens.padding.large
                radius: Tokens.rounding.full
                color: idleRow.isOffline ? Colours.tPalette.m3surfaceContainerHigh : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: idleIcon

                    anchors.centerIn: parent
                    text: idleRow.isOffline ? "tv_off" : (Cast.devices.length > 0 ? "cast" : "search")
                    color: idleRow.isOffline ? Colours.palette.m3outline : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: idleRow.isOffline
                        ? (root.deviceName ? root.deviceName + " (Sin conexión)" : "Tele desconectada")
                        : (Cast.devices.length > 0 ? "Enviar a " + root.deviceName : "Chromecast")
                    font: Tokens.font.body.medium
                    color: idleRow.isOffline ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: idleRow.isOffline
                        ? "Enciende la tele para proyectar o enviar vídeos"
                        : (Cast.devices.length > 0 ? "Arrastra un vídeo o una URL aquí" : "Buscando dispositivos…")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            IconButton {
                visible: Cast.devices.length === 0 || idleRow.isOffline
                icon: "refresh"
                type: IconButton.Text
                onClicked: Cast.scan()
            }

            IconButton {
                visible: Cast.devices.length > 0 && !idleRow.isOffline
                icon: "link"
                type: IconButton.Text
                onClicked: root.pickLink()
            }

            IconButton {
                visible: Cast.devices.length > 0 && !idleRow.isOffline
                icon: "folder_open"
                type: IconButton.Tonal
                onClicked: root.pick()
            }
        }

        // Solo si hay más de un Chromecast accesible.
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: Cast.onlineDevices.length > 1

            Repeater {
                model: Cast.onlineDevices

                StyledRect {
                    id: chip

                    required property var modelData
                    readonly property bool isOnline: modelData.online !== false
                    readonly property bool sel: Cast.selectedDevice?.uuid === modelData.uuid

                    implicitWidth: chipText.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: chipText.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: sel ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh
                    opacity: chip.isOnline ? 1.0 : 0.6

                    StateLayer {
                        color: chip.sel ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        radius: Tokens.rounding.full
                        onClicked: Cast.selectedUuid = chip.modelData.uuid
                    }

                    StyledText {
                        id: chipText

                        anchors.centerIn: parent
                        text: chip.isOnline ? chip.modelData.name : chip.modelData.name + " (offline)"
                        color: chip.sel ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }
            }
        }

        ErrorRow {}
    }

    // ───────────── Reproduciendo ─────────────
    ColumnLayout {
        id: playerCol

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        visible: root.hasAct && !root.mirroring
        opacity: visible ? 1 : 0

        Behavior on opacity {
            Anim {}
        }

        // Fotograma + título
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledClippingRect {
                implicitWidth: 112
                implicitHeight: 63
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainerHighest

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: root.act?.mode === "url" ? "smart_display" : "movie"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.large
                }

                Image {
                    id: art

                    anchors.fill: parent
                    source: root.act?.art ? "file://" + root.act.art : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: 224
                }

                // Insignia de estado sobre el fotograma
                StyledRect {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Tokens.padding.small / 2
                    implicitWidth: badgeRow.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: badgeRow.implicitHeight + Tokens.padding.small / 2
                    radius: Tokens.rounding.full
                    color: Qt.alpha(Colours.palette.m3scrim, 0.6)

                    Row {
                        id: badgeRow

                        anchors.centerIn: parent
                        spacing: 2

                        MaterialIcon {
                            text: "cast_connected"
                            color: "white"
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: root.deviceName
                            color: "white"
                            font: Tokens.font.body.small
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small / 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.act?.title || "Sin título"
                    font: Tokens.font.title.medium
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Cast.preparing ? "Preparando…" : ({
                            "PLAYING": "Reproduciendo",
                            "PAUSED": "En pausa",
                            "BUFFERING": "Cargando…",
                            "IDLE": "Detenido"
                        }[root.act?.state] ?? "")
                    color: root.playing ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            IconButton {
                Layout.alignment: Qt.AlignTop
                icon: "close"
                type: IconButton.Text
                onClicked: Cast.stop()
            }
        }

        // Chips de pistas: tocar abre el menú (subtítulos / audio) con «Desactivados»
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: subChip.visible || audChip.visible

            InfoChip {
                id: subChip

                visible: root.tracks && root.tracks.subs.length > 0
                icon: "closed_caption"
                label: root.act?.subs ?? "Sin subtítulos"
                onClicked: subMenu.expanded = true
            }

            InfoChip {
                id: audChip

                visible: root.tracks && root.tracks.audio.length > 1
                icon: "graphic_eq"
                label: root.audioLabel
                onClicked: audMenu.expanded = true
            }

            InfoChip {
                visible: !audChip.visible && root.act?.mode === "transcode"
                icon: "graphic_eq"
                label: "Audio adaptado"
            }
        }

        // Progreso
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledSlider {
                id: seekSlider

                Layout.fillWidth: true
                implicitHeight: 16
                value: root.duration > 0 ? Math.min(1, root.position / root.duration) : 0
                enabled: root.duration > 0 && !Cast.preparing
                interactionOnMove: false
                onInteraction: v => Cast.seek(v * root.duration)
            }

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    text: Cast.fmtTime(seekSlider.dragging ? seekSlider.pos * root.duration : root.position)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.duration > 0 ? "-" + Cast.fmtTime(root.duration - root.position) : ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }

        // Controles
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconButton {
                icon: "replay_10"
                type: IconButton.Text
                font: Tokens.font.icon.large
                disabled: Cast.preparing
                onClicked: Cast.seek(Math.max(0, root.position - 10))
            }

            Item {
                implicitWidth: playBtn.implicitWidth
                implicitHeight: playBtn.implicitHeight

                IconButton {
                    id: playBtn

                    anchors.centerIn: parent
                    visible: !root.busy
                    icon: root.playing ? "pause" : "play_arrow"
                    type: IconButton.Filled
                    font: Tokens.font.icon.large
                    padding: Tokens.padding.medium
                    onClicked: Cast.toggle()
                }

                LoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.busy
                    implicitSize: playBtn.implicitHeight
                }
            }

            IconButton {
                icon: "forward_30"
                type: IconButton.Text
                font: Tokens.font.icon.large
                disabled: Cast.preparing
                onClicked: Cast.seek(Math.min(root.duration, root.position + 30))
            }

            Item {
                Layout.fillWidth: true
            }

            IconButton {
                icon: (root.act?.muted ?? false) || (root.act?.volume ?? 0) === 0 ? "volume_off" : "volume_up"
                type: IconButton.Text
                onClicked: Cast.mute()
            }

            StyledSlider {
                Layout.preferredWidth: 90
                implicitHeight: 16
                value: (root.act?.volume ?? 0) / 100
                interactionOnMove: false
                onInteraction: v => Cast.setVolume(v * 100)
            }
        }

        ErrorRow {}
    }

    // ───────────── Proyectando la pantalla ─────────────
    // Distinto del mini-reproductor: no hay tiempo ni pausa; se ve qué se emite, en directo, y se cambia
    // la fuente / calidad / codificador / audio sin abrir el drawer (Super+K).
    ColumnLayout {
        id: mirrorCol

        readonly property string src: root.act?.source ?? ""
        readonly property string kind: src.includes(":") ? src.split(":")[0] : (src === "window" || src === "extend" ? src : "monitor")
        readonly property bool live: root.act?.state === "PLAYING" && !Cast.preparing
        property string pendingKind: ""
        readonly property string shownKind: pendingKind || kind
        readonly property var workspaces: Cast.options?.workspaces ?? []
        readonly property string srcIcon: ({
                monitor: "desktop_windows",
                workspace: "grid_view",
                window: "select_window",
                extend: "add_to_queue"
            })[kind] ?? "desktop_windows"
        readonly property string srcTitle: {
            if (kind === "monitor")
                return "Pantalla " + (src.split(":")[1] ?? root.act?.monitor ?? "");
            if (kind === "workspace")
                return "Escritorio " + src.split(":")[1];
            return kind === "window" ? "Una ventana" : "Escritorio extendido";
        }
        readonly property string detail: {
            if (!live)
                return Cast.preparing || root.act?.state === "BUFFERING" ? "Conectando…" : "En pausa";
            const enc = root.act?.encoder ? (root.act.encoder === "nvidia" ? "GPU" : "CPU") : "";
            const lat = root.act?.latency ? "~" + Math.round(root.act.latency * 1000) + " ms" : "";
            return [root.act?.quality, enc, lat].filter(x => x).join(" · ");
        }

        function restartWith(source: string): void {
            pendingKind = "";
            Cast.mirrorStartEx(root.act.device_uuid, {
                source: source,
                quality: root.act?.quality_mode ?? "auto",
                encoder: root.act?.encoder_mode ?? "auto",
                audio: root.act?.audio ?? true
            });
        }

        function pickKind(k: string): void {
            if (k === kind && !pendingKind)
                return;
            if (k === "workspace") {
                pendingKind = k === kind ? "" : k;       // primero elegir cuál
                return;
            }
            if (k === "monitor") {
                const m = Cast.options?.monitors?.find(x => x.focused) ?? Cast.options?.monitors?.[0];
                restartWith("monitor" + (m ? ":" + m.name : ""));
            } else {
                restartWith(k);
            }
        }

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        visible: root.mirroring
        opacity: visible ? 1 : 0
        onVisibleChanged: pendingKind = ""

        Behavior on opacity {
            Anim {}
        }

        // Cabecera: «en directo» + qué se ve + en qué tele
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledClippingRect {
                implicitWidth: 112
                implicitHeight: 63
                radius: Tokens.rounding.medium

                Rectangle {
                    anchors.fill: parent

                    gradient: Gradient {
                        orientation: Gradient.Horizontal

                        GradientStop {
                            position: 0
                            color: Colours.palette.m3primaryContainer
                        }
                        GradientStop {
                            position: 1
                            color: Colours.palette.m3tertiaryContainer
                        }
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 4
                    text: mirrorCol.srcIcon
                    fill: 1
                    color: Colours.palette.m3onPrimaryContainer
                    fontStyle: Tokens.font.icon.extraLarge
                }

                // Píldora EN VIVO
                StyledRect {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.small / 2
                    implicitWidth: liveRow.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: liveRow.implicitHeight + 2
                    radius: Tokens.rounding.full
                    color: mirrorCol.live ? Colours.palette.m3error : Qt.alpha(Colours.palette.m3scrim, 0.55)

                    Row {
                        id: liveRow

                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            id: liveDot

                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: mirrorCol.live ? Colours.palette.m3onError : "white"

                            SequentialAnimation on opacity {
                                running: mirrorCol.visible && mirrorCol.live
                                loops: Animation.Infinite
                                alwaysRunToEnd: true

                                NumberAnimation {
                                    to: 0.25
                                    duration: 700
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: 700
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                        StyledText {
                            text: mirrorCol.live ? "EN VIVO" : "CONECTANDO"
                            color: mirrorCol.live ? Colours.palette.m3onError : "white"
                            font.family: Tokens.font.label.small.family
                            font.pointSize: Tokens.font.label.small.pointSize * 0.85
                            font.weight: Font.Bold
                            font.letterSpacing: 0.6
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: mirrorCol.srcTitle
                    font: Tokens.font.title.medium
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    MaterialIcon {
                        text: "cast_connected"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "en " + root.deviceName
                        color: Colours.palette.m3primary
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: mirrorCol.detail
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            IconButton {
                Layout.alignment: Qt.AlignTop
                icon: "close"
                type: IconButton.Text
                onClicked: Cast.stop()
            }
        }

        // Fuente: grupo de botones conectados; el elegido se ensancha y muestra la etiqueta.
        Item {
            id: srcRow

            readonly property var modes: [
                ["monitor", "Pantalla", "desktop_windows"],
                ["workspace", "Escritorio", "grid_view"],
                ["window", "Ventana", "select_window"],
                ["extend", "Extender", "add_to_queue"]
            ]
            readonly property int activeIndex: {
                for (let i = 0; i < modes.length; i++) {
                    if (mirrorCol.shownKind === modes[i][0])
                        return i;
                }
                return 0;
            }
            readonly property real spacing: Tokens.spacing.small
            readonly property real inactiveWidth: 44
            readonly property real activeWidth: Math.max(80, width - (inactiveWidth * 3 + spacing * 3))

            Layout.fillWidth: true
            implicitWidth: 0
            implicitHeight: 40
            visible: Cast.options !== null

            Repeater {
                id: srcRep

                model: srcRow.modes

                StyledRect {
                    id: sb

                    required property var modelData
                    required property int index
                    readonly property bool on: srcRow.activeIndex === index

                    x: index <= srcRow.activeIndex
                        ? index * (srcRow.inactiveWidth + srcRow.spacing)
                        : (index - 1) * (srcRow.inactiveWidth + srcRow.spacing) + srcRow.activeWidth + srcRow.spacing
                    width: on ? srcRow.activeWidth : srcRow.inactiveWidth
                    height: 40
                    radius: on ? Tokens.rounding.full : Tokens.rounding.small
                    topLeftRadius: on || index === 0 ? Tokens.rounding.full : Tokens.rounding.small
                    bottomLeftRadius: topLeftRadius
                    topRightRadius: on || index === 3 ? Tokens.rounding.full : Tokens.rounding.small
                    bottomRightRadius: topRightRadius
                    color: on ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
                    clip: true

                    Behavior on x {
                        enabled: root.settled

                        Anim {
                            type: Anim.FastSpatial
                        }
                    }

                    Behavior on width {
                        enabled: root.settled

                        Anim {
                            type: Anim.FastSpatial
                        }
                    }

                    StateLayer {
                        radius: sb.radius
                        color: sb.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        disabled: Cast.preparing
                        onClicked: mirrorCol.pickKind(sb.modelData[0])
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: sb.modelData[2]
                            fill: sb.on ? 1 : 0
                            color: sb.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: sb.on && sb.width > 90
                            text: sb.modelData[1]
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.label.medium
                        }
                    }
                }
            }
        }

        // Escritorios (al elegir «Escritorio»): cambiar cuál se emite
        Flow {
            Layout.fillWidth: true
            visible: mirrorCol.shownKind === "workspace" && mirrorCol.workspaces.length > 0
            spacing: Tokens.spacing.small

            Repeater {
                model: mirrorCol.workspaces

                StyledRect {
                    id: ws

                    required property var modelData
                    readonly property bool on: mirrorCol.src === "workspace:" + modelData.id

                    implicitWidth: Math.max(40, wsl.implicitWidth + Tokens.padding.medium * 2)
                    implicitHeight: 40
                    radius: on ? Tokens.rounding.full : Tokens.rounding.medium
                    color: on ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                    StateLayer {
                        radius: ws.radius
                        disabled: ws.on || Cast.preparing
                        onClicked: mirrorCol.restartWith("workspace:" + ws.modelData.id)
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 3

                        StyledText {
                            id: wsl

                            anchors.horizontalCenter: parent.horizontalCenter
                            text: ws.modelData.name && ws.modelData.name !== String(ws.modelData.id) ? ws.modelData.name : String(ws.modelData.id)
                            font: Tokens.font.label.large
                            color: ws.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            height: 3

                            Repeater {
                                model: Math.min(4, ws.modelData.windows)

                                Rectangle {
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: ws.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }

        // Ajustes en caliente
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: liveTune.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surfaceContainerHigh

            Tuning {
                id: liveTune

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                quality: root.act?.quality_mode ?? "auto"
                encoder: root.act?.encoder_mode ?? "auto"
                audio: root.act?.audio ?? true
                onPicked: (k, v) => {
                    if (Cast.options) {
                        const o = {};
                        o[k] = v;
                        Cast.mirrorSet(o);
                    } else if (k === "audio") {
                        Cast.mirrorAudio(v);
                    }
                }
            }
        }

        // Volumen de la tele + detener
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconButton {
                icon: (root.act?.muted ?? false) || (root.act?.volume ?? 0) === 0 ? "volume_off" : "volume_up"
                type: IconButton.Text
                onClicked: Cast.mute()
            }
            StyledSlider {
                Layout.fillWidth: true
                implicitHeight: 24
                value: (root.act?.volume ?? 0) / 100
                interactionOnMove: false
                onInteraction: v => Cast.setVolume(v * 100)
            }
            TextButton {
                Layout.leftMargin: Tokens.spacing.small
                text: "Detener"
                type: TextButton.Tonal
                onClicked: Cast.stop()
            }
        }

        ErrorRow {}
    }

    // ───────────── Velo al arrastrar ─────────────
    StyledRect {
        readonly property bool isOffline: Cast.selectedDevice && Cast.selectedDevice.online === false

        anchors.fill: parent
        radius: root.radius
        color: isOffline ? Qt.alpha(Colours.palette.m3errorContainer, 0.94) : Qt.alpha(Colours.palette.m3primaryContainer, 0.94)
        border.width: 2
        border.color: isOffline ? Colours.palette.m3error : Colours.palette.m3primary
        visible: opacity > 0
        opacity: dropArea.containsDrag ? 1 : 0

        Behavior on opacity {
            Anim {}
        }

        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.parent.isOffline ? "tv_off" : "cast"
                color: parent.parent.isOffline ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimaryContainer
                fontStyle: Tokens.font.icon.large
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.parent.isOffline
                    ? "Tele desconectada (no disponible)"
                    : (root.hasAct ? "Suelta para reproducir esto en su lugar" : "Suelta para enviar a " + root.deviceName)
                color: parent.parent.isOffline ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimaryContainer
                font: Tokens.font.body.medium
            }
        }
    }

    component TrackItem: MenuItem {
        property int n
    }

    Menu {
        id: subMenu

        attachTo: subChip
        items: subVar.instances
        active: items.find(m => (m as TrackItem).n === (root.tracks?.sub_active ?? -1)) ?? null
        onItemSelected: item => Cast.setSub((item as TrackItem).n)

        Variants {
            id: subVar

            model: [
                {
                    n: -1,
                    label: "Desactivados"
                },
                ...(root.tracks?.subs ?? [])
            ]

            TrackItem {
                required property var modelData

                n: modelData.n
                text: modelData.label
                icon: modelData.n === (root.tracks?.sub_active ?? -1) ? "check" : ""
            }
        }
    }

    Menu {
        id: audMenu

        attachTo: audChip
        items: audVar.instances
        active: items.find(m => (m as TrackItem).n === (root.tracks?.audio_active ?? -1)) ?? null
        onItemSelected: item => Cast.setAudioTrack((item as TrackItem).n)

        Variants {
            id: audVar

            model: root.tracks?.audio ?? []

            TrackItem {
                required property var modelData

                n: modelData.n
                text: modelData.label
                icon: modelData.n === (root.tracks?.audio_active ?? -1) ? "check" : ""
            }
        }
    }

    component InfoChip: StyledRect {
        id: ic

        property string icon
        property string label
        signal clicked
        readonly property bool hasListeners: true

        implicitWidth: icRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: icRow.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        color: Colours.palette.m3surfaceContainerHigh

        StateLayer {
            radius: Tokens.rounding.full
            disabled: !ic.hasListeners
            onClicked: ic.clicked()
        }

        Row {
            id: icRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.small / 2

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: ic.icon
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: ic.label
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }
    }

    component ErrorRow: StyledRect {
        Layout.fillWidth: true
        visible: Cast.shownError !== ""
        implicitHeight: errLayout.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.small
        color: Qt.alpha(Colours.palette.m3errorContainer, 0.45)

        RowLayout {
            id: errLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "info"
                color: Colours.palette.m3onErrorContainer
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.fillWidth: true
                text: Cast.shownError
                color: Colours.palette.m3onErrorContainer
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }
        }
    }
}
