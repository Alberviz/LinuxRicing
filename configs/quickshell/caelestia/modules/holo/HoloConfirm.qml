pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Contenido del panel de confirmación de una acción sobre archivos (borrar, mover, renombrar…).
// Lista lo que se va a tocar, el tamaño total y dos botones. Una barra se vacía en un solo
// tramo hasta que el plan caduca. También se puede decir «sí» / «no» por voz.
//
// Movimiento: las filas entran en cascada mientras el panel se asienta; luego los botones.
// La cuenta atrás avanza con un Timer a 10 Hz (no a 60 fps: la barra se mueve <1 px por
// paso) y solo mientras el plan vive; en los últimos 10 s la barra se enciende.
Item {
    id: root

    required property var panel

    readonly property var payload: panel?.payload ?? ({})
    readonly property bool borrar: payload.accion === "borrar"
    readonly property color acento: borrar ? Colours.palette.m3error : Colours.palette.m3primary
    // 1 = recién pedido, 0 = a punto de caducar
    property real restante: 1
    readonly property real total: Math.max(1, payload.segundos ?? 60)
    readonly property bool urge: restante * total <= 10

    function tam(b: real): string {
        if (b >= 1073741824)
            return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576)
            return Math.round(b / 1048576) + " MB";
        if (b >= 1024)
            return Math.round(b / 1024) + " KB";
        return b + " B";
    }

    function actualizar(): void {
        const queda = Math.max(0, (root.payload.expira ?? 0) - Date.now() / 1000);
        root.restante = Math.min(1, queda / root.total);
    }

    Component.onCompleted: actualizar()

    Timer {
        interval: 100
        repeat: true
        running: root.restante > 0 && root.visible
        onTriggered: root.actualizar()
    }

    component Entra: SequentialAnimation {
        id: ent

        required property Item objetivo
        property int retraso: 0

        PropertyAction {
            target: ent.objetivo
            property: "opacity"
            value: 0
        }
        PauseAnimation {
            duration: ent.retraso
        }
        NumberAnimation {
            target: ent.objetivo
            property: "opacity"
            to: 1
            duration: HoloGeo.tMedio
            easing.type: HoloGeo.curvaFundido
        }
    }

    // Lo que se va a tocar
    Column {
        id: filas

        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14

        Repeater {
            model: root.payload.items ?? []

            Item {
                id: fila

                required property var modelData

                required property int index

                width: filas.width
                height: 26
                transform: Translate {
                    x: (1 - fila.opacity) * -10
                }

                Entra {
                    objetivo: fila
                    retraso: 200 + Math.min(HoloGeo.maxEscalon, fila.index * HoloGeo.escalonFila * 2)
                    running: true
                }

                MaterialIcon {
                    id: ic

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: fila.modelData.es_dir ? "folder" : "draft"
                    fill: 1
                    fontStyle: Tokens.font.icon.size(16).build()
                    color: Qt.alpha(root.acento, 0.85)
                }
                StyledText {
                    anchors.left: ic.right
                    anchors.leftMargin: 8
                    anchors.right: tamTxt.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: fila.modelData.nuevo ? fila.modelData.nombre + "  →  " + fila.modelData.nuevo : fila.modelData.nombre
                    color: Colours.palette.m3onSurface
                    font.pixelSize: 13
                    elide: Text.ElideMiddle
                }
                StyledText {
                    id: tamTxt

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.tam(fila.modelData.tamano)
                    color: Colours.palette.m3onSurfaceVariant
                    font.pixelSize: 11
                }
            }
        }
        StyledText {
            visible: (root.payload.mas ?? 0) > 0
            height: visible ? 22 : 0
            text: "y " + root.payload.mas + " más…"
            color: Colours.palette.m3onSurfaceVariant
            font.pixelSize: 12
        }
    }

    // Resumen
    StyledText {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.bottom: botones.top
        anchors.bottomMargin: 10
        text: root.tam(root.payload.total_bytes ?? 0) + (root.payload.destino ? "  ·  a " + root.payload.destino : "")
        color: Colours.palette.m3onSurfaceVariant
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    // Botones (también vale decir «sí» / «no»)
    Row {
        id: botones

        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        spacing: 8

        // Tras las filas: primero se lee qué se va a tocar, luego se decide
        Entra {
            objetivo: botones
            retraso: 260 + Math.min(HoloGeo.maxEscalon, (root.payload.items ?? []).length * HoloGeo.escalonFila * 2)
            running: true
        }

        Rectangle {
            width: lblNo.implicitWidth + 36
            height: 34
            radius: 17
            color: Qt.alpha(Colours.palette.m3onSurface, maNo.pressed ? 0.2 : maNo.containsMouse ? 0.14 : 0.06)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3onSurface, 0.3)
            scale: maNo.pressed ? 0.96 : 1

            Behavior on color {
                ColorAnimation {
                    duration: HoloGeo.tMicro
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: HoloGeo.tMicro
                    easing.type: HoloGeo.curvaEntra
                }
            }

            StyledText {
                id: lblNo

                anchors.centerIn: parent
                text: "Cancelar"
                color: Colours.palette.m3onSurface
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: maNo

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: HoloState.cancelar(root.payload.plan)
            }
        }
        Rectangle {
            width: lblSi.implicitWidth + 36
            height: 34
            radius: 17
            color: Qt.alpha(root.acento, maSi.containsMouse ? 1 : 0.88)
            scale: maSi.pressed ? 0.96 : 1

            Behavior on color {
                ColorAnimation {
                    duration: HoloGeo.tMicro
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: HoloGeo.tMicro
                    easing.type: HoloGeo.curvaEntra
                }
            }

            StyledText {
                id: lblSi

                anchors.centerIn: parent
                text: root.borrar ? "Borrar" : "Confirmar"
                color: root.borrar ? Colours.palette.m3onError : Colours.palette.m3onPrimary
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: maSi

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: HoloState.confirmar(root.payload.plan)
            }
        }
    }

    // Cuenta atrás hasta que el plan caduca (en los últimos 10 s, más viva)
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: root.urge ? 4 : 3
        width: parent.width * root.restante
        color: Qt.alpha(root.acento, root.urge ? 1 : 0.6)

        Behavior on color {
            ColorAnimation {
                duration: HoloGeo.tMedio
            }
        }
    }
}
