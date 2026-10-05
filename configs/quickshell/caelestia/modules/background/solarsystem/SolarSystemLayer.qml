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

        // Sin máscara de input: la ventana recibe el puntero sobre el escritorio
        // vacío (hover por zonas del sistema solar + clic en Configuración). Es la
        // capa Background: las ventanas y las capas de encima siguen recibiendo
        // sus eventos primero.

        // Esta ventana ES el fondo negro del escritorio: siempre presente y opaca.
        // Lo que se enciende/apaga es su CONTENIDO (el Loader de abajo).
        visible: true

        // Panel completo de tareas (se abre con clic en el cometa).
        property bool tasksPanelOpen: false

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

                onConfigClicked: {
                    ShellState.rgbControl?.open();
                }
                onCometClicked: win.tasksPanelOpen = true

                config: SolarSystemModel.config
                values: SolarSystemModel.values
                taskList: SolarSystemModel.taskList
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
                colSecondary: Colours.palette.m3secondary
                colPrimaryC: Colours.palette.m3primaryContainer
                colSecondaryC: Colours.palette.m3secondaryContainer
                colTertiaryC: Colours.palette.m3tertiaryContainer
                colSurface: Colours.palette.m3surface
                colSurfaceC: Colours.palette.m3surfaceContainer
                colOutline: Colours.palette.m3outline
                // Laura = m3tertiaryFixedDim (oro apagado). El m3tertiary del scheme
                // tonalspot es casi blanco y no contrasta con el disco cálido ni con
                // el núcleo blanco-caliente del agujero (decisión D-3).
                colLaura: Colours.palette.m3tertiary
                colError: Colours.palette.m3error
                colBelt: Colours.palette.m3outlineVariant
                colInk: Colours.palette.m3onSurface
                colVoid: Qt.darker(Colours.palette.m3surface, 3)
            }
        }

        // Widget de tareas abajo a la derecha. Fuera del Loader: se ve también en
        // modo ahorro / fondo negro (no tiene animaciones ni shader).
        TasksWidget {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // Los bordes derecho (~70 px) e inferior (~230 px) no reciben clics aquí: los tapa
            // la capa de drawers de Caelestia. El widget debe quedar por dentro de ambos.
            anchors.rightMargin: 100
            anchors.bottomMargin: 260
        }

        TasksPanel {
            anchors.fill: parent
            open: win.tasksPanelOpen
            onClosed: win.tasksPanelOpen = false
        }
    }
}
