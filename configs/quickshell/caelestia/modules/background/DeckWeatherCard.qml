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

    // Referencia al DesktopWidgetDeck dueño de los datos.
    required property var deck

    spacing: Tokens.spacing.large

    // Left: Big Temp & Icon
    RowLayout {
        spacing: Tokens.spacing.medium

        MaterialIcon {
            text: root.deck.weatherIcon
            fontStyle: Tokens.font.icon.large
            color: Colours.palette.m3primary
        }

        ColumnLayout {
            spacing: 0
            StyledText {
                text: root.deck.weatherTemp
                font: Tokens.font.headline.large
                color: Colours.palette.m3onSurface
            }
            StyledText {
                text: `${root.deck.weatherDesc} • ${root.deck.weatherCity}`
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }

    Item { Layout.fillWidth: true }

    // Right: 4 Metrics Grid
    GridLayout {
        columns: 2
        columnSpacing: Tokens.spacing.medium
        rowSpacing: Tokens.spacing.small

        RowLayout {
            spacing: Tokens.spacing.extraSmall
            MaterialIcon { text: "water_drop"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3secondary }
            StyledText { text: `Humedad: ${root.deck.weatherHumidity}`; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
        }
        RowLayout {
            spacing: Tokens.spacing.extraSmall
            MaterialIcon { text: "air"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3secondary }
            StyledText { text: `Viento: ${root.deck.weatherWind}`; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
        }
        RowLayout {
            spacing: Tokens.spacing.extraSmall
            MaterialIcon { text: "wb_twilight"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3tertiary }
            StyledText { text: `Amanecer: ${root.deck.weatherSunrise}`; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
        }
        RowLayout {
            spacing: Tokens.spacing.extraSmall
            MaterialIcon { text: "nights_stay"; fontStyle: Tokens.font.icon.small; color: Colours.palette.m3tertiary }
            StyledText { text: `Atardecer: ${root.deck.weatherSunset}`; font: Tokens.font.label.medium; color: Colours.palette.m3onSurface }
        }
    }
}
