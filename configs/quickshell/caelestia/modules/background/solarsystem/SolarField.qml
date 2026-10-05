pragma ComponentBehavior: Bound

// SolarField.qml — TODO el fondo del sistema solar v3 (variante D) en la GPU.
//
// Un ShaderEffect a pantalla completa que renderiza per-píxel: fondo negro +
// tinte + campo de estrellas (con lente cerca del agujero) + resplandor exterior
// + agujero negro completo (spec §4.1) + los dos soles (fotosfera, granulación
// procedural, cromosfera, corona, prominencias sólo en Laura). El giro y la
// turbulencia van por el uniform `time`; la GPU repinta suave a ritmo de pantalla
// con coste de CPU ~0.
//
// NO dibuja: satélites (agentes/dispositivos), cinturón de tareas ni trazas de
// órbita. Eso es una capa fina QML/Canvas ENCIMA de este componente (la lleva
// SolarSystem.qml), que puede leer dónde caen los soles vía `layout`.
//
// Modo Laura activa (`lauraFocus` 0→1): quien use el componente CONGELA `time`;
// este shader oscurece todo a ~18 % salvo el sol de Laura, cuya corona/brillo
// escala con `lauraFocus` y late con `lauraAmp`.
//
// Todo color sale de la paleta inyectada (roles m3*). Cero hex fijos.
// El shader: shaders/solarfield.frag(.qsb). Recompilar tras editarlo:
//   /usr/lib/qt6/bin/qsb --qt6 -o solarfield.frag.qsb solarfield.frag
//
// AGUJERO NEGRO (B10-B, docs/gargantua-mockup): ya no es analítico. Cadena propia:
//   bhgeo   — raymarch de Schwarzschild (2x2, 3 texturas RGBA32F) en la CAJA del agujero.
//             live:false: SOLO se recalcula si cambia la geometría (_bhGeoKey), nunca por frame.
//   bhshade — sombreado por frame (vetas, motas, rampa de 5 roles del tema, anillo), sigue a `time`.
//   bhbloom — bloom ¼ + ⅛ · bhcomp — ACES por luminancia → textura premultiplicada `bhTex`
//   que solarfield.frag compone delante del fondo (y oscurece con focusAmt como antes).
// Recompilar: for f in bhnoise bhgeo bhshade bhbloom bhcomp; do qsb --qt6 -o shaders/$f.frag.qsb shaders/$f.frag; done

import QtQuick
import qs.services

