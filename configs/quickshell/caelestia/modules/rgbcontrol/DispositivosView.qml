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

    component SectionLabel: StyledText {
        font: Tokens.font.label.medium
        color: Colours.palette.m3onSurfaceVariant
    }

    component Divider: StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
    }

    component ChipRow: Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
    }

    // ---- Base MCHOSE 8K ----
    DeviceCard {
        icon: "mouse"
        name: qsTr("Base MCHOSE 8K")
        subtitle: qsTr("Anillo LED")
        deviceKey: "mchose_base"
        // Collapsed by default so the panel isn't huge next to the Akko card.
        StyledText {
            Layout.fillWidth: true
            text: qsTr("El color del anillo sigue el tema global. Sus reacciones de batería están en Notificaciones → Reacciones de batería.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }

    // ---- Teclado Akko ----
    AkkoCard {}

    // ---- OpenRGB ----
    DeviceCard {
        icon: "developer_board"
        name: qsTr("Placa · RAM · ventiladores")
        subtitle: qsTr("OpenRGB · 2 zonas direccionables")
        deviceKey: "openrgb"

        SectionLabel {
            text: qsTr("Modo de las zonas direccionables (ventiladores)")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Chip {
                Layout.fillWidth: true
                implicitHeight: 32
                label: qsTr("RGB · color estático")
                selected: !RgbConfig.openrgbArgbZones
                onClicked: RgbConfig.setOpenrgbArgbZones(false)
            }
            Chip {
                Layout.fillWidth: true
                implicitHeight: 32
                label: qsTr("ARGB · ola animada")
                selected: RgbConfig.openrgbArgbZones
                onClicked: RgbConfig.setOpenrgbArgbZones(true)
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: qsTr("La RAM y la placa van siempre en color estático (el bus SMBus no admite animación).")
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
            wrapMode: Text.WordWrap
        }
    }

    // ---- MagicHome ----
    DeviceCard {
        icon: "lightbulb"
        name: qsTr("Tira LED MagicHome")
        subtitle: qsTr("Wi-Fi")
        deviceKey: "magichome"

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Si participa, sigue el color global. El encendido/apagado sigue en el widget de la tira.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }
}
