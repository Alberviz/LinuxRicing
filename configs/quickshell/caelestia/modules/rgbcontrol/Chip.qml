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
    // Ancho por defecto a partir de la etiqueta (los usos en Layout con
    // Layout.fillWidth o con implicitWidth explícito lo sobreescriben).
    implicitWidth: chipText.implicitWidth + Tokens.padding.large * 2
    radius: Tokens.rounding.full
    color: selected ? activeColour : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.7)

    Behavior on color {
        CAnim {}
    }

    StateLayer {
        radius: root.radius
        onClicked: root.clicked()
    }

    StyledText {
        id: chipText
        anchors.centerIn: parent
        text: root.label
        font: Tokens.font.label.small
        color: root.selected ? root.activeText : Colours.palette.m3onSurface
    }
}
