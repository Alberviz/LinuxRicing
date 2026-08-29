pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.components.controls
import qs.services

// Editor de un "efecto" de dispositivo RGB: animación + fuente de color +
// velocidad + dirección. Lo usan AkkoCard (teclas / tira), BatteryActionRow
// (por acción) y DeviceCard (anillo MCHOSE). Emite `edited(effect)` con el
// objeto completo cada vez que se toca algo.
ColumnLayout {
    id: root

    required property string device        // "akko_keyboard" | "mchose_base"
    property string zone: "keys"           // "keys" | "sidestrip" | "" sin zonas
    property var effect: DeviceEffects.defaultEffect

    signal edited(var effect)

    readonly property var _eff: DeviceEffects.normalize(root.effect)
    readonly property var _anims: DeviceEffects.animationsFor(root.device, root.zone)
    readonly property var _sources: DeviceEffects.devices[root.device] ? DeviceEffects.devices[root.device].colourSources : []
    readonly property bool _directional: DeviceEffects.isDirectional(root.device, root._eff.animation)
    readonly property bool _ignoresColour: root._eff.animation === "off" || root._eff.animation === "neon"
    readonly property bool _animated: root._eff.animation !== "off" && root._eff.animation !== "solid"

    function _patch(p: var): void {
        root.edited(Object.assign({}, root._eff, p));
    }
    function _patchColour(p: var): void {
        root.edited(Object.assign({}, root._eff, {
            colour: Object.assign({}, root._eff.colour, p)
        }));
    }

    spacing: Tokens.spacing.small

    StyledText {
        text: qsTr("Animación")
        font: Tokens.font.label.small
        color: Colours.palette.m3onSurfaceVariant
    }

    StyledRect {
        id: animDropdownBtn

        Layout.fillWidth: true
        implicitHeight: 38
        radius: Tokens.rounding.medium
        color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.7)

        StateLayer {
            radius: parent.radius
            onClicked: animMenu.expanded = !animMenu.expanded
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "auto_awesome"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3primary
            }

            StyledText {
                Layout.fillWidth: true
                text: DeviceEffects.animationLabel(root._eff.animation)
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            MaterialIcon {
                text: "expand_more"
                fontStyle: Tokens.font.icon.medium
                color: Colours.palette.m3onSurfaceVariant
                rotation: animMenu.expanded ? 180 : 0

                Behavior on rotation {
                    Anim {}
                }
            }
        }

        Menu {
            id: animMenu

            attachTo: animDropdownBtn
            items: animVariants.instances
            active: items.find(m => (m as AnimMenuItem).animKey === root._eff.animation) ?? null
            onItemSelected: item => {
                root._patch({
                    animation: (item as AnimMenuItem).animKey
                });
            }

            Variants {
                id: animVariants

                model: root._anims

                AnimMenuItem {
                    required property string modelData

                    animKey: modelData
                    text: DeviceEffects.animationLabel(modelData)
                    icon: modelData === root._eff.animation ? "check" : ""
                }
            }
        }
    }

    component AnimMenuItem: MenuItem {
        property string animKey
    }

    // ---- Color ----
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: !root._ignoresColour

        StyledText {
            text: qsTr("Color")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: root._sources

                Chip {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 30
                    label: DeviceEffects.colourSourceLabels[modelData] ?? modelData
                    selected: root._eff.colour.source === modelData
                    onClicked: root._patchColour({
                        source: modelData
                    })
                }
            }
        }
        ColourPicker {
            Layout.fillWidth: true
            visible: root._eff.colour.source === "fixed"
            selectedColour: root._eff.colour.hex
            onPicked: hex => root._patchColour({
                hex: hex.replace(/^#/, "")
            })
        }
    }

    // ---- Velocidad ----
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: DeviceEffects.hasSpeed(root.device) && root._animated

        StyledText {
            text: qsTr("Velocidad: %1 / 5").arg(root._eff.speed)
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }
        StyledSlider {
            Layout.fillWidth: true
            implicitHeight: 14
            value: (root._eff.speed - 1) / 4
            interactionOnMove: false
            onInteraction: v => root._patch({
                speed: Math.max(1, Math.min(5, Math.round(1 + v * 4)))
            })
        }
    }

    // ---- Dirección (solo animaciones direccionales) ----
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: root._directional

        StyledText {
            text: qsTr("Dirección")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }
        RowLayout {
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: DeviceEffects.directions

                Chip {
                    required property var modelData
                    implicitWidth: 44
                    implicitHeight: 30
                    label: DeviceEffects.directionLabels[modelData]
                    selected: root._eff.direction === modelData
                    onClicked: root._patch({
                        direction: modelData
                    })
                }
            }
        }
    }
}
