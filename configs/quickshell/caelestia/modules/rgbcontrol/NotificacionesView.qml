pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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
                text: qsTr("Color según la app (Discord, correo…) · Nivel de urgencia · Aviso de batería baja propio de cada dispositivo (el teclado con su batería, no la del ratón).")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
                wrapMode: Text.WordWrap
            }
        }
    }
}
