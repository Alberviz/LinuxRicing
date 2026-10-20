import QtQuick
import QtQuick.Shapes

// Disco (elipse) rellenable con un gradiente — pieza básica del orbe.
// Todo va por Shape (GPU), nunca Canvas ni sombras por-píxel.
Shape {
    id: root

    property alias fillGradient: path.fillGradient
    property alias fillColor: path.fillColor
    property alias strokeColor: path.strokeColor
    property alias strokeWidth: path.strokeWidth
    property alias strokeStyle: path.strokeStyle
    property alias dashPattern: path.dashPattern
    // Radio del trazo hacia dentro, para que el borde no se salga del diámetro.
    property real inset: path.strokeWidth / 2

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        id: path

        fillColor: "transparent"
        strokeColor: "transparent"
        strokeWidth: 0

        PathAngleArc {
            centerX: root.width / 2
            centerY: root.height / 2
            radiusX: Math.max(0.1, root.width / 2 - root.inset)
            radiusY: Math.max(0.1, root.height / 2 - root.inset)
            startAngle: 0
            sweepAngle: 360
        }
    }
}
