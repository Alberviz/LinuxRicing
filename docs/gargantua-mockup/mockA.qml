import QtQuick
import QtQuick.Window

// mockA.qml — renderiza A1 y A2 (1920x1080), guarda PNG y sale.
//   cd docs/gargantua-mockup && qml6 mockA.qml
// Cadena: escena HDR (RGBA16F) → bloom H (1/4 res, con umbral) → bloom V (1/4 res)
//         → composite (ACES + sRGB). Fuentes de color del tema actual (scheme.json).
Window {
    id: win
    width: 1920; height: 1080; visible: true
    color: "black"

    property int variantIdx: 0
    readonly property var names: ["A1-tema", "A2-calido"]
    readonly property string outDir: Qt.resolvedUrl(".").toString().replace("file://", "")

    Item {
        id: root
        width: 1920; height: 1080

        // --- escena HDR ---
        ShaderEffect {
            id: scene
            width: 1920; height: 1080
            fragmentShader: Qt.resolvedUrl("mockA.frag.qsb")
            property var lensLUT0: Image { source: Qt.resolvedUrl("../../configs/quickshell/caelestia/modules/background/solarsystem/shaders/lens_lut_order0.png"); smooth: true; mipmap: false }
            property var lensLUT1: Image { source: Qt.resolvedUrl("../../configs/quickshell/caelestia/modules/background/solarsystem/shaders/lens_lut_order1.png"); smooth: true; mipmap: false }
            property real time: 41.0
            property real variant: win.variantIdx
            property real bhRadius: 290        // sombra ≈ 1.03·281 px (R = 0.26·h) como en vivo
            property real bhTilt: -0.489
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)   // Sim.js: bhFx/bhFy
            property color colPrimary: "#acc9ea"   // m3primary del tema actual
            property color colInk: "#e1e6ef"       // m3onSurface
        }
        ShaderEffectSource {
            id: sceneTex
            x: 0; y: 0; width: 120; height: 68; z: -10
            sourceItem: scene; hideSource: true
            textureSize: Qt.size(1920, 1080); format: ShaderEffectSource.RGBA16F
            smooth: true; mipmap: true
        }
        // --- bloom ¼ res: pasada H (con umbral) ---
        ShaderEffect {
            id: bloomH
            width: 480; height: 270; z: -10
            fragmentShader: Qt.resolvedUrl("bloom.frag.qsb")
            property var src: sceneTex
            property point dir: Qt.point(1, 0)
            property point texel: Qt.point(1 / 480, 1 / 270)
            property real threshold: 1
        }
        ShaderEffectSource {
            id: hTex
            width: 120; height: 68; z: -10
            sourceItem: bloomH; hideSource: true
            textureSize: Qt.size(480, 270); format: ShaderEffectSource.RGBA16F; smooth: true
        }
        // --- pasada V ---
        ShaderEffect {
            id: bloomV
            width: 480; height: 270; z: -10
            fragmentShader: Qt.resolvedUrl("bloom.frag.qsb")
            property var src: hTex
            property point dir: Qt.point(0, 1)
            property point texel: Qt.point(1 / 480, 1 / 270)
            property real threshold: 0
        }
        ShaderEffectSource {
            id: vTex
            width: 120; height: 68; z: -10
            sourceItem: bloomV; hideSource: true
            textureSize: Qt.size(480, 270); format: ShaderEffectSource.RGBA16F; smooth: true
        }
        // --- composite final (opaco, cubre todo) ---
        ShaderEffect {
            id: comp
            width: 1920; height: 1080; z: 10
            fragmentShader: Qt.resolvedUrl("composite.frag.qsb")
            property var scene: sceneTex
            property var bloom: vTex
            property real exposure: 0.85
            property real bloomAmt: 0.45
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: scene.bhCenter
            property real bhRadius: scene.bhRadius
        }
    }

    Timer {
        id: shot
        interval: 1500; running: true
        onTriggered: root.grabToImage(function (res) {
            var p = win.outDir + win.names[win.variantIdx] + ".png"
            res.saveToFile(p)
            console.log("saved " + p)
            if (win.variantIdx === 0) { win.variantIdx = 1; shot.restart() }
            else Qt.quit()
        })
    }
}
