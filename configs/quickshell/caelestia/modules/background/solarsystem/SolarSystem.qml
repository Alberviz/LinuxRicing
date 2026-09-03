pragma ComponentBehavior: Bound

// SolarSystem.qml — la VISTA de la v3 (variante D), tras el cambio a GPU.
//
// El FONDO (agujero negro + los dos soles + campo de estrellas + lente) lo pinta
// un shader GLSL (`SolarField`, lo instancia SolarSystemLayer o el integrador
// como primer hijo de este Item). Este archivo solo mantiene:
//
//  · el motor de posiciones (Sim.js) a ~2 fps — el shader interpola visualmente;
//  · una capa fina en Canvas: cinturón de tareas, trazas de órbita y satélites
//    (agentes/dispositivos) — pocos elementos y datos vivos, no valen un shader;
//  · el MODO LAURA ACTIVA (D-12): con `lauraActive` el tiempo se congela, la
//    capa fina se atenúa (`_dimK`) y el shader recibe `lauraFocus` para oscurecer el
//    fondo y hacer que Laura brille latiendo con `lauraAmplitude`.
//
// Interfaz para el shader del fondo (`SolarField`): `_t` (tiempo, s), `music`
// (0..1), `lauraFocus` (0..1), `lauraAmplitude` (0..1), `layout` (posiciones de Sim:
// `layout.bh`, `layout.suns`, `layout.bary`, `layout.bhSpin`), y los roles de
// paleta `colPrimary/colLaura/colError/colVoid/colInk` + `_hot`.
// Ningún color fijo: la paleta entra como propiedad. Ver docs/sistema-solar-v3-DISENO.md.

import QtQuick
import "Sim.js" as Sim

