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
        expanded: false

        SectionLabel {
            text: qsTr("Eventos de batería")
            color: Colours.palette.m3primary
            font: Tokens.font.title.small
        }

        SectionLabel {
            text: qsTr("Al poner a cargar")
        }
        ChipRow {
            Chip {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Tema")
                selected: MchoseConfig.chargingEffect === "theme_breathing"
                onClicked: MchoseConfig.setCharging("theme_breathing")
            }
            Chip {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Batería")
                selected: MchoseConfig.chargingEffect === "battery_breathing"
                onClicked: MchoseConfig.setCharging("battery_breathing")
            }
            Chip {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Firmware")
                selected: MchoseConfig.chargingEffect === "hardware_battery"
                onClicked: MchoseConfig.setCharging("hardware_battery")
            }
            Chip {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Ola")
                selected: MchoseConfig.chargingEffect === "wave"
                onClicked: MchoseConfig.setCharging("wave")
            }
        }

        SectionLabel {
            text: qsTr("Alerta de batería baja")
        }
        ChipRow {
            Chip {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Roja")
                activeColour: Colours.palette.m3errorContainer
                activeText: Colours.palette.m3onErrorContainer
                selected: MchoseConfig.lowBatEffect === "red_breathing"
                onClicked: MchoseConfig.setLowBat("red_breathing")
            }
            Chip {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Ola")
                selected: MchoseConfig.lowBatEffect === "wave"
                onClicked: MchoseConfig.setLowBat("wave")
            }
            Chip {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Ninguna")
                selected: MchoseConfig.lowBatEffect === "none"
                onClicked: MchoseConfig.setLowBat("none")
            }
            Chip {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Fija")
                selected: MchoseConfig.lowBatEffect === "red_static"
                onClicked: MchoseConfig.setLowBat("red_static")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            spacing: Tokens.spacing.extraSmall

            SectionLabel {
                text: qsTr("Umbral de aviso: ≤ %1 %").arg(MchoseConfig.lowBatThreshold)
            }

            StyledSlider {
                // interaction(v) delivers a normalised 0..1 position, not the
                // real value, so map it onto the 5..40 % range in steps of 5.
                Layout.fillWidth: true
                implicitHeight: 14

                value: (MchoseConfig.lowBatThreshold - 5) / 35
                onInteraction: v => MchoseConfig.setThreshold(Math.min(40, Math.max(5, Math.round((5 + v * 35) / 5) * 5)))
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

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: MchoseConfig.previewCharging()
            }

            RowLayout {
                id: probeRow
                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "science"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurface
                }
                StyledText {
                    text: qsTr("Probar")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurface
                }
            }
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
