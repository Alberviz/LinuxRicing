// Sim.js — motor puro del sistema solar v3. Sin dependencias de Quickshell ni Qt.
//
// v3 (variante D, spec docs/sistema-solar-v3-DISENO.md): escritorio a pantalla
// completa sobre fondo negro. Un AGUJERO NEGRO masivo «música» clavado en la
// esquina superior derecha, saliéndose de cuadro, con el disco de acreción en
// diagonal. Un BINARIO «Laura ↔ Configuración» ANCLADO (baricentro fijo en
// pantalla) centro-izquierda: los dos soles se orbitan entre sí despacio pero el
// baricentro no se traslada. Los AGENTES orbitan Laura; los DISPOSITIVOS
// conectados orbitan Configuración; un CINTURÓN de tareas circumbinario rodea el
// par.
//
//   state = {
//     t:       segundos monótonos,
//     values:  { <signal>: number|bool }   // lo que producen los adaptadores
//     config:  { anchors:[...], bodies:[...] }
//   }
//   geom = { w, h }
//
// Todo son fracciones de la caja; `S` (= h/1080) sólo escala grosores de trazo.
// La DISPOSICIÓN sigue siendo dato: `config` dice QUÉ cuerpos hay y a qué ancla
// orbitan; Sim.js codifica las reglas de composición de la variante D. Alberto
// puede afinar posiciones/tamaños por ~/.config/caelestia/solarsystem.json.
.pragma library

function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
function num(values, name, dflt) {
    if (!name) return dflt;
    var v = values ? values[name] : undefined;
    if (v === true) return 1;
    if (v === false) return 0;
    return (typeof v === "number" && isFinite(v)) ? v : dflt;
}
function bool(values, name, dflt) {
    if (!name) return dflt;
    var v = values ? values[name] : undefined;
    return v === undefined ? dflt : !!v;
}

// --- Constantes de composición de la variante D (fracciones de la caja) ---
var D = {
    // Agujero negro: centro fuera de cuadro por la esquina superior derecha.
    bhFx: 1.02, bhFy: -0.04, bhRFrac: 0.24,        // R en fracción de h
    // Baricentro del binario: ANCLADO. y a 0.47h (no 0.50) para respetar la
    // franja inferior ~200px del overlay de voz de Laura con el binario abajo.
    baryFx: 0.30, baryFy: 0.47,
    lauraRFrac: 0.045, confRFrac: 0.035,           // radios de los soles (fracción de h)
    binPeriod: 105,                                // s de pantalla — uno alrededor del otro
    binSepFrac: 0.052,                             // separación baricentrica base
    binMassRatio: 0.62,                            // Config/Laura → Laura más cerca del baricentro
    binK: 3.6,                                     // multiplicador de separación visible
    binEcc: 0.45, binTilt: -0.15,                  // eje mayor casi horizontal; vaivén vertical acotado
    beltPeriodFrac: 600                            // s — cinturón de tareas
};

function pickAnchor(cfg, kind) {
    var a = cfg.anchors || [];
    for (var i = 0; i < a.length; i++)
        if ((a[i].kind || "sun") === kind) return a[i];
    return null;
}
function anchorById(cfg, id) {
    var a = cfg.anchors || [];
    for (var i = 0; i < a.length; i++)
        if (a[i].id === id) return a[i];
    return null;
}
function bodyCfg(cfg, id) {
    var b = cfg.bodies || [];
    for (var i = 0; i < b.length; i++)
        if (b[i].id === id) return b[i];
    return null;
}

