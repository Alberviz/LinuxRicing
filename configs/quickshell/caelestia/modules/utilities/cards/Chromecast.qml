pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
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
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    Behavior on implicitHeight {
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
            if (t.startsWith("http://") || t.startsWith("https://") || t.startsWith("/"))
                return t;
        }
        return "";
    }

    function pick(): void {
        Cast.picking = true;
        dialog.open();
    }

    FileDialog {
        id: dialog

        title: "Elegir vídeo para Chromecast"
        filterLabel: "Vídeo"
        filters: ["mp4", "m4v", "mkv", "webm", "avi", "mov", "ts", "mp3", "flac"]
        onAccepted: path => {
            Cast.picking = false;
            Cast.castSelected(Cast.normalizeTarget(path));
        }
        onRejected: Cast.picking = false
    }

    DropArea {
        id: dropArea

        anchors.fill: parent
        keys: ["text/uri-list", "text/plain"]
        onDropped: drop => {
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
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: idleIcon.implicitHeight + Tokens.padding.large
                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: idleIcon

                    anchors.centerIn: parent
                    text: Cast.devices.length > 0 ? "cast" : "search"
                    color: Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Cast.devices.length > 0 ? "Enviar a " + root.deviceName : "Chromecast"
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Cast.devices.length > 0 ? "Arrastra un vídeo o una URL aquí" : "Buscando dispositivos…"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            IconButton {
                visible: Cast.devices.length === 0
                icon: "refresh"
                type: IconButton.Text
                onClicked: Cast.scan()
            }

            IconButton {
                visible: Cast.devices.length > 0
                icon: "folder_open"
                type: IconButton.Tonal
                onClicked: root.pick()
            }
        }

        // Solo si hay más de un Chromecast.
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: Cast.devices.length > 1

            Repeater {
                model: Cast.devices

                StyledRect {
                    id: chip

                    required property var modelData
                    readonly property bool sel: Cast.selectedDevice?.uuid === modelData.uuid

                    implicitWidth: chipText.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: chipText.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: sel ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh

                    StateLayer {
                        color: chip.sel ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        radius: Tokens.rounding.full
                        onClicked: Cast.selectedUuid = chip.modelData.uuid
                    }

                    StyledText {
                        id: chipText

                        anchors.centerIn: parent
                        text: chip.modelData.name
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
        // OJO: Item y no Row. Con un Row (posicionador) el ancho de los hijos dependía del ancho del Row y el del
        // Row de los hijos: con la columna oculta (sin Layout que fije el ancho) el polish no convergía y el shell
        // se quedaba al 100 % de CPU al abrir el panel. Aquí el ancho lo fija SOLO el Layout y la x se calcula a mano.
        Item {
            id: srcRow

            readonly property real spacing: 3
            readonly property real avail: Math.max(0, width - spacing * 3)
            // Suma de los `grow` (animados); no depende de ninguna geometría
            readonly property real totalGrow: {
                let t = 0;
                for (let i = 0; i < srcRep.count; i++) {
                    const it = srcRep.itemAt(i);
                    t += it ? it.grow : 1;
                }
                return t > 0 ? t : 1;
            }
            function growBefore(n: int): real {
                let t = 0;
                for (let i = 0; i < n; i++) {
                    const it = srcRep.itemAt(i);
                    t += it ? it.grow : 1;
                }
                return t;
            }

            Layout.fillWidth: true
            implicitWidth: 0
            implicitHeight: 40
            visible: Cast.options !== null

            Repeater {
                id: srcRep

                model: [["monitor", "Pantalla", "desktop_windows"], ["workspace", "Escritorio", "grid_view"], ["window", "Ventana", "select_window"], ["extend", "Extender", "add_to_queue"]]

                StyledRect {
                    id: sb

                    required property var modelData
                    required property int index
                    readonly property bool on: mirrorCol.shownKind === modelData[0]
                    property real grow: on ? 3.4 : 1

                    x: srcRow.avail * srcRow.growBefore(index) / srcRow.totalGrow + srcRow.spacing * index
                    width: srcRow.avail * grow / srcRow.totalGrow
                    height: 40
                    radius: on ? Tokens.rounding.full : Tokens.rounding.small
                    topLeftRadius: on || index === 0 ? Tokens.rounding.full : Tokens.rounding.small
                    bottomLeftRadius: topLeftRadius
                    topRightRadius: on || index === 3 ? Tokens.rounding.full : Tokens.rounding.small
                    bottomRightRadius: topRightRadius
                    color: on ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                    Behavior on grow {
                        Anim {
                            type: Anim.FastSpatial
                        }
                    }

                    StateLayer {
                        radius: Tokens.rounding.full
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
                            visible: sb.on && sb.width > 100
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
                icon: (root.act?.muted ?? false) || (root.act?.volume ?? 0) === 0 ? "volume_off" : "tv"
                type: IconButton.Text
                onClicked: Cast.mute()
            }
            StyledSlider {
                Layout.fillWidth: true
                implicitHeight: 16
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
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(Colours.palette.m3primaryContainer, 0.94)
        border.width: 2
        border.color: Colours.palette.m3primary
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
                text: "cast"
                color: Colours.palette.m3onPrimaryContainer
                fontStyle: Tokens.font.icon.large
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hasAct ? "Suelta para reproducir esto en su lugar" : "Suelta para enviar a " + root.deviceName
                color: Colours.palette.m3onPrimaryContainer
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

    component ErrorRow: RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        visible: Cast.shownError !== ""

        MaterialIcon {
            Layout.alignment: Qt.AlignTop
            text: "error"
            color: Colours.palette.m3error
            fontStyle: Tokens.font.icon.small
        }

        StyledText {
            Layout.fillWidth: true
            text: Cast.shownError
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }
    }
}
