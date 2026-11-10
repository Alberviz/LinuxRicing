pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.services
import qs.modules.assistant

// Hilos de puntos que unen cada fila abierta de la lista con su visor.
// Salen del borde derecho de la fila con un nodo, describen una curva suave y
// entran en el lado más cercano del visor con otro nodo.
//
// Coreografía (todo de una sola vez, nada en bucle):
//   dibujarse — cuando el visor termina su vuelo, el hilo crece desde la fila hasta él
//               (la punta lleva el nodo), así se lee «este archivo → este visor».
//   seguir    — los extremos van pegados a la posición VIVA de la lista y del visor:
//               si la lista se aparta o arrastras el visor, el hilo va con ellos.
//   resaltar  — se ilumina con la fila o el visor bajo el ratón, y con «esa».
//   retraerse — si el visor se va (píldora, papelera o móvil), el hilo se recoge hacia
//               la fila antes de que el visor desaparezca.
Item {
    id: root

    required property var capa

    component Nodo: Item {
        id: nodo

        property real cx
        property real cy
        property real s
        property real luz

        x: cx - 5
        y: cy - 5
        width: 10
        height: 10
        scale: s * (1 + 0.25 * luz)

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: Qt.alpha(Colours.palette.m3primary, 0.25 + 0.15 * nodo.luz)
        }
        Rectangle {
            anchors.centerIn: parent
            width: 5
            height: 5
            radius: 2.5
            color: Colours.palette.m3primary
        }
    }

    Repeater {
        // Los paneles vivos de la capa (ListModel: cada hilo conserva su delegado aunque
        // cambie la escena, y existe mientras su visor se está yendo)
        model: root.capa.modelo

        Item {
            id: hilo

            required property string pid

            readonly property var datos: root.capa.datos[pid] ?? null
            readonly property int n: datos && datos.kind === "visor" && datos.item_n ? datos.item_n : 0
            readonly property var visor: n > 0 ? (root.capa.reg[pid] ?? null) : null
            readonly property var lista: root.capa.reg["lista"] ?? null
            readonly property bool ok: !!visor && !!lista
            // Visor en su sitio y la lista también: el hilo puede estar tendido
            readonly property bool tendido: ok && visor.llegado && !visor.saliendo && !visor.enviando && !lista.saliendo
            readonly property bool brilla: n === HoloState.resaltado || n === HoloState.seleccionado

            // Desde el borde de la lista que mira al visor
            readonly property bool derecha: ok && visor.x + visor.width / 2 >= lista.x + lista.width / 2
            readonly property real x0: ok ? (derecha ? lista.x + lista.width : lista.x) : 0
            readonly property real y0: ok ? lista.y + HoloGeo.cabecera + HoloGeo.listaArriba + HoloGeo.fila * (n - 1) + HoloGeo.fila / 2 : 0
            readonly property real xv: ok ? (derecha ? visor.x : visor.x + visor.width) : 0
            readonly property real yv: ok ? Math.max(visor.y + 28, Math.min(visor.y + visor.height - 28, y0 + (visor.y + visor.height / 2 - y0) * 0.35)) : 0
            readonly property real tirV: Math.max(60, Math.abs(xv - x0) * 0.5) * (derecha ? 1 : -1)

            // 0 = recogido en la fila, 1 = llega al visor. La curva se acorta escalando su
            // extremo y sus controles hacia el origen: crece siguiendo su propia forma.
            property real d: 0
            readonly property real x1: x0 + (xv - x0) * d
            readonly property real y1: y0 + (yv - y0) * d
            readonly property real tir: tirV * d
            // Brillo animado (0 reposo, 1 resaltado)
            property real luz: brilla ? 1 : 0

            anchors.fill: parent
            visible: ok && d > 0.001

            Component.onCompleted: {
                if (tendido)
                    dibuja.start();
            }
            onTendidoChanged: {
                if (tendido) {
                    recoge.stop();
                    dibuja.start();
                } else if (d > 0) {
                    dibuja.stop();
                    recoge.start();
                }
            }

            Behavior on luz {
                NumberAnimation {
                    duration: HoloGeo.tRapido
                    easing.type: HoloGeo.curvaFundido
                }
            }

            NumberAnimation {
                id: dibuja

                target: hilo
                property: "d"
                to: 1
                duration: HoloGeo.tLento
                easing.type: HoloGeo.curvaEntra
            }
            NumberAnimation {
                id: recoge

                target: hilo
                property: "d"
                to: 0
                duration: HoloGeo.tRapido
                easing.type: HoloGeo.curvaSale
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                // Halo del hilo
                ShapePath {
                    strokeColor: Qt.alpha(Colours.palette.m3primary, 0.10 + 0.10 * hilo.luz)
                    strokeWidth: 5 + 2 * hilo.luz
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
                    strokeColor: Qt.alpha(Colours.palette.m3primary, 0.7 + 0.3 * hilo.luz)
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

            // Nodos en los extremos: el de la fila aparece al empezar; el del visor viaja
            // en la punta y «se engancha» (crece) al llegar.
            Nodo {
                cx: hilo.x0
                cy: hilo.y0
                s: Math.min(1, hilo.d * 4)
                luz: hilo.luz
            }
            Nodo {
                cx: hilo.x1
                cy: hilo.y1
                s: 0.6 + 0.4 * Math.max(0, (hilo.d - 0.85) / 0.15)
                luz: hilo.luz
            }
        }
    }
}