function computeLayout(state, geom) {
    var t = state.t || 0;
    var values = state.values || {};
    var cfg = state.config || { anchors: [], bodies: [] };
    var w = geom.w, h = geom.h;
    var S = h / 1080;
    var music = clamp01(num(values, "music", 0));

    // Overrides opcionales desde config (fixed motion del ancla blackhole, etc.)
    var bhCfg = pickAnchor(cfg, "blackhole");
    var bhm = (bhCfg && bhCfg.motion) || {};
    var bh = {
        x: (bhm.fx != null ? bhm.fx : D.bhFx) * w,
        y: (bhm.fy != null ? bhm.fy : D.bhFy) * h,
        R: (bhCfg && bhCfg.rFrac != null ? bhCfg.rFrac : D.bhRFrac) * h
    };

    var bary = { x: D.baryFx * w, y: D.baryFy * h };

    // --- Binario: dos soles orbitando el baricentro FIJO ---
    var wBin = 2 * Math.PI / D.binPeriod;
    var ang = wBin * t;
    var sep = D.binSepFrac * h;
    var aLaura = sep * D.binMassRatio;
    var aConf = sep * (1 - D.binMassRatio) + sep * D.binMassRatio * 0.15;
    function binPos(a, phase) {
        var rx = a, ry = a * (1 - D.binEcc);
        var lx = Math.cos(ang + phase) * rx, ly = Math.sin(ang + phase) * ry;
        var ct = Math.cos(D.binTilt), st = Math.sin(D.binTilt);
        return { x: bary.x + lx * ct - ly * st, y: bary.y + lx * st + ly * ct };
    }
    var lauraCfg = anchorById(cfg, "laura");
    var confCfg = anchorById(cfg, "config");
    var lauraLit = bool(values, lauraCfg ? lauraCfg.dimSignal : null, true);
    var laura = binPos(aLaura * D.binK, Math.PI);
    var conf = binPos(aConf * D.binK, 0);
    laura.id = "laura"; laura.role = "primary";
    laura.r = (lauraCfg && lauraCfg.rFrac != null ? lauraCfg.rFrac : D.lauraRFrac) * h;
    laura.dim = lauraLit ? 0 : 0.35;
    conf.id = "config"; conf.role = "secondary";
    conf.r = (confCfg && confCfg.rFrac != null ? confCfg.rFrac : D.confRFrac) * h;
    conf.dim = 0;
    var suns = [conf, laura];   // Config detrás, Laura (primario) encima

    // --- Cuerpos dinámicos: agentes (Laura) y dispositivos (Config) ---
    var bodies = [];
    var cfgBodies = cfg.bodies || [];
    for (var i = 0; i < cfgBodies.length; i++) {
        var b = cfgBodies[i];
        if ((b.kind || "planet") === "belt") continue;
        var host = (b.anchor === "laura") ? laura : (b.anchor === "config" ? conf : bary);
        var isDevice = (b.anchor === "config");
        var act = b.activitySignal ? clamp01(num(values, b.activitySignal, 0)) : 1;
        var alert = clamp01(num(values, b.alertSignal, 0));
        var sizeF = b.sizeSignal ? clamp01(num(values, b.sizeSignal, 1)) : 1;
        var running = !!b.ring && act > 0.35;

        // Período: agentes en curso 40-60s, completados ~120s; dispositivos 70-100s.
        var per = b.period || (isDevice ? 88 : (running ? 50 : 120));
        // Radio orbital en fracción del radio del host.
        var orbK = b.orbitK || (isDevice ? (2.0 + (i % 3) * 0.85)
                                         : (running ? (2.1 + (i % 3) * 0.85) : (3.4 + (i % 2) * 1.1)));
        var orb = host.r * orbK;
        var phase = (b.phase != null ? b.phase : (i * 2.399));
        var speedMul = (b.anchor === "laura" && !lauraLit) ? 0.5 : 1.0;
        var oa = phase + (2 * Math.PI / per) * t * speedMul;

        // Tamaño del cuerpo. Dispositivo: tamaño/brillo = batería. Agente: fijo.
        var baseR = isDevice ? host.r * (0.13 + 0.13 * sizeF)
                             : host.r * (running ? 0.16 : 0.12);

        bodies.push({
            id: b.id,
            kind: isDevice ? "device" : "agent",
            hostx: host.x, hosty: host.y,
            x: host.x + Math.cos(oa) * orb,
            y: host.y + Math.sin(oa) * orb * 0.52,
            r: baseR,
            running: running,
            alert: alert,
            batt: act
        });
    }

    // --- Cinturón circumbinario de tareas ---
    var tasks = clamp01(num(values, "tasks", 0));
    var beltCfg = null;
    for (var j = 0; j < cfgBodies.length; j++)
        if ((cfgBodies[j].kind || "") === "belt") beltCfg = cfgBodies[j];
    var belt = {
        cx: bary.x, cy: bary.y,
        rx: (beltCfg && beltCfg.rxFrac != null ? beltCfg.rxFrac : 0.14) * w,
        ry: (beltCfg && beltCfg.rxFrac != null ? beltCfg.rxFrac : 0.14) * w * 0.42,
        tilt: D.binTilt + 0.1,
        n: Math.round(28 + tasks * 72),
        spin: (2 * Math.PI / D.beltPeriodFrac) * t
    };

    // --- Cajas del contenido, estables frame a frame (salen de constantes) ---
    // Se separan la del AGUJERO NEGRO y la del BINARIO: cada una va a su propio
    // Canvas con su propio ritmo de repintado (el agujero, mucho más lento — su
    // giro tiene período ~30 s). Pintar 1920×1080 de FBO por tic es tirar fill
    // (spec §6.7); pintar el disco entero por tic siendo casi estático, también.
    function clampBox(x0, y0, x1, y1, pad) {
        var ax = Math.max(0, x0 - pad), ay = Math.max(0, y0 - pad);
        return {
            x: ax, y: ay,
            w: Math.min(w, x1 + pad) - ax,
            h: Math.min(h, y1 + pad) - ay
        };
    }
    var pad = 40 * S;
    // El disco raking hacia abajo-izquierda: eje mayor a -28°, radio exterior 4·R.
    var bhBounds = clampBox(bh.x - bh.R * 4.2, 0, w, bh.y + bh.R * 3.6, pad);
    // Caja del binario alrededor del baricentro FIJO. Radio estable = máxima
    // excursión orbital + alcance de los satélites + el cinturón. No usa
    // posiciones vivas (si no, el Canvas se redimensionaría cada frame).
    var binExc = sep * D.binK;
    var binHalfX = Math.max(belt.rx, binExc + laura.r * 5) + pad;
    var binHalfY = Math.max(belt.ry, binExc + laura.r * 5) + pad;
    var binBounds = clampBox(bary.x - binHalfX, bary.y - binHalfY,
                             bary.x + binHalfX, bary.y + binHalfY, 0);
    // Unión (para la región de input de la tanda de interacción, D-7).
    var bounds = clampBox(
        Math.min(bhBounds.x, binBounds.x), Math.min(bhBounds.y, binBounds.y),
        Math.max(bhBounds.x + bhBounds.w, binBounds.x + binBounds.w),
        Math.max(bhBounds.y + bhBounds.h, binBounds.y + binBounds.h), 0);

    return {
        t: t, scale: S, music: music,
        bh: bh, bary: bary,
        suns: suns, bodies: bodies, belt: belt,
        bhBounds: bhBounds, binBounds: binBounds, bounds: bounds
    };
}
