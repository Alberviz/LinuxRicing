pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Battery lighting design for the Akko 5075B. Frontend only: it reads/writes
// AkkoConfig (~/.config/caelestia/akko-config.json) and previews each effect,
// but nothing drives the keyboard yet - the Akko does not expose its battery
// over 2.4 GHz. See AkkoConfig.qml / docs/HARDWARE_PROTOCOLS.md §1.B.
DeviceCard {
    id: card

    icon: "keyboard"
    name: qsTr("Teclado Akko 5075B")
    subtitle: qsTr("Retro + tira lateral")
    deviceKey: "akko_keyboard"
    expanded: true

    // Which event the preview + chip groups are showing.
    property bool showLow: false
    readonly property bool reactive: AkkoConfig.reactiveEnabled

    component SectionLabel: StyledText {
        font: Tokens.font.label.medium
        color: Colours.palette.m3onSurfaceVariant
    }

    component ZoneTitle: StyledText {
        font: Tokens.font.title.small
        color: Colours.palette.m3primary
    }

    component Divider: StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
    }

    // A row of mutually-exclusive chips bound to an AkkoConfig option list.
    component ChipGroup: RowLayout {
        id: chipGroup

        property var options: []
        property string current
        property bool danger: false
        signal picked(string key)

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        enabled: card.reactive
        opacity: card.reactive ? 1 : 0.4

        Repeater {
            model: chipGroup.options

            Chip {
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 30
                label: modelData.label
                selected: chipGroup.current === modelData.key
                activeColour: chipGroup.danger ? Colours.palette.m3errorContainer : Colours.palette.m3primary
                activeText: chipGroup.danger ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimary
                onClicked: chipGroup.picked(modelData.key)
            }
        }
    }

    // ---- Live preview ----
    KeyboardPreview {
        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.spacing.extraSmall
        opacity: card.reactive ? 1 : 0.4
        mode: card.showLow ? AkkoConfig.lowBatBacklight : AkkoConfig.chargingBacklight
        sidestripMode: card.showLow ? AkkoConfig.lowBatSidestrip : AkkoConfig.chargingSidestrip
        lowColour: Colours.palette.m3error
    }

    // ---- Event selector for the preview ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        Chip {
            Layout.fillWidth: true
            implicitHeight: 30
            label: qsTr("Al cargar")
            selected: !card.showLow
            onClicked: card.showLow = false
        }
        Chip {
            Layout.fillWidth: true
            implicitHeight: 30
            label: qsTr("Batería baja")
            selected: card.showLow
            onClicked: card.showLow = true
        }
    }

    // ---- Master toggle ----
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        spacing: Tokens.spacing.small

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: qsTr("Reaccionar a la batería")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }
            StyledText {
                Layout.fillWidth: true
                text: qsTr("Si se apaga, el teclado solo sigue el color global.")
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }

        StyledSwitch {
            checked: AkkoConfig.reactiveEnabled
            onToggled: AkkoConfig.setReactiveEnabled(checked)
        }
    }

    Divider {}

    // ---- Retroiluminación ----
    ZoneTitle {
        text: qsTr("Retroiluminación (teclas)")
    }

    SectionLabel {
        text: qsTr("Al poner a cargar")
    }
    ChipGroup {
        options: AkkoConfig.chargingBacklightOptions
        current: AkkoConfig.chargingBacklight
        onPicked: key => {
            AkkoConfig.setChargingBacklight(key);
            card.showLow = false;
        }
    }

    SectionLabel {
        text: qsTr("Alerta de batería baja")
    }
    ChipGroup {
        options: AkkoConfig.lowBatOptions
        current: AkkoConfig.lowBatBacklight
        danger: true
        onPicked: key => {
            AkkoConfig.setLowBatBacklight(key);
            card.showLow = true;
        }
    }

    Divider {}

    // ---- Tira lateral ----
    ZoneTitle {
        text: qsTr("Tira lateral")
    }

    SectionLabel {
        text: qsTr("Al poner a cargar")
    }
    ChipGroup {
        options: AkkoConfig.chargingSidestripOptions
        current: AkkoConfig.chargingSidestrip
        onPicked: key => {
            AkkoConfig.setChargingSidestrip(key);
            card.showLow = false;
        }
    }

    SectionLabel {
        text: qsTr("Alerta de batería baja")
    }
    ChipGroup {
        options: AkkoConfig.lowBatOptions
        current: AkkoConfig.lowBatSidestrip
        danger: true
        onPicked: key => {
            AkkoConfig.setLowBatSidestrip(key);
            card.showLow = true;
        }
    }

    Divider {}

    // ---- Threshold ----
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        enabled: card.reactive
        opacity: card.reactive ? 1 : 0.4

        SectionLabel {
            text: qsTr("Umbral de aviso: ≤ %1 %").arg(AkkoConfig.lowBatThreshold)
        }

        StyledSlider {
            // interaction(v) gives a normalised 0..1 position; map it onto the
            // 5..40 % range in steps of 5 (same as the Base card).
            Layout.fillWidth: true
            implicitHeight: 14
            value: (AkkoConfig.lowBatThreshold - 5) / 35
            onInteraction: v => AkkoConfig.setThreshold(Math.min(40, Math.max(5, Math.round((5 + v * 35) / 5) * 5)))
        }
    }

    // ---- Status note ----
    StyledRect {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        implicitHeight: noteRow.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.small
        color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.5)

        RowLayout {
            id: noteRow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignTop
                text: "info"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("El teclado todavía no informa de su batería por 2.4 GHz. Esta pantalla guarda tus preferencias y se aplicarán en cuanto se pueda leer el nivel.")
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }
}
