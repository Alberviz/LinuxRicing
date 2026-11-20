pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    signal close

    implicitWidth: 500
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.palette.m3surfaceContainer
    border.width: 1
    border.color: Colours.palette.m3outlineVariant

    // Swallow clicks inside the dialog
    MouseArea {
        anchors.fill: parent
    }

    focus: true
    Component.onCompleted: forceActiveFocus()

    Keys.onEscapePressed: root.close()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_1) {
            root.modeExternalOnly();
            event.accepted = true;
        } else if (event.key === Qt.Key_2) {
            root.modeExtend();
            event.accepted = true;
        } else if (event.key === Qt.Key_3) {
            root.modeMirror();
            event.accepted = true;
        } else if (event.key === Qt.Key_4) {
            root.modeLaptopOnly();
            event.accepted = true;
        }
    }

    // Estado real de los monitores (lo da `display-mode status`).
    property var info: ({
            "mode": "unknown",
            "targetHz": 60,
            "internal": null,
            "externals": []
        })
    readonly property bool hasExternal: info.externals.length > 0
    readonly property bool hasInternal: info.internal !== null
    readonly property string externalName: {
        const n = info.externals.length;
        return n === 0 ? qsTr("monitor externo") : n === 1 ? info.externals[0].name : qsTr("%1 pantallas externas").arg(n);
    }

    Process {
        id: statusProc

        command: [root.helper, "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.info = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    readonly property string helper: `${Quickshell.env("HOME")}/.local/bin/display-mode`

    function apply(mode: string): void {
        root.close();
        Quickshell.execDetached([root.helper, mode]);
    }

    function modeExternalOnly(): void {
        if (root.hasExternal)
            root.apply("external");
    }

    function modeExtend(): void {
        if (root.hasExternal && root.hasInternal)
            root.apply("extend");
    }

    function modeMirror(): void {
        if (root.hasExternal && root.hasInternal)
            root.apply("mirror");
    }

    function modeLaptopOnly(): void {
        if (root.hasInternal)
            root.apply("laptop");
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: Tokens.rounding.medium
                color: Qt.alpha(Colours.palette.m3primary, 0.2)
                border.width: 1.5
                border.color: Colours.palette.m3primary

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "cast"
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.2).weight(Font.Bold).build()
                    color: Colours.palette.m3primary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Proyectar pantalla")
                    font: Tokens.font.title.medium
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Selecciona el modo de distribución de pantallas")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            StyledRect {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: Tokens.rounding.full
                color: closeLayer.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent"

                StateLayer {
                    id: closeLayer
                    radius: Tokens.rounding.full
                    onClicked: root.close()
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "close"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Divider
        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            color: Colours.palette.m3outlineVariant
        }

        // Option 1: Solo monitor externo (Apagar portátil)
        ProjectCard {
            Layout.fillWidth: true
            icon: "desktop_windows"
            title: qsTr("Solo monitor externo")
            description: root.hasExternal ? qsTr("Apaga el portátil y usa %1").arg(root.externalName) : qsTr("No hay ningún monitor externo conectado")
            shortcutKey: "1"
            enabled: root.hasExternal
            current: root.info.mode === "external"
            iconColor: Colours.palette.m3primary
            iconBgColor: Qt.alpha(Colours.palette.m3primary, 0.2)
            onClicked: root.modeExternalOnly()
        }

        // Option 2: Extender
        ProjectCard {
            Layout.fillWidth: true
            icon: "splitscreen"
            title: qsTr("Extender pantallas")
            description: root.hasExternal ? qsTr("Escritorio ampliado, portátil a %1 Hz").arg(root.info.targetHz) : qsTr("No hay ningún monitor externo conectado")
            shortcutKey: "2"
            enabled: root.hasExternal && root.hasInternal
            current: root.info.mode === "extend"
            iconColor: Colours.palette.m3secondary
            iconBgColor: Qt.alpha(Colours.palette.m3secondary, 0.2)
            onClicked: root.modeExtend()
        }

        // Option 3: Duplicar
        ProjectCard {
            Layout.fillWidth: true
            icon: "flip_to_front"
            title: qsTr("Duplicar / Espejo")
            description: root.hasExternal ? qsTr("Muestra lo mismo en el portátil y en %1").arg(root.externalName) : qsTr("No hay ningún monitor externo conectado")
            shortcutKey: "3"
            enabled: root.hasExternal && root.hasInternal
            current: root.info.mode === "mirror"
            iconColor: Colours.palette.m3tertiary
            iconBgColor: Qt.alpha(Colours.palette.m3tertiary, 0.2)
            onClicked: root.modeMirror()
        }

        // Option 4: Solo portátil
        ProjectCard {
            Layout.fillWidth: true
            icon: "laptop"
            title: qsTr("Solo pantalla del portátil")
            description: qsTr("Apaga las pantallas externas y deja solo el portátil a %1 Hz").arg(root.info.targetHz)
            shortcutKey: "4"
            enabled: root.hasInternal
            current: root.info.mode === "laptop"
            iconColor: Colours.palette.m3outline
            iconBgColor: Qt.alpha(Colours.palette.m3outline, 0.2)
            onClicked: root.modeLaptopOnly()
        }

        // Sección Tele Unificada (HDMI > Wi-Fi)
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: teleCol.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            ColumnLayout {
                id: teleCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    MaterialIcon {
                        text: "tv"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tele.transport === "hdmi"
                            ? qsTr("Tele · HDMI activo")
                            : (Tele.transport === "wifi" ? qsTr("Tele · Wi-Fi (%1)").arg(Tele.chromecastName)
                            : (Tele.available ? qsTr("Modo de Tele (HDMI > Wi-Fi)") : qsTr("Tele sin conexión")))
                        font: Tokens.font.label.large
                        color: Colours.palette.m3onSurface
                    }

                    StyledRect {
                        visible: Tele.active
                        implicitWidth: interactTxt.implicitWidth + 16
                        implicitHeight: 24
                        radius: Tokens.rounding.full
                        color: Tele.interacting ? Colours.palette.m3tertiaryContainer : Colours.palette.m3surfaceContainerHighest

                        StateLayer {
                            radius: parent.radius
                            onClicked: {
                                root.close();
                                Tele.toggleInteract();
                            }
                        }

                        StyledText {
                            id: interactTxt
                            anchors.centerIn: parent
                            text: Tele.interacting ? qsTr("Devolver") : qsTr("Interactuar")
                            font: Tokens.font.label.small
                            color: Tele.interacting ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: [
                            { id: "personal", label: qsTr("Personal"), icon: "desktop_windows" },
                            { id: "agents", label: qsTr("Agentes"), icon: "smart_toy" },
                            { id: "gaming", label: qsTr("Juegos"), icon: "sports_esports" },
                            { id: "off", label: qsTr("Apagar"), icon: "power_settings_new" }
                        ]

                        StyledRect {
                            id: tBtn
                            required property var modelData
                            readonly property bool sel: Tele.mode === modelData.id && (modelData.id !== "off" || !Tele.active)

                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: Tokens.rounding.medium
                            color: sel ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainer
                            opacity: (Tele.available || modelData.id === "off") ? 1 : 0.45

                            StateLayer {
                                radius: parent.radius
                                disabled: !Tele.available && tBtn.modelData.id !== "off"
                                onClicked: {
                                    root.close();
                                    if (tBtn.modelData.id === "gaming")
                                        Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "elysium", "enter"]);
                                    else
                                        Tele.setMode(tBtn.modelData.id, false);
                                }
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialIcon {
                                    text: tBtn.modelData.icon
                                    fontStyle: Tokens.font.icon.small
                                    color: tBtn.sel ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                                }

                                StyledText {
                                    text: tBtn.modelData.label
                                    font: Tokens.font.label.small
                                    color: tBtn.sel ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                }
                            }
                        }
                    }
                }
            }
        }

        // Footer / Cancel button
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6

            Item {
                Layout.fillWidth: true
            }

            StyledRect {
                id: cancelBtn
                implicitWidth: cancelRow.implicitWidth + 36
                implicitHeight: 38
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                radius: Tokens.rounding.full
                color: cancelLayer.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainerHigh
                border.width: 1
                border.color: cancelLayer.containsMouse ? Colours.palette.m3outline : Colours.palette.m3outlineVariant

                StateLayer {
                    id: cancelLayer
                    radius: Tokens.rounding.full
                    onClicked: root.close()
                }

                RowLayout {
                    id: cancelRow
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialIcon {
                        text: "close"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        text: qsTr("Cancelar")
                        font: Tokens.font.label.large
                        color: Colours.palette.m3onSurface
                    }

                    StyledRect {
                        implicitHeight: 20
                        implicitWidth: 32
                        radius: Tokens.rounding.extraSmall
                        color: Colours.palette.m3surfaceContainerLowest
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant

                        StyledText {
                            anchors.centerIn: parent
                            text: "Esc"
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
