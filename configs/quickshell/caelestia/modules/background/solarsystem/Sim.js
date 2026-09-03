// Sim.js — motor puro del sistema solar. Sin dependencias de Quickshell ni Qt.
//
// La DISPOSICIÓN es dato, no código: el `config` define qué anclas (soles,
// agujeros negros, centros de gravedad) hay y qué cuerpos orbitan cuál. Así se
// puede reorganizar "como queramos" — binario música+Laura, un sol de
// configuración con los LEDs alrededor, la música como agujero negro lejano —
// sin tocar esto. Ver docs/sistema-solar-binario.md.
//
//   state = {
//     t:       segundos monótonos,
//     values:  { <signal>: number|bool }   // lo que producen los adaptadores
//     config:  { anchors:[...], bodies:[...] }
//   }
//   geom = { w, h, cx, cy }
//
//   anchor = {
//     id, label,
//     motion: { kind: "barycenter" }                              // el punto del usuario
//           | { kind: "orbit", around, orbit, ecc, phase, speed } // gira alrededor de `around`
//           | { kind: "fixed", fx, fy },                          // fx,fy en fracción 0..1 del lienzo
//     sizeSignal, glowSignal,   // nombres de señal 0..1 (opcional)
//     baseSize, baseGlow,       // px de diseño
//     dimSignal                 // señal bool: si es false, el ancla se atenúa
//   }
//   body = {
//     id, kind, anchor,               // a qué ancla orbita
//     orbit, ecc, phase, speed,
//     activitySignal, alertSignal, sizeSignal,
//     baseSize, ring
//   }
.pragma library

var DESIGN_H = 340;   // media-altura de diseño; el `scale` la lleva a px reales

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
function onEllipse(ox, oy, rx, ry, a) {
    return { x: ox + Math.cos(a) * rx, y: oy + Math.sin(a) * ry };
}

// Resuelve la posición de un ancla. `resolved` acumula las ya calculadas para
// permitir que un ancla orbite a otra (un nivel de anidamiento basta para v1;
// si `around` aún no está resuelto se cae al baricentro).
function resolveAnchor(a, t, S, geom, resolved) {
    var m = a.motion || { kind: "barycenter" };
    if (m.kind === "fixed") {
        return { x: (m.fx != null ? m.fx : 0.5) * geom.w, y: (m.fy != null ? m.fy : 0.5) * geom.h };
    }
    if (m.kind === "orbit") {
        var base = resolved[m.around] || { x: geom.cx, y: geom.cy };
        var rx = (m.orbit || 40) * S;
        var ry = rx * (1 - clamp01(m.ecc != null ? m.ecc : 0.5));
        var ang = (m.phase || 0) + t * (m.speed || 0.2);
        return onEllipse(base.x, base.y, rx, ry, ang);
    }
    return { x: geom.cx, y: geom.cy }; // barycenter
}

function computeLayout(state, geom) {
    var t = state.t || 0;
    var values = state.values || {};
    var cfg = state.config || { anchors: [], bodies: [] };
    var S = geom.scale || (Math.min(geom.w, geom.h * 1.5) / (DESIGN_H * 2));
    var pulse = 0.5 + 0.5 * Math.sin(t * 3);

    // --- Anclas ---
    var resolved = {};
    var anchorsOut = [];
    var anchors = cfg.anchors || [];
    // Dos pasadas: primero las que no dependen de otras anclas, luego el resto.
    for (var pass = 0; pass < 2; pass++) {
        for (var i = 0; i < anchors.length; i++) {
            var a = anchors[i];
            if (resolved[a.id]) continue;
            var m = a.motion || { kind: "barycenter" };
            var dependsOnAnchor = m.kind === "orbit" && m.around && m.around !== "barycenter";
            if (pass === 0 && dependsOnAnchor) continue;

            var pos = resolveAnchor(a, t, S, geom, resolved);
            resolved[a.id] = pos;

            var lit = bool(values, a.dimSignal, true);
            var dim = lit ? 0 : 0.5;   // en reposo se atenúa, pero no desaparece
            var sizeF = a.sizeSignal ? clamp01(num(values, a.sizeSignal, 0)) : 1;
            var glowF = a.glowSignal ? clamp01(num(values, a.glowSignal, 0)) : 0;

            anchorsOut.push({
                id: a.id,
                label: a.label || a.id,
                kind: a.kind || "sun",
                x: pos.x, y: pos.y,
                r: (a.baseSize || 14) * S * (0.7 + 0.5 * sizeF) + (lit ? pulse * 2 * S : 0),
                glow: ((a.baseGlow || 22) + glowF * 22) * S,
                dim: dim,
                pulse: pulse
            });
        }
    }

    // --- Cuerpos ---
    var bodiesOut = [];
    var bodies = cfg.bodies || [];
    var lauraActive = bool(values, "lauraActive", false);
    for (var b = 0; b < bodies.length; b++) {
        var body = bodies[b];
        var host = resolved[body.anchor] || { x: geom.cx, y: geom.cy };

        // El séquito de un ancla apagada gira más lento (calmo por defecto).
        var hostLit = true;
        for (var k = 0; k < anchors.length; k++)
            if (anchors[k].id === body.anchor)
                hostLit = bool(values, anchors[k].dimSignal, true);
        var speedMul = hostLit ? 1.0 : 0.33;

        var rx = (body.orbit || 40) * S;
        var ry = rx * (1 - clamp01(body.ecc != null ? body.ecc : 0.5));
        var ang = (body.phase || 0) + t * (body.speed || 0.6) * speedMul;
        var p = onEllipse(host.x, host.y, rx, ry, ang);

        var act = body.activitySignal ? clamp01(num(values, body.activitySignal, 0))
                                      : 1;
        var alert = clamp01(num(values, body.alertSignal, 0));
        var sizeF = body.sizeSignal ? clamp01(num(values, body.sizeSignal, 1)) : 1;

        bodiesOut.push({
            id: body.id,
            kind: body.kind || "planet",
            anchor: body.anchor,
            x: p.x, y: p.y,
            r: (body.baseSize || 4) * S * (0.55 + 0.45 * act) * (0.6 + 0.4 * sizeF),
            activity: act,
            alert: alert,
            ring: !!body.ring && act > 0.35,
            pulse: pulse
        });
    }

    return {
        t: t,
        scale: S,
        barycenter: { x: geom.cx, y: geom.cy },
        anchors: anchorsOut,
        bodies: bodiesOut
    };
}
