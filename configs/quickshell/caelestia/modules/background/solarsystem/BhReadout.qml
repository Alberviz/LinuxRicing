import QtQuick

// Lectura discreta de la canción dentro de la sombra del agujero: tiempo, título y artista.
// Sin dependencias de servicios (todo por propiedades) para poder probarla en un arnés.
// Se funde a nada si no hay canción; el color sale de los roles del tema que le pasa el padre.
Item {
    id: root

    property string title: ""
    property string artist: ""
    property real position: 0     // s
    property real length: 0       // s
    property bool playing: false
    property color colInk: "#f8e1d6"
    property color colPrimary: "#f7b999"
    property string fontFamily: "JetBrainsMono NF"

    readonly property bool shown: title !== ""
    implicitHeight: col.implicitHeight
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

    function fmt(s) {
        if (typeof s !== "number" || isNaN(s) || s < 0) return "--:--";
        const t = Math.floor(s), m = Math.floor(t / 60), r = t % 60;
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }

    Column {
        id: col
        width: parent.width
        spacing: 3

        // «󰏤 00:12 / 02:22» — pausa/play y tiempo, muy tenue
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: (root.playing ? "󰐊 " : "󰏤 ") + root.fmt(root.position) + "  /  " + root.fmt(root.length)
            color: root.colPrimary
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 1.2
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            elide: Text.ElideRight
            color: root.colInk
            opacity: 0.92
            font.family: root.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.artist
            elide: Text.ElideRight
            color: root.colPrimary
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 0.6
        }
    }
}
