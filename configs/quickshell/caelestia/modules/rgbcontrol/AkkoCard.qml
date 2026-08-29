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
    readonly property var keysEffect: DeviceEffects.normalize(profile.keys ?? profile.keys_mode ?? "theme")
    readonly property var sidestripEffect: DeviceEffects.normalize(profile.sidestrip ?? profile.sidestrip_mode ?? "stream_battery")

    component SectionLabel: StyledText {
        font: Tokens.font.label.medium
        color: Colours.palette.m3primary
    }

    // ---- TECLAS ----
    SectionLabel {
        text: qsTr("Teclas (retroiluminación)")
    }

    EffectEditor {
        Layout.fillWidth: true
        device: "akko_keyboard"
        zone: "keys"
        effect: card.keysEffect
        onEdited: eff => RgbConfig.setAkkoEffect("keys", eff)
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        text: qsTr("Solo efectos del firmware: por 2.4 GHz un efecto por tecla congela el teclado. La animación la hace el propio teclado.")
        font: Tokens.font.label.small
        color: Colours.palette.m3outline
        wrapMode: Text.WordWrap
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        Layout.bottomMargin: Tokens.spacing.small
        implicitHeight: 1
        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
    }

    // ---- TIRA LATERAL ----
    SectionLabel {
        text: qsTr("Tira lateral (side-strip)")
    }

    EffectEditor {
        Layout.fillWidth: true
        device: "akko_keyboard"
        zone: "sidestrip"
        effect: card.sidestripEffect
        onEdited: eff => RgbConfig.setAkkoEffect("sidestrip", eff)
    }

    // ---- Vista previa ----
    KeyboardPreview {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        keysEffect: card.keysEffect
        sidestripEffect: card.sidestripEffect
    }
}
