pragma ComponentBehavior: Bound

// SolarSystemLayer — la capa del escritorio. Un layershell transparente y
// click-through (v1: solo lectura, sin interacción) por pantalla, con la vista
// del sistema solar en la zona libre, dejando despejada la franja inferior para
// el overlay de Laura. La disposición y las señales vienen de SolarSystemModel;
// los colores, de la paleta del wallpaper (Colours.palette).

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.services

Variants {
    model: Quickshell.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        screen: modelData
        name: "solar-system"
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        // Click-through completo en v1 (la interacción llega en v2).
        mask: Region {}

        visible: SolarSystemModel.enabled

        SolarSystem {
            anchors.fill: parent
            // El baricentro cae en la zona libre (centro-derecha, un poco
            // arriba) para no pisar la franja inferior de Laura ni el reloj.
            centerFracX: 0.62
            centerFracY: 0.44

            config: SolarSystemModel.config
            values: SolarSystemModel.values
            active: SolarSystemModel.anyActivity
            fastRate: SolarSystemModel.musicPlaying
            // En modo juego el shell congela sus animaciones; el sistema solar
            // hace lo mismo para no competir por GPU.
            paused: GameMode.enabled

            colAnchorPrimary: Colours.palette.m3primary
            colAnchorSecondary: Colours.palette.m3secondary
            colBody: Colours.palette.m3tertiary
            colBodyAlt: Colours.palette.m3primary
            colAlert: Colours.palette.m3error
            colBelt: Colours.palette.m3outlineVariant
            colVoid: Qt.darker(Colours.palette.m3surface, 2)
        }
    }
}
