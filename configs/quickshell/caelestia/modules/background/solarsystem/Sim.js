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

var _lastT = 0;
var _bodyPhases = {};
var _init = false;
var _cometPhase = 0;
var _cometInit = false;

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
//
// CÓMO CAMBIAR DE DISPOSICIÓN: edita `D.layoutVariant` abajo (1 | 2 | 3) y
// reinicia el shell (restart limpio, nunca hot-reload). Las tres:
//   1 — CONSERVADORA.  Mismo baricentro (0.30, 0.46). Soles ~+40 % más separados,
//       órbitas de satélites ~+25 %, cinturón algo más ancho, trazas visibles.
//   2 — APROVECHAR EL HUECO.  Baricentro desplazado abajo-izquierda (0.25, 0.51)
//       al espacio vacío. Soles ~+70 %. El binario equilibra al agujero negro.
//   3 — DIAGONAL COMPLETA.  Binario empujado a la esquina inferior izquierda
//       (0.16, 0.52) y su órbita mutua inclinada hacia la diagonal del agujero.
//
// REGLA DE MOVIMIENTO: al separar más los soles, los PERÍODOS crecen en la misma
// proporción (`binPeriod ∝ binK`, `satPeriodMul == orbitMul`) para que la
// velocidad angular aparente en px/s NO suba. Restricción dura: nada del sistema
// puede invadir la franja inferior de ~200 px (overlay de voz de Laura) → hay un
// recorte del semieje vertical de cada satélite en computeLayout().
var LAYOUTS = {
    1: {
        baryFx: 0.30, baryFy: 0.46,
        binK: 5.0, binPeriod: 306, binTilt: -0.15,
        orbitMul: 1.25, beltRxFrac: 0.165, orbitAlpha: 0.14
    },
    2: {
        baryFx: 0.25, baryFy: 0.51,
        binK: 6.1, binPeriod: 373, binTilt: -0.15,
        orbitMul: 1.35, beltRxFrac: 0.185, orbitAlpha: 0.15
    },
    3: {
        baryFx: 0.17, baryFy: 0.53,
        binK: 6.5, binPeriod: 397, binTilt: -0.42,
        orbitMul: 1.40, beltRxFrac: 0.205, orbitAlpha: 0.16
    },
    // 4 — BINARIO AMPLIO, abajo-izquierda (oct-2026). Con más planetas todo se
    //     veía junto: baricentro bajado y a la izquierda (lejos del reloj y de la
    //     cola del agujero negro), soles más separados, órbitas de satélites
    //     ~+20 % sobre la 1. Períodos ∝ separación (misma velocidad aparente).
    4: {
        baryFx: 0.37, baryFy: 0.60,
        binK: 8.5, binPeriod: 520, binTilt: -0.15,
        orbitMul: 1.7, beltRxFrac: 0.20, orbitAlpha: 0.15
    }
};

