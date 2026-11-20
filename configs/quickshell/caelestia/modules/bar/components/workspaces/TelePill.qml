pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Indicador especial en la barra cuando la Tele está activa (Agentes / Personal / Juegos).
// Clic izquierdo: alterna interacción con la pantalla de la Tele.
// Clic derecho: apaga el modo de Tele o abre Win+P.
StyledRect {
    id: root

    visible: Tele.active && (Tele.mode === "agents" || Tele.transport === "wifi")
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: visible ? col.implicitHeight + 12 : 0
    radius: Tokens.rounding.full
    color: Tele.interacting
        ? Colours.palette.m3tertiaryContainer
        : (Tele.mode === "agents" ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh)
    border.width: 1
    border.color: Tele.transport === "hdmi" ? Colours.palette.m3primary : Colours.palette.m3tertiary

    Behavior on implicitHeight {
        Anim {}
    }

    StateLayer {
        radius: parent.radius
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.RightButton)
                Tele.setMode("off", false);
            else
                Tele.toggleInteract();
        }
    }

    ColumnLayout {
        id: col

        anchors.centerIn: parent
        spacing: 2

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: Tele.mode === "agents" ? "smart_toy" : (Tele.mode === "gaming" ? "sports_esports" : "tv")
            fontStyle: Tokens.font.icon.small
            color: Tele.interacting
                ? Colours.palette.m3onTertiaryContainer
                : (Tele.mode === "agents" ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface)
        }

        // Mini etiqueta HDMI / WF
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Tele.transport === "hdmi" ? "HD" : "WF"
            font.pixelSize: 8
            font.weight: Font.Bold
            color: Tele.transport === "hdmi" ? Colours.palette.m3primary : Colours.palette.m3tertiary
        }

        // Contador de ventanas de agentes si hay alguna
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: Tele.mode === "agents" && Tele.agentsWindows > 0
            text: String(Tele.agentsWindows)
            font.pixelSize: 9
            font.weight: Font.Bold
            color: Colours.palette.m3onPrimaryContainer
        }
    }
}
