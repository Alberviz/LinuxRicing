pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.assistant

// Hilos de puntos holográficos que conectan cada fila de la lista con su visor abierto.
Item {
    id: root

    required property var holoLayer

    readonly property var visores: (HoloState.paneles || []).filter(p => p && p.kind === "visor" && p.item_n !== null && p.item_n !== undefined)

    Repeater {
        model: root.visores

        Shape {
            id: shape

            required property var modelData

            anchors.fill: parent

            readonly property var listPos: root.holoLayer ? root.holoLayer.posiciones["lista"] : null
            readonly property var vPos: root.holoLayer ? root.holoLayer.posiciones[modelData.id] : null
            readonly property int itemN: modelData.item_n ?? 1

            readonly property real startX: listPos ? listPos.x + listPos.w : 0
            readonly property real startY: listPos ? listPos.y + 64 + 38 * (itemN - 1) + 19 : 0
            readonly property real endX: vPos ? (startX <= vPos.x ? vPos.x : vPos.x + vPos.w) : 0
            readonly property real endY: vPos ? Math.max(vPos.y + 16, Math.min(vPos.y + vPos.h - 16, startY)) : 0

            visible: !!listPos && !!vPos

            ShapePath {
                strokeColor: Qt.alpha(Colours.palette.m3primary, 0.7)
                strokeWidth: 1.5
                strokeStyle: ShapePath.DashLine
                fillColor: "transparent"

                startX: shape.startX
                startY: shape.startY

                PathCubic {
                    x: shape.endX
                    y: shape.endY
                    control1X: shape.startX + (shape.endX - shape.startX) * 0.5
                    control1Y: shape.startY
                    control2X: shape.endX - (shape.endX - shape.startX) * 0.5
                    control2Y: shape.endY
                }
            }
        }
    }
}
