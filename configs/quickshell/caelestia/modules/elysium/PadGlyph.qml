import QtQuick
import qs.components
import qs.services

// Botón del mando dibujado (A, B, X, Y, −, ⌂).
Rectangle {
    id: g

    property string letter
    property color tone: Colours.palette.m3onSurface

    width: 26
    height: 26
    radius: 13
    color: "transparent"
    border.width: 1.5
    border.color: tone

    StyledText {
        anchors.centerIn: parent
        text: g.letter
        color: g.tone
        font.pointSize: 9
        font.weight: Font.Bold
    }
}
