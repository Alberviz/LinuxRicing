pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Visor de imagen holográfica.
// Permite zoom entre 1× y 5× centrado en el cursor mediante la rueda del ratón,
// desplazamiento arrastrando cuando hay zoom activo y restablecer a 1× con doble clic.
Item {
    id: root

    required property var panel

    readonly property var payload: panel && panel.payload ? panel.payload : ({})
    property real zoom: 1.0

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

                const factor = deltaY > 0 ? 1.25 : 0.8;
                const oldZoom = root.zoom;
                const newZoom = Math.max(1.0, Math.min(5.0, oldZoom * factor));
                if (Math.abs(newZoom - oldZoom) < 0.001)
                    return;

                const mouseX = (event.position !== undefined ? event.position.x : (event.point ? event.point.position.x : flickable.width / 2));
                const mouseY = (event.position !== undefined ? event.position.y : (event.point ? event.point.position.y : flickable.height / 2));

                const relX = (flickable.contentX + mouseX) / (flickable.width * oldZoom);
                const relY = (flickable.contentY + mouseY) / (flickable.height * oldZoom);

                root.zoom = newZoom;

                if (newZoom <= 1.01) {
                    root.zoom = 1.0;
                    flickable.contentX = 0;
                    flickable.contentY = 0;
                } else {
                    const newContentW = flickable.width * newZoom;
                    const newContentH = flickable.height * newZoom;
                    const targetX = relX * newContentW - mouseX;
                    const targetY = relY * newContentH - mouseY;
                    flickable.contentX = Math.max(0, Math.min(newContentW - flickable.width, targetX));
                    flickable.contentY = Math.max(0, Math.min(newContentH - flickable.height, targetY));
                }
            }
        }

        // Doble clic para volver a 1×
        TapHandler {
            id: tapHandler
            onDoubleTapped: {
                root.zoom = 1.0;
                flickable.contentX = 0;
                flickable.contentY = 0;
            }
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
        visible: root.zoom > 1.05

        Text {
            id: zoomText
            anchors.centerIn: parent
            text: root.zoom.toFixed(1) + "×"
            color: Colours.palette.m3primary
            font.family: Tokens.font.label.small.family
            font.pixelSize: 11
            font.weight: Font.Bold
        }
    }
}
