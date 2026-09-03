pragma ComponentBehavior: Bound

// _labelPreview.qml — banco de pruebas de BodyLabel.qml (archivo de desarrollo,
// el guion bajo lo marca). No entra en el shell.
//
//   qs -p configs/quickshell/caelestia/modules/background/solarsystem/_labelPreview.qml
//
// Muestra las tres variantes a la vez, cada una sobre una mini-composición falsa
// (un sol grande, un sol mediano y tres satélites) con colores parecidos a la
// paleta real (cálidos). Sirve para capturar con grim y elegir mirando.

import QtQuick
import Quickshell

FloatingWindow {
    id: win
    implicitWidth: 1500
    implicitHeight: 820
    color: "#050505"

    // Paleta de la maqueta (cálidos). En el shell real esto sale de Colours.palette.
    readonly property color cPeach: "#f7b999"
    readonly property color cGold: "#efd994"
    readonly property color cInk: "#f8e1d6"
    readonly property color cError: "#f97758"

    Row {
        anchors.fill: parent

        Repeater {
            model: [
                { v: "A", label: "VARIANTE A  ·  MÍNIMA" },
                { v: "B", label: "VARIANTE B  ·  CON GUÍA" },
                { v: "C", label: "VARIANTE C  ·  FICHA DE CATÁLOGO" }
            ]

            delegate: Item {
                id: col
                required property var modelData
                width: win.width / 3
                height: win.height

                // separador tenue entre columnas
                Rectangle {
                    width: 1
                    height: parent.height
                    color: "#ffffff"
                    opacity: 0.06
                    visible: col.x > 0
                }

                Text {
                    x: 22
                    y: 18
                    text: col.modelData.label
                    color: win.cInk
                    opacity: 0.5
                    renderType: Text.NativeRendering
                    font.family: "JetBrainsMono NF"
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }

                // ---- escena falsa: cuerpos + etiquetas ----
                Item {
                    id: scene
                    anchors.fill: parent

                    // modelo de cuerpos (coords locales de la columna)
                    readonly property var bodies: [
                        { x: 0.50, y: 0.30, r: 42, col: win.cGold,  em: 1.00,
                          title: "LAURA",          sub: "escuchando" },
                        { x: 0.32, y: 0.72, r: 30, col: win.cPeach, em: 0.82,
                          title: "CONFIGURACIÓN",  sub: "" },
                        { x: 0.82, y: 0.20, r: 9,  col: win.cGold,  em: 0.30,
                          title: "CLAUDE",         sub: "en curso" },
                        { x: 0.66, y: 0.52, r: 12, col: win.cPeach, em: 0.38,
                          title: "RATÓN",          sub: "87%" },
                        { x: 0.13, y: 0.46, r: 10, col: win.cError, em: 0.42,
                          title: "AKKO",           sub: "14%" }
                    ]

                    Repeater {
                        model: scene.bodies
                        delegate: Item {
                            id: bodyWrap
                            required property var modelData
                            required property int index
                            readonly property real cx: modelData.x * col.width
                            readonly property real cy: modelData.y * col.height
                            readonly property real rr: modelData.r
                            anchors.fill: parent

                            // resplandor
                            Rectangle {
                                width: bodyWrap.rr * 3.4
                                height: width
                                radius: width / 2
                                x: bodyWrap.cx - width / 2
                                y: bodyWrap.cy - height / 2
                                color: bodyWrap.modelData.col
                                opacity: 0.07
                            }
                            // cuerpo
                            Rectangle {
                                width: bodyWrap.rr * 2
                                height: width
                                radius: width / 2
                                x: bodyWrap.cx - bodyWrap.rr
                                y: bodyWrap.cy - bodyWrap.rr
                                color: bodyWrap.modelData.col
                                antialiasing: true
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.5
                                    height: width
                                    radius: width / 2
                                    color: Qt.lighter(bodyWrap.modelData.col, 1.6)
                                    opacity: 0.9
                                }
                            }

                            BodyLabel {
                                targetX: bodyWrap.cx
                                targetY: bodyWrap.cy
                                targetRadius: bodyWrap.rr
                                title: bodyWrap.modelData.title
                                subtitle: bodyWrap.modelData.sub
                                col: bodyWrap.modelData.col
                                emphasis: bodyWrap.modelData.em
                                variant: col.modelData.v
                                fieldWidth: col.width
                                fieldHeight: col.height
                            }
                        }
                    }
                }
            }
        }
    }
}
