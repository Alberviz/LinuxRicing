import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Chip seleccionable (Material You): mismo estilo que los chips de pantalla del drawer.
StyledRect {
    id: root

    property string label
    property string icon
    property bool selected
    signal clicked

    implicitWidth: row.implicitWidth + Tokens.padding.large * 2
    implicitHeight: row.implicitHeight + Tokens.padding.small * 2
    radius: Tokens.rounding.full
    color: selected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

    StateLayer {
        radius: Tokens.rounding.full
        onClicked: root.clicked()
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        MaterialIcon {
            visible: root.icon !== ""
            text: root.icon
            anchors.verticalCenter: parent.verticalCenter
            color: root.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font: Tokens.font.body.small
            color: root.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
        }
    }
}
