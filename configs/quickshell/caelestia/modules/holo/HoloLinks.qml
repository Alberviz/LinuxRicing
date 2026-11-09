pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.services
import qs.modules.assistant

// Hilos de puntos que unen cada fila abierta de la lista con su visor.
// Salen del borde derecho de la fila con un nodo, describen una curva suave y
// entran en el lado más cercano del visor con otro nodo. Aparecen con un fundido
// cuando el visor ya ha llegado (nada se anima en bucle).
Item {
    id: root

    required property var capa

    readonly property var visores: (HoloState.paneles || []).filter(p => p && p.kind === "visor" && p.item_n)

    Repeater {
        model: root.visores

        Item {
            id: hilo

            required property var modelData

            readonly property var lista: root.capa.pos["lista"] ?? null
            readonly property var caja: root.capa.pos[modelData.id] ?? null
            readonly property bool ok: !!lista && !!caja
            // Desde el borde de la lista que mira al visor
            readonly property bool derecha: ok && caja.x + caja.w / 2 >= lista.x + lista.w / 2
            property real x0: ok ? (derecha ? lista.x + lista.w : lista.x) : 0
            property real y0: ok ? root.capa.filaY(modelData.item_n) : 0
            readonly property real x1: ok ? (derecha ? caja.x : caja.x + caja.w) : 0
            readonly property real y1: ok ? Math.max(caja.y + 28, Math.min(caja.y + caja.h - 28, y0 + (caja.y + caja.h / 2 - y0) * 0.35)) : 0
            readonly property real tir: Math.max(60, Math.abs(x1 - x0) * 0.5) * (derecha ? 1 : -1)

            anchors.fill: parent
            visible: ok
            opacity: 0

            Component.onCompleted: aparece.start()

            Behavior on x0 {
                Anim {}
            }
            Behavior on y0 {
                Anim {}
            }

            SequentialAnimation {
                id: aparece

                PauseAnimation {
                    duration: 640
                }
                NumberAnimation {
                    target: hilo
                    property: "opacity"
                    to: 1
                    duration: 360
                    easing.type: Easing.OutCubic
                }
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                // Halo del hilo
                ShapePath {
                    strokeColor: Qt.alpha(Colours.palette.m3primary, 0.10)
                    strokeWidth: 5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: hilo.x0
                    startY: hilo.y0

                    PathCubic {
                        x: hilo.x1
                        y: hilo.y1
                        control1X: hilo.x0 + hilo.tir
                        control1Y: hilo.y0
                        control2X: hilo.x1 - hilo.tir
                        control2Y: hilo.y1
                    }
                }
                // Hilo de puntos
                ShapePath {
                    strokeColor: Qt.alpha(Colours.palette.m3primary, 0.75)
                    strokeWidth: 1.4
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 3.5]
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: hilo.x0
                    startY: hilo.y0

                    PathCubic {
                        x: hilo.x1
                        y: hilo.y1
                        control1X: hilo.x0 + hilo.tir
                        control1Y: hilo.y0
                        control2X: hilo.x1 - hilo.tir
                        control2Y: hilo.y1
                    }
                }
            }

            // Nodos en los extremos
            Repeater {
                model: [
                    {
                        x: hilo.x0,
                        y: hilo.y0
                    },
                    {
                        x: hilo.x1,
                        y: hilo.y1
                    }
                ]

                Item {
                    required property var modelData

                    x: modelData.x - 5
                    y: modelData.y - 5
                    width: 10
                    height: 10

                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: Qt.alpha(Colours.palette.m3primary, 0.25)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 5
                        height: 5
                        radius: 2.5
                        color: Colours.palette.m3primary
                    }
                }
            }
        }
    }
}
