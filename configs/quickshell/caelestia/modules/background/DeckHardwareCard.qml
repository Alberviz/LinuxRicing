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

GridLayout {
    id: root

    // Referencia al DesktopWidgetDeck dueño de los datos.
    required property var deck

    columns: 2
    columnSpacing: Tokens.spacing.large
    rowSpacing: Tokens.spacing.small

    // CPU
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        RowLayout {
            Layout.fillWidth: true
            MaterialIcon { text: "memory"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
            StyledText { text: "CPU"; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
            Item { Layout.fillWidth: true }
            StyledText { text: `${root.deck.cpuPct}%`; font: Tokens.font.label.medium; color: Colours.palette.m3primary }
        }
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4
            color: (root.deck.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5) : Colours.palette.m3surfaceContainerHigh)
            StyledRect {
                width: parent.width * (root.deck.cpuPct / 100.0)
                height: parent.height
                radius: 4
                color: Colours.palette.m3primary
                Behavior on width { Anim { duration: 300 } }
            }
        }
    }

    // RAM
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        RowLayout {
            Layout.fillWidth: true
            MaterialIcon { text: "straighten"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3secondary }
            StyledText { text: "RAM"; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
            Item { Layout.fillWidth: true }
            StyledText { text: `${root.deck.ramUsed} (${root.deck.ramPct}%)`; font: Tokens.font.label.medium; color: Colours.palette.m3secondary }
        }
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4
            color: (root.deck.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5) : Colours.palette.m3surfaceContainerHigh)
            StyledRect {
                width: parent.width * (root.deck.ramPct / 100.0)
                height: parent.height
                radius: 4
                color: Colours.palette.m3secondary
                Behavior on width { Anim { duration: 300 } }
            }
        }
    }

    // GPU
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        RowLayout {
            Layout.fillWidth: true
            MaterialIcon { text: "videogame_asset"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3tertiary }
            StyledText { text: "GPU (Nvidia)"; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
            Item { Layout.fillWidth: true }
            StyledText { text: `${root.deck.gpuTemp}°C (${root.deck.gpuUtil}%)`; font: Tokens.font.label.medium; color: Colours.palette.m3tertiary }
        }
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4
            color: (root.deck.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5) : Colours.palette.m3surfaceContainerHigh)
            StyledRect {
                width: parent.width * (Math.min(100, root.deck.gpuTemp) / 100.0)
                height: parent.height
                radius: 4
                color: Colours.palette.m3tertiary
                Behavior on width { Anim { duration: 300 } }
            }
        }
    }

    // VRAM
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        RowLayout {
            Layout.fillWidth: true
            MaterialIcon { text: "layers"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3primary }
            StyledText { text: "VRAM"; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
            Item { Layout.fillWidth: true }
            StyledText { text: `${root.deck.vramUsed} (${root.deck.vramPct}%)`; font: Tokens.font.label.medium; color: Colours.palette.m3primary }
        }
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4
            color: (root.deck.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.5) : Colours.palette.m3surfaceContainerHigh)
            StyledRect {
                width: parent.width * (root.deck.vramPct / 100.0)
                height: parent.height
                radius: 4
                color: Colours.palette.m3primary
                Behavior on width { Anim { duration: 300 } }
            }
        }
    }
}
