pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Agenda en holograma. vista «dia»: raíl de horas con lo pasado atenuado y lo siguiente
// resaltado. vista «semana»: 7 columnas con chips de evento. Sin bucles: un Timer de
// 60 s mueve «ahora» solo mientras el panel existe.
Item {
    id: root

    required property var panel
    readonly property var payload: panel?.payload ?? ({})
    readonly property var dias: payload.dias ?? []
    readonly property bool semana: payload.vista === "semana"
    readonly property color acc: Colours.palette.m3primary
    property string ahora: Qt.formatTime(new Date(), "HH:mm")

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.ahora = Qt.formatTime(new Date(), "HH:mm")
    }

    // estado de un evento de hoy respecto a la hora actual
    function fase(dia, ev): string {
        if (!dia.hoy || !ev.ini)
            return dia.fecha < Qt.formatDate(new Date(), "yyyy-MM-dd") ? "pasado" : "futuro";
        if ((ev.fin || ev.ini) <= ahora)
            return "pasado";
        return ev.ini <= ahora ? "ahora" : "futuro";
    }

    // ---------------------------------------------------------------- vista día
    Flickable {
        id: diaView
        visible: !root.semana
        anchors.fill: parent
        anchors.margins: 16
        contentHeight: diaCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        readonly property var dia: root.dias.length ? root.dias[0] : ({ eventos: [] })
        // primer evento que aún no ha terminado = «lo siguiente»
        readonly property int sig: {
            const evs = dia.eventos ?? [];
            for (let i = 0; i < evs.length; i++)
                if (root.fase(dia, evs[i]) !== "pasado")
                    return i;
            return -1;
        }

        Column {
            id: diaCol
            width: parent.width
            spacing: 0

            Repeater {
                model: diaView.dia.eventos ?? []

                Item {
                    id: fila
                    required property var modelData
                    required property int index
                    readonly property string f: root.fase(diaView.dia, modelData)
                    readonly property bool nuevo: modelData.nuevo ?? false
                    readonly property bool choca: modelData.choca ?? false
                    readonly property bool destacado: root.payload.propuesta ? nuevo : index === diaView.sig
                    width: diaCol.width
                    height: 58
                    opacity: f === "pasado" && !root.payload.propuesta ? 0.45 : 1

                    // aparición escalonada
                    property real t: 0
                    Component.onCompleted: entrada.start()
                    NumberAnimation {
                        id: entrada
                        target: fila
                        property: "t"
                        to: 1
                        duration: 420 + fila.index * 70
                        easing.type: Easing.OutCubic
                    }
                    transform: Translate {
                        y: (1 - fila.t) * 14
                    }

                    // hora
                    Column {
                        id: horas
                        width: 50
                        anchors.verticalCenter: parent.verticalCenter
                        StyledText {
                            anchors.right: parent.right
                            text: fila.modelData.ini || "todo"
                            color: fila.destacado ? root.acc : Colours.palette.m3onSurface
                            font.pointSize: 11
                            font.weight: Font.DemiBold
                            font.features: {
                                "tnum": 1
                            }
                        }
                        StyledText {
                            anchors.right: parent.right
                            text: fila.modelData.fin || (fila.modelData.ini ? "" : "el día")
                            color: Colours.palette.m3onSurfaceVariant
                            font.pointSize: 9
                            font.features: {
                                "tnum": 1
                            }
                        }
                    }
                    // raíl
                    Rectangle {
                        x: horas.width + 15
                        width: 2
                        height: parent.height
                        color: Qt.alpha(Colours.palette.m3onSurface, 0.1)
                    }
                    Rectangle {
                        x: horas.width + 16 - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: fila.destacado ? 12 : 8
                        height: width
                        radius: width / 2
                        color: fila.destacado ? root.acc : Colours.palette.m3surface
                        border.width: 2
                        border.color: fila.destacado ? Qt.alpha(root.acc, 0.35) : Qt.alpha(Colours.palette.m3onSurface, 0.35)
                    }
                    // tarjeta
                    Rectangle {
                        x: horas.width + 32
                        width: parent.width - x
                        height: 46
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 12
                        color: fila.destacado ? Qt.alpha(root.acc, 0.16) : fila.choca ? Qt.alpha(Colours.palette.m3error, 0.1) : Qt.alpha(Colours.palette.m3onSurface, 0.05)
                        border.width: fila.destacado || fila.choca ? 1 : 0
                        border.color: fila.choca && !fila.nuevo ? Qt.alpha(Colours.palette.m3error, 0.5) : Qt.alpha(root.acc, 0.4)
                        // el evento propuesto respira (borde discontinuo no hay en Rectangle: pulso de opacidad de un disparo)
                        SequentialAnimation on opacity {
                            running: fila.nuevo
                            loops: 2
                            NumberAnimation { to: 0.55; duration: 450; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: chip.left
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: fila.modelData.titulo
                            elide: Text.ElideRight
                            color: Colours.palette.m3onSurface
                            font.pointSize: 11
                            font.weight: fila.destacado ? Font.DemiBold : Font.Normal
                        }
                        Rectangle {
                            id: chip
                            visible: fila.destacado
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: visible ? chipTxt.implicitWidth + 14 : 0
                            height: 20
                            radius: 10
                            color: fila.nuevo && fila.choca ? Colours.palette.m3error : root.acc
                            StyledText {
                                id: chipTxt
                                anchors.centerIn: parent
                                text: fila.nuevo ? (fila.choca ? "SE SOLAPA" : "NUEVO") : fila.f === "ahora" ? "AHORA" : "SIGUIENTE"
                                color: fila.nuevo && fila.choca ? Colours.palette.m3onError : Colours.palette.m3onPrimary
                                font.pointSize: 7.5
                                font.weight: Font.Bold
                                font.letterSpacing: 1
                            }
                        }
                    }
                }
            }
        }

        // día libre
        Column {
            visible: (diaView.dia.eventos ?? []).length === 0
            anchors.centerIn: parent
            spacing: 8
            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "event_available"
                color: root.acc
                fill: 1
                fontStyle: Tokens.font.icon.size(40).build()
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Día libre"
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: 12
            }
        }
    }

    // ---------------------------------------------------------------- vista semana
    Row {
        id: semRow
        visible: root.semana
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        Repeater {
            model: root.semana ? root.dias : []

            Rectangle {
                id: col
                required property var modelData
                required property int index
                readonly property var evs: modelData.eventos ?? []
                width: (semRow.width - semRow.spacing * 6) / 7
                height: semRow.height
                radius: 14
                color: modelData.hoy ? Qt.alpha(root.acc, 0.1) : Qt.alpha(Colours.palette.m3onSurface, 0.035)
                border.width: modelData.hoy ? 1 : 0
                border.color: Qt.alpha(root.acc, 0.35)

                property real t: 0
                opacity: t
                transform: Translate {
                    y: (1 - col.t) * 18
                }
                NumberAnimation on t {
                    from: 0
                    to: 1
                    duration: 380 + col.index * 55
                    easing.type: Easing.OutCubic
                }

                Column {
                    id: cab
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: col.modelData.dia.toUpperCase()
                        color: col.modelData.hoy ? root.acc : Colours.palette.m3onSurfaceVariant
                        font.pointSize: 8
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 30
                        height: 30
                        radius: 15
                        color: col.modelData.hoy ? root.acc : "transparent"
                        StyledText {
                            anchors.centerIn: parent
                            text: col.modelData.num
                            color: col.modelData.hoy ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            font.pointSize: 13
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Column {
                    anchors.top: cab.bottom
                    anchors.topMargin: 10
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 5
                    spacing: 5

                    Repeater {
                        model: col.evs.slice(0, 5)
                        Rectangle {
                            id: ev
                            required property var modelData
                            readonly property bool pasado: root.fase(col.modelData, modelData) === "pasado"
                            width: parent.width
                            height: evCol.implicitHeight + 10
                            radius: 8
                            color: Qt.alpha(root.acc, ev.pasado ? 0.06 : 0.16)
                            opacity: ev.pasado ? 0.5 : 1
                            Rectangle {
                                width: 3
                                height: parent.height - 10
                                anchors.verticalCenter: parent.verticalCenter
                                x: 4
                                radius: 1.5
                                color: root.acc
                            }
                            Column {
                                id: evCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 12
                                anchors.rightMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: ev.modelData.ini || "todo el día"
                                    color: root.acc
                                    font.pointSize: 7.5
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    width: parent.width
                                    text: ev.modelData.titulo
                                    color: Colours.palette.m3onSurface
                                    font.pointSize: 8.5
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                    StyledText {
                        visible: col.evs.length > 5
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "+" + (col.evs.length - 5)
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: 8.5
                    }
                }
            }
        }
    }
}
