pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Contenido del panel de lista de archivos holográficos.
// Muestra los elementos de la escena con numeración, miniatura por tipo,
// nombre y fecha relativa (o marca de envío al móvil).
Item {
    id: root

    required property var panel

    // Formateador de fecha relativa («hace 3 min», «ayer», «lun», etc.)
    function formatRelativeTime(mtime: real): string {
        if (!mtime || mtime <= 0)
            return "";
        const now = Date.now() / 1000;
        const diff = Math.max(0, now - mtime);
        if (diff < 60)
            return "hace un momento";
        if (diff < 3600)
            return "hace " + Math.floor(diff / 60) + " min";
        if (diff < 86400)
            return "hace " + Math.floor(diff / 3600) + " h";
        if (diff < 172800)
            return "ayer";
        const d = new Date(mtime * 1000);
        const dias = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
        if (diff < 604800)
            return dias[d.getDay()];
        const meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
        return d.getDate() + " " + meses[d.getMonth()];
    }

    ListView {
        id: listView
        anchors.top: parent.top
        anchors.topMargin: (typeof HoloGeo !== "undefined" && HoloGeo.listaArriba !== undefined) ? HoloGeo.listaArriba : 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: HoloState.items

        delegate: Item {
            id: fila

            required property var modelData
            required property int index

            readonly property bool abierto: (HoloState.paneles || []).some(p => p && p.id === "v" + fila.modelData.n)
            readonly property bool enviado: !!(fila.modelData && fila.modelData.enviado)

            // Acción ejecutada sobre esta fila (borrada, movida…): se va deslizando y se apaga
            property real fuera: 0

            opacity: 1 - fuera
            transform: Translate {
                x: fila.fuera * 70
            }

            Connections {
                function onFx(ev: var): void {
                    if ((ev.filas || []).indexOf(fila.modelData.n) >= 0)
                        desaparece.start();
                }

                target: HoloState
            }
            NumberAnimation {
                id: desaparece

                target: fila
                property: "fuera"
                to: 1
                duration: 420
                easing.type: Easing.InCubic
            }

            width: listView.width
            height: (typeof HoloGeo !== "undefined" && HoloGeo.fila !== undefined) ? HoloGeo.fila : 38

            // Fondo con realce al pasar el ratón
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                radius: Tokens.rounding.small
                color: rowMouse.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.08) : "transparent"
            }

            // Número en píldora
            Rectangle {
                id: pillNum
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 22
                radius: 11
                color: fila.abierto ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3primary, 0.18)

                Text {
                    anchors.centerIn: parent
                    text: fila.modelData ? fila.modelData.n : ""
                    color: fila.abierto ? Colours.palette.m3onPrimary : Colours.palette.m3primary
                    font.family: Tokens.font.label.small.family
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }

            // Miniatura 22×16 redondeada
            Item {
                id: thumb
                anchors.left: pillNum.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 16

                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    clip: true
                    color: {
                        if (!fila.modelData)
                            return Colours.palette.m3secondary;
                        switch (fila.modelData.tipo) {
                        case "carpeta":
                            return "transparent";
                        case "pdf":
                            return Colours.palette.m3error;
                        case "texto":
                            return Colours.palette.m3outline;
                        case "video":
                        case "audio":
                            return Colours.palette.m3tertiary;
                        default:
                            return Colours.palette.m3secondary;
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: !!(fila.modelData && fila.modelData.tipo === "carpeta")
                        text: "folder"
                        fill: 1
                        fontStyle: Tokens.font.icon.size(20).build()
                        color: Colours.palette.m3primary
                    }

                    Image {
                        anchors.fill: parent
                        visible: !!(fila.modelData && fila.modelData.tipo === "imagen")
                        source: (fila.modelData && fila.modelData.tipo === "imagen" && fila.modelData.ruta)
                                ? (fila.modelData.ruta.startsWith("file://") ? fila.modelData.ruta : ("file://" + fila.modelData.ruta))
                                : ""
                        sourceSize.width: 44
                        sourceSize.height: 32
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
            }

            // Fecha relativa o aviso de envío a la derecha
            Text {
                id: metaText
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: fila.enviado ? "→ móvil ✓" : (fila.modelData ? root.formatRelativeTime(fila.modelData.mtime) : "")
                color: fila.enviado ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                font.family: Tokens.font.label.small.family
                font.pixelSize: 11
                font.weight: fila.enviado ? Font.Bold : Font.Normal
            }

            // Nombre con elipsis
            Text {
                anchors.left: thumb.right
                anchors.leftMargin: 8
                anchors.right: metaText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: fila.modelData.nombre ?? ""
                color: Colours.palette.m3onSurface
                font.family: Tokens.font.body.small.family
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: HoloState.abrir(fila.modelData.n)
            }
        }
    }

    // Pie con dos chips de sugerencia
    Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: (typeof HoloGeo !== "undefined" && HoloGeo.listaPie !== undefined) ? HoloGeo.listaPie : 52

        Row {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                height: 24
                width: chip1.implicitWidth + 16
                radius: 12
                color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.6)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outline, 0.25)

                Text {
                    id: chip1
                    anchors.centerIn: parent
                    text: "di «abre la 2»"
                    color: Colours.palette.m3onSurfaceVariant
                    font.family: Tokens.font.label.small.family
                    font.pixelSize: 11
                }
            }

            Rectangle {
                height: 24
                width: chip2.implicitWidth + 16
                radius: 12
                color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.6)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outline, 0.25)

                Text {
                    id: chip2
                    anchors.centerIn: parent
                    text: "o haz clic"
                    color: Colours.palette.m3onSurfaceVariant
                    font.family: Tokens.font.label.small.family
                    font.pixelSize: 11
                }
            }
        }
    }
}
