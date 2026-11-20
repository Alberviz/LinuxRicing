import QtQuick
import qs.components
import qs.services

// Botón o gatillo del mando dibujado (A, B, X, Y, −, ⌂, LB, RB, LB+↓…).
Rectangle {
    id: g

    property string letter
    property color tone: Colours.palette.m3onSurface
    property int size: 26

    implicitWidth: Math.max(size, lbl.implicitWidth + (letter.length > 1 ? 14 : 0))
    implicitHeight: size
    width: implicitWidth
    height: implicitHeight
    radius: size / 2
    color: "transparent"
    border.width: 1.5
    border.color: tone

    StyledText {
        id: lbl

        anchors.centerIn: parent
        text: g.letter
        color: g.tone
        font.pointSize: g.letter.length > 2 ? 7.5 : (g.size < 24 ? 8 : 9)
        font.weight: Font.Bold
    }
}
