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

import QtQuick

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
        property real bhTilt: -0.489

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
