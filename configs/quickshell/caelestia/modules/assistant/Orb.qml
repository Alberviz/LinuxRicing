pragma ComponentBehavior: Bound

import QtQuick
import M3Shapes
import qs.components
import qs.services
import qs.modules.assistant

// Núcleo visual de Laura. Una forma expresiva de Material 3 (M3Shapes) — el
// mismo lenguaje que el LoadingIndicator y el resto de Caelestia: morphea
// entre formas según el estado y late con la voz.
MaterialShape {
    id: root

    // "idle" | "listening" | "thinking" | "speaking"
    property string state: "idle"
    // Nivel de voz 0..1 (ya suavizado por el servicio Laura)
    property real level: 0
    // Tamaño de referencia (el consumidor lo fija)
    property real baseSize: 300

    // Formas por las que va pasando mientras "piensa" / "habla"
    readonly property var _cycle: [MaterialShape.SoftBurst, MaterialShape.Cookie9Sided, MaterialShape.Flower, MaterialShape.Puffy, MaterialShape.Sunny]
    property int _tick: 0

    readonly property bool busy: state === "thinking" || state === "speaking"

    animationDuration: state === "thinking" ? 460 : 820
    animationEasing.type: Easing.InOutCubic

    shape: {
        switch (state) {
        case "listening":
            return MaterialShape.Sunny;
        case "thinking":
            return root._cycle[root._tick % root._cycle.length];
        case "speaking":
            return root._tick % 2 ? MaterialShape.SoftBoom : MaterialShape.Puffy;
        default:
            return MaterialShape.Oval;
        }
    }

    color: state === "thinking" ? Colours.palette.m3tertiary : Colours.palette.m3primary
    Behavior on color {
        CAnim {}
    }

    // Respiración lenta (solo activa mientras Laura está en uso)
    property real breath: 0
    SequentialAnimation on breath {
        running: root.state !== "idle"
        loops: Animation.Infinite
        NumberAnimation {
            to: 1
            duration: 2400
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0
            duration: 2400
            easing.type: Easing.InOutSine
        }
    }

    implicitSize: root.baseSize * (root.state === "idle" ? 0.6 + 0.04 * root.breath : 0.78 + 0.05 * root.breath + 0.4 * root.level)
    Behavior on implicitSize {
        NumberAnimation {
            duration: 130
            easing.type: Easing.OutQuad
        }
    }

    // Giro lento continuo, más vivo al pensar (solo activo mientras Laura está en uso)
    RotationAnimation on rotation {
        running: root.state !== "idle"
        from: 0
        to: 360
        loops: Animation.Infinite
        duration: root.state === "thinking" ? 2800 : 15000
    }

    // Avanza el ciclo de formas mientras piensa o habla
    Timer {
        interval: root.state === "thinking" ? 520 : 700
        repeat: true
        running: root.busy
        onTriggered: root._tick++
    }
}