Item {
    id: root

    // --- Entradas dinámicas ---
    property real time: 0            // s — el motor lo congela en modo Laura
    property real music: 0           // 0..1
    property real musicProgress: 0   // 0..1  (0 sin canción / sin progreso)
    property real musicPulse: 0      // 0..1  detector de golpe/beat (ya decae solo)
    property real musicBass: 0       // 0..1  energía de graves
    property real musicTreble: 0     // 0..1  energía de agudos
    property real musicBurstAge: 999 // s     segundos desde último golpe (999 = inactivo)
    property real lauraFocus: 0      // 0..1  (0 normal · 1 foco-Laura)
    property real lauraAmp: 0        // 0..1  nivel de voz en vivo

    // --- Geometría: el objeto layout de Sim.js (bh, suns[], bhSpin) ---
    // Si es null se usan fracciones por defecto de la variante D.
    property var layout: null

    // --- Paleta (roles de Colours.palette.m3*) ---
    property color colPrimary: "#f7b999"
    property color colLaura: "#efd994"
    property color colError: "#f97758"
    property color colVoid: "#060403"
    property color colInk: "#f8e1d6"
    property color colBelt: "#54453d"

    // Posiciones de los soles en px del Item — expuestas para la capa fina de
    // satélites/cinturón que va encima (así no recalcula la órbita del binario).
    readonly property point confPos: _l ? Qt.point(_l.suns[0].x, _l.suns[0].y)
                                        : Qt.point(width * 0.30, height * 0.47)
    readonly property point lauraPos: _l ? Qt.point(_l.suns[1].x, _l.suns[1].y)
                                         : Qt.point(width * 0.30, height * 0.47)
    readonly property real confRadius: _l ? _l.suns[0].r : height * 0.035
    readonly property real lauraRadius: _l ? _l.suns[1].r : height * 0.045

    readonly property var _l: layout && layout.suns && layout.suns.length >= 2 && layout.bh ? layout : null
    readonly property point _bhCenter: _l ? Qt.point(_l.bh.x, _l.bh.y)
                                          : Qt.point(width * 0.86, height * 0.09)
    readonly property real _bhRadius: _l ? _l.bh.R : height * 0.26

    // --- Agujero B10-B: geometría (6°, giro -0.30, r_out 10.5, gravedad débil lejos) ---
    readonly property real _bhShadow: Math.round(_bhRadius * 1.03)   // radio de la sombra (b_crit) en px
    readonly property real _bhTiltB: -0.30
    readonly property real _bhElev: 6 * Math.PI / 180
    readonly property real _bhROut: 10.5
    readonly property real _bhWeakR: 3.0
    // caja de pantalla que cubre disco + resplandor (recortada a la pantalla)
    readonly property rect _bhBox: {
        const R = _bhShadow, cx = _bhCenter.x, cy = _bhCenter.y;
        const x0 = Math.max(0, Math.floor(cx - 3.8 * R)), x1 = Math.min(width, Math.ceil(cx + 2.0 * R));
        const y0 = Math.max(0, Math.floor(cy - 2.0 * R)), y1 = Math.min(height, Math.ceil(cy + 1.9 * R));
        return Qt.rect(x0, y0, Math.max(16, x1 - x0), Math.max(16, y1 - y0));
    }
    readonly property string _bhGeoKey: [_bhBox.x, _bhBox.y, _bhBox.width, _bhBox.height,
                                         Math.round(_bhCenter.x), Math.round(_bhCenter.y), _bhShadow].join(",")
    on_BhGeoKeyChanged: bhGeoRebuild.restart()
    // El giro se deriva del `time` continuo (que avanza a ~30 fps), NO del
    // layout de Sim (que se recalcula a ~10 fps): así el beaming/Doppler del
    // disco es fluido aunque las posiciones de los soles se refresquen despacio.
    // Fase del disco INTEGRADA por la vista (velocidad variable en hover); si no
    // la cablea, cae al derivado de `time`.
    property real bhPhase: -1
    readonly property real _bhSpin: bhPhase >= 0 ? bhPhase : (2 * Math.PI / 150) * time

    // Cinturón de tareas: geometría del layout de Sim (baricentro FIJO, radios),
    // pero el GIRO se deriva del `time` continuo → rota fluido a 60 fps aunque
    // Sim se recalcule despacio. Período 1400 s (constante D.beltPeriodFrac).
    readonly property point _beltCenter: _l && _l.belt ? Qt.point(_l.belt.cx, _l.belt.cy)
                                                       : Qt.point(width * 0.30, height * 0.47)
    readonly property size _beltRadii: _l && _l.belt ? Qt.size(_l.belt.rx, _l.belt.ry)
                                                     : Qt.size(width * 0.14, width * 0.14 * 0.42)
    readonly property real _beltTilt: _l && _l.belt ? _l.belt.tilt : -0.05
    readonly property real _beltSpin: (2 * Math.PI / 1400) * time
    readonly property real _beltDensity: _l && _l.belt && _l.belt.density !== undefined ? _l.belt.density : 0.28

    // --- Progreso de la canción, interpolado ---
    // El modelo lo entrega a saltos (25 Hz, posición MPRIS); aquí se suaviza.
    // Un salto grande (cambio de tema, seek) viaja con animación más larga:
    // vuelve a 0 con transición suave, no de golpe.
    property real _progressSmooth: musicProgress
    Behavior on _progressSmooth {
        NumberAnimation {
            duration: Math.abs(root.musicProgress - root._progressSmooth) > 0.03 ? 700 : 120
            easing.type: Easing.OutCubic
        }
    }

    // --- Energía para las líneas finas (nunca destellos) ---
    // Dos seguidores: el rápido (ataque ~150 ms) y el lento (caída ~700 ms);
    // la salida es el máximo → sube rápido y baja despacio.
    readonly property real _linesTarget: Math.min(1, music * 0.5 + musicBass * 0.3 + musicTreble * 0.3)
    property real _linesFast: _linesTarget
    property real _linesSlow: _linesTarget
    Behavior on _linesFast { NumberAnimation { duration: 150 } }
    Behavior on _linesSlow { NumberAnimation { duration: 700 } }
    readonly property real _linesEnergy: Math.max(_linesFast, _linesSlow)

    // --- Música en el agujero ---
    // Hay música con progreso → el agujero pasa de «todo encendido» (aspecto aprobado) a «relleno
    // por progreso». En pausa se queda donde está; sin canción vuelve a todo encendido.
    readonly property bool _musicOn: musicProgress > 0.0005
    property real _musicActive: _musicOn ? 1 : 0
    Behavior on _musicActive { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    // fase de nacimiento del punto caliente: una nueva en cada golpe (la edad vuelve a ~0)
    property real _beatSeed: 0.37
    property real _lastBurstAge: 999
    // instantes (en `time`) de los dos últimos golpes → ondas de choque que se solapan sin saltos;
    // mínimo 0.35 s entre golpes para que no se amontonen
    property real _beatT0: -1e6
    property real _beatT1: -1e6
    readonly property real _beatAgeA: Math.min(999, time - _beatT0)
    readonly property real _beatAgeB: Math.min(999, time - _beatT1)
    onMusicBurstAgeChanged: {
        if (musicBurstAge < _lastBurstAge - 0.01) {
            _beatSeed = Math.random();
            if (time - _beatT0 > 0.35) { _beatT1 = _beatT0; _beatT0 = time; }
        }
        _lastBurstAge = musicBurstAge;
    }
    // onda gravitacional: el progreso vuelve casi a 0 desde bastante avanzado = canción nueva (o reinicio)
    property real _waveT: -1e6
    property real _lastProg: 0
    readonly property real _waveAge: Math.min(999, time - _waveT)
    onMusicProgressChanged: {
        if (musicProgress < 0.05 && _lastProg > 0.15) _waveT = time;
        _lastProg = musicProgress;
    }
    // tiempo de flujo del disco: como `time`, pero con música el giro se acelera hasta ×1.9 según la energía
    // (en silencio avanza igual que `time`, así que el aspecto en reposo no cambia)
    property real _flowT: 0
    property real _lastT: -1
    onTimeChanged: {
        if (_lastT >= 0) {
            const dt = time - _lastT;
            if (dt > 0 && dt < 2) _flowT += dt * (1 + 0.9 * _musicActive * Math.min(1, music));
        }
        _lastT = time;
    }

    // ===================== AGUJERO B10-B (fuera de pantalla: todo visible:false) =====================
    // Recalcular la caché geométrica: agrupa cambios seguidos (layout de Sim a ~10 Hz) en uno.
    Timer {
        id: bhGeoRebuild
        interval: 120
        onTriggered: { bhGeoA.scheduleUpdate(); bhGeoB.scheduleUpdate(); bhGeoH.scheduleUpdate() }
    }
    Item {
        id: bhChain
        width: root._bhBox.width
        height: root._bhBox.height

        // ruido periódico (una vez)
        ShaderEffect {
            id: bhNoiseFx
            width: 256; height: 256
            fragmentShader: Qt.resolvedUrl("shaders/bhnoise.frag.qsb")
        }
        ShaderEffectSource {
            id: bhNoise
            visible: false
            sourceItem: bhNoiseFx; hideSource: true; live: false
            textureSize: Qt.size(256, 256); wrapMode: ShaderEffectSource.Repeat; smooth: true
            Component.onCompleted: scheduleUpdate()
        }

        // caché geométrica: 3 salidas del MISMO raymarch (outSel 0, 1, 2)
        component BhGeo: ShaderEffect {
            width: bhChain.width; height: bhChain.height
            fragmentShader: Qt.resolvedUrl("shaders/bhgeo.frag.qsb")
            property real outSel: 0
            property real elev: root._bhElev
            property real bhRadius: root._bhShadow
            property real bhTilt: root._bhTiltB
            property size resolution: Qt.size(width, height)
            property point bhCenter: root._bhCenter
            property point boxOrigin: Qt.point(root._bhBox.x, root._bhBox.y)
            property real rOut: root._bhROut
            property real weakR: root._bhWeakR
        }
        component BhCache: ShaderEffectSource {
            visible: false
            hideSource: true; live: false; smooth: false
            textureSize: Qt.size(bhChain.width, bhChain.height); format: ShaderEffectSource.RGBA32F
            Component.onCompleted: scheduleUpdate()
        }
        BhGeo { id: bhGeoFxA; outSel: 0 }
        BhGeo { id: bhGeoFxB; outSel: 1 }
        BhGeo { id: bhGeoFxH; outSel: 2 }
        BhCache { id: bhGeoA; sourceItem: bhGeoFxA }
        BhCache { id: bhGeoB; sourceItem: bhGeoFxB }
        BhCache { id: bhGeoH; sourceItem: bhGeoFxH }

        // sombreado por frame (sigue a `time`, que ya avanza a los fps de calma del motor)
        ShaderEffect {
            id: bhShade
            width: bhChain.width; height: bhChain.height
            fragmentShader: Qt.resolvedUrl("shaders/bhshade.frag.qsb")
            property var geoA: bhGeoA
            property var geoB: bhGeoB
            property var geoH: bhGeoH
            property var noiseTex: bhNoise
            property real time: root.time
            property real bhRadius: root._bhShadow
            property real bhTilt: root._bhTiltB
            property size resolution: Qt.size(width, height)
            property point bhCenter: root._bhCenter
            property color colPrimary: Colours.palette.m3primary
            property color colInk: Colours.palette.m3onSurface
            property color colOnPC: Colours.palette.m3onPrimaryContainer
            property color colPC: Colours.palette.m3primaryContainer
            property color colTert: Colours.palette.m3tertiary
            property point boxOrigin: Qt.point(root._bhBox.x, root._bhBox.y)
            property real rOut: root._bhROut
            property real musicActive: root._musicActive
            property real musicProgress: root._progressSmooth
            property real musicBass: root.musicBass
            property real musicTreble: root.musicTreble
            property real beatAge: root.musicBurstAge
            property real beatSeed: root._beatSeed
            property real ftime: root._flowT
            property real beatAgeA: root._beatAgeA
            property real beatAgeB: root._beatAgeB
            property real waveAge: root._waveAge
        }
        ShaderEffectSource {
            id: bhScene
            visible: false
            sourceItem: bhShade; hideSource: true
            textureSize: Qt.size(bhChain.width, bhChain.height); format: ShaderEffectSource.RGBA16F
            smooth: true; mipmap: true
        }
        // bloom ¼ y ⅛ (separable)
        component BhBlur: ShaderEffect {
            fragmentShader: Qt.resolvedUrl("shaders/bhbloom.frag.qsb")
            property var src
            property point dir
            property point texel: Qt.point(1 / width, 1 / height)
            property real threshold: 0
            property real spread: 1.5
        }
        component BhTex: ShaderEffectSource {
            visible: false
            hideSource: true; format: ShaderEffectSource.RGBA16F; smooth: true
            textureSize: Qt.size(sourceItem.width, sourceItem.height)
        }
        BhBlur { id: bhBlurH;  width: Math.ceil(bhChain.width / 4); height: Math.ceil(bhChain.height / 4); src: bhScene; dir: Qt.point(1, 0); threshold: 1 }
        BhTex  { id: bhBlurHT; sourceItem: bhBlurH }
        BhBlur { id: bhBlurV;  width: bhBlurH.width; height: bhBlurH.height; src: bhBlurHT; dir: Qt.point(0, 1) }
        BhTex  { id: bhBlurVT; sourceItem: bhBlurV }
        BhBlur { id: bhBlurH2; width: Math.ceil(bhChain.width / 8); height: Math.ceil(bhChain.height / 8); src: bhScene; dir: Qt.point(1, 0); threshold: 1; spread: 2.4 }
        BhTex  { id: bhBlurH2T; sourceItem: bhBlurH2 }
        BhBlur { id: bhBlurV2; width: bhBlurH2.width; height: bhBlurH2.height; src: bhBlurH2T; dir: Qt.point(0, 1); spread: 2.4 }
        BhTex  { id: bhBlurV2T; sourceItem: bhBlurV2 }
        // suavizado de bordes contra el vacío: desenfoque de la escena completa (rgb + alfa) a media resolución;
        // bhcomp solo lo usa donde la cobertura cambia de golpe y fuera del radio de la sombra
        component BhSoft: ShaderEffect {
            fragmentShader: Qt.resolvedUrl("shaders/bhsoft.frag.qsb")
            property var src
            property point dir
            property point texel: Qt.point(1 / width, 1 / height)
            property real sigma: 5
        }
        BhSoft { id: bhSoftH; width: Math.ceil(bhChain.width / 2); height: Math.ceil(bhChain.height / 2); src: bhScene; dir: Qt.point(1, 0) }
        BhTex  { id: bhSoftHT; sourceItem: bhSoftH }
        BhSoft { id: bhSoftV; width: bhSoftH.width; height: bhSoftH.height; src: bhSoftHT; dir: Qt.point(0, 1) }
        BhTex  { id: bhSoftVT; sourceItem: bhSoftV }
        // composite: ACES por luminancia, bloom lavanda (tertiary), salida premultiplicada
        ShaderEffect {
            id: bhComp
            width: bhChain.width; height: bhChain.height
            fragmentShader: Qt.resolvedUrl("shaders/bhcomp.frag.qsb")
            property var scene: bhScene
            property var bloom: bhBlurVT
            property var bloom2: bhBlurV2T
            property var soft: bhSoftVT
            property real softAmt: 1.0
            property point boxOrigin: Qt.point(root._bhBox.x, root._bhBox.y)
            readonly property color _t: Colours.palette.m3tertiary
            property color tint: Qt.tint(Qt.rgba(1, 1, 1, 1), Qt.rgba(_t.r, _t.g, _t.b, 0.55))
            property real exposure: 0.8
            property real bloomAmt: 1.4
            property size resolution: Qt.size(width, height)
            property point bhCenter: root._bhCenter
            property real bhRadius: root._bhShadow
            // bordes de caja que coinciden con el de pantalla: sin desvanecer el resplandor
            property point edgeOpen: Qt.point(root._bhBox.x <= 0 ? 1e4 : 0,
                                              root._bhBox.y + root._bhBox.height >= root.height ? 1e4 : 0)
        }
        ShaderEffectSource {
            id: bhOut
            visible: false
            sourceItem: bhComp; hideSource: true
            textureSize: Qt.size(bhChain.width, bhChain.height); smooth: true
        }
    }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("shaders/solarfield.frag.qsb")
        blending: true

        // nombres = uniforms del shader (buf). `focusAmt` no `focus`: `focus` es
        // una propiedad FINAL de QQuickItem y no se puede sombrear.
        property real time: root.time
        property real music: root.music
        property real focusAmt: root.lauraFocus
        property real lauraAmp: root.lauraAmp

        property real bhRadius: root._bhRadius
        property real bhSpin: root._bhSpin
        property real bhTilt: root._bhTiltB
        property var bhTex: bhOut
        property point bhBoxOrigin: Qt.point(root._bhBox.x, root._bhBox.y)
        property size bhBoxSize: Qt.size(root._bhBox.width, root._bhBox.height)

        property real sun0Radius: root.confRadius
        property real sun1Radius: root.lauraRadius

        property size resolution: Qt.size(width, height)
        property point bhCenter: root._bhCenter
        property point binBary: root._l && root._l.bin ? Qt.point(root._l.bin.bx, root._l.bin.by) : Qt.point(width * 0.30, height * 0.47)
        property point binSemiAxes: root._l && root._l.bin ? Qt.point(root._l.bin.aConf, root._l.bin.aLaura) : Qt.point(50, 50)
        property real binEcc: root._l && root._l.bin ? root._l.bin.ecc : 0.45
        property real binTilt: root._l && root._l.bin ? root._l.bin.tilt : -0.15
        property real binOmega: root._l && root._l.bin ? root._l.bin.omega : 0.028

        property point beltCenter: root._beltCenter
        property size beltRadii: Qt.size(root._beltRadii.width, root._beltRadii.height)
        property real beltTilt: root._beltTilt
        property real beltSpin: root._beltSpin
        property real beltDensity: root._beltDensity
        property real musicProgress: root._progressSmooth
        property real musicLines: root._linesEnergy

        property color colPrimary: root.colPrimary
        property color colLaura: root.colLaura
        property color colError: root.colError
        property color colVoid: root.colVoid
        property color colInk: root.colInk
        property color colBelt: root.colBelt
    }
}
