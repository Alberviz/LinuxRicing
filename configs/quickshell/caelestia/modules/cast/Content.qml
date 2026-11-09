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

    function start(dev): void {
        busy = true;
        if (effMonitor)
            lastView.setText(effMonitor);
        Cast.mirrorStart(dev.uuid, effMonitor, true);
    }

    Connections {
        target: Cast

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
                        text: (root.act?.state === "PLAYING" ? "Pantalla " : "Conectando · pantalla ") + (root.act?.monitor ?? "")
                        color: Colours.palette.m3onPrimaryContainer
                        font: Tokens.font.body.small
                        opacity: 0.8
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: al.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    id: al

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "volume_up"
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Enviar el audio del sistema"
                        font: Tokens.font.body.medium
                    }
                    StyledSwitch {
                        checked: root.act?.audio ?? true
                        onToggled: Cast.mirrorAudio(checked)
                    }
                }
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

            // Qué pantalla (solo si hay más de una)
            RowLayout {
                Layout.fillWidth: true
                visible: Cast.monitors.length > 1
                spacing: Tokens.spacing.small

                StyledText {
                    text: "Pantalla"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
                Repeater {
                    model: Cast.monitors

                    StyledRect {
                        id: mchip

                        required property var modelData
                        readonly property bool sel: root.effMonitor === modelData.name

                        implicitWidth: mt.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: mt.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: sel ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

                        StateLayer {
                            radius: Tokens.rounding.full
                            onClicked: root.monitor = mchip.modelData.name
                        }
                        StyledText {
                            id: mt

                            anchors.centerIn: parent
                            text: mchip.modelData.name
                            font: Tokens.font.body.small
                            color: mchip.sel ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }

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