var D = {
    // >>> INTERRUPTOR DE DISPOSICIÓN <<<  (1 conservadora · 2 hueco · 3 diagonal)
    layoutVariant: 4,

    // Cuerpos sintéticos para medir rendimiento (0 = ninguno). Deja 0 en commits.
    testBodies: 0,

    // Agujero negro: asomando más hacia el interior de la pantalla para que el
    // horizonte de sucesos (la parte negra pura) sea visible y aloje la UI de música.
    // bhRFrac: la sombra real (b_crit=2.6R) ocupa mucho más pantalla que la
    // aproximación anterior (~1.03R) a igual R. OJO: esto es solo el default
    // si no hay ancla "blackhole" en config — el valor que MANDA de verdad
    // hoy es el rFrac del anchor "blackhole" en
    // services/SolarSystemModel.qml (pickAnchor lo encuentra y pisa esto).
    bhFx: 0.86, bhFy: 0.09, bhRFrac: 0.26,        // R en fracción de h
    // Baricentro del binario: ANCLADO (no traslada). El sitio concreto lo pone
    // la variante (LAYOUTS); estos son sólo el defecto si la variante no existe.
    baryFx: 0.30, baryFy: 0.47,
    lauraRFrac: 0.045, confRFrac: 0.035,           // radios de los soles (fracción de h)
    // Períodos LARGOS a propósito. El sistema anima siempre pero a ~2 fps, así que
    // cada frame debe mover un cuerpo un pelín: nada por debajo de ~180 s de
    // período orbital (a 2 fps son ~1°/frame). Es un sistema informativo, no un
    // salvapantallas — la atención se gana con brillo, no con velocidad.
    binPeriod: 220,                               // s — los dos soles, uno alrededor del otro
    binSepFrac: 0.052,                             // separación baricentrica base
    binMassRatio: 0.62,                            // Config/Laura → Laura más cerca del baricentro
    binK: 3.6,                                     // multiplicador de separación visible
    binEcc: 0.45, binTilt: -0.15,                  // eje mayor casi horizontal; vaivén vertical acotado
    beltPeriodFrac: 1400,                          // s — cinturón de tareas (casi imperceptible)
    bhSpinPeriod: 150,                             // s — giro del disco (Doppler/beaming)
    orbitMul: 1.0, beltRxFrac: 0.14, orbitAlpha: 0.06
};

