pragma ComponentBehavior: Bound

// SolarSystemLayer — la capa de fondo del escritorio en la v3. Es EL fondo:
// layershell opaco negro a pantalla completa en WlrLayer.Background, con el
// sistema solar (variante D) pintado encima. Click-through completo (la
// interacción llega en una tanda posterior — D-7). El reloj de Caelestia vive
// en su propia capa (Background.qml, en Bottom) por encima de ésta.
//
// La disposición y las señales vienen de SolarSystemModel; los colores, de la
// paleta del wallpaper (Colours.palette) — cero hex fijos.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

Variants {
    model: Quickshell.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        screen: modelData
        name: "solar-system"
        color: "black"                       // fondo negro puro garantizado (spec §2.6)

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        // Click-through completo (sin interacción en esta tanda — D-7).
        mask: Region {}

        // Esta ventana ES el fondo negro del escritorio: siempre presente y opaca.
        // Lo que se enciende/apaga es su CONTENIDO (el Loader de abajo).
        visible: true

        // El sistema solar entero — shader GPU, capa Canvas y el FrameAnimation —
        // se DESCARGA (no se pausa: Loader.active) cuando:
        //   · el modo ahorro está activo (batería / perfil power-saver / <20 %), o
        //   · Alberto ha apagado el fondo a mano desde el popout de batería.
        // En ambos casos queda sólo esta ventana negra a pantalla completa; al
        // reactivar se reinstancia limpio (nada de hot-reload — CLAUDE.md).
        Loader {
            id: solarLoader

            anchors.fill: parent
            active: !PowerSaving.active && SolarSystemModel.enabled

            sourceComponent: SolarSystem {
                anchors.fill: parent

                config: SolarSystemModel.config
                values: SolarSystemModel.values
                active: SolarSystemModel.anyActivity
                fastRate: SolarSystemModel.musicPlaying
                musicVariant: SolarSystemModel.musicVariant
                targetFps: SolarSystemModel.targetFps
                // En modo juego el shell congela sus animaciones; el sistema solar
                // hace lo mismo para no competir por GPU.
                paused: GameMode.enabled

                // Modo Laura activa (D-12): al hablarle a Laura, el sistema se
                // congela y oscurece y Laura brilla latiendo con su voz.
                lauraActive: Laura.active
                lauraAmplitude: Laura.amplitude

                // Etiquetas de cuerpos (BodyLabel): tipografía mono del shell y
                // color por proveedor de IA (rol resuelto en SolarSystemModel).
                labelFont: Tokens.font.mono.small.family
                agentProviderColours: ({
                    "claude": Colours.palette[SolarSystemModel.providerPaletteRole["claude"]],
                    "gemini": Colours.palette[SolarSystemModel.providerPaletteRole["gemini"]],
                    "codex": Colours.palette[SolarSystemModel.providerPaletteRole["codex"]],
                    "otro": Colours.palette[SolarSystemModel.providerPaletteRole["otro"]]
                })

                colPrimary: Colours.palette.m3primary
                // Laura = m3tertiaryFixedDim (oro apagado). El m3tertiary del scheme
                // tonalspot es casi blanco y no contrasta con el disco cálido ni con
                // el núcleo blanco-caliente del agujero (decisión D-3).
                colLaura: Colours.palette.m3tertiaryFixedDim
                colError: Colours.palette.m3error
                colBelt: Colours.palette.m3outlineVariant
                colInk: Colours.palette.m3onSurface
                colVoid: Qt.darker(Colours.palette.m3surface, 3)
            }
        }
    }
}
