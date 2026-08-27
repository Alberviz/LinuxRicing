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

    StyledText {
        Layout.fillWidth: true
        text: qsTr("El color del teclado sigue el tema global. Sus reacciones de batería están en Notificaciones → Reacciones de batería.")
        font: Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
        wrapMode: Text.WordWrap
    }
}

