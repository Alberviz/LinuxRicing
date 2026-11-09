pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Visor de archivo de texto u código holográfico.
// Soporta formato Markdown (con estilos renderizados) o texto monoespaciado plano.
// Permite selección de texto con ratón, desplazamiento fluido y muestra
// un aviso de «… (recortado)» cuando el archivo supera los límites de captura.
Item {
    id: root

    required property var panel

    readonly property var payload: panel && panel.payload ? panel.payload : ({})
    readonly property string texto: (root.payload && root.payload.texto) ? root.payload.texto : ""
    readonly property string formato: (root.payload && root.payload.formato) ? root.payload.formato : "mono"
    readonly property bool truncado: !!(root.payload && root.payload.truncado)

    Flickable {
        id: flickable
        anchors.fill: parent
        anchors.margins: (typeof HoloGeo !== "undefined" && HoloGeo.margenContenido !== undefined) ? HoloGeo.margenContenido : 10
        contentWidth: width
        contentHeight: textCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        WheelHandler {
            target: flickable
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (flickable.contentHeight <= flickable.height)
                    return;
                const dy = event.angleDelta.y ? -(event.angleDelta.y / 120) * 60 : -(event.pixelDelta.y || 0);
                const maxY = flickable.contentHeight - flickable.height;
                flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY + dy));
            }
        }

        Column {
            id: textCol
            width: flickable.width
            spacing: 8

            TextEdit {
                id: textEdit
                width: parent.width
                readOnly: true
                textFormat: root.formato === "markdown" ? TextEdit.MarkdownText : TextEdit.PlainText
                font.family: root.formato === "mono" ? "JetBrains Mono" : Tokens.font.body.small.family
                font.pixelSize: 13
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                color: Colours.palette.m3onSurface
                selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                selectedTextColor: Colours.palette.m3onPrimary
                text: root.texto
            }

            Text {
                visible: root.truncado
                width: parent.width
                text: "… (recortado)"
                color: Colours.palette.m3onSurfaceVariant
                font.family: root.formato === "mono" ? "JetBrains Mono" : Tokens.font.body.small.family
                font.pixelSize: 12
                font.italic: true
            }
        }
    }
}
