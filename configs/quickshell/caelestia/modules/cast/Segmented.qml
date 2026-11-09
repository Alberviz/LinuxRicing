pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Botón segmentado (M3) con indicador deslizante. model: [[valor, etiqueta], ...]
StyledRect {
    id: root

    property var model: []
    property string value
    signal picked(string value)

    readonly property int index: Math.max(0, model.findIndex(m => m[0] === value))
    readonly property real segW: model.length > 0 ? (width - pad * 2) / model.length : 0
    readonly property real pad: 3

    implicitWidth: model.length * 60 + pad * 2
    implicitHeight: 32
    radius: Tokens.rounding.full
    color: Colours.tPalette.m3surfaceContainerHighest

    StyledRect {
        x: root.pad + root.index * root.segW
        y: root.pad
        width: root.segW
        height: root.height - root.pad * 2
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary

        Behavior on x {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    Row {
        x: root.pad
        y: root.pad
        height: root.height - root.pad * 2

        Repeater {
            model: root.model

            Item {
                id: seg

                required property var modelData
                required property int index
                readonly property bool on: root.index === index

                width: root.segW
                height: parent.height

                StateLayer {
                    radius: Tokens.rounding.full
                    color: seg.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                    onClicked: if (!seg.on)
                        root.picked(seg.modelData[0])
                }
                StyledText {
                    anchors.centerIn: parent
                    text: seg.modelData[1]
                    font: Tokens.font.label.medium
                    color: seg.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant

                    Behavior on color {
                        CAnim {}
                    }
                }
            }
        }
    }
}
