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

    // Filas que se pintan. Al cerrar la escena el daemon vacía `items` antes de que el panel
    // termine de irse: se conservan las últimas para que no se vacíe a medio vuelo.
    // (se asigna a mano, sin binding: un binding se actualizaría solo y no se podría congelar)
    property var filas: []

    // El daemon manda `items` antes que `paneles`: decidir al final del evento, cuando ya se
    // sabe si la escena sigue abierta
    function tomarFilas(): void {
        if (HoloState.activo || (HoloState.items || []).length > 0)
            filas = HoloState.items;
    }

    Connections {
        function onItemsChanged(): void {
            Qt.callLater(root.tomarFilas);
        }

        target: HoloState
    }

    // Las filas entran en cascada solo cuando el contenido es nuevo (lista recién abierta u
    // otra búsqueda). El daemon reenvía `items` en cada evento y la ListView recrea sus
    // delegados: sin esta guarda la cascada se repetiría cada vez que se abre un visor.
    readonly property string firma: (filas || []).map(i => i.n + ":" + i.nombre).join("|")
    // Hasta cuándo una fila recién creada debe entrar animada, y desde cuándo cuenta
    property real cascadaHasta: Date.now() + 900
    property real cascadaDesde: Date.now() + 160   // al abrirse la lista: mientras aún vuela

    Component.onCompleted: filas = HoloState.items

    onFirmaChanged: {
        // La carga inicial ya tiene su cascada (cascadaDesde/Hasta de arriba)
        if (Date.now() < cascadaHasta - 300)
            return;
        cascadaDesde = Date.now();
        cascadaHasta = Date.now() + 600;
    }

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
        model: root.filas

        delegate: Item {
            id: fila

            required property var modelData
            required property int index

            readonly property bool abierto: (HoloState.paneles || []).some(p => p && p.id === "v" + fila.modelData.n)
            readonly property bool enviado: !!(fila.modelData && fila.modelData.enviado)

            readonly property bool sel: !!fila.modelData && fila.modelData.n === HoloState.seleccionado
            readonly property bool senalada: rowMouse.containsMouse || (!!fila.modelData && fila.modelData.n === HoloState.resaltado)

            // Acción ejecutada sobre esta fila (borrada, movida…): se va deslizando y se apaga
            property real fuera: 0
            // 0 → 1 al entrar (cascada)
            property real entra: 1

            opacity: entra * (1 - fuera)
            transform: Translate {
                x: fila.fuera * 70 - (1 - fila.entra) * 14
            }

            Component.onCompleted: {
                const ahora = Date.now();
                if (ahora > root.cascadaHasta)
                    return;
                entra = 0;
                entrada.retraso = Math.max(0, root.cascadaDesde - ahora) + Math.min(HoloGeo.maxEscalon, index * HoloGeo.escalonFila);
                entrada.start();
            }

            SequentialAnimation {
                id: entrada

                property int retraso: 0

                PauseAnimation {
                    duration: entrada.retraso
                }
                NumberAnimation {
                    target: fila
                    property: "entra"
                    to: 1
                    duration: HoloGeo.tMedio
                    easing.type: HoloGeo.curvaEntra
                }
            }

            Connections {
                function onFx(ev: var): void {
                    const filas = ev.filas || [];
                    const i = filas.indexOf(fila.modelData.n);
                    if (i < 0)
                        return;
                    // Varias filas: se van una tras otra, de arriba abajo
                    desaparece.retraso = Math.min(HoloGeo.maxEscalon, i * HoloGeo.escalonFila * 2);
                    entrada.stop();
                    desaparece.start();
                }

                target: HoloState
            }
            SequentialAnimation {
                id: desaparece

                property int retraso: 0

                PauseAnimation {
                    duration: desaparece.retraso
                }
                NumberAnimation {
                    target: fila
                    property: "fuera"
                    to: 1
                    duration: HoloGeo.tLento
                    easing.type: HoloGeo.curvaSale
                }
            }

            width: listView.width
            height: (typeof HoloGeo !== "undefined" && HoloGeo.fila !== undefined) ? HoloGeo.fila : 38

            // Fondo: realce al pasar el ratón (o su visor), tinte del tema si es «esa»
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                radius: Tokens.rounding.small
                color: fila.sel ? Qt.alpha(Colours.palette.m3primary, fila.senalada ? 0.16 : 0.10) : Qt.alpha(Colours.palette.m3onSurface, fila.senalada ? 0.08 : 0)
                scale: rowMouse.pressed ? 0.985 : 1

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

                // Marca lateral de «esa»: crece desde el centro
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: fila.sel ? parent.height - 14 : 0
                    radius: 1
                    color: Colours.palette.m3primary
                    visible: height > 0.5

                    Behavior on height {
                        NumberAnimation {
                            duration: HoloGeo.tMedio
                            easing.type: HoloGeo.curvaEntra
                        }
                    }
                }
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

                Behavior on color {
                    ColorAnimation {
                        duration: HoloGeo.tMedio
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: fila.modelData ? fila.modelData.n : ""
                    color: fila.abierto ? Colours.palette.m3onPrimary : Colours.palette.m3primary

                    Behavior on color {
                        ColorAnimation {
                            duration: HoloGeo.tMedio
                        }
                    }
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
                // Señala su visor (y el hilo) mientras el ratón está encima
                onContainsMouseChanged: {
                    if (!fila.modelData)
                        return;
                    if (containsMouse)
                        HoloState.resaltado = fila.modelData.n;
                    else if (HoloState.resaltado === fila.modelData.n)
                        HoloState.resaltado = -1;
                }
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
        opacity: 0

        // Las sugerencias llegan al final de la cascada de filas: primero el contenido
        SequentialAnimation on opacity {
            PauseAnimation {
                duration: 160 + Math.min(HoloGeo.maxEscalon, (root.filas || []).length * HoloGeo.escalonFila)
            }
            NumberAnimation {
                to: 1
                duration: HoloGeo.tMedio
                easing.type: HoloGeo.curvaFundido
            }
        }

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
