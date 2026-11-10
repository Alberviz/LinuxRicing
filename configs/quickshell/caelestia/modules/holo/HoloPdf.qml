pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Visor de documento PDF holográfico.
// Muestra la imagen de la página actual renderizada por el backend poppler,
// indicando «pág N/M» abajo y permitiendo cambiar de página con la rueda
// del ratón con un temporizador de desfase de 250 ms para evitar saturar el daemon.
Item {
    id: root

    required property var panel

    readonly property var payload: panel && panel.payload ? panel.payload : ({})
    readonly property int paginaActual: (root.payload && root.payload.pagina) ? root.payload.pagina : 1
    readonly property int totalPaginas: (root.payload && root.payload.paginas) ? root.payload.paginas : 1

    property int paginaPendiente: paginaActual

    onPaginaActualChanged: {
        root.paginaPendiente = root.paginaActual;
    }

    readonly property string srcUrl: {
        const s = (root.payload && root.payload.src) ? root.payload.src : "";
        if (!s)
            return "";
        return s.startsWith("file://") ? s : ("file://" + s);
    }

    // Página renderizada, con doble búfer: la página nueva carga en la hoja oculta y solo
    // cuando está lista se cruza con la anterior, deslizándose en el sentido del cambio
    // (siguiente → entra desde abajo). Así no hay hueco en blanco mientras carga.
    property int hojaFrente: 0
    property int sentido: 1
    property int paginaMostrada: 1

    function hoja(i: int): Image {
        return i === 0 ? hoja0 : hoja1;
    }

    Component.onCompleted: {
        paginaMostrada = paginaActual;
        hoja0.source = srcUrl;
    }

    onSrcUrlChanged: {
        const atras = hoja(1 - hojaFrente);
        if (!srcUrl || atras.source.toString() === srcUrl)
            return;
        sentido = paginaActual >= paginaMostrada ? 1 : -1;
        cruce.stop();
        // Al quedar lista, su onStatusChanged hace el cruce
        atras.source = srcUrl;
    }

    function cruzar(): void {
        const atras = hoja(1 - hojaFrente);
        const frente = hoja(hojaFrente);
        sale.target = frente;
        entra.target = atras;
        saleY.target = frente;
        entraY.target = atras;
        saleY.to = -sentido * 18;
        entraY.from = sentido * 18;
        atras.z = 1;
        frente.z = 0;
        hojaFrente = 1 - hojaFrente;
        paginaMostrada = paginaActual;
        cruce.restart();
    }

    Item {
        id: hojas

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomBar.top
        anchors.margins: 8
        clip: true

        Hoja {
            id: hoja0

            indice: 0
        }
        Hoja {
            id: hoja1

            indice: 1
            opacity: 0
        }
    }

    component Hoja: Image {
        required property int indice

        width: hojas.width
        height: hojas.height
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        smooth: true
        onStatusChanged: {
            if (status === Image.Ready && indice !== root.hojaFrente && source.toString() === root.srcUrl)
                root.cruzar();
        }
    }

    ParallelAnimation {
        id: cruce

        NumberAnimation {
            id: sale

            property: "opacity"
            to: 0
            duration: HoloGeo.tRapido
            easing.type: HoloGeo.curvaFundido
        }
        NumberAnimation {
            id: saleY

            property: "y"
            duration: HoloGeo.tMedio
            easing.type: HoloGeo.curvaSale
        }
        NumberAnimation {
            id: entra

            property: "opacity"
            to: 1
            duration: HoloGeo.tMedio
            easing.type: HoloGeo.curvaFundido
        }
        NumberAnimation {
            id: entraY

            property: "y"
            to: 0
            duration: HoloGeo.tMedio
            easing.type: HoloGeo.curvaEntra
        }
    }

    // Temporizador de desborde para cambios rápidos de rueda
    Timer {
        id: debounceTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root.panel && root.panel.id && root.paginaPendiente !== root.paginaActual) {
                HoloState.pagina(root.panel.id, root.paginaPendiente);
            }
        }
    }

    function pedirPagina(p: int): void {
        const nueva = Math.max(1, Math.min(root.totalPaginas, p));
        if (nueva === root.paginaPendiente && nueva === root.paginaActual)
            return;
        root.paginaPendiente = nueva;
        debounceTimer.restart();
    }

    // Detección de rueda para avance / retroceso de páginas
    WheelHandler {
        id: wheelHandler
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            const deltaY = event.angleDelta ? event.angleDelta.y : (event.pixelDelta ? event.pixelDelta.y : 0);
            if (deltaY < 0) {
                root.pedirPagina(root.paginaPendiente + 1);
            } else if (deltaY > 0) {
                root.pedirPagina(root.paginaPendiente - 1);
            }
        }
    }

    // Barra inferior con indicador de página «pág N/M»
    Item {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36

        Rectangle {
            anchors.centerIn: parent
            height: 26
            width: pagText.implicitWidth + 24
            radius: 13
            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.75)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outline, 0.3)

            Text {
                id: pagText
                anchors.centerIn: parent
                text: "pág " + root.paginaPendiente + " / " + root.totalPaginas
                color: Colours.palette.m3onSurface
                font.family: Tokens.font.label.small.family
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
    }
}
