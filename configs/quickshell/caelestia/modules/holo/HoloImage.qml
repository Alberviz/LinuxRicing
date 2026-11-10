pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Visor de imagen holográfica.
// Permite zoom entre 1× y 5× centrado en el cursor mediante la rueda del ratón,
// desplazamiento arrastrando cuando hay zoom activo y restablecer a 1× con doble clic.
//
// El zoom no salta: se anima corto (tRapido) manteniendo fijo bajo el cursor el punto de la
// imagen que señalaba; varias muescas seguidas encadenan desde el valor en curso.
Item {
    id: root

    required property var panel

    readonly property var payload: panel && panel.payload ? panel.payload : ({})
    property real zoom: 1.0
    // Zoom al que se va (las muescas se acumulan sobre este, no sobre el valor animado)
    property real zoomObjetivo: 1.0
    // Ancla: punto relativo de la imagen (0..1) que se queda bajo (ax, ay) del visor
    property real relX: 0.5
    property real relY: 0.5
    property real ax: 0
    property real ay: 0

    function hacerZoom(nuevo: real, mx: real, my: real): void {
        nuevo = Math.max(1.0, Math.min(5.0, nuevo));
        relX = (flickable.contentX + mx) / (flickable.width * zoom);
        relY = (flickable.contentY + my) / (flickable.height * zoom);
        ax = mx;
        ay = my;
        zoomObjetivo = nuevo;
        zoomAnim.stop();
        zoomAnim.to = nuevo;
        zoomAnim.start();
    }

    // Cada fotograma del zoom recoloca el contenido para que el ancla no se mueva
    onZoomChanged: {
        const cw = flickable.width * zoom, ch = flickable.height * zoom;
        flickable.contentX = Math.max(0, Math.min(cw - flickable.width, relX * cw - ax));
        flickable.contentY = Math.max(0, Math.min(ch - flickable.height, relY * ch - ay));
    }

    NumberAnimation {
        id: zoomAnim

        target: root
        property: "zoom"
        duration: HoloGeo.tRapido
        easing.type: HoloGeo.curvaEntra
    }

    readonly property string srcUrl: {
        const s = (root.payload && root.payload.src) ? root.payload.src : "";
        if (!s)
            return "";
        return s.startsWith("file://") ? s : ("file://" + s);
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        clip: true
        contentWidth: Math.max(width, width * root.zoom)
        contentHeight: Math.max(height, height * root.zoom)
        interactive: root.zoom > 1.01
        boundsBehavior: Flickable.StopAtBounds

        Image {
            id: img
            width: flickable.contentWidth
            height: flickable.contentHeight
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            source: root.srcUrl
            smooth: true
            mipmap: true
        }

        // Control de zoom con la rueda del ratón centrado en el cursor
        WheelHandler {
            id: wheelHandler
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                const deltaY = event.angleDelta ? event.angleDelta.y : (event.pixelDelta ? event.pixelDelta.y : 0);
                if (deltaY === 0)
                    return;
                const nuevo = Math.max(1.0, Math.min(5.0, root.zoomObjetivo * (deltaY > 0 ? 1.25 : 0.8)));
                if (Math.abs(nuevo - root.zoomObjetivo) < 0.001)
                    return;
                // El handler vive dentro del contenido (que se desplaza): pasar a coordenadas
                // del visor restando el desplazamiento
                const pp = wheelHandler.point.position;
                const mx = Math.max(0, Math.min(flickable.width, pp.x - flickable.contentX));
                const my = Math.max(0, Math.min(flickable.height, pp.y - flickable.contentY));
                root.hacerZoom(nuevo < 1.01 ? 1 : nuevo, mx, my);
            }
        }

        // Doble clic para volver a 1×
        TapHandler {
            id: tapHandler
            onDoubleTapped: eventPoint => root.hacerZoom(1, eventPoint.position.x - flickable.contentX, eventPoint.position.y - flickable.contentY)
        }
    }

    // Indicador discreto de nivel de zoom cuando está ampliado
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        height: 22
        width: zoomText.implicitWidth + 14
        radius: 11
        color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.75)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.4)
        opacity: root.zoomObjetivo > 1.05 ? 1 : 0
        visible: opacity > 0
        scale: 0.9 + 0.1 * opacity

        Behavior on opacity {
            NumberAnimation {
                duration: HoloGeo.tRapido
                easing.type: HoloGeo.curvaFundido
            }
        }

        Text {
            id: zoomText
            anchors.centerIn: parent
            text: root.zoomObjetivo.toFixed(1) + "×"
            color: Colours.palette.m3primary
            font.family: Tokens.font.label.small.family
            font.pixelSize: 11
            font.weight: Font.Bold
        }
    }
}
