pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.modules.assistant

// Convergencia «a»: la luz de borde recorre el perímetro desde el centro del
// borde inferior en las dos direcciones y se enrolla en un punto del borde
// derecho, de donde nace el orbe. Ventana de pantalla completa, click-through,
// SOLO visible mientras dura la transición (~1,4 s); fuera de eso no existe.
StyledWindow {
    id: win

    required property ShellScreen modelData
    // Y (px de pantalla) del centro del orbe principal
    property real ty: height * 0.4
    property color tint: "#bfb0ff"
    property real u: 0
    property bool on: false
    signal born

    screen: modelData
    name: "laura-conv"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    mask: Region {}
    visible: on

    function start(c: color, centerY: real): void {
        tint = c;
        ty = centerY;
        u = 0;
        _born = false;
        on = true;
        anim.restart();
    }

    property bool _born: false
    onUChanged: {
        if (!_born && u >= 0.8) {
            _born = true;
            born();
        }
    }

    NumberAnimation {
        id: anim

        target: win
        property: "u"
        from: 0
        to: 1
        duration: 1400
        onFinished: win.on = false
    }

    readonly property real e: u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2
    readonly property real fade: u > 0.86 ? Math.max(0, (1 - u) / 0.14) : 1
    readonly property real k: Math.max(1, width / 1000)
    readonly property real sw: width
    readonly property real sh: height
    readonly property real sb: (sh - 3 - ty) + (sw - 6) / 2
    readonly property real perim: (sh - 3 - ty) + (sw - 6) + (sh - 6) + (sw - 6) + (ty - 3)
    readonly property real tailLen: Math.min(e * sb, (260 - 230 * e) * k)

    Item {
        anchors.fill: parent
        opacity: win.fade

        // Resplandor inicial en el centro del borde inferior (la barra de luz)
        OrbDisc {
            readonly property real rr: 320 * win.k
            x: win.sw / 2 - rr
            y: win.sh - rr
            width: rr * 2
            height: rr * 2
            opacity: 0.34 * (1 - win.e)
            fillGradient: RadialGradient {
                centerX: 320 * win.k
                centerY: 320 * win.k
                centerRadius: 320 * win.k
                focalX: centerX
                focalY: centerY
                GradientStop {
                    position: 0
                    color: Qt.alpha(win.tint, 0.85)
                }
                GradientStop {
                    position: 0.28
                    color: Qt.alpha(win.tint, 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(win.tint, 0)
                }
            }
        }

        ConvTrail {
            anchors.fill: parent
            sw: win.sw
            sh: win.sh
            ty: win.ty
            dir: -1
            head: win.sb - win.e * win.sb
            tail: Math.min(win.tailLen, win.e * win.sb)
            tint: win.tint
        }
        ConvTrail {
            anchors.fill: parent
            sw: win.sw
            sh: win.sh
            ty: win.ty
            dir: 1
            head: win.sb + win.e * (win.perim - win.sb)
            tail: Math.min(win.tailLen, win.e * (win.perim - win.sb))
            tint: win.tint
        }

        // Cabeza: punto brillante que se va encendiendo en el borde derecho
        OrbDisc {
            id: headDot

            readonly property real g: Math.pow(win.e, 3)
            readonly property real rr: (10 + 36 * g) * Math.max(1, win.k * 0.8)
            x: win.sw - 3 - rr
            y: win.ty - rr
            width: rr * 2
            height: rr * 2
            opacity: g * 0.9
            fillGradient: RadialGradient {
                centerX: headDot.rr
                centerY: headDot.rr
                centerRadius: headDot.rr
                focalX: centerX
                focalY: centerY
                GradientStop {
                    position: 0
                    color: "#d9ffffff"
                }
                GradientStop {
                    position: 0.28
                    color: Qt.alpha(win.tint, 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(win.tint, 0)
                }
            }
        }
    }
}
