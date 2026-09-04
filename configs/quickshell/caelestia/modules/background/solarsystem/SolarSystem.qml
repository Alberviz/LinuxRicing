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
import QtQuick.Shapes
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

    // --- Etiquetas de cuerpos (BodyLabel, variante C) ---
    // La tipografía y los colores por proveedor de IA entran como propiedad
    // (mismo patrón que la paleta): la vista no importa Config ni servicios.
    property string labelFont: "JetBrainsMono NF"   // fallback; lo cablea la capa
    // provider ("claude"|"gemini"|"codex"|"otro") → color ya resuelto por
    // SolarSystemLayer desde SolarSystemModel.providerPaletteRole. Vacío = usa colLaura.
    property var agentProviderColours: ({})

    property bool paused: false
    property bool reduceMotion: false
    property bool active: false                // ¿hay un agente en curso? (sube el ritmo del Sim)
    property bool fastRate: false              // ¿música sonando? (sube el ritmo del Sim)
    property int musicVariant: 2               // Variante de visualizador en agujero negro (1..6)

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

    // ---- Etiquetas: nombre legible, dato real y color por rol ----
    // Diccionario id → nombre. Los ids de agente ("term:<algo>") traen su propio
    // `name` desde el modelo; aquí sólo se nombran anclas y dispositivos fijos.
    readonly property var _labelNames: ({
        "laura": "Laura",
        "config": "Configuración",
        "music": "Música",
        "dev-headset": "Auriculares",
        "dev-mouse": "Ratón",
        "dev-keyboard": "Teclado"
    })
    function _bodyName(b) {
        if (!b) return "";
        if (b.name && b.name.length) return b.name;          // agentes (del modelo)
        return root._labelNames[b.id] || "";
    }
    // Subtítulo: SÓLO dato real. Dispositivo → batería; agente → estado. Nada más.
    function _bodySubtitle(b) {
        if (!b) return "";
        if (b.kind === "device")
            return (typeof b.batt === "number") ? (Math.round(b.batt * 100) + "%") : "";
        if (b.kind === "agent") {
            const prefix = b.ws ? ("ws " + b.ws + " · ") : "";
            const pct = (typeof b.contextRatio === "number") ? Math.round(b.contextRatio * 100) : 0;
            const ctxText = (pct > 0) ? (" · " + pct + "% ctx") : "";
            if (b.running) return prefix + "en curso" + ctxText;
            if (b.status === "done") return prefix + "hecho" + ctxText;
            if (b.status === "session") return prefix + "sesión" + ctxText;
            return prefix + "sesión" + ctxText;
        }
        return "";
    }
    // Color de la etiqueta por rol de paleta (cero hex). Alerta manda; luego el
    // proveedor de IA para agentes; si no, el rol del ancla que orbita.
    function _bodyCol(b) {
        if (!b) return root.colInk;
        if (b.alert > 0.5) return root.colError;
        if (b.kind === "agent") {
            const pc = root.agentProviderColours[b.provider];
            return (pc !== undefined && pc !== null) ? pc : root.colLaura;
        }
        return root.colPrimary;   // dispositivo → sol Configuración
    }
    // Énfasis del satélite, derivado de su radio (acotado). Anclas van a 1.0.
    function _bodyEmphasis(b) {
        if (!b) return 0.35;
        if (b.status === "done") return 1.0;
        if (b.running) return 0.85;
        if (b.status === "session") return 0.28;
        const k = Math.max(0, Math.min(1, (b.r - 4) / 14));
        return 0.30 + 0.22 * k;
    }

    function _recompute() {
        if (width <= 0 || height <= 0)
            return;
        root._layout = Sim.computeLayout({ t: root.simTime, values: root.values, config: root.config }, root._geom());
        root._rescanPulseFlags();
    }
    function _paintDyn() {
        // Repintar orbitsCanvas solo si hay un cambio estructural (opcional, 
        // actualmente manejado por bindings y onNumBodiesChanged)
    }

    property int numBodies: root._layout ? root._layout.bodies.length : 0

    // Revisión de las texturas base de los satélites: sube cada vez que
    // texDevice/texAgent se repintan (cambio de tamaño o de paleta). Los
    // ShaderEffectSource de los delegados escuchan esto para hacer UN
    // scheduleUpdate() puntual — NO son `live`, así que en reposo no cuestan
    // ningún render-target por frame (regresión de CPU del Repeater, sept-2026).
    property int _texRev: 0

    // Pulsos de UI (aro de alerta, anillo de actividad, parpadeo de terminado).
    // Sólo se recalculan si hay AL MENOS un cuerpo que los use.
    property bool _anyAlert: false
    property bool _anyRunning: false
    property bool _anyDone: false
    property real _alertPulse: 0.75
    property real _ringPulse: 0.5
    property real _donePulse: 0.5
    property real _accPulse: 0
    function _rescanPulseFlags() {
        let aa = false, ar = false, ad = false;
        const L = root._layout;
        if (L)
            for (let i = 0; i < L.bodies.length; i++) {
                if (L.bodies[i].alert > 0.5) aa = true;
                if (L.bodies[i].running) ar = true;
                if (L.bodies[i].status === "done") ad = true;
            }
        root._anyAlert = aa;
        root._anyRunning = ar;
        root._anyDone = ad;
    }

    // ---------------- Órbitas y estelas: ahora en GPU vía QtQuick.Shapes ----------------

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

    // ===================== CAPA FINA (órbitas + estelas en GPU) =====================
    Item {
        id: orbitsLayer
        anchors.fill: parent
        opacity: root._dimK

        Repeater {
            model: root._layout ? root._layout.bodies.length : 0
            delegate: Item {
                id: orbitItem
                required property int index
                readonly property var b: root._layout ? root._layout.bodies[index] : null
                visible: b !== null && b.orbX !== undefined
                anchors.fill: parent

                readonly property bool dev: b ? b.kind === "device" : false
                readonly property color col: dev ? root.colPrimary : root.colLaura
                readonly property bool isSession: b ? b.status === "session" : false
                readonly property bool isRunning: b ? b.running : false
                readonly property bool isDone: b ? b.status === "done" : false
                readonly property real baseA: (root._layout && root._layout.orbitAlpha !== undefined) ? root._layout.orbitAlpha : 0.12

                // Opacidad y longitud de la estela por estado:
                // - running: brillante (baseA * 6.5) y larga (~75°)
                // - done: media (baseA * 3.8) y media (~42°)
                // - session (idle): tenue/apagada (baseA * 0.9) y corta (~18°)
                // - device: sólida (baseA * 4.5) y estándar (~45°)
                readonly property real headA: isRunning
                    ? Math.min(0.85, baseA * 6.5)
                    : (dev ? Math.min(0.75, baseA * 4.5)
                           : (isDone ? Math.min(0.70, baseA * 3.8) : Math.min(0.18, baseA * 0.9)))

                readonly property real deg: b ? (b.oa * 180 / Math.PI) : 0
                readonly property real spanDeg: isRunning
                    ? (1.30 * 180 / Math.PI)
                    : (dev ? (0.80 * 180 / Math.PI)
                           : (isDone ? (0.75 * 180 / Math.PI) : (0.32 * 180 / Math.PI)))
                readonly property real scaleFactor: root._layout ? root._layout.scale : 1.0

                Shape {
                    anchors.fill: parent

                    // 1 · Elipse orbital completa
                    ShapePath {
                        strokeColor: Qt.rgba(orbitItem.col.r, orbitItem.col.g, orbitItem.col.b,
                                             orbitItem.baseA * (orbitItem.isRunning ? 1.35 : (orbitItem.dev ? 1.0 : (orbitItem.isDone ? 0.90 : 0.35))))
                        strokeWidth: (orbitItem.isRunning ? 1.4 : (orbitItem.isSession ? 0.75 : 1.0)) * orbitItem.scaleFactor
                        fillColor: "transparent"
                        PathAngleArc {
                            centerX: orbitItem.b ? orbitItem.b.hostx : 0
                            centerY: orbitItem.b ? orbitItem.b.hosty : 0
                            radiusX: orbitItem.b ? orbitItem.b.orbX : 0
                            radiusY: orbitItem.b ? orbitItem.b.orbV : 0
                            startAngle: 0
                            sweepAngle: 360
                        }
                    }

                    // 2 · Estela de cometa (cola lejana)
                    ShapePath {
                        strokeColor: Qt.rgba(orbitItem.col.r, orbitItem.col.g, orbitItem.col.b, orbitItem.headA * 0.20)
                        strokeWidth: (2.4 * 0.5) * orbitItem.scaleFactor
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: orbitItem.b ? orbitItem.b.hostx : 0
                            centerY: orbitItem.b ? orbitItem.b.hosty : 0
                            radiusX: orbitItem.b ? orbitItem.b.orbX : 0
                            radiusY: orbitItem.b ? orbitItem.b.orbV : 0
                            startAngle: orbitItem.deg - orbitItem.spanDeg
                            sweepAngle: orbitItem.spanDeg * 0.45
                        }
                    }

                    // 3 · Estela de cometa (cola media)
                    ShapePath {
                        strokeColor: Qt.rgba(orbitItem.col.r, orbitItem.col.g, orbitItem.col.b, orbitItem.headA * 0.50)
                        strokeWidth: (2.4 * 0.75) * orbitItem.scaleFactor
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: orbitItem.b ? orbitItem.b.hostx : 0
                            centerY: orbitItem.b ? orbitItem.b.hosty : 0
                            radiusX: orbitItem.b ? orbitItem.b.orbX : 0
                            radiusY: orbitItem.b ? orbitItem.b.orbV : 0
                            startAngle: orbitItem.deg - orbitItem.spanDeg * 0.60
                            sweepAngle: orbitItem.spanDeg * 0.40
                        }
                    }

                    // 4 · Estela de cometa (cabeza luminosa junto al planeta)
                    ShapePath {
                        strokeColor: Qt.rgba(orbitItem.col.r, orbitItem.col.g, orbitItem.col.b, orbitItem.headA * 0.95)
                        strokeWidth: 2.4 * orbitItem.scaleFactor
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: orbitItem.b ? orbitItem.b.hostx : 0
                            centerY: orbitItem.b ? orbitItem.b.hosty : 0
                            radiusX: orbitItem.b ? orbitItem.b.orbX : 0
                            radiusY: orbitItem.b ? orbitItem.b.orbV : 0
                            startAngle: orbitItem.deg - orbitItem.spanDeg * 0.25
                            sweepAngle: orbitItem.spanDeg * 0.25
                        }
                    }
                }
            }
        }
    }

    // Texturas base para planetas (generadas una vez; se repintan sólo al
    // cambiar tamaño o paleta, y entonces suben `_texRev`).
    Canvas {
        id: texDevice
        width: 128; height: 128; visible: false
        renderTarget: Canvas.Image
        onAvailableChanged: if (available) requestPaint()
        onPainted: root._texRev++
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
        onAvailableChanged: if (available) requestPaint()
        onPainted: root._texRev++
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
        id: bodyRep
        model: root._layout ? root._layout.bodies.length : 0
        Item {
            id: bodyItem
            required property int index
            readonly property var b: root._layout ? root._layout.bodies[index] : null
            visible: b !== null
            x: b ? b.x - b.r : 0
            y: b ? b.y - b.r : 0
            width: b ? b.r * 2 : 0
            height: width

            readonly property bool isSession: bodyItem.b ? bodyItem.b.status === "session" : false
            readonly property bool isDone: bodyItem.b ? bodyItem.b.status === "done" : false
            readonly property bool isRunning: bodyItem.b ? bodyItem.b.running : false

            // Opacidad del cuerpo:
            // - session (idle): atenuado/apagado (0.42)
            // - done (terminado): parpadea con _donePulse (0.60 .. 1.0)
            // - running / device: brillo pleno (1.0)
            opacity: root._dimK * (isSession ? 0.42 : (isDone ? (0.60 + 0.40 * root._donePulse) : 1.0))

            // Aro de alerta (batería < 20 %). Loader: si el cuerpo no está en
            // alerta el binding del pulso NI EXISTE.
            Loader {
                anchors.centerIn: parent
                active: bodyItem.b !== null && bodyItem.b.alert > 0.5 && bodyItem.b.kind === "device"
                sourceComponent: Rectangle {
                    width: bodyItem.width + 8 * (root._layout ? root._layout.scale : 1.0)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: root._a(root.colError, 0.3 + 0.6 * root._alertPulse)
                    border.width: 1.5
                }
            }

            // Halo parpadeante para agentes terminados pendientes de ver ("¡hecho!")
            Loader {
                anchors.centerIn: parent
                active: bodyItem.isDone
                sourceComponent: Rectangle {
                    width: bodyItem.width + 12 * (root._layout ? root._layout.scale : 1.0)
                    height: width
                    radius: width / 2
                    color: Qt.rgba(bodyCol.r, bodyCol.g, bodyCol.b, 0.15 * root._donePulse)
                    border.color: Qt.rgba(bodyCol.r, bodyCol.g, bodyCol.b, 0.40 + 0.60 * root._donePulse)
                    border.width: 1.8
                    readonly property color bodyCol: root._bodyCol(bodyItem.b)
                }
            }

            // Anillo de actividad (agente en curso). Igual: sin cuerpo en curso,
            // sin Canvas y sin binding de opacidad animado.
            Loader {
                anchors.centerIn: parent
                active: bodyItem.isRunning
                sourceComponent: Canvas {
                    width: bodyItem.width * 2.8
                    height: width
                    renderTarget: Canvas.Image
                    opacity: 0.28 + 0.32 * root._ringPulse
                    Component.onCompleted: if (available) requestPaint()
                    property int rev: root._texRev
                    onRevChanged: if (available) requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        root._glow(ctx, width / 2, height / 2, width / 2 * 0.17, width / 2, root.colLaura, 1.0);
                        root._strokeEllipse(ctx, width / 2, height / 2, width / 2 * 0.67, width / 2 * 0.28, 0.5, 0, 2 * Math.PI, root._a(root._lit(root.colLaura, 0.3), 0.5), 1);
                    }
                }
            }

            // Planeta: textura base cacheada, sólo transformada (posición +
            // rotación del terminador hacia su ancla). `live: false` → el
            // render-target se pinta UNA vez (y al subir `_texRev`); la rotación
            // es un transform del scene-graph, no obliga a repintar la FBO.
            ShaderEffectSource {
                anchors.fill: parent
                live: false
                hideSource: true
                sourceItem: (bodyItem.b && bodyItem.b.kind === "device") ? texDevice : texAgent
                sourceRect: Qt.rect(0, 0, 128, 128)
                rotation: bodyItem.b ? Math.atan2(bodyItem.b.hosty - bodyItem.b.y, bodyItem.b.hostx - bodyItem.b.x) * 180 / Math.PI : 0
                property int rev: root._texRev
                onRevChanged: scheduleUpdate()
                Component.onCompleted: scheduleUpdate()
            }
        }
    }

    // ===================== ETIQUETAS (BodyLabel, variante C) =====================
    // Último hijo → por encima del shader y de los cuerpos. Una etiqueta por sol,
    // una por el agujero negro y una por satélite. Bindings puros: se recolocan
    // solas al cambiar `_layout` (NO hay temporizador nuevo). Cada etiqueta hace
    // un único fundido de aparición al crearse; nada en bucle.
    //
    // MODO LAURA (D-12): la capa se atenúa como el resto (`_dimK`) SALVO la
    // etiqueta de Laura, que es quien habla — se queda a opacidad plena.
    Item {
        id: labelLayer
        anchors.fill: parent

        // Anclas: los dos soles del binario.
        Repeater {
            model: root._layout ? root._layout.suns.length : 0
            delegate: Item {
                id: sunWrap
                required property int index
                readonly property var s: root._layout ? root._layout.suns[index] : null
                anchors.fill: parent
                opacity: (root.lauraActive && sunWrap.s && sunWrap.s.id === "laura")
                    ? 1 : root._dimK
                Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                BodyLabel {
                    variant: "B"
                    fontFamily: root.labelFont
                    basePixelSize: 13
                    showReticle: false
                    visible: sunWrap.s !== null
                    targetX: sunWrap.s ? sunWrap.s.x : 0
                    targetY: sunWrap.s ? sunWrap.s.y : 0
                    targetRadius: sunWrap.s ? sunWrap.s.r : 0
                    title: sunWrap.s ? (root._labelNames[sunWrap.s.id] || "") : ""
                    subtitle: ""
                    emphasis: 0.55
                    col: sunWrap.s
                        ? (sunWrap.s.id === "laura" ? root.colLaura : root.colPrimary)
                        : root.colInk
                }
            }
        }

        // Agujero negro «Música»: su centro cae fuera de cuadro (~1.02W, -0.04H),
        // así que la etiqueta apunta a un punto VISIBLE del borde inferior-izq.
        // del disco, no al centro.
        Item {
            id: bhWrap
            readonly property var bh: root._layout ? root._layout.bh : null
            anchors.fill: parent
            opacity: root._dimK

            MusicHole {
                center: bhWrap.bh ? Qt.point(bhWrap.bh.x, bhWrap.bh.y) : Qt.point(0,0)
                radius: bhWrap.bh ? bhWrap.bh.R : 100
                time: root._t
                musicBass: root._layout && root._layout.musicBass !== undefined ? root._layout.musicBass : 0
                musicPulse: root._layout && root._layout.musicPulse !== undefined ? root._layout.musicPulse : 0
                musicTreble: root._layout && root._layout.musicTreble !== undefined ? root._layout.musicTreble : 0
                colPrimary: root.colPrimary
                colInk: root.colInk
                colVoid: root.colVoid
                colError: root.colError
                fontFamily: root.labelFont
                variant: root.musicVariant
                onVariantChanged: root.musicVariant = variant
            }
        }

        // Satélites: agentes (séquito de Laura) y dispositivos (séquito de
        // Configuración). Sin retículo si el cuerpo ya lleva anillo de actividad
        // o aro de alerta (no apilar dos círculos).
        Repeater {
            model: root._layout ? root._layout.bodies.length : 0
            delegate: Item {
                id: satWrap
                required property int index
                readonly property var b: root._layout ? root._layout.bodies[index] : null
                anchors.fill: parent
                opacity: root._dimK
                visible: satWrap.b !== null && root._bodyName(satWrap.b).length > 0

                BodyLabel {
                    variant: "B"
                    fontFamily: root.labelFont
                    basePixelSize: 12
                    visible: satWrap.b !== null
                    targetX: satWrap.b ? satWrap.b.x : 0
                    targetY: satWrap.b ? satWrap.b.y : 0
                    labelY: satWrap.b ? satWrap.b.ly : 0
                    targetRadius: satWrap.b ? satWrap.b.r : 0
                    title: root._bodyName(satWrap.b)
                    subtitle: root._bodySubtitle(satWrap.b)
                    emphasis: root._bodyEmphasis(satWrap.b)
                    col: root._bodyCol(satWrap.b)
                    showReticle: false
                }
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
            // Pulsos de UI: sólo si hay algún cuerpo que los use, y a ~25 fps.
            if (root._anyAlert || root._anyRunning || root._anyDone) {
                root._accPulse += frameTime;
                if (root._accPulse >= 0.04) {
                    root._accPulse = 0;
                    if (root._anyAlert)
                        root._alertPulse = 0.5 + 0.5 * Math.sin(root._t * 1.4);
                    if (root._anyRunning)
                        root._ringPulse = 0.5 + 0.5 * Math.sin(root._t * 0.7);
                    if (root._anyDone)
                        root._donePulse = 0.5 + 0.5 * Math.sin(root._t * 4.2);
                }
            }
        }
        onRunningChanged: if (!running) { root._recompute(); }
    }
    property real _accSim: 0

    // Transición del foco-Laura: repinta la capa fina mientras `lauraFocus`
    // anima (el shader del fondo dima solo, atado a `lauraFocus` por binding).
    onLauraFocusChanged: if (Math.abs(lauraFocus - _pf) > 0.015) { _pf = lauraFocus; }

    // Al cambiar datos (aparece un agente, cambia la batería) o tamaño/paleta:
    // recalcular posiciones de los cuerpos.
    Timer {
        id: settle
        interval: 300
        onTriggered: { root._recompute(); }
    }
    onValuesChanged: settle.restart()
    onConfigChanged: settle.restart()
    onWidthChanged: { _recompute(); }
    onHeightChanged: { _recompute(); }
    onColPrimaryChanged: { _recompute(); texDevice.requestPaint(); }
    onColLauraChanged: { texAgent.requestPaint(); }
    onColErrorChanged: { } // el aro de alerta reacciona automático
    onColBeltChanged: { } // el shader reacciona automático

    Component.onCompleted: { texDevice.requestPaint(); texAgent.requestPaint(); _recompute(); }
}
