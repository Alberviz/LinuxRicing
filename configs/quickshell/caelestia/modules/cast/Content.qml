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
    readonly property var availableMonitors: (Cast.monitors && Cast.monitors.length > 0) ? Cast.monitors : (opt?.monitors ?? [])
    readonly property string effMonitor: availableMonitors.some(m => m.name === monitor) ? monitor : (availableMonitors[0]?.name ?? "")

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

    readonly property string summary: {
        const q = quality === "auto" ? "Calidad auto" : quality;
        const e = encoder === "auto" ? (opt?.encoder_auto === "nvidia" ? "GPU (auto)" : "CPU (auto)") : encoder === "nvidia" ? "GPU" : "CPU";
        return [q, e, audioOn ? "con audio" : "sin audio"].join(" · ");
    }

    function sourceLabel(src): string {
        if (!src)
            return "";
        if (!src.includes(":") && src !== "window" && src !== "extend")
            return "Pantalla " + src;
        if (src.startsWith("monitor:"))
            return "Pantalla " + src.substring(8);
        if (src.startsWith("workspace:"))
            return "Escritorio " + src.substring(10);
        return src === "window" ? "Ventana" : src === "extend" ? "Pantalla extendida" : src;
    }

    // `mirror options` puede fallar si el drawer se abre mientras el daemon arranca: reintentar.
    property int optTries: 0
    Timer {
        interval: 1500
        repeat: true
        running: root.opt === null && root.optTries < 4
        onTriggered: {
            root.optTries++;
            Cast.mirrorOptions();
        }
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
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: pl.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.extraLarge
                color: Colours.palette.m3primaryContainer

                RowLayout {
                    id: pl

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "cast_connected"
                            fill: 1
                            color: Colours.palette.m3onPrimary
                            fontStyle: Tokens.font.icon.medium
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.act?.device_name ?? ""
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.title.small
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: (root.act?.state === "PLAYING" ? "" : "Conectando · ") + (root.act?.source ? root.sourceLabel(root.act.source) : "Pantalla " + (root.act?.monitor ?? ""))
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.body.small
                            opacity: 0.85
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: [root.act?.quality, root.act?.encoder ? (root.act.encoder === "nvidia" ? "GPU" : "CPU") + (root.act?.encoder_mode === "auto" ? " (auto)" : "") : "", root.act?.latency ? "~" + Math.round(root.act.latency * 1000) + " ms" : ""].filter(x => x).join(" · ")
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.label.small
                            opacity: 0.7
                        }
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: liveTuning.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                Tuning {
                    id: liveTuning

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    quality: root.act?.quality_mode ?? "auto"
                    encoder: root.act?.encoder_mode ?? "auto"
                    audio: root.act?.audio ?? true
                    onPicked: (k, v) => root.pickedLive(k, v)
                }
            }

            TextButton {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                text: "Dejar de proyectar"
                type: TextButton.Tonal
                onClicked: {
                    Cast.stop();
                    root.close();
                }
            }
        }

        // --- Elegir qué y dónde
        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.mirroring
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                visible: root.opt !== null
                spacing: Tokens.spacing.small

                Repeater {
                    model: [["monitor", "Pantalla", "desktop_windows"], ["workspace", "Escritorio", "grid_view"], ["window", "Ventana", "select_window"], ["extend", "Extender", "add_to_queue"]]

                    SourceTile {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: modelData[1]
                        icon: modelData[2]
                        selected: root.srcKind === modelData[0]
                        onClicked: root.srcKind = modelData[0]
                    }
                }
            }

            // Detalle de la fuente: monitores a escala / escritorios / explicación
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.extraSmall
                visible: root.srcKind === "monitor" && root.availableMonitors.length > 1
                spacing: Tokens.spacing.small

                Repeater {
                    model: root.availableMonitors

                    StyledRect {
                        id: mon

                        required property var modelData
                        readonly property bool on: root.effMonitor === modelData.name

                        height: 46
                        width: Math.round(height * modelData.width / Math.max(1, modelData.height))
                        radius: Tokens.rounding.small
                        color: on ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
                        border.width: 2
                        border.color: on ? Colours.palette.m3primary : "transparent"

                        StateLayer {
                            radius: Tokens.rounding.small
                            onClicked: root.monitor = mon.modelData.name
                        }
                        StyledText {
                            anchors.centerIn: parent
                            text: mon.modelData.name
                            font: Tokens.font.label.small
                            color: mon.on ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall
                visible: root.srcKind === "workspace" && root.workspaces.length > 0
                spacing: Tokens.spacing.small

                Repeater {
                    model: root.workspaces

                    StyledRect {
                        id: ws

                        required property var modelData
                        readonly property bool on: root.effWorkspace === String(modelData.id)
                        readonly property string label: modelData.name && modelData.name !== String(modelData.id) ? modelData.name : String(modelData.id)

                        implicitWidth: Math.max(48, wsl.implicitWidth + Tokens.padding.large * 2)
                        implicitHeight: 52
                        radius: on ? Tokens.rounding.large : Tokens.rounding.medium
                        color: on ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                        Behavior on radius {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }

                        StateLayer {
                            radius: ws.radius
                            color: ws.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            onClicked: root.srcWorkspace = String(ws.modelData.id)
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            StyledText {
                                id: wsl

                                anchors.horizontalCenter: parent.horizontalCenter
                                text: ws.label
                                font: Tokens.font.title.small
                                color: ws.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            }
                            // un punto por ventana (máx. 4); vacío = escritorio sin ventanas
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 3
                                height: 4

                                Repeater {
                                    model: Math.min(4, ws.modelData.windows)

                                    Rectangle {
                                        width: 4
                                        height: 4
                                        radius: 2
                                        color: ws.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.small
                Layout.topMargin: Tokens.spacing.extraSmall
                visible: root.srcKind === "window" || root.srcKind === "extend"
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "info"
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.srcKind === "window" ? "Al conectar, elige la ventana en el selector del sistema." : "La tele será una pantalla más, vacía, a la que mover ventanas."
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }
            }

            // --- Dónde
            StyledText {
                Layout.topMargin: Tokens.spacing.medium
                Layout.leftMargin: Tokens.padding.small
                text: "Enviar a"
                color: Colours.palette.m3primary
                font: Tokens.font.label.large
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.small
                visible: root.scanning
                text: "Buscando teles en la red…"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
            StyledText {
                Layout.fillWidth: true
                visible: !root.scanning && root.availableMonitors.length === 0
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
                        disabled: root.busy || (root.srcKind === "monitor" && root.availableMonitors.length === 0)
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
                        StyledRect {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3primary

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "cast"
                                color: Colours.palette.m3onPrimary
                            }
                        }
                    }
                }
            }

            // --- Ajustes (plegable, con resumen)
            StyledRect {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                visible: root.opt !== null
                implicitHeight: advCol.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer
                clip: true

                ColumnLayout {
                    id: advCol

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: advHead.implicitHeight

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.large
                            anchors.bottomMargin: root.advanced ? 0 : -Tokens.padding.large
                            radius: Tokens.rounding.large
                            onClicked: root.advanced = !root.advanced
                        }
                        RowLayout {
                            id: advHead

                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                text: "tune"
                                color: Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.medium
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Ajustes"
                                    font: Tokens.font.body.medium
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: !root.advanced
                                    text: root.summary
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                }
                            }
                            MaterialIcon {
                                text: "expand_more"
                                rotation: root.advanced ? 180 : 0
                                color: Colours.palette.m3onSurfaceVariant

                                Behavior on rotation {
                                    Anim {
                                        type: Anim.FastSpatial
                                    }
                                }
                            }
                        }
                    }

                    Tuning {
                        Layout.fillWidth: true
                        visible: root.advanced
                        quality: root.quality
                        encoder: root.encoder
                        audio: root.audioOn
                        onPicked: (k, v) => root.pickedIdle(k, v)
                    }
                }
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
