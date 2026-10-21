import QtQuick
import QtQuick.Shapes

// Icono del agente (los glifos del mockup, viewBox 24x24) como paths SVG
// vectoriales. laura / gemini rellenos; claude / aurora de trazo.
Item {
    id: root

    property string agent: "laura"
    property color color: "white"
    property real size: 16

    width: size
    height: size

    readonly property bool stroked: agent === "claude" || agent === "aurora"
    readonly property string d1: {
        switch (agent) {
        case "aviso":
            return "M12 22a2 2 0 0 0 2-2h-4a2 2 0 0 0 2 2zm6-6V11c0-3.07-1.63-5.64-4.5-6.32V4a1.5 1.5 0 0 0-3 0v.68C7.64 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z";
        case "gemini":
            return "M10 3c.5 4.2 3.8 7.5 8 8-4.2.5-7.5 3.8-8 8-.5-4.2-3.8-7.5-8-8 4.2-.5 7.5-3.8 8-8z";
        case "claude":
            return "M12 3v18M3 12h18M5.6 5.6l12.8 12.8M18.4 5.6L5.6 18.4";
        case "aurora":
            return "M2.5 9c3-5 6-5 9.5 0s6.5 5 9.5 0M2.5 16c3-5 6-5 9.5 0s6.5 5 9.5 0";
        }
        return "M12 2c.6 5.2 4.8 9.4 10 10-5.2.6-9.4 4.8-10 10-.6-5.2-4.8-9.4-10-10 5.2-.6 9.4-4.8 10-10z";
    }
    readonly property string d2: agent === "gemini" ? "M19 14c.2 1.7 1.3 2.8 3 3-1.7.2-2.8 1.3-3 3-.2-1.7-1.3-2.8-3-3 1.7-.2 2.8-1.3 3-3z" : ""

    Shape {
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.stroked ? "transparent" : root.color
            strokeColor: root.stroked ? root.color : "transparent"
            strokeWidth: root.agent === "claude" ? 2.4 : 2.2
            capStyle: ShapePath.RoundCap
            PathSvg {
                path: root.d1
            }
        }
        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            PathSvg {
                path: root.d2
            }
        }
    }
}
