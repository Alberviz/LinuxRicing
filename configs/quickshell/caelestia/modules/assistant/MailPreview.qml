import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Borrador de correo: para, asunto y texto (recortado salvo `full`).
Rectangle {
    id: root

    property var mail: ({})
    property bool full: false

    implicitHeight: col.implicitHeight + 20
    radius: 11
    color: Qt.alpha(Colours.palette.m3onSurface, 0.06)
    clip: true
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        anchors.topMargin: 10
        spacing: 6

        StyledText {
            Layout.fillWidth: true
            textFormat: Text.StyledText
            elide: Text.ElideRight
            color: Colours.palette.m3onSurfaceVariant
            font.pixelSize: 12.5
            text: `Para <b><font color="${Colours.palette.m3onSurface}">${root.mail.para ?? ""}</font></b> · Asunto <b><font color="${Colours.palette.m3onSurface}">${root.mail.asunto ?? ""}</font></b>`
        }
        StyledText {
            Layout.fillWidth: true
            text: root.mail.cuerpo ?? ""
            wrapMode: Text.Wrap
            maximumLineCount: root.full ? 40 : 4
            elide: Text.ElideRight
            font.pixelSize: 13
            lineHeight: 1.1
        }
    }
}
