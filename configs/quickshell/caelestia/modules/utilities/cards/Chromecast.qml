pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services

// Tarjeta «Chromecast» con dos estados:
//  · Reposo: una fila compacta (dispositivo + «Elegir»); toda la tarjeta acepta archivos/URLs soltados.
//  · Reproduciendo: mini-reproductor (fotograma, título, chips, progreso, controles). Sin zona de soltar
//    visible; si se arrastra algo encima, un velo ofrece reemplazar lo que suena.
// Estado: services/Cast.qml (state.json del daemon cast-helper).
StyledRect {
    id: root

    readonly property var act: Cast.active
    readonly property bool hasAct: act !== null
    readonly property bool playing: act?.state === "PLAYING" || act?.state === "BUFFERING"
    readonly property bool busy: Cast.preparing || act?.state === "BUFFERING"
    readonly property real duration: act?.duration ?? 0
    readonly property real position: act?.position ?? 0
    readonly property string deviceName: act?.device_name ?? Cast.selectedDevice?.name ?? ""
    readonly property real nonAnimHeight: (hasAct ? playerCol.implicitHeight : idleCol.implicitHeight) + Tokens.padding.large * 2

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
    }
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

        visible: root.hasAct
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
                            font.pointSize: Tokens.font.body.small.pointSize
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

        // Chips de información
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: !!root.act?.subs || root.act?.mode === "transcode"

            InfoChip {
                visible: !!root.act?.subs
                icon: "closed_caption"
                label: root.act?.subs ?? ""
            }

            InfoChip {
                visible: root.act?.mode === "transcode"
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

    component InfoChip: StyledRect {
        id: ic

        property string icon
        property string label

        implicitWidth: icRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: icRow.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        color: Colours.palette.m3surfaceContainerHigh

        Row {
            id: icRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.small / 2

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: ic.icon
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.body.medium.pointSize
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
            font.pointSize: Tokens.font.body.medium.pointSize
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
