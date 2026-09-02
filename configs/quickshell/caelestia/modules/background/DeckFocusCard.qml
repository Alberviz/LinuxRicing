pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Services
import Caelestia.Components
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services

RowLayout {
    id: root

    // Referencia al DesktopWidgetDeck dueño de los datos y las acciones.
    required property var deck

    spacing: Tokens.spacing.large

    // Left: Timer Display
    ColumnLayout {
        spacing: 0
        StyledText {
            readonly property int mins: Math.floor(root.deck.focusSeconds / 60)
            readonly property int secs: root.deck.focusSeconds % 60
            text: `${mins < 10 ? '0' + mins : mins}:${secs < 10 ? '0' + secs : secs}`
            font: Tokens.font.headline.large
            color: Colours.palette.m3primary
        }
        StyledText {
            text: root.deck.focusIsBreak ? "Descanso" : `Sesión de enfoque #${root.deck.focusSessions}`
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    Item { Layout.fillWidth: true }

    // Right: Controls
    RowLayout {
        spacing: Tokens.spacing.small

        // Play / Pause
        StyledRect {
            implicitWidth: 44
            implicitHeight: 44
            radius: Tokens.rounding.full
            color: Colours.palette.m3primaryContainer

            MaterialIcon {
                anchors.centerIn: parent
                text: root.deck.focusRunning ? "pause" : "play_arrow"
                fontStyle: Tokens.font.icon.medium
                color: Colours.palette.m3onPrimaryContainer
            }
            StateLayer {
                radius: Tokens.rounding.full
                onClicked: root.deck.toggleFocus()
            }
        }

        // Reset
        StyledRect {
            implicitWidth: 44
            implicitHeight: 44
            radius: Tokens.rounding.full
            color: (root.deck.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

            MaterialIcon {
                anchors.centerIn: parent
                text: "restart_alt"
                fontStyle: Tokens.font.icon.medium
                color: Colours.palette.m3onSurfaceVariant
            }
            StateLayer {
                radius: Tokens.rounding.full
                onClicked: root.deck.resetFocus()
            }
        }

        // Focus Ambient Light Toggle
        StyledRect {
            implicitWidth: 44
            implicitHeight: 44
            radius: Tokens.rounding.full
            color: root.deck.focusLightActive ? Colours.palette.m3tertiaryContainer : (root.deck.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

            MaterialIcon {
                anchors.centerIn: parent
                text: "wb_incandescent"
                fontStyle: Tokens.font.icon.medium
                color: root.deck.focusLightActive ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
            }
            StateLayer {
                radius: Tokens.rounding.full
                onClicked: root.deck.setFocusLight(!root.deck.focusLightActive)
            }
        }
    }
}
