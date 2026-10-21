pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Vista previa del evento que se va a crear (o ya creado): fecha, hora con
// duración, franja del día con solapes, aviso de solape y descripción.
Rectangle {
    id: root

    property var ev: ({})
    property bool created: false
    property bool full: false

    readonly property var d0: new Date(ev.inicio ?? 0)
    readonly property var d1: new Date(ev.fin ?? 0)
    readonly property real mins: Math.round((d1 - d0) / 60000)
    readonly property color okCol: "#6fdcb4"

    function _dur(m: real): string {
        const h = Math.floor(m / 60), r = m % 60;
        return h > 0 ? (r > 0 ? h + " h " + r + " min" : h + " h") : r + " min";
    }
    readonly property var _dias: ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
    readonly property var _meses: ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]
    function _t(d): string {
        return d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes();
    }

    implicitHeight: col.implicitHeight + 20
    radius: 14
    color: created ? Qt.alpha(okCol, 0.13) : Qt.alpha(Colours.palette.m3onSurface, 0.06)
    border.width: created ? 1.5 : 0
    border.color: okCol
    Behavior on color {
        ColorAnimation {
            duration: 400
        }
    }

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        anchors.topMargin: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // «calendario»: mes y día
            Rectangle {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                radius: 9
                color: Colours.palette.m3surfaceContainerHigh
                clip: true

                Rectangle {
                    width: parent.width
                    height: 15
                    color: root.created ? root.okCol : Laura.cWait

                    StyledText {
                        anchors.centerIn: parent
                        text: root._meses[root.d0.getMonth()]
                        color: "#2a1d00"
                        font.pixelSize: 10
                        font.weight: Font.ExtraBold
                    }
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 17
                    text: root.d0.getDate()
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.ev.titulo ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    color: Colours.palette.m3onSurfaceVariant
                    text: `${root._dias[root.d0.getDay()]} ${root.d0.getDate()} · <b><font color="${root.created ? root.okCol : Laura.cWait}">${root._t(root.d0)}–${root._t(root.d1)}</font></b> (${root._dur(root.mins)})`
                    font.pixelSize: 13
                }
            }
        }

        DayStrip {
            id: strip

            Layout.fillWidth: true
            start: root.d0
            end: root.d1
            others: root.ev.dia ?? []
            created: root.created
        }

        // aviso de solape
        Rectangle {
            id: warn

            readonly property bool clash: strip.clashes.length > 0
            readonly property var c0: clash ? strip.clashes[0] : null
            Layout.fillWidth: true
            visible: !root.created
            implicitHeight: wt.implicitHeight + 12
            radius: 9
            color: Qt.alpha(clash ? Laura.cFail : root.okCol, clash ? 0.13 : 0.11)


            StyledText {
                id: wt

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 9
                wrapMode: Text.Wrap
                color: warn.clash ? Laura.cFail : root.okCol
                font.pixelSize: 12
                text: warn.clash ? `Se solapa ${Math.round(strip.clashMin)} min con «${warn.c0.titulo}» (${strip.hh(warn.c0.os)}–${strip.hh(warn.c0.oe)}). Puedes crearlo igualmente.` : "Sin solapes ese día."
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: (root.ev.descripcion ?? "").length > 0
            text: root.ev.descripcion ?? ""
            wrapMode: Text.Wrap
            maximumLineCount: root.full ? 8 : 2
            elide: Text.ElideRight
            color: Colours.palette.m3onSurfaceVariant
            font.pixelSize: 13
        }
    }
}
