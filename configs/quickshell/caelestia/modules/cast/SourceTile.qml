import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Tarjeta de «Qué proyectar»: icono grande sobre la etiqueta. La elegida se rellena (icono y fondo)
// y redondea más, como los botones expresivos de M3.
StyledRect {
    id: root

    property string label
    property string icon
    property bool selected
    signal clicked

    implicitHeight: 74
    radius: selected ? Tokens.rounding.extraLarge : Tokens.rounding.large
    color: selected ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer

    Behavior on radius {
        Anim {
            type: Anim.FastSpatial
        }
    }

    StateLayer {
        radius: root.radius
        color: root.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
        onClicked: root.clicked()
    }

    Column {
        anchors.centerIn: parent
        spacing: 2

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            fill: root.selected ? 1 : 0
            fontStyle: Tokens.font.icon.large
            color: root.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant

            Behavior on fill {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font: Tokens.font.label.medium
            color: root.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
        }
    }
}
