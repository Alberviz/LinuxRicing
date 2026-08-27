pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

DeviceCard {
    id: card

    icon: "keyboard"
    name: qsTr("Teclado Akko 5075B")
    subtitle: qsTr("Retro + tira lateral")
    deviceKey: "akko_keyboard"
    expanded: false

    readonly property var profile: RgbConfig.deviceProfiles.akko_keyboard ?? ({})
    readonly property string keysMode: profile.keys_mode ?? "theme"
    readonly property string keysFixed: profile.keys_fixed_color ?? "d8bde7"
    readonly property string sidestripMode: profile.sidestrip_mode ?? "stream_battery"
    readonly property string sidestripFixed: profile.sidestrip_fixed_color ?? "d8bde7"

    component SectionLabel: StyledText {
        font: Tokens.font.label.medium
        color: Colours.palette.m3onSurfaceVariant
    }

    component ChipRow: Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
    }

    // ---- TECLAS (BACKLIGHT) ----
    SectionLabel {
        text: qsTr("Modo de las teclas (Backlight)")
    }

    ChipRow {
        Chip {
            implicitHeight: 32
            label: qsTr("Tema global")
            selected: card.keysMode === "theme"
            onClicked: RgbConfig.setAkkoKeysMode("theme")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Color fijo")
            selected: card.keysMode === "fixed"
            onClicked: RgbConfig.setAkkoKeysMode("fixed")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Nivel de batería")
            selected: card.keysMode === "battery_color"
            onClicked: RgbConfig.setAkkoKeysMode("battery_color")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Letra a letra")
            selected: card.keysMode === "battery_meter_keys"
            onClicked: RgbConfig.setAkkoKeysMode("battery_meter_keys")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Fila a fila")
            selected: card.keysMode === "battery_meter_rows"
            onClicked: RgbConfig.setAkkoKeysMode("battery_meter_rows")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Respiración (batería)")
            selected: card.keysMode === "breathing_battery"
            onClicked: RgbConfig.setAkkoKeysMode("breathing_battery")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Respiración (tema)")
            selected: card.keysMode === "breathing"
            onClicked: RgbConfig.setAkkoKeysMode("breathing")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Reactivo al pulsar")
            selected: card.keysMode === "reactive_press"
            onClicked: RgbConfig.setAkkoKeysMode("reactive_press")
        }
    }

    ColourPicker {
        Layout.fillWidth: true
        visible: card.keysMode === "fixed"
        selectedColour: card.keysFixed
        onPicked: hex => RgbConfig.setAkkoKeysFixedColor(hex)
    }

    // ---- TIRA LATERAL (SIDE-STRIP) ----
    SectionLabel {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Modo de la tira lateral (Side-Strip)")
    }

    ChipRow {
        Chip {
            implicitHeight: 32
            label: qsTr("Flujo batería")
            selected: card.sidestripMode === "stream_battery"
            onClicked: RgbConfig.setAkkoSidestripMode("stream_battery")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Tema global")
            selected: card.sidestripMode === "theme"
            onClicked: RgbConfig.setAkkoSidestripMode("theme")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Color fijo")
            selected: card.sidestripMode === "fixed"
            onClicked: RgbConfig.setAkkoSidestripMode("fixed")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Nivel de batería")
            selected: card.sidestripMode === "battery_color"
            onClicked: RgbConfig.setAkkoSidestripMode("battery_color")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Respiración (batería)")
            selected: card.sidestripMode === "breathing_battery"
            onClicked: RgbConfig.setAkkoSidestripMode("breathing_battery")
        }
        Chip {
            implicitHeight: 32
            label: qsTr("Apagada")
            selected: card.sidestripMode === "off"
            onClicked: RgbConfig.setAkkoSidestripMode("off")
        }
    }

    ColourPicker {
        Layout.fillWidth: true
        visible: card.sidestripMode === "fixed"
        selectedColour: card.sidestripFixed
        onPicked: hex => RgbConfig.setAkkoSidestripFixedColor(hex)
    }
}