// Devuelve las constantes de composición con la variante activa ya fusionada.
function layout() {
    var v = LAYOUTS[D.layoutVariant] || {};
    var o = {};
    for (var k in D) o[k] = D[k];
    for (var j in v) o[j] = v[j];
    return o;
}

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
    var dt = t - _lastT;
    if (dt < 0 || !_init) dt = 0;
    _lastT = t;
    _init = true;

    var values = state.values || {};
    // Velocidad del tiempo POR ZONA (hover): 1 = normal, 0.25 = zona enfocada.
    // La fase se INTEGRA con esta velocidad variable → al cambiar no hay salto.
    var zs = state.zoneSpeed || {};
    var zBody = zs.body || {};
    var zComet = (typeof zs.comet === "number") ? zs.comet : 1;
    var cfg = state.config || { anchors: [], bodies: [] };
    var w = geom.w, h = geom.h;
    var S = h / 1080;
    var music = clamp01(num(values, "music", 0));
    var C = layout();               // constantes de composición de la variante activa
    // Techo vertical: nada del sistema por debajo de esta línea (franja de ~200 px
    // del overlay de voz de Laura). Restricción dura de la spec (D-10).
    var yFloor = h - 200;

    // Overrides opcionales desde config (fixed motion del ancla blackhole, etc.)
    var bhCfg = pickAnchor(cfg, "blackhole");
    var bhm = (bhCfg && bhCfg.motion) || {};
    var bh = {
        x: (bhm.fx != null ? bhm.fx : D.bhFx) * w,
        y: (bhm.fy != null ? bhm.fy : D.bhFy) * h,
        R: (bhCfg && bhCfg.rFrac != null ? bhCfg.rFrac : D.bhRFrac) * h
    };

    var bary = { x: C.baryFx * w, y: C.baryFy * h };

    // --- Binario: dos soles orbitando el baricentro FIJO ---
    // Período ∝ separación visible (binK): con los soles más lejos, giran más
    // despacio → la velocidad angular aparente en px/s no sube.
    var wBin = 2 * Math.PI / C.binPeriod;
    var ang = wBin * t;
    var sep = D.binSepFrac * h;
    var aLaura = sep * D.binMassRatio;
    var aConf = sep * (1 - D.binMassRatio) + sep * D.binMassRatio * 0.15;
    function binPos(a, phase) {
        var rx = a, ry = a * (1 - D.binEcc);
        var lx = Math.cos(ang + phase) * rx, ly = Math.sin(ang + phase) * ry;
        var ct = Math.cos(C.binTilt), st = Math.sin(C.binTilt);
        return { x: bary.x + lx * ct - ly * st, y: bary.y + lx * st + ly * ct };
    }
    var lauraCfg = anchorById(cfg, "laura");
    var confCfg = anchorById(cfg, "config");
    var lauraLit = bool(values, lauraCfg ? lauraCfg.dimSignal : null, true);
    var laura = binPos(aLaura * C.binK, Math.PI);
    var conf = binPos(aConf * C.binK, 0);
    laura.id = "laura"; laura.role = "primary";
    laura.r = (lauraCfg && lauraCfg.rFrac != null ? lauraCfg.rFrac : D.lauraRFrac) * h;
    laura.dim = lauraLit ? 0 : 0.35;
    conf.id = "config"; conf.role = "secondary";
    conf.r = (confCfg && confCfg.rFrac != null ? confCfg.rFrac : D.confRFrac) * h;
    conf.dim = 0;
    var suns = [conf, laura];   // Config detrás, Laura (primario) encima

    var bin = {
        bx: bary.x, by: bary.y,
        aLaura: aLaura * C.binK,
        aConf: aConf * C.binK,
        ecc: D.binEcc,
        tilt: C.binTilt,
        omega: wBin,
        rLaura: laura.r, rConf: conf.r
    };

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

        // Períodos largos (ver nota en D): en curso ~200s, completados ~360s,
        // dispositivos ~260s. A 2 fps son ~1-1.5°/frame — movimiento apenas
        // perceptible, que es lo que se quiere en un sistema informativo.
        var per = b.period || (isDevice ? 260 : (running ? 200 : 360));
        // Radio orbital en fracción del radio del host.
        var orbK = b.orbitK || (isDevice ? (2.0 + (i % 3) * 0.85)
                                         : (running ? (2.1 + (i % 3) * 0.85) : (3.4 + (i % 2) * 1.1)));
        // Órbita más ancha por variante → período proporcionalmente más largo
        // (misma velocidad angular aparente).
        var orb = host.r * orbK * C.orbitMul;
        per *= C.orbitMul;
        var phase = (b.phase != null ? b.phase : (i * 2.399));
        var speedMul = ((b.anchor === "laura" && !lauraLit) ? 0.5 : 1.0)
                     * (typeof zBody[b.id] === "number" ? zBody[b.id] : 1);
        if (_bodyPhases[b.id] === undefined) _bodyPhases[b.id] = phase;
        _bodyPhases[b.id] += (2 * Math.PI / per) * dt * speedMul;
        var oa = _bodyPhases[b.id];

        // Tamaño del cuerpo.
        // Dispositivo: tamaño según % de batería (0.13 .. 0.26 de host.r).
        // Agente: masa estelar según ventana de contexto acumulada (sizeF: 0.05 asteroide / satélite .. 1.0 gigante masivo).
        // A 95% de contexto, el cuerpo triplica con creces su radio (0.11 .. 0.41 de host.r) para visibilidad imponente.
        // Agente = PLANETA: el % de contexto se expresa con el tamaño, de 0.6× a 2×
        // del radio base (host.r·0.5). Dispositivo: según batería.
        var baseR = isDevice ? host.r * (0.26 + 0.14 * sizeF)
                             : host.r * 0.5 * (0.6 + 1.4 * sizeF);

        // Semieje vertical de la órbita, RECORTADO para no invadir la franja
        // inferior de ~200 px (la órbita se achata por abajo, no se traslada).
        var orbV = orb * 0.52;
        var room = (yFloor - baseR) - host.y;
        if (room > baseR && orbV > room)
            orbV = room;
        var by = host.y + Math.sin(oa) * orbV;
        if (by > yFloor - baseR) by = yFloor - baseR;

        // Lunas = subagentes en curso de esta sesión (b.moons). Cada una orbita su
        // planeta con fase integrada (respeta la velocidad por astro del hover).
        var moonList = [];
        var nMoons = isDevice ? 0 : Math.min(5, (b.moons | 0));
        for (var mk = 0; mk < nMoons; mk++) {
            var mkey = b.id + "#m" + mk;
            if (_bodyPhases[mkey] === undefined) _bodyPhases[mkey] = mk * 2.1;
            _bodyPhases[mkey] += (2 * Math.PI / (9 + 2.5 * mk)) * dt * speedMul;
            var mr = baseR * (1.75 + 0.45 * mk) + 5 * S;
            moonList.push({
                x: host.x + Math.cos(oa) * orb + Math.cos(_bodyPhases[mkey]) * mr,
                y: by + Math.sin(_bodyPhases[mkey]) * mr * 0.6,
                r: Math.max(2.8 * S, baseR * 0.24),
                orbR: mr
            });
        }

        bodies.push({
            moonList: moonList,
            id: b.id,
            // Nombre legible y proveedor de IA: pasan tal cual desde `config`
            // (los pone SolarSystemModel). Sólo se copian; Sim.js no los inventa.
            name: b.name,
            provider: b.provider,
            ws: b.ws,
            startTime: b.startTime,
            // Un dispositivo NO está «terminado»: status "device" (si no, hereda
            // el halo y el parpadeo de «¡hecho!» de los agentes).
            status: b.status || (isDevice ? "device" : (running ? "running" : "done")),
            kind: isDevice ? "device" : "agent",
            contextRatio: isDevice ? undefined : sizeF,
            hostx: host.x, hosty: host.y,
            x: host.x + Math.cos(oa) * orb,
            y: by,
            r: baseR,
            running: running,
            alert: alert,
            batt: act,
            battKnown: b.battKnown !== false,
            charging: isDevice && bool(values, b.chargingSignal, false),
            // Geometría de la órbita para la traza + la estela de cometa (la
            // dibuja la capa fina en Canvas). orbX/orbV = semiejes; oa = ángulo
            // actual; el cuerpo avanza en +oa.
            orbX: orb, orbV: orbV, oa: oa
        });
    }

    // --- Cuerpos sintéticos de prueba (D.testBodies > 0) para medir CPU ---
    for (var ti = 0; ti < (D.testBodies | 0); ti++) {
        var thost = (ti % 2 === 0) ? laura : conf;
        var tOrb = thost.r * (2.0 + (ti % 5) * 0.6) * C.orbitMul;
        var tPer = (150 + ti * 3) * C.orbitMul;
        var tOa = ti + (2 * Math.PI / tPer) * t;
        var tR = thost.r * 0.11;
        var tOrbV = Math.min(tOrb * 0.52, Math.max(tR, (yFloor - tR) - thost.y));
        bodies.push({
            id: "test-" + ti, kind: (ti % 2 === 0) ? "agent" : "device",
            hostx: thost.x, hosty: thost.y,
            x: thost.x + Math.cos(tOa) * tOrb,
            y: Math.min(thost.y + Math.sin(tOa) * tOrbV, yFloor - tR),
            r: tR, running: false, alert: 0, batt: 1
        });
    }

    // --- Lógica anti-colisión vertical para etiquetas ---
    // Inicializar ly (label Y)
    for (var i = 0; i < bodies.length; i++) {
        bodies[i].ly = bodies[i].y;
    }
    // Índices ordenados por y para no alterar el array original (importante para Repeater)
    var idxs = [];
    for (var i = 0; i < bodies.length; i++) idxs.push(i);
    
    for (var iter = 0; iter < 4; iter++) {
        idxs.sort(function(i, j) { return bodies[i].ly - bodies[j].ly; });
        var moved = false;
        for (var k = 0; k < idxs.length - 1; k++) {
            var a = bodies[idxs[k]], b = bodies[idxs[k+1]];
            // Si están en el mismo lado de la pantalla (x similar)
            if ((a.x < w/2) === (b.x < w/2)) {
                var diff = Math.abs(a.ly - b.ly);
                if (diff < 32) { // 32 px es una buena separación vertical para las etiquetas
                    a.ly -= (32 - diff) / 2;
                    b.ly += (32 - diff) / 2;
                    moved = true;
                }
            }
        }
        if (!moved) break;
    }

    // --- Cinturón circumbinario: ELIMINADO (sustituido por el cometa de tareas) ---
    // Se conserva el objeto con density 0 para que el shader lo salte (early-out).
    var beltRxFrac = C.beltRxFrac;
    var belt = {
        cx: bary.x, cy: bary.y,
        rx: beltRxFrac * w, ry: beltRxFrac * w * 0.42,
        tilt: C.binTilt + 0.1, n: 0, spin: 0, density: 0
    };

    // --- Cometa de tareas ---
    // Un único cometa en una elipse amplia y lenta (~7 min/vuelta) alrededor del
    // binario. La cola apunta contra el avance y crece con las tareas pendientes.
    // Sin tareas, sin cometa. La fase se integra (velocidad variable por hover).
    var nTasks = Math.max(0, Math.floor(num(values, "taskCount", 0)));
    var comet = null;
    if (!_cometInit) { _cometPhase = 1.1; _cometInit = true; }
    _cometPhase += (2 * Math.PI / 420) * dt * zComet;
    if (nTasks > 0) {
        var ccx = bary.x + 0.06 * w, ccy = bary.y - 0.04 * h;
        var crx = 0.27 * w;
        var cry = Math.min(0.27 * h, (yFloor - 24 * S) - ccy);
        var ctilt = -0.10;
        var cth = _cometPhase;
        var clx = Math.cos(cth) * crx, cly = Math.sin(cth) * cry;
        var cct = Math.cos(ctilt), cst = Math.sin(ctilt);
        var vx = -Math.sin(cth) * crx, vy = Math.cos(cth) * cry;   // dirección de avance
        var vxr = vx * cct - vy * cst, vyr = vx * cst + vy * cct;
        var vl = Math.sqrt(vxr * vxr + vyr * vyr) || 1;
        comet = {
            x: ccx + clx * cct - cly * cst,
            y: ccy + clx * cst + cly * cct,
            tx: -vxr / vl, ty: -vyr / vl,                           // cola: contra el avance
            len: (46 + 14 * Math.min(nTasks, 18)) * S,
            r: 4.5 * S, n: nTasks,
            cx: ccx, cy: ccy, rx: crx, ry: cry, tilt: ctilt
        };
    }

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
    var binExc = sep * C.binK;
    var maxSatOrbit = 20 * 6 * 1.2 * C.orbitMul * S; // margen holgado para satélites
    var binHalfX = Math.max(belt.rx, binExc + maxSatOrbit + laura.r) + pad;
    var binHalfY = Math.max(belt.ry, binExc + maxSatOrbit + laura.r) + pad;
    var binBounds = clampBox(bary.x - binHalfX, bary.y - binHalfY,
                             bary.x + binHalfX, bary.y + binHalfY, 0);
    // Unión (para la región de input de la tanda de interacción, D-7).
    var bounds = clampBox(
        Math.min(bhBounds.x, binBounds.x), Math.min(bhBounds.y, binBounds.y),
        Math.max(bhBounds.x + bhBounds.w, binBounds.x + binBounds.w),
        Math.max(bhBounds.y + bhBounds.h, binBounds.y + binBounds.h), 0);

    return {
        t: t, scale: S, music: music,
        musicBass: num(values, "musicBass", 0),
        musicTreble: num(values, "musicTreble", 0),
        musicPulse: num(values, "musicPulse", 0),
        musicBurstAge: num(values, "musicBurstAge", 999),
        musicProgress: clamp01(num(values, "musicProgress", 0)),
        variant: D.layoutVariant, orbitAlpha: C.orbitAlpha,
        bh: bh, bary: bary, bhSpin: (2 * Math.PI / D.bhSpinPeriod) * t,
        suns: suns, bodies: bodies, belt: belt, bin: bin, comet: comet,
        bhBounds: bhBounds, binBounds: binBounds, bounds: bounds
    };
}