Item {
    id: root

    // --- Entradas de datos ---
    property var config: ({ anchors: [], bodies: [] })
    property var values: ({})

    // --- Paleta (roles de Colours.palette.m3*) — para el shader y la capa fina ---
    property color colPrimary: "#f7b999"       // disco del agujero, sol Configuración
    property color colLaura: "#efd994"         // sol Laura (m3tertiaryFixedDim — D-9)
    property color colError: "#f97758"         // alerta de batería < 20 %
    property color colBelt: "#54453d"          // cinturón de tareas
    property color colInk: "#f8e1d6"           // estrellas
    property color colVoid: "#050302"          // horizonte de sucesos (darker(m3surface, 3))
    readonly property color _hot: _lit(colPrimary, 0.86)

    property bool paused: false
    property bool reduceMotion: false
    property bool active: false                // ¿hay un agente en curso? (sube el ritmo del Sim)
    property bool fastRate: false              // ¿música sonando? (sube el ritmo del Sim)

    // --- Modo Laura activa (D-12) ---
    // Lo cablea SolarSystemLayer desde el singleton Laura. La vista solo ve dos
    // entradas (mantiene el desacople: nada de servicios aquí dentro).
    property bool lauraActive: false
    property real lauraAmplitude: 0            // nivel de voz 0..1 (en vivo, ya suavizado)
    property real lauraFocus: lauraActive ? 1 : 0   // 0 normal · 1 foco-Laura (fondo oscuro, Laura brilla)
    Behavior on lauraFocus {
        NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
    }
    // Atenuación de la capa fina: focus 0 → 1 (sin cambio), focus 1 → 0.18.
    readonly property real _dimK: 1 - 0.82 * lauraFocus

    // `_t` avanza siempre (NumberAnimation). `simTime` es el tiempo del SISTEMA:
    // igual a `_t` menos el rato acumulado en modo Laura, así que se CONGELA
    // mientras Laura habla y REANUDA sin salto al terminar. Lo usan el shader y
    // Sim.js. Una sola fuente de verdad.
    property real _frozenAccum: 0
    property real _tFreeze: 0
    readonly property real simTime: lauraActive ? _tFreeze : (_t - _frozenAccum)
    onLauraActiveChanged: {
        if (lauraActive)
            _tFreeze = _t - _frozenAccum;                 // dónde congelamos
        else
            _frozenAccum += (_t - _frozenAccum) - _tFreeze; // suma el rato congelado
    }

    // --- Estado ---
    property real _t: 0                         // tiempo de simulación (s); se congela con focus
    property int _tick: 0
    property real _pf: 0                        // último lauraFocus pintado (para la transición)
    property var _layout: null
    readonly property var layout: _layout
    readonly property real music: _layout ? _layout.music : 0

    // Bounding box del contenido (región de input de la tanda de interacción, D-7).
    readonly property rect contentBounds: _layout
        ? Qt.rect(_layout.bounds.x, _layout.bounds.y, _layout.bounds.w, _layout.bounds.h)
        : Qt.rect(0, 0, width, height)

    // ---- helpers de color (los usa la capa fina en Canvas) ----
    function _a(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
             + Math.round(c.b * 255) + "," + Math.max(0, Math.min(1, a)) + ")";
    }
    function _lit(c, k) { return Qt.rgba(c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, 1); }
    function _dk(c, k) { return Qt.rgba(c.r * (1 - k), c.g * (1 - k), c.b * (1 - k), 1); }
    function _mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1); }
    function _glow(ctx, x, y, inner, outer, col, a0) {
        const g = ctx.createRadialGradient(x, y, inner, x, y, outer);
        g.addColorStop(0, _a(col, a0));
        g.addColorStop(1, _a(col, 0));
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(x, y, outer, 0, 2 * Math.PI);
        ctx.fill();
    }
    // elipse por scale+arc (QML Canvas no tiene el ellipse de HTML5)
    function _strokeEllipse(ctx, cx, cy, rx, ry, rot, a0, a1, style, lw) {
        ctx.save();
        ctx.translate(cx, cy);
        if (rot) ctx.rotate(rot);
        ctx.scale(1, ry / rx);
        ctx.strokeStyle = style;
        ctx.lineWidth = lw;
        ctx.beginPath();
        ctx.arc(0, 0, rx, a0, a1);
        ctx.stroke();
        ctx.restore();
    }

    function _geom() { return { w: width, h: height }; }

    function _recompute() {
        if (width <= 0 || height <= 0)
            return;
        root._layout = Sim.computeLayout({ t: root.simTime, values: root.values, config: root.config }, root._geom());
    }
    function _paintDyn() {
        // Repintar orbitsCanvas solo si hay un cambio estructural (opcional, 
        // actualmente manejado por bindings y onNumBodiesChanged)
    }

    property int numBodies: root._layout ? root._layout.bodies.length : 0
    onNumBodiesChanged: if (orbitsCanvas.available) orbitsCanvas.requestPaint()

    // ---------------- Órbitas (trazas casi invisibles en reposo, spec §4.3) ----------------
    function _drawOrbits(ctx, L) {
        for (let i = 0; i < L.bodies.length; i++) {
            const b = L.bodies[i];
            if (b.kind === "agent" && !b.running) continue;
            const rr = Math.hypot(b.x - b.hostx, (b.y - b.hosty) / 0.52);
            root._strokeEllipse(ctx, b.hostx, b.hosty, rr, rr * 0.52, 0, 0, 2 * Math.PI,
                           root._a(b.kind === "device" ? root.colPrimary : root.colLaura, 0.035), 1);
        }
    }

    // El cinturón circumbinario (spec §2.4) lo pinta el shader desde v3.1 —
    // procedural en la GPU. Antes era un bucle Canvas de hasta 100 partículas
    // (con string de color por partícula) que saturaba el hilo de la GUI.

    // ===================== FONDO (shader GPU, D-13) =====================
    // Agujero negro + los dos soles + campo de estrellas + lente, per-píxel en
    // la GPU. Coste de CPU ~0: solo actualizar uniforms. Primer hijo → al fondo.
    SolarField {
        anchors.fill: parent
        time: root.simTime
        music: root.music
        lauraFocus: root.lauraFocus
        lauraAmp: root.lauraAmplitude
        layout: root._layout
        colPrimary: root.colPrimary
        colLaura: root.colLaura
        colError: root.colError
        colVoid: root.colVoid
        colInk: root.colInk
        colBelt: root.colBelt
    }

    // ===================== CAPA FINA (cinturón + órbitas + satélites) =====================
    // Órbitas (estático, se repinta solo al cambiar layout)
    Canvas {
        id: orbitsCanvas
        renderTarget: Canvas.Image
        antialiasing: true
        onAvailableChanged: if (available) requestPaint()
        Component.onCompleted: if (available) requestPaint()
        x: root._layout ? root._layout.binBounds.x : 0
        y: root._layout ? root._layout.binBounds.y : 0
        width: root._layout ? root._layout.binBounds.w : root.width
        height: root._layout ? root._layout.binBounds.h : root.height
        opacity: root._dimK

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const L = root._layout;
            if (!L) return;
            ctx.translate(-x, -y);
            root._drawOrbits(ctx, L);
        }
    }

    // Texturas base para planetas (generadas una vez)
    Canvas {
        id: texDevice
        width: 128; height: 128; visible: false
        renderTarget: Canvas.Image
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = 64; const base = root.colPrimary;
            const pg = ctx.createRadialGradient(r + r*0.45, r, r*0.1, r, r, r);
            pg.addColorStop(0, root._a(root._lit(base, 0.55), 1));
            pg.addColorStop(0.6, root._a(base, 1));
            pg.addColorStop(1, root._a(root._dk(base, 0.55), 1));
            ctx.fillStyle = pg;
            ctx.beginPath(); ctx.arc(r, r, r, 0, 2*Math.PI); ctx.fill();
            ctx.strokeStyle = root._a(root._lit(base, 0.6), 0.45);
            ctx.lineWidth = 2;
            ctx.beginPath(); ctx.arc(r, r, r, -1.4, 1.4); ctx.stroke();
        }
    }
    Canvas {
        id: texAgent
        width: 128; height: 128; visible: false
        renderTarget: Canvas.Image
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = 64; const base = root.colLaura;
            const pg = ctx.createRadialGradient(r + r*0.45, r, r*0.1, r, r, r);
            pg.addColorStop(0, root._a(root._lit(base, 0.55), 1));
            pg.addColorStop(0.6, root._a(base, 1));
            pg.addColorStop(1, root._a(root._dk(base, 0.55), 1));
            ctx.fillStyle = pg;
            ctx.beginPath(); ctx.arc(r, r, r, 0, 2*Math.PI); ctx.fill();
            ctx.strokeStyle = root._a(root._lit(base, 0.6), 0.45);
            ctx.lineWidth = 2;
            ctx.beginPath(); ctx.arc(r, r, r, -1.4, 1.4); ctx.stroke();
        }
    }
    // Texturas instanciadas y coloreadas por el Repetidor

    Repeater {
        model: root._layout ? root._layout.bodies.length : 0
        Item {
            property var b: root._layout.bodies[index]
            x: b.x - b.r
            y: b.y - b.r
            width: b.r * 2
            height: b.r * 2
            opacity: root._dimK

            // Aro de alerta
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 8 * root.layout.scale
                height: width
                radius: width / 2
                color: "transparent"
                border.color: root._a(root.colError, 0.3 + 0.5 * (0.5 + 0.5 * Math.sin(root._t * 1.4)))
                border.width: 1.5
                visible: b.alert > 0.5
            }

            // Anillo de actividad (agente en curso)
            Item {
                anchors.centerIn: parent
                visible: b.running
                width: parent.width * 2.8
                height: parent.height * 2.8
                // QML no tiene radial gradient nativo fácil sin QtGraphicalEffects
                // Usamos un Canvas muy simple o ShaderEffect
                Canvas {
                    anchors.fill: parent
                    renderTarget: Canvas.Image
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        root._glow(ctx, width/2, height/2, width/2 * 0.17, width/2, root.colLaura, 1.0);
                        root._strokeEllipse(ctx, width/2, height/2, width/2 * 0.67, width/2 * 0.28, 0.5, 0, 2*Math.PI, root._a(root._lit(root.colLaura, 0.3), 0.5), 1);
                    }
                    opacity: 0.28 + 0.2 * (0.5 + 0.5 * Math.sin(root._t * 0.7))
                }
            }

            // Planeta (textura instanciada y rotada)
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: b.kind === "device" ? texDevice : texAgent
                sourceRect: Qt.rect(0, 0, 128, 128)
                rotation: Math.atan2(b.hosty - b.y, b.hostx - b.x) * 180 / Math.PI
            }
        }
    }

    // ===================== TIC =====================
    // Movimiento CONTINUO por frame (vsync). Alberto: «que se vea fluido aunque
    // cueste rendimiento; órbitas lentas pero fluidas». La lentitud la dan los
    // períodos largos de Sim.js (binario 220 s, disco 150 s), NO un fps bajo:
    // pintar a 10 fps un movimiento lento se ve a tirones. Aquí `_t` avanza cada
    // frame → el shader del fondo (beaming/turbulencia/resplandor) y las
    // posiciones de los soles se refrescan suave.
    //
    // GATEADO (visible / no-pausa / no-reduce-motion) — nunca incondicional
    // (CLAUDE.md). En foco-Laura sigue avanzando `_t` (monótono) pero se salta el
    // recálculo: el sistema está congelado (`simTime` latcheado) y el shader no
    // necesita repintar (su `time` es `simTime`, el latido de Laura va por
    // `lauraAmp`). Siempre restart limpio del shell, nunca hot-reload.
    FrameAnimation {
        id: clock
        running: root.visible && !root.paused && !root.reduceMotion
        onTriggered: {
            root._t += frameTime;                // reloj del shader: CADA frame (60 fps, fluido)
            if (root.lauraActive)
                return;                          // sistema congelado: nada que recalcular
            root._accSim += frameTime;
            if (root._accSim >= 0.028) {          // ~33 fps: posiciones (Sim)
                root._accSim = 0;
                root._recompute();
            }
        }
        onRunningChanged: if (!running) { root._recompute(); }
    }
    property real _accSim: 0

    // Transición del foco-Laura: repinta la capa fina mientras `lauraFocus`
    // anima (el shader del fondo dima solo, atado a `lauraFocus` por binding).
    onLauraFocusChanged: if (Math.abs(lauraFocus - _pf) > 0.015) { _pf = lauraFocus; }

    // Al cambiar datos (aparece un agente, cambia la batería) o tamaño/paleta:
    // recalcular y repintar la capa fina, coalescido para no repintar de más
    // (`values`/`config` son var computadas y re-emiten con referencia nueva).
    Timer {
        id: settle
        interval: 300
        onTriggered: { root._recompute(); if (orbitsCanvas.available) orbitsCanvas.requestPaint(); }
    }
    onValuesChanged: settle.restart()
    onConfigChanged: settle.restart()
    onWidthChanged: { _recompute(); if (orbitsCanvas.available) orbitsCanvas.requestPaint(); }
    onHeightChanged: { _recompute(); if (orbitsCanvas.available) orbitsCanvas.requestPaint(); }
    onColPrimaryChanged: { _recompute(); if (orbitsCanvas.available) orbitsCanvas.requestPaint(); texDevice.requestPaint(); }
    onColLauraChanged: { texAgent.requestPaint(); if (orbitsCanvas.available) orbitsCanvas.requestPaint(); }
    onColErrorChanged: { } // el aro de alerta reacciona automático
    onColBeltChanged: { } // el shader reacciona automático

    Component.onCompleted: { texDevice.requestPaint(); texAgent.requestPaint(); _recompute(); if (orbitsCanvas.available) orbitsCanvas.requestPaint(); }
}
