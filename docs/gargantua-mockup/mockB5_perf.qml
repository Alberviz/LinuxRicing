import QtQuick
import QtQuick.Window

// mockB5_perf.qml — medición de mockB5 (ver bloque final). Base: mockB5.qml — caché geométrica UNA vez (3 búferes RGBA32F, live:false: 2 tramos de capa fina
// y bruma+horizonte) + pase de sombreado por frame + bloom ¼+⅛ + composite ACES por luminancia.
// Renderiza B5-tema / B5-test-rojo (1920x1080), guarda PNG y sale.   ./runB5.sh
Window {
    id: win
    width: 1920; height: 1080; visible: true
    color: "black"

    property int variantIdx: 0
    readonly property var names: ["B5-tema", "B5-test-rojo"]
    readonly property var primaries: ["#acc9ea", "#ffb4a9"]
    readonly property string outDir: Qt.resolvedUrl(".").toString().replace("file://", "")

    Item {
        id: root
        width: 1920; height: 1080

        ShaderEffect {
            id: geoFxA
            width: 1920; height: 1080
            fragmentShader: Qt.resolvedUrl("mockB5_geo.frag.qsb")
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
            fragmentShader: Qt.resolvedUrl("mockB5_geo.frag.qsb")
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
            id: geoFxH
            width: 1920; height: 1080
            fragmentShader: Qt.resolvedUrl("mockB5_geo.frag.qsb")
            property real outSel: 2
            property real elev: 1.6 * Math.PI / 180
            property real bhRadius: 290
            property real bhTilt: -0.489
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)
        }
        ShaderEffectSource {
            id: geoH
            x: 0; y: 0; width: 60; height: 34; z: -10
            sourceItem: geoFxH; hideSource: true; live: false
            textureSize: Qt.size(1920, 1080); format: ShaderEffectSource.RGBA32F
            smooth: false
            Component.onCompleted: scheduleUpdate()
        }
        // ruido periódico horneado una vez (4 canales, periodo 16, wrap Repeat)
        ShaderEffect {
            id: noiseFx
            width: 256; height: 256
            fragmentShader: Qt.resolvedUrl("noise5.frag.qsb")
        }
        ShaderEffectSource {
            id: noiseTex
            x: 0; y: 0; width: 16; height: 16; z: -10
            sourceItem: noiseFx; hideSource: true; live: false
            textureSize: Qt.size(256, 256); wrapMode: ShaderEffectSource.Repeat
            smooth: true
            Component.onCompleted: scheduleUpdate()
        }
        // --- sombreado por frame ---
        ShaderEffect {
            id: shade
            width: 1920; height: 1080
            fragmentShader: Qt.resolvedUrl("mockB5.frag.qsb")
            property var geoA: geoA
            property var geoB: geoB
            property var geoH: geoH
            property var noiseTex: noiseTex
            property real time: 41.0
            property real bhRadius: 290
            property real bhTilt: -0.489
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)
            property color colPrimary: win.primaries[win.variantIdx]
            property color colInk: "#e1e6ef"
            property real dbg: 0
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
            fragmentShader: Qt.resolvedUrl("composite5.frag.qsb")
            property var scene: sceneTex
            property var bloom: vTex
            property var bloom2: vTex2
            property color tint: Qt.tint(Qt.rgba(1,1,1,1), Qt.rgba(Qt.color(win.primaries[win.variantIdx]).r, Qt.color(win.primaries[win.variantIdx]).g, Qt.color(win.primaries[win.variantIdx]).b, 0.55))
            property real exposure: 0.85
            property real bloomAmt: 1.0
            property size resolution: Qt.size(1920, 1080)
            property point bhCenter: Qt.point(0.86 * 1920, 0.09 * 1080)
            property real bhRadius: 290
        }
    }

    // --- medición: arg "frame" = pase por frame (sombreado+bloom+composite) con time animado;
    //     arg "cache" = además re-renderiza la caché geométrica (3 pases) cada frame.
    readonly property string mode: Qt.application.arguments[Qt.application.arguments.length - 1]
    property int frames: 0
    property double t0: 0
    FrameAnimation {
        running: true
        onTriggered: {
            shade.time += frameTime
            if (win.mode === "cache") { geoFxA.elev += 1e-7; geoFxB.elev += 1e-7; geoFxH.elev += 1e-7; geoA.scheduleUpdate(); geoB.scheduleUpdate(); geoH.scheduleUpdate() }
            win.frames++
            if (win.frames === (win.mode === "cache" ? 3 : 60)) win.t0 = Date.now()
            if (win.frames === (win.mode === "cache" ? 8 : 660)) {
                var n = win.frames - (win.mode === "cache" ? 3 : 60)
                var ms = ((Date.now() - win.t0) / n).toFixed(2)
                // la consola de qml6 está silenciada aquí: el resultado va en el nombre del fichero
                root.grabToImage(function (res) { res.saveToFile("/tmp/claude-1000/-home-alberviz-LinuxRicing/7d238499-987b-402e-bf19-e9a8e803d94c/scratchpad/perfB5_" + win.mode + "_" + ms + "ms.png"); Qt.quit() }, Qt.size(64, 36))
            }
        }
    }
}
