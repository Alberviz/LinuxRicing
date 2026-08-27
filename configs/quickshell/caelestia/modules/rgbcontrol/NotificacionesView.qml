pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    component Card: StyledRect {
        default property alias content: inner.data
        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh

        ColumnLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium
        }
    }

    component CheckRow: Item {
        id: cr
        property string label
        property string hint
        property bool checked
        property bool enabled: true
        signal toggled(bool on)

        Layout.fillWidth: true
        implicitHeight: 34
        opacity: enabled ? 1 : 0.45

        StateLayer {
            radius: Tokens.rounding.small
            disabled: !cr.enabled
            onClicked: cr.toggled(!cr.checked)
        }

        RowLayout {
            anchors.fill: parent
            spacing: Tokens.spacing.small

            StyledRect {
                implicitWidth: 22
                implicitHeight: 22
                radius: Tokens.rounding.extraSmall
                color: cr.checked ? Colours.palette.m3primary : "transparent"
                border.width: cr.checked ? 0 : 1
                border.color: Colours.palette.m3outline

                Behavior on color {
                    CAnim {}
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: cr.checked
                    text: "check"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onPrimary
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: cr.label
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurface
            }

            StyledText {
                visible: !!cr.hint
                text: cr.hint
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }
        }
    }

    // ---- Flash toggle + colour + pulses ----
    Card {
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: qsTr("Flash al recibir notificación")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Un pulso corto de color y vuelta al estado anterior.")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }

            StyledSwitch {
                checked: RgbConfig.flashEnabled
                onToggled: RgbConfig.setFlashEnabled(checked)
            }
        }

        StyledText {
            text: qsTr("Color del flash")
            font: Tokens.font.label.medium
            color: Colours.palette.m3onSurfaceVariant
            enabled: RgbConfig.flashEnabled
            opacity: RgbConfig.flashEnabled ? 1 : 0.45
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            enabled: RgbConfig.flashEnabled
            opacity: RgbConfig.flashEnabled ? 1 : 0.45

            Chip {
                Layout.fillWidth: true
                implicitHeight: 32
                label: qsTr("Rojo")
                selected: RgbConfig.flashMode === "red"
                onClicked: RgbConfig.setFlashMode("red")
            }
            Chip {
                Layout.fillWidth: true
                implicitHeight: 32
                label: qsTr("Acento")
                selected: RgbConfig.flashMode === "accent"
                onClicked: RgbConfig.setFlashMode("accent")
            }
            Chip {
                Layout.fillWidth: true
                implicitHeight: 32
                label: qsTr("Complementario")
                selected: RgbConfig.flashMode === "complementary"
                onClicked: RgbConfig.setFlashMode("complementary")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            enabled: RgbConfig.flashEnabled
            opacity: RgbConfig.flashEnabled ? 1 : 0.45

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Pulsos")
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }
            StyledSpinBox {
                from: 1
                to: 5
                stepSize: 1
                value: RgbConfig.flashPulses
                onValueModified: RgbConfig.setFlashPulses(value)
            }
        }

        StyledRect {
            Layout.alignment: Qt.AlignLeft
            implicitWidth: probeRow.implicitWidth + Tokens.padding.large * 2
            implicitHeight: 32
            radius: Tokens.rounding.full
            color: "transparent"
            border.width: 1
            border.color: Colours.palette.m3outline
            enabled: RgbConfig.flashEnabled
            opacity: RgbConfig.flashEnabled ? 1 : 0.45

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/rgb-notify-flash", "--test"])
            }

            RowLayout {
                id: probeRow
                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "bolt"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurface
                }
                StyledText {
                    text: qsTr("Probar flash")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurface
                }
            }
        }
    }

    // ---- Which devices flash ----
    Card {
        StyledText {
            text: qsTr("Dispositivos que flashean")
            font: Tokens.font.title.small
            color: Colours.palette.m3primary
        }

        CheckRow {
            label: qsTr("Base MCHOSE 8K")
            checked: RgbConfig.flashDevices.includes("mchose_base")
            onToggled: on => RgbConfig.setFlashDevice("mchose_base", on)
        }
        CheckRow {
            label: qsTr("Teclado Akko 5075B")
            checked: RgbConfig.flashDevices.includes("akko_keyboard")
            onToggled: on => RgbConfig.setFlashDevice("akko_keyboard", on)
        }
        CheckRow {
            label: qsTr("Tira LED MagicHome")
            hint: qsTr("lenta por Wi-Fi")
            checked: RgbConfig.flashDevices.includes("magichome")
            onToggled: on => RgbConfig.setFlashDevice("magichome", on)
        }
        CheckRow {
            label: qsTr("Placa · RAM · ventiladores")
            hint: qsTr("bus lento, no disponible")
            enabled: false
            checked: false
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            text: qsTr("Respeta «No molestar». Ignora las notificaciones del propio sistema de batería.")
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
            wrapMode: Text.WordWrap
        }
    }

    // ---- Reacciones de batería ----
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: qsTr("Reacciones de batería")
                font: Tokens.font.title.small
                color: Colours.palette.m3primary
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("La batería de un dispositivo acciona luces.")
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }

        Repeater {
            model: BatteryLightingConfig.rules

            BatteryRuleCard {
                required property var modelData

                rule: modelData
            }
        }

        // Add rule dialog / form
        StyledRect {
            id: newRuleBox

            property bool open: false
            property string chosenSource: "mchose_mouse"
            property string chosenTrigger: "low"

            Layout.fillWidth: true
            implicitHeight: open ? newRuleCol.implicitHeight + Tokens.padding.large * 2 : 0
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3primary, 0.4)
            clip: true
            visible: open

            Behavior on implicitHeight {
                Anim {}
            }

            ColumnLayout {
                id: newRuleCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    text: qsTr("Nueva regla de batería")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: qsTr("Dispositivo origen")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: BatteryLightingConfig.sources

                        Chip {
                            id: srcChip

                            required property var modelData

                            implicitWidth: srcLabel.implicitWidth + Tokens.padding.large * 2
                            implicitHeight: 30
                            label: modelData.label
                            selected: newRuleBox.chosenSource === modelData.key
                            onClicked: newRuleBox.chosenSource = modelData.key

                            StyledText {
                                id: srcLabel

                                visible: false
                                text: srcChip.modelData.label
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }

                StyledText {
                    text: qsTr("Disparador")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: BatteryLightingConfig.triggers

                        Chip {
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: 30
                            label: modelData.label
                            selected: newRuleBox.chosenTrigger === modelData.key
                            onClicked: newRuleBox.chosenTrigger = modelData.key
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledRect {
                        implicitWidth: cancelText.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: 32
                        radius: Tokens.rounding.full
                        color: "transparent"
                        border.width: 1
                        border.color: Colours.palette.m3outline

                        StateLayer {
                            radius: Tokens.rounding.full
                            onClicked: newRuleBox.open = false
                        }

                        StyledText {
                            id: cancelText

                            anchors.centerIn: parent
                            text: qsTr("Cancelar")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onSurface
                        }
                    }

                    StyledRect {
                        implicitWidth: createText.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        StateLayer {
                            radius: Tokens.rounding.full
                            onClicked: {
                                BatteryLightingConfig.addRule(newRuleBox.chosenSource, newRuleBox.chosenTrigger);
                                newRuleBox.open = false;
                            }
                        }

                        StyledText {
                            id: createText

                            anchors.centerIn: parent
                            text: qsTr("Crear regla")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onPrimary
                        }
                    }
                }
            }
        }

        // "+ Añadir regla" button
        StyledRect {
            Layout.alignment: Qt.AlignLeft
            visible: !newRuleBox.open
            implicitWidth: addRuleRow.implicitWidth + Tokens.padding.large * 2
            implicitHeight: 34
            radius: Tokens.rounding.full
            color: "transparent"
            border.width: 1
            border.color: Colours.palette.m3outline

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: newRuleBox.open = true
            }

            RowLayout {
                id: addRuleRow

                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "add"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: qsTr("Añadir regla")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurface
                }
            }
        }
    }

    // ---- Future ----
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: futureCol.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)

        ColumnLayout {
            id: futureCol

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Más adelante")
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Color según la app (Discord, correo…) · Nivel de urgencia.")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
                wrapMode: Text.WordWrap
            }
        }
    }
}
