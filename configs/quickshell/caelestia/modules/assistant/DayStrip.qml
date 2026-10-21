pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Caelestia.Config
import qs.components
import qs.services

// Franja del día: los eventos que ya hay (grises), el hueco del nuevo (ámbar o
// verde si ya se creó) y los solapes rayados en rojo. Todo Rectangles / Shape.
Item {
    id: root

    // Evento propuesto {inicio, fin} y lista del día [{titulo, inicio, fin}] (ISO)
    property var start: new Date()
    property var end: new Date()
    property var others: []
    property bool created: false
    property color tone: Laura.cWait

    function _h(d): real {
        return d.getHours() + d.getMinutes() / 60;
    }
    readonly property var parsed: others.map(o => ({
                titulo: o.titulo,
                s: _h(new Date(o.inicio)),
                e: _h(new Date(o.fin))
            })).filter(o => !isNaN(o.s) && !isNaN(o.e) && o.e > o.s)
    readonly property real ns: _h(start)
    readonly property real ne: _h(end) <= ns ? ns + 1 : _h(end)
    readonly property real r0: {
        let lo = ns;
        for (const o of parsed)
            lo = Math.min(lo, o.s);
        return Math.max(0, Math.min(Math.floor(lo) - 1, 24 - 4));
    }
    readonly property real r1: {
        let hi = ne;
        for (const o of parsed)
            hi = Math.max(hi, o.e);
        return Math.min(24, Math.max(Math.ceil(hi) + 1, r0 + 4));
    }
    readonly property var clashes: parsed.filter(o => o.s < ne && o.e > ns).map(o => ({
                s: Math.max(o.s, ns),
                e: Math.min(o.e, ne),
                os: o.s,
                oe: o.e,
                titulo: o.titulo
            }))
    readonly property real clashMin: clashes.reduce((a, c) => a + (c.e - c.s) * 60, 0)
    function hh(h: real): string {
        const m = Math.round((h % 1) * 60);
        return Math.floor(h) + ":" + (m < 10 ? "0" : "") + m;
    }
    function px(h: real): real {
        return (h - r0) / (r1 - r0) * lane.width;
    }

    implicitHeight: 15 + 50
    height: implicitHeight

    Repeater {
        model: Math.floor((root.r1 - root.r0) / 2) + 1

        StyledText {
            required property int index

            readonly property real h: root.r0 + index * 2
            visible: h <= root.r1
            x: Math.min(root.px(h) - width / 2, root.width - width)
            text: h + "h"
            color: Colours.palette.m3onSurfaceVariant
            font.pixelSize: 10
            font.family: Tokens.font.mono.small.family
        }
    }

    Rectangle {
        id: lane

        y: 15
        width: parent.width
        height: 50
        radius: 9
        color: Qt.alpha(Colours.palette.m3onSurface, 0.05)
        clip: true

        Repeater {
            model: root.parsed

            Rectangle {
                id: ex

                required property var modelData

                x: root.px(modelData.s)
                y: 26
                width: Math.max(4, root.px(modelData.e) - x)
                height: 20
                radius: 6
                color: Qt.alpha(Colours.palette.m3onSurface, 0.15)

                Rectangle {
                    width: 3
                    height: parent.height
                    color: Qt.alpha(Colours.palette.m3onSurface, 0.38)
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 7
                    width: parent.width - 9
                    elide: Text.ElideRight
                    text: ex.modelData.titulo
                    color: Colours.palette.m3onSurfaceVariant
                    font.pixelSize: 10
                }
            }
        }

        // el evento nuevo
        Rectangle {
            id: nw

            readonly property color col: root.created ? "#6fdcb4" : root.tone

            x: root.px(root.ns)
            y: 4
            width: Math.max(8, root.px(root.ne) - x)
            height: 42
            radius: 6
            color: Qt.alpha(col, root.created ? 0.4 : 0.32)
            border.width: 2
            border.color: col

            StyledText {
                x: 7
                y: 7
                width: parent.width - 10
                elide: Text.ElideRight
                visible: !root.created
                text: "Nuevo · " + root.hh(root.ns) + "–" + root.hh(root.ne)
                font.pixelSize: 11
                font.bold: true
            }
            StyledText {
                id: tick

                anchors.centerIn: parent
                visible: root.created
                text: "✓"
                font.pixelSize: 20
                font.bold: true
                scale: root.created ? 1 : 0.2
                Behavior on scale {
                    NumberAnimation {
                        duration: 420
                        easing.type: Easing.OutBack
                        easing.overshoot: 2
                    }
                }
            }
        }

        // solapes: rayado rojo
        Repeater {
            model: root.created ? [] : root.clashes

            Item {
                id: cl

                required property var modelData

                x: root.px(modelData.s)
                y: 4
                width: Math.max(2, root.px(modelData.e) - x)
                height: 42
                clip: true

                Shape {
                    anchors.fill: parent
                    opacity: 0.8
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: Laura.cFail
                        strokeWidth: 2
                        fillColor: "transparent"
                        PathSvg {
                            path: {
                                let d = "", h = cl.height;
                                for (let x = -h; x < cl.width; x += 8)
                                    d += `M${x} ${h} L${x + h} 0 `;
                                return d;
                            }
                        }
                    }
                }
            }
        }
    }
}
