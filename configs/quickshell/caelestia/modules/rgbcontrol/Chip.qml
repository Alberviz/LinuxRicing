pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    property string label
    property bool selected
    property color activeColour: Colours.palette.m3primary
    property color activeText: Colours.palette.m3onPrimary
    signal clicked

    implicitHeight: 30
    radius: Tokens.rounding.normal
    color: selected ? activeColour : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.7)

    Behavior on color {
        CAnim {}
    }

    StateLayer {
        radius: root.radius
        onClicked: root.clicked()
    }

    StyledText {
        anchors.centerIn: parent
        text: root.label
        font: Tokens.font.label.small
        color: root.selected ? root.activeText : Colours.palette.m3onSurface
    }
}
