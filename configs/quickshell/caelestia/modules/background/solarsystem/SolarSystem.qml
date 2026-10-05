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
    // Tareas pendientes [{prio, title}] ordenadas por prioridad (cometa de tareas).
    property var taskList: []

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
    property int musicVariant: 2               // Variante de visualizador en agujero negro (0..6, 0=sin overlay)
    property int targetFps: 60                 // Límite de FPS para el fondo (evita 144 Hz innecesarios en iGPU)

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

    // --- HOVER PRECISO POR ASTRO ---
    // Solo el astro bajo el puntero (su disco + ~8 px, o su etiqueta) se enfoca:
    // ids "s:laura", "s:config", "b:<id>" (satélites), "comet" y "bh". La
    // selección se calcula SOLO cuando el puntero se mueve (HoverHandler). El
    // astro enfocado tiene un `amount` 0..1 con transición de 600 ms (el que
    // pierde el foco se desvanece aparte): de él cuelgan la velocidad de SU
    // tiempo (×1 → ×0.25), su órbita, su etiqueta con detalle y la atenuación
    // (70 %) del resto.
    property string hoverId: ""
    property string _prevId: ""
    property real _aCur: 0
    property real _aPrev: 0
    NumberAnimation { id: fadeIn; target: root; property: "_aCur"; to: 1; duration: 600; easing.type: Easing.InOutCubic }
    NumberAnimation { id: fadeOut; target: root; property: "_aPrev"; to: 0; duration: 600; easing.type: Easing.InOutCubic }
    onHoverIdChanged: {
        fadeIn.stop(); fadeOut.stop();
        _prevId = _lastId; _aPrev = _aCur;
        _lastId = hoverId;
        _aCur = 0;
        if (_prevId !== "") fadeOut.start();
        if (hoverId !== "") fadeIn.start();
    }
    property string _lastId: ""
    function amountOf(id) {
        return id === hoverId ? _aCur : (id === _prevId ? _aPrev : 0);
    }
    readonly property real hoverAny: Math.max(_aCur, _aPrev)
    readonly property real zLaura: amountOf("s:laura")
    readonly property real zConfig: amountOf("s:config")
    readonly property real zComet: amountOf("comet")
    readonly property real zBh: amountOf("bh")
    // Factor de atenuación de un elemento con amount `z`: 1 si es el enfocado,
    // hasta 0.70 si hay otro astro enfocado.
    function _dimOf(z) { return 1 - 0.30 * Math.max(0, hoverAny - z); }
    function _zoneOfBody(b) { return b ? amountOf("b:" + b.id) : 0; }
    // Giro del disco del agujero negro, INTEGRADO (velocidad variable por hover).
    property real bhPhase: 0

    // ¿El puntero está sobre el disco (+8 px) o la etiqueta de un astro?
    function _hitAstro(p, x, y, r, ly, name, S) {
        if (Math.hypot(p.x - x, p.y - y) < r + 8 * S) return true;
        if (!name || !name.length) return false;
        const gap = r + 26 * S, w = name.length * 10.5 * S;
        const left = x + gap + w + 8 > root.width;
        const x0 = left ? x - gap - w : x + gap;
        return p.x >= x0 - 4 && p.x <= x0 + w + 4 && Math.abs(p.y - ly) < 12 * S + 4;
    }
    function _updateZone(p) {
        const L = root._layout;
        if (!L) { hoverId = ""; return; }
        const S = L.scale;
        let found = "";
        const c = L.comet;
        if (c) {
            // Distancia al segmento cabeza→punta de la cola (cabeza y cola cuentan).
            const sx = c.tx * c.len, sy = c.ty * c.len;
            const t = Math.max(0, Math.min(1, ((p.x - c.x) * sx + (p.y - c.y) * sy) / (sx * sx + sy * sy)));
            if (Math.hypot(p.x - (c.x + sx * t), p.y - (c.y + sy * t)) < 22 * S) found = "comet";
        }
        if (found === "")
            for (let i = 0; i < L.suns.length && found === ""; i++) {
                const sun = L.suns[i];
                if (_hitAstro(p, sun.x, sun.y, sun.r, sun.y, root._labelNames[sun.id], S)) found = "s:" + sun.id;
            }
        if (found === "")
            for (let j = 0; j < L.bodies.length; j++) {
                const b = L.bodies[j];
                if (_hitAstro(p, b.x, b.y, b.r, b.ly, root._bodyName(b), S)) { found = "b:" + b.id; break; }
            }
        if (found === "" && L.bh && Math.hypot(p.x - L.bh.x, p.y - L.bh.y) < L.bh.R * 1.25)
            found = "bh";
        if (found !== hoverId) hoverId = found;
    }
    HoverHandler {
        id: zoneHover
        onPointChanged: root._updateZone(point.position)
        onHoveredChanged: if (!hovered) root.hoverId = ""
    }

    // --- Estado ---
    property real _t: 0                         // tiempo de simulación (s); se congela con focus
    property int _tick: 0
    property real _pf: 0                        // último lauraFocus pintado (para la transición)
    property var _layout: null
    readonly property var layout: _layout
    readonly property real music: _layout ? _layout.music : 0
    readonly property real musicProgress: _layout ? _layout.musicProgress : 0
    readonly property real musicPulse: _layout && _layout.musicPulse !== undefined ? _layout.musicPulse : 0
    readonly property real musicBass: _layout && _layout.musicBass !== undefined ? _layout.musicBass : 0
    readonly property real musicTreble: _layout && _layout.musicTreble !== undefined ? _layout.musicTreble : 0
    readonly property real musicBurstAge: _layout && _layout.musicBurstAge !== undefined ? _layout.musicBurstAge : 999

    // --- Interacción con Configuración (sol/planeta secundario) ---
    signal configClicked()

    readonly property var _confSun: {
        if (!_layout || !_layout.suns) return null;
        for (let i = 0; i < _layout.suns.length; i++) {
            if (_layout.suns[i].id === "config") return _layout.suns[i];
        }
        return null;
    }

    // Área interactiva alrededor del sol y etiqueta de Configuración
    readonly property real configClickX: _confSun ? (_confSun.x - _confSun.r - 16) : 0
    readonly property real configClickY: _confSun ? (_confSun.y - Math.max(_confSun.r, 24) - 16) : 0
    readonly property real configClickW: _confSun ? (_confSun.r * 2 + 32 + 230) : 0
    readonly property real configClickH: _confSun ? (Math.max(_confSun.r, 24) * 2 + 32) : 0

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
    // Subtítulo (solo en hover): SÓLO dato real.
    // Agente: ws · estado · % ctx · modelo (proveedor) · tiempo de sesión.
    // Dispositivo: batería · carga · conexión.
    function _fmtDur(ms) {
        const m = Math.floor(ms / 60000);
        if (m < 1) return "<1 min";
        if (m < 60) return m + " min";
        return Math.floor(m / 60) + " h " + (m % 60) + " min";
    }
    function _bodySubtitle(b) {
        if (!b) return "";
        if (b.kind === "device") {
            const parts = [];
            if (b.battKnown !== false && typeof b.batt === "number")
                parts.push(Math.round(b.batt * 100) + "%");
            if (b.charging) parts.push("cargando");
            parts.push("conectado");
            return parts.join(" · ");
        }
        if (b.kind === "agent") {
            const parts = [];
            if (b.ws) parts.push("ws " + b.ws);
            parts.push(b.running ? "en curso" : (b.status === "done" ? "hecho" : "sesión"));
            const pct = (typeof b.contextRatio === "number") ? Math.round(b.contextRatio * 100) : 0;
            if (pct > 0) parts.push(pct + "% ctx");
            if (b.provider) parts.push(b.provider);
            if (typeof b.startTime === "number" && b.startTime > 0)
                parts.push(_fmtDur(Date.now() - b.startTime));
            return parts.join(" · ");
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
    // Énfasis del satélite, derivado de su radio y contexto (acotado). Anclas van a 1.0.
    function _bodyEmphasis(b) {
        if (!b) return 0.35;
        if (b.kind === "device") return 0.6;
        if (b.status === "done") return 1.0;
        if (b.running) return 0.85;
        if (b.status === "session") {
            const cr = (typeof b.contextRatio === "number") ? b.contextRatio : 0;
            return 0.26 + 0.24 * cr;
        }
        const k = Math.max(0, Math.min(1, (b.r - 4) / 18));
        return 0.30 + 0.22 * k;
    }

    // Velocidad del tiempo por astro (solo el enfocado y el que acaba de soltarse).
    function _speeds() {
        const sp = { comet: 1 - 0.75 * zComet, body: {} };
        if (hoverId.indexOf("b:") === 0) sp.body[hoverId.slice(2)] = 1 - 0.75 * _aCur;
        if (_prevId.indexOf("b:") === 0) sp.body[_prevId.slice(2)] = 1 - 0.75 * _aPrev;
        return sp;
    }
    function _recompute() {
        if (width <= 0 || height <= 0)
            return;
        root._layout = Sim.computeLayout({
            t: root.simTime, values: root.values, config: root.config,
            zoneSpeed: root._speeds()
        }, root._geom());
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
    property bool _anyCharging: false
    property real _chargePulse: 0.5
    property real _alertPulse: 0.75
    property real _ringPulse: 0.5
    property real _donePulse: 0.5
    property real _accPulse: 0
    function _rescanPulseFlags() {
        let aa = false, ar = false, ad = false, ac = false;
        const L = root._layout;
        if (L)
            for (let i = 0; i < L.bodies.length; i++) {
                if (L.bodies[i].alert > 0.5) aa = true;
                if (L.bodies[i].running) ar = true;
                if (L.bodies[i].status === "done") ad = true;
                if (L.bodies[i].charging) ac = true;
            }
        root._anyAlert = aa;
        root._anyRunning = ar;
        root._anyDone = ad;
        root._anyCharging = ac;
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
        musicProgress: root.musicProgress
        musicPulse: root.musicPulse
        musicBass: root.musicBass
        musicTreble: root.musicTreble
        musicBurstAge: root.musicBurstAge
        lauraFocus: root.lauraFocus
        lauraAmp: root.lauraAmplitude
        bhPhase: root.bhPhase
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

        // Órbita COMPARTIDA del binario: las dos trayectorias de los soles (elipses
        // con foco común en el baricentro), la marca del baricentro y la cuerda
        // que une a los soles. Estático salvo la cuerda (se recoloca con _layout).
        Shape {
            id: binTrace
            anchors.fill: parent
            readonly property var bn: root._layout ? root._layout.bin : null
            readonly property real k: root._layout ? root._layout.scale : 1.0
            visible: bn !== null
            opacity: root._dimOf(Math.max(root.zLaura, root.zConfig))
            transform: Rotation {
                origin.x: binTrace.bn ? binTrace.bn.bx : 0
                origin.y: binTrace.bn ? binTrace.bn.by : 0
                angle: binTrace.bn ? binTrace.bn.tilt * 180 / Math.PI : 0
            }
            ShapePath {
                strokeColor: Qt.rgba(root.colLaura.r, root.colLaura.g, root.colLaura.b, 0.07 + 0.48 * root.zLaura)
                strokeWidth: 1.2 * binTrace.k
                fillColor: "transparent"
                PathAngleArc {
                    centerX: binTrace.bn ? binTrace.bn.bx : 0
                    centerY: binTrace.bn ? binTrace.bn.by : 0
                    radiusX: binTrace.bn ? binTrace.bn.aLaura : 0
                    radiusY: binTrace.bn ? binTrace.bn.aLaura * (1 - binTrace.bn.ecc) : 0
                    startAngle: 0; sweepAngle: 360
                }
            }
            ShapePath {
                strokeColor: Qt.rgba(root.colPrimary.r, root.colPrimary.g, root.colPrimary.b, 0.07 + 0.48 * root.zConfig)
                strokeWidth: 1.2 * binTrace.k
                fillColor: "transparent"
                PathAngleArc {
                    centerX: binTrace.bn ? binTrace.bn.bx : 0
                    centerY: binTrace.bn ? binTrace.bn.by : 0
                    radiusX: binTrace.bn ? binTrace.bn.aConf : 0
                    radiusY: binTrace.bn ? binTrace.bn.aConf * (1 - binTrace.bn.ecc) : 0
                    startAngle: 0; sweepAngle: 360
                }
            }
        }
        Repeater {
            model: root._layout ? root._layout.bodies.length : 0
            delegate: Item {
                id: orbitItem
                required property int index
                readonly property var b: root._layout ? root._layout.bodies[index] : null
                visible: b !== null && b.orbX !== undefined
                anchors.fill: parent
                readonly property real zone: root._zoneOfBody(b)
                opacity: root._dimOf(zone)

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

                // Estelas: en calma, a ~45 %; con hover en la zona, plenas.
                readonly property real trailK: 0.25 + 0.75 * zone
                readonly property real deg: b ? (b.oa * 180 / Math.PI) : 0
                readonly property real spanDeg: isRunning
                    ? (1.30 * 180 / Math.PI)
                    : (dev ? (0.80 * 180 / Math.PI)
                           : (isDone ? (0.75 * 180 / Math.PI) : (0.32 * 180 / Math.PI)))
                readonly property real scaleFactor: root._layout ? root._layout.scale : 1.0

                Shape {
                    anchors.fill: parent

                    // 0 · Resplandor de la órbita (solo con hover; GPU, sin blur)
                    ShapePath {
                        strokeColor: Qt.rgba(orbitItem.col.r, orbitItem.col.g, orbitItem.col.b, 0.12 * orbitItem.zone)
                        strokeWidth: 5 * orbitItem.scaleFactor
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

                    // 1 · Elipse orbital completa
                    ShapePath {
                        // Calma: visible pero finísima. Hover en su zona: se marca.
                        strokeColor: Qt.rgba(orbitItem.col.r, orbitItem.col.g, orbitItem.col.b,
                                             0.07 + 0.48 * orbitItem.zone)
                        strokeWidth: (0.55 + 0.65 * orbitItem.zone) * orbitItem.scaleFactor
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
                        strokeColor: Qt.rgba(orbitItem.col.r, orbitItem.col.g, orbitItem.col.b, orbitItem.headA * 0.20 * orbitItem.trailK)
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
                        strokeColor: Qt.rgba(orbitItem.col.r, orbitItem.col.g, orbitItem.col.b, orbitItem.headA * 0.50 * orbitItem.trailK)
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
                        strokeColor: Qt.rgba(orbitItem.col.r, orbitItem.col.g, orbitItem.col.b, orbitItem.headA * 0.95 * orbitItem.trailK)
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
            opacity: root._dimK * root._dimOf(root._zoneOfBody(bodyItem.b)) * (isSession ? 0.42 : (isDone ? (0.60 + 0.40 * root._donePulse) : 1.0))

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

            // Cargando (campo `charging` de mchose-battery): único movimiento
            // permitido en un dispositivo — pulso MUY suave (~7 s de ciclo).
            Loader {
                anchors.centerIn: parent
                active: bodyItem.b !== null && bodyItem.b.charging === true
                sourceComponent: Rectangle {
                    width: bodyItem.width + 10 * (root._layout ? root._layout.scale : 1.0)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: Qt.rgba(root.colPrimary.r, root.colPrimary.g, root.colPrimary.b, 0.18 + 0.32 * root._chargePulse)
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


    // ===================== COMETA DE TAREAS =====================
    // Un único cometa en órbita elíptica amplia y lenta alrededor del binario.
    // Cola contra el avance, longitud ∝ tareas pendientes. Sin tareas, no existe.
    // Todo Rectangle/Shape (GPU, scene graph): sin Canvas ni bucles propios — se
    // mueve con el `_layout` que ya recalcula el reloj existente.
    Item {
        id: cometLayer
        anchors.fill: parent
        readonly property var c: root._layout ? root._layout.comet : null
        readonly property real sc: root._layout ? root._layout.scale : 1
        readonly property color tint: root._lit(root.colInk, 0.1)
        visible: c !== null
        opacity: root._dimK * root._dimOf(root.zComet) * (0.72 + 0.28 * root.zComet)

        // Órbita (casi invisible; sube con hover).
        Shape {
            anchors.fill: parent
            transform: Rotation {
                origin.x: cometLayer.c ? cometLayer.c.cx : 0
                origin.y: cometLayer.c ? cometLayer.c.cy : 0
                angle: cometLayer.c ? cometLayer.c.tilt * 180 / Math.PI : 0
            }
            ShapePath {
                strokeColor: Qt.rgba(cometLayer.tint.r, cometLayer.tint.g, cometLayer.tint.b, 0.07 + 0.48 * root.zComet)
                strokeWidth: 1 * cometLayer.sc
                fillColor: "transparent"
                PathAngleArc {
                    centerX: cometLayer.c ? cometLayer.c.cx : 0
                    centerY: cometLayer.c ? cometLayer.c.cy : 0
                    radiusX: cometLayer.c ? cometLayer.c.rx : 0
                    radiusY: cometLayer.c ? cometLayer.c.ry : 0
                    startAngle: 0; sweepAngle: 360
                }
            }
        }

        // Cola de polvo (ancha, tenue) y cola de iones (fina, más viva).
        Rectangle {
            x: cometLayer.c ? cometLayer.c.x : 0
            y: (cometLayer.c ? cometLayer.c.y : 0) - height / 2
            width: cometLayer.c ? cometLayer.c.len : 0
            height: 9 * cometLayer.sc
            radius: height / 2
            transformOrigin: Item.Left
            rotation: cometLayer.c ? Math.atan2(cometLayer.c.ty, cometLayer.c.tx) * 180 / Math.PI : 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(root.colLaura.r, root.colLaura.g, root.colLaura.b, 0.30) }
                GradientStop { position: 1; color: Qt.rgba(root.colLaura.r, root.colLaura.g, root.colLaura.b, 0) }
            }
        }
        Rectangle {
            x: cometLayer.c ? cometLayer.c.x : 0
            y: (cometLayer.c ? cometLayer.c.y : 0) - height / 2
            width: cometLayer.c ? cometLayer.c.len * 1.2 : 0
            height: 2 * cometLayer.sc
            transformOrigin: Item.Left
            rotation: cometLayer.c ? Math.atan2(cometLayer.c.ty, cometLayer.c.tx) * 180 / Math.PI : 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(root.colPrimary.r, root.colPrimary.g, root.colPrimary.b, 0.70) }
                GradientStop { position: 1; color: Qt.rgba(root.colPrimary.r, root.colPrimary.g, root.colPrimary.b, 0) }
            }
        }
        // Cabeza: halo + núcleo.
        Rectangle {
            x: (cometLayer.c ? cometLayer.c.x : 0) - width / 2
            y: (cometLayer.c ? cometLayer.c.y : 0) - height / 2
            width: (cometLayer.c ? cometLayer.c.r : 0) * 4
            height: width; radius: width / 2
            color: Qt.rgba(cometLayer.tint.r, cometLayer.tint.g, cometLayer.tint.b, 0.10)
        }
        Rectangle {
            x: (cometLayer.c ? cometLayer.c.x : 0) - width / 2
            y: (cometLayer.c ? cometLayer.c.y : 0) - height / 2
            width: (cometLayer.c ? cometLayer.c.r : 0) * 1.6
            height: width; radius: width / 2
            color: cometLayer.tint
        }

        // Las 3 próximas tareas, solo al enfocar el cometa (con velo oscuro para
        // leerse sobre órbitas y etiquetas).
        Rectangle {
            visible: cometTasks.visible
            opacity: root.zComet
            x: cometTasks.x - 12
            y: cometTasks.y - 9
            width: cometTasks.width + 24
            height: cometTasks.height + 18
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.62)
        }
        Column {
            id: cometTasks
            visible: root.zComet > 0.01 && cometLayer.c !== null
            opacity: root.zComet
            spacing: 4
            // Debajo de la cabeza (o encima si la cola apunta hacia abajo), sin pisar la cola.
            readonly property bool onLeft: false
            x: cometLayer.c ? Math.max(8, Math.min(root.width - 340, cometLayer.c.x - 8)) : 0
            y: cometLayer.c
                ? Math.max(8, Math.min(root.height - height - 8,
                    cometLayer.c.ty > 0.2 ? cometLayer.c.y - 22 * cometLayer.sc - height
                                          : cometLayer.c.y + 22 * cometLayer.sc))
                : 0
            Text {
                text: cometLayer.c ? (cometLayer.c.n + (cometLayer.c.n === 1 ? " TAREA PENDIENTE" : " TAREAS PENDIENTES")) : ""
                color: cometLayer.tint
                opacity: 0.7
                font.family: root.labelFont
                font.pixelSize: 11
                font.letterSpacing: 2
                horizontalAlignment: cometTasks.onLeft ? Text.AlignRight : Text.AlignLeft
                width: Math.max(implicitWidth, 240)
            }
            Repeater {
                model: Math.min(3, root.taskList.length)
                delegate: Text {
                    required property int index
                    text: (index + 1) + "  " + (root.taskList[index] ? root.taskList[index].title : "")
                    color: cometLayer.tint
                    opacity: 0.9 - 0.15 * index
                    font.family: root.labelFont
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: 340
                    horizontalAlignment: cometTasks.onLeft ? Text.AlignRight : Text.AlignLeft
                }
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
                readonly property bool isConfig: sunWrap.s !== null && sunWrap.s.id === "config"
                property bool hovered: false

                anchors.fill: parent
                readonly property real zone: sunWrap.s ? root.amountOf("s:" + sunWrap.s.id) : 0
                opacity: ((root.lauraActive && sunWrap.s && sunWrap.s.id === "laura")
                    ? 1 : root._dimK) * root._dimOf(zone)
                Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                // Anillo sutil de hover interactivo para el planeta/sol de Configuración
                Rectangle {
                    visible: sunWrap.isConfig
                    x: (sunWrap.s ? sunWrap.s.x : 0) - width / 2
                    y: (sunWrap.s ? sunWrap.s.y : 0) - height / 2
                    width: (sunWrap.s ? sunWrap.s.r * 2 : 0) + 16
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: root.colPrimary
                    border.width: 1.5
                    opacity: sunWrap.hovered ? 0.8 : 0.0

                    Behavior on opacity {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }

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
                    // Calma: una línea tenue. En hover de su zona, algo más marcada.
                    emphasis: (sunWrap.isConfig && sunWrap.hovered) ? 1.0 : (0.18 + 0.40 * sunWrap.zone)
                    col: sunWrap.s
                        ? (sunWrap.s.id === "laura" ? root.colLaura : root.colPrimary)
                        : root.colInk
                }

                MouseArea {
                    id: configMouseArea
                    visible: sunWrap.isConfig
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    x: root.configClickX
                    y: root.configClickY
                    width: root.configClickW
                    height: root.configClickH
                    onEntered: sunWrap.hovered = true
                    onExited: sunWrap.hovered = false
                    onClicked: root.configClicked()
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
            opacity: root._dimK * root._dimOf(root.zBh)

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
                // Todos los astros llevan etiqueta (tenue); con hover en su zona se marca y
                // muestra el detalle (subtítulo).
                readonly property real zone: root._zoneOfBody(satWrap.b)
                opacity: root._dimK * root._dimOf(zone)
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
                    subtitle: satWrap.zone > 0.01 ? root._bodySubtitle(satWrap.b) : ""
                    detailAmount: satWrap.zone
                    emphasis: Math.min(1, 0.16 + 0.12 * root._bodyEmphasis(satWrap.b) + 0.45 * satWrap.zone)
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
    // Ritmo ADAPTATIVO (CPU en reposo): el movimiento orbital es lentísimo, así que
    // en reposo bastan ~6 fps. Hover/transición de zona o de foco-Laura: `targetFps`;
    // música sonando (cava va a 25 Hz) o agente «terminado» parpadeando: 30. Timer (no FrameAnimation): no despierta a
    // cada vsync y el intervalo es regulable.
    readonly property bool _hovering: hoverId !== "" || hoverAny > 0.001
        || Math.abs(lauraFocus - (lauraActive ? 1 : 0)) > 0.001
    readonly property real _fps: _hovering ? (targetFps > 0 ? targetFps : 60)
        : (fastRate ? Math.min(30, targetFps > 0 ? targetFps : 30) : (_anyDone ? 30 : 6))
    Timer {
        id: clock
        repeat: true
        interval: Math.round(1000 / root._fps)
        running: root.visible && !root.paused && !root.reduceMotion
        property double last: 0
        onTriggered: {
            const now = Date.now();
            let dt = last > 0 ? (now - last) / 1000 : interval / 1000;
            last = now;
            if (dt > 0.5) dt = 0.5;

            root._t += dt;
            if (root.lauraActive)
                return;                          // sistema congelado: nada que recalcular
            root.bhPhase += dt * (2 * Math.PI / 150) * (1 - 0.75 * root.zBh);
            root._recompute();
            // Pulsos de UI: sólo si hay algún cuerpo que los use.
            if (root._anyAlert || root._anyRunning || root._anyDone || root._anyCharging) {
                if (root._anyAlert)
                    root._alertPulse = 0.5 + 0.5 * Math.sin(root._t * 1.4);
                if (root._anyRunning)
                    root._ringPulse = 0.5 + 0.5 * Math.sin(root._t * 0.7);
                if (root._anyCharging)
                    root._chargePulse = 0.5 + 0.5 * Math.sin(root._t * 0.9);
                if (root._anyDone)
                    root._donePulse = 0.5 + 0.5 * Math.sin(root._t * 4.2);
            }
        }
        onRunningChanged: { last = 0; if (!running) root._recompute(); }
    }

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
