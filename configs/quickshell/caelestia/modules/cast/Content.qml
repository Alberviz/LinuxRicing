pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Contenido del drawer «Proyectar» (ver Wrapper.qml). Sin marco propio: el fondo lo pinta el blob
// del drawer en ContentWindow; aquí solo tarjetas, como en utilities.
Item {
    id: root

    required property ScreenState screenState

    readonly property bool mirroring: Cast.mirroring
    readonly property var act: Cast.active
    property string monitor: ""
    property bool busy: false
    readonly property bool scanning: Cast.devices.length === 0
    // Qué proyectar / ajustes de la próxima proyección (los defaults vienen del backend)
    property string srcKind: "monitor"
    property string srcWorkspace: ""
    property string quality: "auto"
    property string encoder: "auto"
    property bool audioOn: true
    property bool advanced: false
    readonly property var opt: Cast.options
    readonly property var workspaces: opt?.workspaces ?? []
    readonly property string effWorkspace: workspaces.some(w => String(w.id) === srcWorkspace) ? srcWorkspace : (workspaces.length > 0 ? String(workspaces[0].id) : "")
    readonly property string sourceString: srcKind === "monitor" ? "monitor:" + effMonitor : srcKind === "workspace" ? "workspace:" + effWorkspace : srcKind
    readonly property string lastFile: `${Quickshell.env("HOME")}/.config/caelestia/cast-last-monitor`

    implicitHeight: col.implicitHeight
    focus: true

    Behavior on implicitHeight {
        Anim {}
    }

    function close(): void {
        screenState.cast = false;
    }

    Keys.onEscapePressed: root.close()
    Component.onCompleted: {
        forceActiveFocus();
        Cast.observers++;
        Cast.refresh();
        Cast.scan();
        Cast.mirrorOptions();
    }
    Component.onDestruction: Cast.observers--

    // Pantalla elegida: la última usada si existe, si no la primera
    FileView {
        id: lastView

        path: root.lastFile
        printErrors: false
        onLoaded: root.monitor = text().trim()
    }
    readonly property string effMonitor: Cast.monitors.some(m => m.name === monitor) ? monitor : (Cast.monitors[0]?.name ?? "")

    function applyDefaults(): void {
        const d = opt?.defaults;
        if (!d)
            return;
        quality = d.quality ?? quality;
        encoder = d.encoder ?? encoder;
        audioOn = d.audio ?? audioOn;
    }

    function start(dev): void {
        busy = true;
        if (effMonitor)
            lastView.setText(effMonitor);
        if (opt)
            Cast.mirrorStartEx(dev.uuid, {
                source: sourceString,
                quality: quality,
                encoder: encoder,
                audio: audioOn
            });
        else
            Cast.mirrorStart(dev.uuid, effMonitor, true);
    }

    function pickedIdle(key, value): void {
        if (key === "quality")
            quality = value;
        else if (key === "encoder")
            encoder = value;
        else
            audioOn = value;
    }

    function pickedLive(key, value): void {
        if (!opt && key === "audio") {
            Cast.mirrorAudio(value);
            return;
        }
        const o = {};
        o[key] = value;
        Cast.mirrorSet(o);
    }

    function sourceLabel(src): string {
        if (!src)
            return "";
        if (!src.includes(":") && src !== "window" && src !== "extend")
            return "Pantalla " + src;
        if (src.startsWith("monitor:"))
            return "Pantalla " + src.substring(8);
        if (src.startsWith("workspace:"))
            return "Workspace " + src.substring(10);
        return src === "window" ? "Ventana" : src === "extend" ? "Pantalla extendida" : src;
    }

    Connections {
        target: Cast

        function onOptionsChanged() {
            root.applyDefaults();
        }
        function onMirroringChanged() {
            root.busy = false;
        }
        function onCmdErrorChanged() {
            if (Cast.cmdError)
                root.busy = false;
        }
    }

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: root.mirroring ? "cast_connected" : "cast"
                color: root.mirroring ? Colours.palette.m3primary : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.large
            }
            StyledText {
                Layout.fillWidth: true
                text: "Proyectar"
                font: Tokens.font.title.small
            }
            CircularIndicator {
                visible: root.scanning || root.busy
                running: visible
                implicitSize: 22
                strokeWidth: 3
            }
        }

        // --- Proyectando
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.mirroring
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: pl.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.palette.m3primaryContainer

                ColumnLayout {
                    id: pl

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: "Proyectando en " + (root.act?.device_name ?? "")
                        color: Colours.palette.m3onPrimaryContainer
                        font: Tokens.font.body.large
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: (root.act?.state === "PLAYING" ? "" : "Conectando · ") + (root.act?.source ? root.sourceLabel(root.act.source) : "Pantalla " + (root.act?.monitor ?? ""))
                        color: Colours.palette.m3onPrimaryContainer
                        font: Tokens.font.body.small
                        opacity: 0.8
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.act?.quality !== undefined || root.act?.encoder !== undefined
                        text: [root.act?.quality, root.act?.encoder ? (root.act.encoder === "nvidia" ? "NVIDIA" : "CPU") + (root.act?.encoder_mode === "auto" ? " (auto)" : "") : ""].filter(x => x).join(" · ")
                        color: Colours.palette.m3onPrimaryContainer
                        font: Tokens.font.body.small
                        opacity: 0.8
                    }
                }
            }

            Tuning {
                Layout.fillWidth: true
                quality: root.act?.quality ?? "auto"
                encoder: root.act?.encoder_mode ?? "auto"
                audio: root.act?.audio ?? true
                onPicked: (k, v) => root.pickedLive(k, v)
            }

            TextButton {
                Layout.fillWidth: true
                text: "Desconectar"
                type: TextButton.Tonal
                onClicked: {
                    Cast.stop();
                    root.close();
                }
            }
        }

        // --- Elegir destino
        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.mirroring
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                visible: root.scanning
                text: "Buscando pantallas en la red…"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
            StyledText {
                Layout.fillWidth: true
                visible: !root.scanning && Cast.monitors.length === 0
                text: "No hay ninguna pantalla capturable (¿está encendida?)"
                color: Colours.palette.m3error
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: Cast.devices

                StyledRect {
                    id: row

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: rl.implicitHeight + Tokens.padding.large * 2
                    radius: Tokens.rounding.large
                    color: Colours.tPalette.m3surfaceContainer

                    StateLayer {
                        radius: Tokens.rounding.large
                        disabled: root.busy || Cast.monitors.length === 0
                        onClicked: root.start(row.modelData)
                    }

                    RowLayout {
                        id: rl

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "tv"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.large
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                font: Tokens.font.body.medium
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.model + " · " + row.modelData.host
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }
                        }
                        MaterialIcon {
                            text: "chevron_right"
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }

            // --- Qué proyectar
            StyledText {
                Layout.topMargin: Tokens.spacing.small
                text: "Qué proyectar"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: root.opt ? [["monitor", "Pantalla", "desktop_windows"], ["workspace", "Workspace", "grid_view"], ["window", "Ventana", "web_asset"], ["extend", "Extender", "add_to_queue"]] : [["monitor", "Pantalla", "desktop_windows"]]

                    Chip {
                        required property var modelData

                        label: modelData[1]
                        icon: modelData[2]
                        selected: root.srcKind === modelData[0]
                        onClicked: root.srcKind = modelData[0]
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                visible: root.srcKind === "monitor" && Cast.monitors.length > 1
                spacing: Tokens.spacing.small

                Repeater {
                    model: Cast.monitors

                    Chip {
                        required property var modelData

                        label: modelData.name
                        selected: root.effMonitor === modelData.name
                        onClicked: root.monitor = modelData.name
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                visible: root.srcKind === "workspace"
                spacing: Tokens.spacing.small

                Repeater {
                    model: root.workspaces

                    Chip {
                        required property var modelData

                        label: (modelData.name && modelData.name !== String(modelData.id) ? modelData.name : String(modelData.id)) + " · " + modelData.windows + (modelData.windows === 1 ? " ventana" : " ventanas")
                        selected: root.effWorkspace === String(modelData.id)
                        onClicked: root.srcWorkspace = String(modelData.id)
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.srcKind === "window" || root.srcKind === "extend"
                text: root.srcKind === "window" ? "Se abrirá el selector del sistema para elegir la ventana." : "Se crea una pantalla nueva y vacía en la tele para extender el escritorio."
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            // --- Avanzado (plegable)
            StyledRect {
                Layout.fillWidth: true
                visible: root.opt !== null
                implicitHeight: adv.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                StateLayer {
                    radius: Tokens.rounding.large
                    onClicked: root.advanced = !root.advanced
                }
                RowLayout {
                    id: adv

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large

                    StyledText {
                        Layout.fillWidth: true
                        text: "Avanzado"
                        font: Tokens.font.body.medium
                    }
                    MaterialIcon {
                        text: root.advanced ? "expand_less" : "expand_more"
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
            Tuning {
                Layout.fillWidth: true
                visible: root.opt !== null && root.advanced
                quality: root.quality
                encoder: root.encoder
                audio: root.audioOn
                onPicked: (k, v) => root.pickedIdle(k, v)
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: Cast.shownError !== ""
            text: Cast.shownError
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }
    }
}
