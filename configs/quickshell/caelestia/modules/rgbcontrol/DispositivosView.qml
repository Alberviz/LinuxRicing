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
        id: mchoseCard
        icon: "mouse"
        name: qsTr("Base MCHOSE 8K")
        subtitle: qsTr("Anillo LED")
        deviceKey: "mchose_base"

        readonly property var profile: RgbConfig.deviceProfiles.mchose_base ?? ({})
        readonly property var ringEffect: DeviceEffects.normalize(profile.ring ?? profile.mode ?? "theme")

        SectionLabel {
            text: qsTr("Anillo LED")
        }

        EffectEditor {
            Layout.fillWidth: true
            device: "mchose_base"
            zone: ""
            effect: mchoseCard.ringEffect
            onEdited: eff => RgbConfig.setMchoseBaseEffect(eff)
        }
    }

    // ---- Teclado Akko ----
    AkkoCard {}

    // ---- OpenRGB (torre) ----
    DeviceCard {
        icon: "developer_board"
        name: qsTr("Placa · RAM · ventiladores")
        subtitle: qsTr("OpenRGB · 2 zonas direccionables")
        deviceKey: "openrgb"

        SectionLabel {
            text: qsTr("Zonas direccionables (ventiladores)")
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
        id: magichomeCard
        icon: "lightbulb"
        name: qsTr("Tira LED MagicHome")
        subtitle: qsTr("Wi-Fi")
        deviceKey: "magichome"

        readonly property var profile: RgbConfig.deviceProfiles.magichome ?? ({})
        readonly property string magichomeMode: profile.mode ?? "theme"
        readonly property string magichomeFixed: profile.fixed_color ?? "d8bde7"

        SectionLabel {
            text: qsTr("Modo de la tira")
        }

        ChipRow {
            Chip {
                implicitHeight: 32
                label: qsTr("Tema global")
                selected: magichomeCard.magichomeMode === "theme"
                onClicked: RgbConfig.setDeviceMode("magichome", "theme")
            }
            Chip {
                implicitHeight: 32
                label: qsTr("Color fijo")
                selected: magichomeCard.magichomeMode === "fixed"
                onClicked: RgbConfig.setDeviceMode("magichome", "fixed")
            }
            Chip {
                implicitHeight: 32
                label: qsTr("Nivel de batería")
                selected: magichomeCard.magichomeMode === "battery_color"
                onClicked: RgbConfig.setDeviceMode("magichome", "battery_color")
            }
        }

        ColourPicker {
            Layout.fillWidth: true
            visible: magichomeCard.magichomeMode === "fixed"
            selectedColour: magichomeCard.magichomeFixed
            onPicked: hex => RgbConfig.setDeviceFixedColor("magichome", hex)
        }
    }

    // ---- Cadencia de Actualización de Batería ----
    StyledRect {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh
        implicitHeight: pollCol.implicitHeight + Tokens.padding.large * 2

        ColumnLayout {
            id: pollCol
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    readonly property int displaySecs: pollSlider.dragging
                        ? Math.min(120, Math.max(15, Math.round((15 + pollSlider.pos * 105) / 5) * 5))
                        : (BatteryLightingConfig.poll.idle_seconds ?? 60)
                    text: qsTr("Cadencia de sondeo de batería: %1 s").arg(displaySecs)
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Frecuencia con la que se comprueba el nivel de batería en reposo. Al conectar a cargar se acelera a 3 s automáticamente.")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }

            StyledSlider {
                id: pollSlider
                Layout.fillWidth: true
                implicitHeight: 14
                value: ((BatteryLightingConfig.poll.idle_seconds ?? 60) - 15) / 105
                interactionOnMove: false
                onInteraction: v => BatteryLightingConfig.setPollIdleSeconds(Math.min(120, Math.max(15, Math.round((15 + v * 105) / 5) * 5)))
            }
        }
    }
}

