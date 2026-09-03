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
                                          : Qt.point(width * 1.02, height * -0.04)
    readonly property real _bhRadius: _l ? _l.bh.R : height * 0.24
    readonly property real _bhSpin: _l && _l.bhSpin !== undefined ? _l.bhSpin
                                                                  : (2 * Math.PI / 150) * time

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
        property point sun0Pos: root.confPos
        property point sun1Pos: root.lauraPos

        property color colPrimary: root.colPrimary
        property color colLaura: root.colLaura
        property color colError: root.colError
        property color colVoid: root.colVoid
        property color colInk: root.colInk
    }
}
