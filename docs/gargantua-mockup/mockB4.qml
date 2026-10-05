import QtQuick
import QtQuick.Window

// mockB4.qml — B3: geometría raymarcheada UNA vez (4 búferes RGBA32F, live:false) + pase de
// sombreado por frame. Renderiza B4-tema / B4-test-rojo (1920x1080), guarda PNG y sale.
//   cd docs/gargantua-mockup && ./runB3.sh
Window {
    id: win
    width: 1920; height: 1080; visible: true
    color: "black"

    property int variantIdx: 0
    readonly property var names: ["B4-tema", "B4-test-rojo"]
    readonly property var primaries: ["#acc9ea", "#ffb4a9"]
    readonly property string outDir: Qt.resolvedUrl(".").toString().replace("file://", "")

    Item {
        id: root
        width: 1920; height: 1080

        ShaderEffect {
            id: geoFxA
            width: 1920; height: 1080
            fragmentShader: Qt.resolvedUrl("mockB4_geo.frag.qsb")
            property real outSel: 0
            property real elev: 1.6 * Math.PI / 180
            property real bhRadius: 290
            property real bhTilt: -0.489
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)
        }
        ShaderEffectSource {
            id: geoA
            x: 0; y: 0; width: 60; height: 34; z: -10
            sourceItem: geoFxA; hideSource: true; live: false
            textureSize: Qt.size(1920, 1080); format: ShaderEffectSource.RGBA32F
            smooth: false
            Component.onCompleted: scheduleUpdate()
        }
        ShaderEffect {
            id: geoFxB
            width: 1920; height: 1080
            fragmentShader: Qt.resolvedUrl("mockB4_geo.frag.qsb")
            property real outSel: 1
            property real elev: 1.6 * Math.PI / 180
            property real bhRadius: 290
            property real bhTilt: -0.489
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)
        }
        ShaderEffectSource {
            id: geoB
            x: 0; y: 0; width: 60; height: 34; z: -10
            sourceItem: geoFxB; hideSource: true; live: false
            textureSize: Qt.size(1920, 1080); format: ShaderEffectSource.RGBA32F
            smooth: false
            Component.onCompleted: scheduleUpdate()
        }
        ShaderEffect {
            id: geoFxC
            width: 1920; height: 1080
            fragmentShader: Qt.resolvedUrl("mockB4_geo.frag.qsb")
            property real outSel: 2
            property real elev: 1.6 * Math.PI / 180
            property real bhRadius: 290
            property real bhTilt: -0.489
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)
        }
        ShaderEffectSource {
            id: geoC
            x: 0; y: 0; width: 60; height: 34; z: -10
            sourceItem: geoFxC; hideSource: true; live: false
            textureSize: Qt.size(1920, 1080); format: ShaderEffectSource.RGBA32F
            smooth: false
            Component.onCompleted: scheduleUpdate()
        }
        ShaderEffect {
            id: geoFxF
            width: 1920; height: 1080
            fragmentShader: Qt.resolvedUrl("mockB4_geo.frag.qsb")
            property real outSel: 3
            property real elev: 1.6 * Math.PI / 180
            property real bhRadius: 290
            property real bhTilt: -0.489
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)
        }
        ShaderEffectSource {
            id: geoF
            x: 0; y: 0; width: 60; height: 34; z: -10
            sourceItem: geoFxF; hideSource: true; live: false
            textureSize: Qt.size(1920, 1080); format: ShaderEffectSource.RGBA32F
            smooth: false
            Component.onCompleted: scheduleUpdate()
        }
        // --- sombreado por frame ---
        ShaderEffect {
            id: shade
            width: 1920; height: 1080
            fragmentShader: Qt.resolvedUrl("mockB4.frag.qsb")
            property var geoA: geoA
            property var geoB: geoB
            property var geoC: geoC
            property var geoF: geoF
            property real time: 41.0
            property real bhRadius: 290
            property real bhTilt: -0.489
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)
            property color colPrimary: win.primaries[win.variantIdx]
            property color colInk: "#e1e6ef"
        }
        ShaderEffectSource {
            id: sceneTex
            x: 0; y: 0; width: 120; height: 68; z: -10
            sourceItem: shade; hideSource: true
            textureSize: Qt.size(1920, 1080); format: ShaderEffectSource.RGBA16F
            smooth: true; mipmap: true
        }
        // --- bloom ¼ res: pasada H (con umbral) + pasada V ---
        ShaderEffect {
            id: bloomH
            width: 480; height: 270; z: -10
            fragmentShader: Qt.resolvedUrl("bloom4.frag.qsb")
            property var src: sceneTex
            property point dir: Qt.point(1, 0)
            property point texel: Qt.point(1 / 480, 1 / 270)
            property real threshold: 1
            property real spread: 1.5
        }
        ShaderEffectSource {
            id: hTex
            width: 120; height: 68; z: -10
            sourceItem: bloomH; hideSource: true
            textureSize: Qt.size(480, 270); format: ShaderEffectSource.RGBA16F; smooth: true
        }
        ShaderEffect {
            id: bloomV
            width: 480; height: 270; z: -10
            fragmentShader: Qt.resolvedUrl("bloom4.frag.qsb")
            property var src: hTex
            property point dir: Qt.point(0, 1)
            property point texel: Qt.point(1 / 480, 1 / 270)
            property real threshold: 0
            property real spread: 1.5
        }
        ShaderEffectSource {
            id: vTex
            width: 120; height: 68; z: -10
            sourceItem: bloomV; hideSource: true
            textureSize: Qt.size(480, 270); format: ShaderEffectSource.RGBA16F; smooth: true
        }
        // --- bloom ⅛ res (más ancho) ---
        ShaderEffect {
            id: bloomH2
            width: 240; height: 135; z: -10
            fragmentShader: Qt.resolvedUrl("bloom4.frag.qsb")
            property var src: sceneTex
            property point dir: Qt.point(1, 0)
            property point texel: Qt.point(1 / 240, 1 / 135)
            property real threshold: 1
            property real spread: 2.4
        }
        ShaderEffectSource {
            id: hTex2
            width: 120; height: 68; z: -10
            sourceItem: bloomH2; hideSource: true
            textureSize: Qt.size(240, 135); format: ShaderEffectSource.RGBA16F; smooth: true
        }
        ShaderEffect {
            id: bloomV2
            width: 240; height: 135; z: -10
            fragmentShader: Qt.resolvedUrl("bloom4.frag.qsb")
            property var src: hTex2
            property point dir: Qt.point(0, 1)
            property point texel: Qt.point(1 / 240, 1 / 135)
            property real threshold: 0
            property real spread: 2.4
        }
        ShaderEffectSource {
            id: vTex2
            width: 120; height: 68; z: -10
            sourceItem: bloomV2; hideSource: true
            textureSize: Qt.size(240, 135); format: ShaderEffectSource.RGBA16F; smooth: true
        }
        ShaderEffect {
            id: comp
            width: 1920; height: 1080; z: 10
            fragmentShader: Qt.resolvedUrl("composite4.frag.qsb")
            property var scene: sceneTex
            property var bloom: vTex
            property var bloom2: vTex2
            property color tint: Qt.tint(Qt.rgba(1,1,1,1), Qt.rgba(Qt.color(win.primaries[win.variantIdx]).r, Qt.color(win.primaries[win.variantIdx]).g, Qt.color(win.primaries[win.variantIdx]).b, 0.55))
            property real exposure: 0.4
            property real bloomAmt: 1.0
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)
            property real bhRadius: 290
        }
    }

    Timer {
        id: shot
        interval: 2500; running: true
        onTriggered: root.grabToImage(function (res) {
            res.saveToFile(win.outDir + win.names[win.variantIdx] + ".png")
            if (win.variantIdx === 0) { win.variantIdx = 1; shot.interval = 600; shot.restart() }
            else Qt.quit()
        })
    }
}
