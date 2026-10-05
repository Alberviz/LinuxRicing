import QtQuick

// PlanetFx — un cuerpo pintado por shaders/planet.frag (planeta de IA, luna de
// subagente o periférico). El item mide 4·R (R = radio del cuerpo). Los colores
// son los roles del tema que expone `pal` (el SolarSystem): cambian en vivo.
ShaderEffect {
    id: fx
    required property Item pal           // el SolarSystem (fuente de la paleta)
    property real bodyRadius: 10         // R en px
    property real kind: 0
    property real ctxAlert: 0
    property real batt: 0
    property real glyph: 0

    width: bodyRadius * 4
    height: width
    blending: true
    fragmentShader: Qt.resolvedUrl("shaders/planet.frag.qsb")

    property color cPrimary: pal.colPrimary
    property color cSecondary: pal.colSecondary
    property color cTertiary: pal.colLaura
    property color cPrimaryC: pal.colPrimaryC
    property color cSecondaryC: pal.colSecondaryC
    property color cTertiaryC: pal.colTertiaryC
    property color cSurface: pal.colSurface
    property color cSurfaceC: pal.colSurfaceC
    property color cOnSurface: pal.colInk
    property color cOutline: pal.colOutline
    property color cError: pal.colError
    property color cClaude: pal.claudeCol
    property color cGemini: pal.geminiCol
}
