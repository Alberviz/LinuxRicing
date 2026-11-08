pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services

// Tarjeta «Chromecast»: selector de dispositivo, zona de soltar archivos / URL y,
// con reproducción activa, controles (título, seek, play/pausa, stop, volumen).
// El estado viene de services/Cast.qml (state.json del daemon cast-helper).
StyledRect {
    id: root

    readonly property var act: Cast.active
    readonly property bool playing: act?.state === "PLAYING" || act?.state === "BUFFERING"
    readonly property real nonAnimHeight: layout.implicitHeight + Tokens.padding.large * 2

    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

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

    FileDialog {
        id: dialog

        title: "Elegir vídeo para Chromecast"
        filterLabel: "Vídeo"
        filters: ["mp4", "m4v", "mkv", "webm", "avi", "mov", "ts", "mp3", "flac"]
        onAccepted: path => Cast.castSelected(Cast.normalizeTarget(path))
    }

    ColumnLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Cabecera
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: icon.implicitHeight + Tokens.padding.large

                radius: Tokens.rounding.full
                color: root.act ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: "cast"
                    color: root.act ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: "Chromecast"
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Cast.preparing ? "Preparando…" : root.act ? ({
                                "PLAYING": "Reproduciendo",
                                "PAUSED": "En pausa",
                                "BUFFERING": "Cargando…",
                                "IDLE": "Inactivo"
                            }[root.act.state] ?? root.act.state) + " · " + root.act.device_name : Cast.selectedDevice ? "Sin reproducción" : "Buscando dispositivos…"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            IconButton {
                icon: "refresh"
                type: IconButton.Text
                onClicked: Cast.scan()
            }
        }

        // Selector de dispositivo
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: Cast.devices.length > 0

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

        // Zona de soltar + botón
        StyledRect {
            id: dropZone

            Layout.fillWidth: true
            implicitHeight: dropRow.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.medium
            color: dropArea.containsDrag ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHigh
            border.width: 2
            border.color: dropArea.containsDrag ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.5)

            Behavior on color {
                CAnim {}
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

            RowLayout {
                id: dropRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "upload_file"
                    color: dropArea.containsDrag ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.large
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Suelta aquí un vídeo o una URL"
                    color: dropArea.containsDrag ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }

                TextButton {
                    text: "Elegir archivo"
                    type: TextButton.Tonal
                    disabled: !Cast.selectedDevice
                    onClicked: dialog.open()
                }
            }
        }

        // Controles de reproducción
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: root.act !== null

            StyledText {
                Layout.fillWidth: true
                text: root.act?.title ?? ""
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: !!root.act?.subs
                text: "Subtítulos: " + (root.act?.subs ?? "")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    text: Cast.fmtTime(seekSlider.dragging ? seekSlider.pos * (root.act?.duration ?? 0) : (root.act?.position ?? 0))
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }

                StyledSlider {
                    id: seekSlider

                    Layout.fillWidth: true
                    implicitHeight: 14
                    value: (root.act?.duration ?? 0) > 0 ? Math.min(1, (root.act?.position ?? 0) / root.act.duration) : 0
                    enabled: (root.act?.duration ?? 0) > 0
                    interactionOnMove: false
                    onInteraction: v => Cast.seek(v * (root.act?.duration ?? 0))
                }

                StyledText {
                    text: Cast.fmtTime(root.act?.duration ?? 0)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconButton {
                    icon: root.playing ? "pause" : "play_arrow"
                    type: IconButton.Filled
                    onClicked: Cast.toggle()
                }

                IconButton {
                    icon: "stop"
                    type: IconButton.Tonal
                    onClicked: Cast.stop()
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
                    Layout.preferredWidth: 110
                    implicitHeight: 14
                    value: (root.act?.volume ?? 0) / 100
                    interactionOnMove: false
                    onInteraction: v => Cast.setVolume(v * 100)
                }
            }
        }

        // Error
        StyledRect {
            Layout.fillWidth: true
            visible: Cast.shownError !== ""
            implicitHeight: errText.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.medium
            color: Colours.palette.m3errorContainer

            StyledText {
                id: errText

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                text: Cast.shownError
                color: Colours.palette.m3onErrorContainer
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }
        }
    }
}
