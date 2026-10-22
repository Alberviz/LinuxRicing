pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Column {
    id: root

    spacing: Tokens.spacing.medium
    width: Tokens.sizes.bar.batteryWidth

    readonly property bool isLaptop: UPower.displayDevice.isLaptopBattery

    function formatSeconds(secs: int): string {
        const day = Math.floor(secs / 86400);
        const hr = Math.floor(secs / 3600) % 24;
        const min = Math.floor(secs / 60) % 60;

        let comps = [];
        if (day > 0)
            comps.push(`${day} d`);
        if (hr > 0)
            comps.push(`${hr} h`);
        if (min > 0)
            comps.push(`${min} min`);

        return comps.join(" ");
    }

    // Cabecera: icono y porcentaje grandes, y debajo el estado de carga.
    Row {
        visible: root.isLaptop
        spacing: Tokens.spacing.medium

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.getBatteryIcon(UPower.displayDevice.percentage, !UPower.onBattery)
            fontStyle: Tokens.font.icon.extraLarge
            color: Colours.palette.m3primary
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: `${Math.round(UPower.displayDevice.percentage * 100)} %`
                font: Tokens.font.title.medium
            }

            StyledText {
                text: {
                    const dev = UPower.displayDevice;
                    if (UPower.onBattery) {
                        const t = root.formatSeconds(dev.timeToEmpty);
                        return t ? qsTr("Quedan %1").arg(t) : qsTr("Calculando…");
                    }
                    if (dev.state === UPowerDeviceState.FullyCharged)
                        return qsTr("Cargada");
                    if (dev.state === UPowerDeviceState.Charging) {
                        const t = root.formatSeconds(dev.timeToFull);
                        return t ? qsTr("Cargando · llena en %1").arg(t) : qsTr("Cargando");
                    }
                    return qsTr("Enchufada");
                }
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }

    StyledText {
        visible: !root.isLaptop
        text: qsTr("Perfil de energía: %1").arg(PowerProfile.toString(PowerProfiles.profile))
    }

    Loader {
        asynchronous: true
        anchors.horizontalCenter: parent.horizontalCenter

        active: PowerProfiles.degradationReason !== PerformanceDegradationReason.None

        height: active ? ((item as Item)?.implicitHeight ?? 0) : 0

        sourceComponent: StyledRect {
            implicitWidth: child.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: child.implicitHeight + Tokens.padding.large

            color: Colours.palette.m3error
            radius: Tokens.rounding.large

            Column {
                id: child

                anchors.centerIn: parent

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -font.pointSize / 10

                        text: "warning"
                        color: Colours.palette.m3onError
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Performance Degraded")
                        color: Colours.palette.m3onError
                        font: Tokens.font.mono.builders.medium.weight(Font.Medium).build()
                    }

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -font.pointSize / 10

                        text: "warning"
                        color: Colours.palette.m3onError
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: qsTr("Reason: %1").arg(PerformanceDegradationReason.toString(PowerProfiles.degradationReason))
                    color: Colours.palette.m3onError
                }
            }
        }
    }

    StyledRect {
        id: profiles

        property string current: {
            const p = PowerProfiles.profile;
            if (p === PowerProfile.PowerSaver)
                return saver.icon;
            if (p === PowerProfile.Performance)
                return perf.icon;
            return balance.icon;
        }

        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: saver.implicitHeight + balance.implicitHeight + perf.implicitHeight + Tokens.padding.medium * 2 + Tokens.spacing.largeIncreased * 2
        implicitHeight: Math.max(saver.implicitHeight, balance.implicitHeight, perf.implicitHeight) + Tokens.padding.small

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.full

        StyledRect {
            id: indicator

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
            state: profiles.current

            states: [
                State {
                    name: saver.icon

                    Fill {
                        item: saver
                    }
                },
                State {
                    name: balance.icon

                    Fill {
                        item: balance
                    }
                },
                State {
                    name: perf.icon

                    Fill {
                        item: perf
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }
        }

        Profile {
            id: saver

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.extraSmall

            profile: PowerProfile.PowerSaver
            icon: "energy_savings_leaf"
        }

        Profile {
            id: balance

            anchors.centerIn: parent

            profile: PowerProfile.Balanced
            icon: "balance"
        }

        Profile {
            id: perf

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.extraSmall

            profile: PowerProfile.Performance
            icon: "rocket_launch"
        }
    }

    // ---- Acciones extra bajo los perfiles ----

    // Estado del "boost" de carga (lo escribe `lenovo-battery-control --monitor`).
    FileView {
        id: boostState

        path: `${Quickshell.env("HOME")}/.cache/lenovo-battery/boost_state.json`
        printErrors: false
        watchChanges: true

        property bool active: false

        onFileChanged: reload()
        onLoaded: active = true
        onLoadFailed: active = false
    }

    // Acciones como filas a todo el ancho: icono en círculo y título + estado.
    Column {
        width: parent.width
        spacing: Tokens.spacing.small

        // Cargar al 100% una sola vez (portátiles Lenovo con Modo Conservación).
        // Al llegar al 100% el propio script reactiva el límite del 80%.
        ActionTile {
            visible: root.isLaptop
            icon: boostState.active ? "stop_circle" : "battery_android_bolt"
            title: qsTr("Carga 100%")
            subtitle: boostState.active ? qsTr("En curso · cancelar") : qsTr("Una sola vez")
            checked: boostState.active
            onTriggered: Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/lenovo-battery-control`, boostState.active ? "--cancel" : "--boost"])
        }

        // Apagar/encender el shader del sistema solar a mano, sin entrar en modo
        // ahorro (no toca el perfil de CPU ni Hyprland — sólo descarga la vista).
        // Al apagarlo, el escritorio cae al wallpaper estático (no a negro plano).
        ActionTile {
            icon: SolarSystemModel.enabled ? "planet" : "wallpaper"
            title: qsTr("Sistema solar")
            subtitle: SolarSystemModel.enabled ? qsTr("Shaders activos") : qsTr("Solo wallpaper")
            checked: SolarSystemModel.enabled
            onTriggered: SolarSystemModel.toggle()
        }
    }

    component ActionTile: StyledRect {
        id: tile

        required property string icon
        required property string title
        required property string subtitle
        property bool checked: false

        signal triggered

        width: parent.width
        implicitHeight: tileContent.implicitHeight + Tokens.padding.small * 2

        color: tile.checked ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.full

        StateLayer {
            radius: tile.radius
            color: tile.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            onClicked: tile.triggered()
        }

        Row {
            id: tileContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledRect {
                id: iconBubble

                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: implicitHeight
                implicitHeight: tileIcon.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.full
                color: tile.checked ? Qt.alpha(Colours.palette.m3onPrimary, 0.16) : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

                MaterialIcon {
                    id: tileIcon

                    anchors.centerIn: parent
                    text: tile.icon
                    fontStyle: Tokens.font.icon.medium
                    fill: tile.checked ? 1 : 0
                    color: tile.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - iconBubble.width - parent.spacing

                StyledText {
                    width: parent.width
                    text: tile.title
                    font: Tokens.font.label.large
                    elide: Text.ElideRight
                    color: tile.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                }

                StyledText {
                    width: parent.width
                    text: tile.subtitle
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                    color: tile.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    opacity: 0.85
                }
            }
        }
    }

    component Fill: AnchorChanges {
        required property Item item

        target: indicator
        anchors.left: item.left
        anchors.right: item.right
        anchors.top: item.top
        anchors.bottom: item.bottom
    }

    component Profile: Item {
        required property string icon
        required property int profile

        implicitWidth: icon.implicitHeight + Tokens.padding.small
        implicitHeight: icon.implicitHeight + Tokens.padding.small

        StateLayer {
            radius: Tokens.rounding.full
            color: profiles.current === parent.icon ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            onClicked: PowerProfiles.profile = parent.profile
        }

        MaterialIcon {
            id: icon

            anchors.centerIn: parent

            text: parent.icon
            fontStyle: Tokens.font.icon.large
            color: profiles.current === text ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
            fill: profiles.current === text ? 1 : 0

            Behavior on fill {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }
}
