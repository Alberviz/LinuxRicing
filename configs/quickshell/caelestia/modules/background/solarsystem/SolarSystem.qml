pragma ComponentBehavior: Bound

// SolarSystem.qml — la VISTA de la v3 (variante D). Dos Canvas:
//
//  · staticCanvas  — se pinta UNA vez (y sólo al cambiar tamaño o paleta):
//    fondo negro, campo de estrellas, estrellas lensadas en arcos y el
//    resplandor exterior del agujero negro. Son capas estáticas (spec §6.6).
//  · dynCanvas     — se repinta cada tic (Timer gateado, 2-4 fps en reposo):
//    disco de acreción, horizonte, anillo de fotones, jet, los dos soles con
//    granulación y prominencias, los satélites y el cinturón. Dimensionado a la
//    caja del contenido, no a 1920×1080 (spec §6.7).
//
// Ningún color fijo: la paleta entra como propiedad y se ata a Colours.palette
// (extraída del wallpaper). Los blancos calientes se derivan aclarando el rol.
// El motor puro (Sim.js) calcula posiciones. Ver docs/sistema-solar-v3-DISENO.md.

import QtQuick
import "Sim.js" as Sim

Item {
    id: root

    // --- Entradas ---
    property var config: ({ anchors: [], bodies: [] })
    property var values: ({})

    // Paleta (roles de Colours.palette.m3*). El motor nunca ve un hex.
    property color colPrimary: "#f7b999"       // disco del agujero, sol Configuración
    property color colLaura: "#f8e19c"         // sol Laura (m3tertiary — decidido D-3)
    property color colError: "#f97758"         // alerta de batería < 20 %
    property color colBelt: "#54453d"          // cinturón de tareas
    property color colInk: "#f8e1d6"           // estrellas
    property color colVoid: "#050302"          // horizonte de sucesos (darker(m3surface, 3))

    property bool paused: false
    property bool reduceMotion: false
    property bool active: false                // ¿hay algo que animar? (música / agente en curso)
    property bool fastRate: false              // ~30 fps sólo con música

    // Bounding box del contenido dinámico (para la tanda de interacción, D-7).
    readonly property rect contentBounds: _layout
        ? Qt.rect(_layout.bounds.x, _layout.bounds.y, _layout.bounds.w, _layout.bounds.h)
        : Qt.rect(0, 0, width, height)

    property var _layout: null
    property real _t: 0

    // ---- helpers de color (todo deriva de la paleta inyectada) ----
    function _a(c, a) { return Qt.rgba(c.r, c.g, c.b, Math.max(0, Math.min(1, a))); }
    function _lit(c, k) { return Qt.rgba(c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, 1); }
    function _dk(c, k) { return Qt.rgba(c.r * (1 - k), c.g * (1 - k), c.b * (1 - k), 1); }
    function _mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1); }
    readonly property color _hot: _lit(colPrimary, 0.86)

    // ---- campo de estrellas determinista (se regenera sólo al cambiar tamaño) ----
    property var _stars: []
    function _seedStars() {
        const out = [];
        let s = 1337;
        const rnd = () => { s = (s * 1664525 + 1013904223) & 0x7fffffff; return s / 0x7fffffff; };
        const n = Math.round(220 * Math.max(0.5, (width * height) / (1920 * 1080)));
        for (let i = 0; i < n; i++) out.push({ x: rnd(), y: rnd(), b: rnd() });
        root._stars = out;
    }

    function _geom() { return { w: width, h: height }; }

    function _recompute() {
        if (width <= 0 || height <= 0)
            return;
        root._layout = Sim.computeLayout({ t: root._t, values: root.values, config: root.config }, root._geom());
        dynCanvas.requestPaint();
    }

    // ===================== CANVAS ESTÁTICO =====================
    Canvas {
        id: staticCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        antialiasing: true

        function _repaintStatic() { requestPaint() }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height;
            const L = root._layout;
            // fondo negro puro
            ctx.fillStyle = "#000000";
            ctx.fillRect(0, 0, w, h);
            if (!L) return;
            const bh = L.bh;

            // tinte tenue del disco cerca del agujero
            const tg = ctx.createRadialGradient(bh.x, bh.y, bh.R * 0.5, bh.x, bh.y, Math.max(w, h) * 0.9);
            tg.addColorStop(0, root._a(root._dk(root.colPrimary, 0.55), 0.16));
            tg.addColorStop(0.4, root._a(root._dk(root.colPrimary, 0.8), 0.05));
            tg.addColorStop(1, "transparent");
            ctx.fillStyle = tg;
            ctx.fillRect(0, 0, w, h);

            // estrellas: las cercanas al agujero → arcos lensados
            const stars = root._stars || [];
            for (let i = 0; i < stars.length; i++) {
                const st = stars[i];
                const sx = st.x * w, sy = st.y * h;
                const d = Math.hypot(sx - bh.x, sy - bh.y);
                if (d < bh.R * 1.9 && d > bh.R * 0.95) {
                    const ang = Math.atan2(sy - bh.y, sx - bh.x);
                    const bend = (bh.R / d) * 0.22;
                    ctx.strokeStyle = root._a(root._lit(root.colInk, 0.5), 0.05 + st.b * 0.13);
                    ctx.lineWidth = 0.6;
                    ctx.beginPath();
                    ctx.arc(bh.x, bh.y, d, ang - bend, ang + bend);
                    ctx.stroke();
                } else {
                    ctx.fillStyle = root._a(root._lit(root.colInk, 0.4), 0.12 + st.b * 0.5);
                    const sz = st.b < 0.7 ? 1.0 : 1.8;
                    ctx.fillRect(sx, sy, sz, sz);
                }
            }

            // resplandor exterior del agujero negro (gradiente radial, jamás shadowBlur)
            const og = ctx.createRadialGradient(bh.x, bh.y, bh.R * 0.8, bh.x, bh.y, bh.R * 4.8);
            og.addColorStop(0, root._a(root._lit(root.colPrimary, 0.30), 0.18));
            og.addColorStop(0.35, root._a(root.colPrimary, 0.07));
            og.addColorStop(1, root._a(root.colPrimary, 0));
            ctx.fillStyle = og;
            ctx.beginPath();
            ctx.arc(bh.x, bh.y, bh.R * 4.8, 0, 2 * Math.PI);
            ctx.fill();
        }
    }

    // ===================== CANVAS DINÁMICO =====================
    Canvas {
        id: dynCanvas
        renderTarget: Canvas.FramebufferObject
        antialiasing: true

        // Dimensionado a la caja del contenido (estable frame a frame porque sale
        // de constantes de composición, no de posiciones vivas).
        x: root._layout ? root._layout.bounds.x : 0
        y: root._layout ? root._layout.bounds.y : 0
        width: root._layout ? root._layout.bounds.w : root.width
        height: root._layout ? root._layout.bounds.h : root.height

        // ---- helpers geométricos: elipse por scale+arc (QML no tiene el ellipse HTML5) ----
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

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const L = root._layout;
            if (!L) return;
            // trabajamos en coordenadas del Item completo, pero el canvas está
            // desplazado a la caja del contenido:
            ctx.translate(-x, -y);

            _drawBelt(ctx, L);
            _drawOrbits(ctx, L);
            _drawBlackHole(ctx, L);
            _drawSun(ctx, L.suns[0], root.colPrimary, L.t, false);   // Config detrás
            _drawSun(ctx, L.suns[1], root.colLaura, L.t, true);      // Laura encima
            for (let i = 0; i < L.bodies.length; i++) {
                const b = L.bodies[i];
                _drawPlanet(ctx, b, b.kind === "device" ? root.colPrimary : root.colLaura, L.t);
            }
        }

        function _glow(ctx, x, y, inner, outer, col, a0) {
            const g = ctx.createRadialGradient(x, y, inner, x, y, outer);
            g.addColorStop(0, root._a(col, a0));
            g.addColorStop(1, root._a(col, 0));
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(x, y, outer, 0, 2 * Math.PI);
            ctx.fill();
        }

        function _fillEllipticAnnulus(ctx, rInner, rOuter, style) {
            ctx.fillStyle = style;
            ctx.beginPath();
            ctx.arc(0, 0, rOuter, 0, 2 * Math.PI);
            ctx.arc(0, 0, rInner, 0, 2 * Math.PI, true);
            ctx.fill();
        }

        // ---------------- Agujero negro (capas de atrás a delante, spec §4.1) ----------------
        function _drawBlackHole(ctx, L) {
            const x = L.bh.x, y = L.bh.y, R = L.bh.R;
            const t = L.t;
            const tilt = -0.489;                 // -28° — disco raking down-left
            const flat = 0.14;                   // ry/rx casi de canto
            const beam = 2 * Math.PI / 30 * t;    // rotación visible ~30 s (spin/beaming)
            const music = L.music;
            const innerR = R * 1.30, outerR = R * 4.0;
            const HOT = root._hot, P = root.colPrimary, ERR = root.colError, VOID = root.colVoid;

            function paintDisk(clipMode) {
                ctx.save();
                ctx.translate(x, y);
                ctx.rotate(tilt);
                if (clipMode === "back")  { ctx.beginPath(); ctx.rect(-outerR * 1.4, -outerR * 1.4, outerR * 2.8, outerR * 1.4); ctx.clip(); }
                if (clipMode === "front") { ctx.beginPath(); ctx.rect(-outerR * 1.4, 0, outerR * 2.8, outerR * 1.4); ctx.clip(); }
                ctx.scale(1, flat);
                const g = ctx.createRadialGradient(0, 0, innerR * 0.9, 0, 0, outerR);
                g.addColorStop(0.00, root._a(HOT, 0.0));
                g.addColorStop(0.06, root._a(HOT, 0.95));
                g.addColorStop(0.14, root._a(root._lit(P, 0.35), 0.92));
                g.addColorStop(0.45, root._a(P, 0.62));
                g.addColorStop(0.72, root._a(root._dk(P, 0.25), 0.42));
                g.addColorStop(0.88, root._a(root._dk(ERR, 0.35), 0.22));
                g.addColorStop(1.00, root._a(root._dk(ERR, 0.6), 0));
                _fillEllipticAnnulus(ctx, innerR * 0.98, outerR, g);
                // bandeado sutil + turbulencia lenta (textura, con el mismo falloff que el relleno)
                for (let i = 0; i < 13; i++) {
                    const f = 0.06 + i * 0.05;
                    if (f > 0.72) break;
                    const rr = innerR + (outerR - innerR) * f;
                    const phase = Math.sin(f * 9 + t * 0.5 + i * 0.7);
                    const col = (i % 2 === 0) ? root._dk(P, 0.35) : root._lit(P, 0.25);
                    const falloff = Math.pow(1 - f / 0.72, 1.3);
                    ctx.strokeStyle = root._a(col, (0.13 * falloff + music * 0.05) * (0.6 + 0.4 * phase));
                    ctx.lineWidth = R * 0.05 * (1 - f * 0.35);
                    ctx.beginPath();
                    ctx.arc(0, 0, rr, 0, 2 * Math.PI);
                    ctx.stroke();
                }
                ctx.restore();
            }

            function paintBeaming() {
                ctx.save();
                ctx.translate(x, y); ctx.rotate(tilt); ctx.scale(1, flat);
                ctx.beginPath();
                ctx.arc(0, 0, outerR * 0.92, beam - 1.5, beam + 1.5);
                ctx.arc(0, 0, innerR * 0.98, beam + 1.5, beam - 1.5, true);
                ctx.closePath();
                const bg = ctx.createRadialGradient(0, 0, innerR, 0, 0, outerR * 0.92);
                bg.addColorStop(0, root._a(root._lit(P, 0.5), 0.5 + music * 0.2));
                bg.addColorStop(0.5, root._a(root._lit(P, 0.15), 0.22));
                bg.addColorStop(1, root._a(P, 0));
                ctx.fillStyle = bg;
                ctx.fill();
                ctx.restore();
            }

            // 1. resplandor exterior → lo pinta el canvas estático.

            // 2. borde lejano lensado SOBRE el horizonte (halo «Gargantua»)
            ctx.save();
            ctx.translate(x, y); ctx.rotate(tilt);
            ctx.save();
            ctx.beginPath();
            ctx.rect(-outerR * 1.4, -outerR * 1.4, outerR * 2.8, outerR * 1.4 - R * 0.05);
            ctx.clip();
            for (let b = 0; b < 3; b++) {
                const rr = R * (1.05 + b * 0.06);
                _strokeEllipse(ctx, 0, -R * 0.16, rr, rr * flat * 2.4, 0,
                               Math.PI * 1.08, Math.PI * 1.92,
                               root._a(root._mix(HOT, P, b / 2), 0.42 - b * 0.13),
                               R * (0.085 - b * 0.02));
            }
            ctx.restore();
            ctx.restore();

            // 3. disco: mitad de ATRÁS
            paintDisk("back");

            // 4. horizonte de sucesos (rol de fondo casi a negro; nunca hex fijo)
            ctx.fillStyle = root._a(VOID, 1);
            ctx.beginPath();
            ctx.arc(x, y, R, 0, 2 * Math.PI);
            ctx.fill();

            // 5. anillo de fotones + halo suave + Doppler
            ctx.save();
            ctx.translate(x, y); ctx.rotate(tilt);
            ctx.strokeStyle = root._a(root._lit(P, 0.7), 0.16);
            ctx.lineWidth = R * 0.09;
            ctx.beginPath(); ctx.arc(0, 0, R * 1.09, 0, 2 * Math.PI); ctx.stroke();
            ctx.strokeStyle = root._a(root._lit(P, 0.92), 0.55);
            ctx.lineWidth = Math.max(1.5, R * 0.022);
            ctx.beginPath(); ctx.arc(0, 0, R * 1.035, 0, 2 * Math.PI); ctx.stroke();
            ctx.strokeStyle = root._a(root._lit(P, 0.98), 0.95);
            ctx.lineWidth = Math.max(1.5, R * 0.028);
            ctx.beginPath(); ctx.arc(0, 0, R * 1.035, beam - 1.6, beam + 1.6); ctx.stroke();
            ctx.restore();

            // 6. disco: mitad FRONTAL (pasa por delante del horizonte, abajo)
            paintDisk("front");
            paintBeaming();

            // 7. labio interior caliente (ISCO)
            ctx.save();
            ctx.translate(x, y); ctx.rotate(tilt); ctx.scale(1, flat);
            const hb = 0.5 + 0.5 * Math.cos(Math.PI - beam);
            const lip = ctx.createLinearGradient(-innerR, 0, innerR, 0);
            lip.addColorStop(0, root._a(HOT, 0.22 + 0.5 * (1 - hb) + music * 0.2));
            lip.addColorStop(0.5, root._a(root._lit(P, 0.3), 0.16));
            lip.addColorStop(1, root._a(HOT, 0.22 + 0.5 * hb + music * 0.2));
            ctx.strokeStyle = lip;
            ctx.lineWidth = R * 0.14;
            ctx.beginPath(); ctx.arc(0, 0, innerR * 1.04, 0, 2 * Math.PI); ctx.stroke();
            ctx.restore();

            // 8. jet relativista muy tenue (perpendicular al plano del disco)
            ctx.save();
            ctx.translate(x, y); ctx.rotate(tilt);
            for (const dir of [-1, 1]) {
                const jl = R * 3.2;
                const jg = ctx.createLinearGradient(0, 0, 0, dir * jl);
                jg.addColorStop(0, root._a(root._lit(P, 0.6), 0.12));
                jg.addColorStop(1, root._a(root._lit(P, 0.6), 0));
                ctx.strokeStyle = jg;
                ctx.lineWidth = R * 0.10;
                ctx.beginPath();
                ctx.moveTo(0, dir * R * 0.5);
                ctx.lineTo(0, dir * jl);
                ctx.stroke();
            }
            ctx.restore();
        }

        // ---------------- Soles (spec §4.2) ----------------
        function _drawSun(ctx, s, col, t, prominences) {
            const r = s.r;
            const op = 1 - (s.dim || 0);
            const breath = 1 + 0.04 * Math.sin(t * 0.7);
            // 1. corona (contenida para que el binario no se funda en un solo halo)
            _glow(ctx, s.x, s.y, r * 0.3, r * 3.0 * breath, col, 0.11 * op);
            _glow(ctx, s.x, s.y, r * 0.4, r * 1.6 * breath, col, 0.30 * op);
            // 2. fotosfera (gradiente radial descentrado — luz arriba-izquierda)
            const bg = ctx.createRadialGradient(s.x - r * 0.35, s.y - r * 0.35, r * 0.1, s.x, s.y, r);
            bg.addColorStop(0, root._a(root._lit(col, 0.9), op));
            bg.addColorStop(0.5, root._a(root._lit(col, 0.22), op));
            bg.addColorStop(1, root._a(root._dk(col, 0.28), op));
            ctx.fillStyle = bg;
            ctx.beginPath(); ctx.arc(s.x, s.y, r, 0, 2 * Math.PI); ctx.fill();
            // 3. granulación: muchas celdas pequeñas de bajo contraste, rotan muy despacio
            ctx.save();
            ctx.beginPath(); ctx.arc(s.x, s.y, r, 0, 2 * Math.PI); ctx.clip();
            const gsp = t * 0.04;
            for (let i = 0; i < 80; i++) {
                const a = i * 2.399 + gsp;
                const rr = r * (0.05 + 0.92 * Math.sqrt(((i * 37) % 100) / 100));
                const gx = s.x + Math.cos(a) * rr, gy = s.y + Math.sin(a) * rr;
                const gs = r * (0.05 + 0.06 * ((i * 53) % 100) / 100);
                const shade = (i % 2) ? 0.05 : -0.045;
                ctx.fillStyle = root._a(shade > 0 ? root._lit(col, shade * 3) : root._dk(col, -shade * 3), 0.18 * op);
                ctx.beginPath(); ctx.arc(gx, gy, gs, 0, 2 * Math.PI); ctx.fill();
            }
            ctx.restore();
            // 4. cromosfera / limbo
            ctx.strokeStyle = root._a(root._lit(col, 0.45), 0.55 * op);
            ctx.lineWidth = Math.max(1, r * 0.05);
            ctx.beginPath(); ctx.arc(s.x, s.y, r * 1.005, 0, 2 * Math.PI); ctx.stroke();
            // 5. prominencias lentas (sólo Laura; aparecen y se desvanecen en ~20 s)
            if (prominences) {
                for (let i = 0; i < 3; i++) {
                    const base = i * 2.1 + t * 0.03;
                    const life = 0.5 + 0.5 * Math.sin(t * (2 * Math.PI / 20) + i * 2.0);
                    if (life < 0.1) continue;
                    ctx.strokeStyle = root._a(root._lit(col, 0.5), 0.4 * life * op);
                    ctx.lineWidth = Math.max(1, r * 0.04);
                    const a0 = base, a1 = base + 0.5;
                    const x0 = s.x + Math.cos(a0) * r * 0.98, y0 = s.y + Math.sin(a0) * r * 0.98;
                    const x1 = s.x + Math.cos(a1) * r * 0.98, y1 = s.y + Math.sin(a1) * r * 0.98;
                    const mx = s.x + Math.cos((a0 + a1) / 2) * r * (1.35 + 0.3 * life);
                    const my = s.y + Math.sin((a0 + a1) / 2) * r * (1.35 + 0.3 * life);
                    ctx.beginPath();
                    ctx.moveTo(x0, y0);
                    ctx.quadraticCurveTo(mx, my, x1, y1);
                    ctx.stroke();
                }
            }
        }

        // ---------------- Satélites: agentes / dispositivos (spec §4.3) ----------------
        function _drawPlanet(ctx, b, col, t) {
            const r = b.r;
            const base = b.alert > 0.5 ? root.colError : col;
            // aro de alerta (batería < 20 %)
            if (b.alert > 0.5) {
                const p = 0.5 + 0.5 * Math.sin(t * 3);
                ctx.strokeStyle = root._a(root.colError, 0.3 + 0.5 * p);
                ctx.lineWidth = 1.5;
                ctx.beginPath(); ctx.arc(b.x, b.y, r + 4 * root._layout.scale, 0, 2 * Math.PI); ctx.stroke();
            }
            // anillo de actividad (agente en curso)
            if (b.running) {
                _glow(ctx, b.x, b.y, r * 0.5, r * 2.8, col, 0.28 + 0.2 * (0.5 + 0.5 * Math.sin(t * 1.5)));
                _strokeEllipse(ctx, b.x, b.y, r * 1.9, r * 0.8, 0.5, 0, 2 * Math.PI,
                               root._a(root._lit(col, 0.3), 0.5), 1);
            }
            // cuerpo con lado iluminado mirando a su ancla
            const dir = Math.atan2(b.hosty - b.y, b.hostx - b.x);
            const lx = b.x + Math.cos(dir) * r * 0.45, ly = b.y + Math.sin(dir) * r * 0.45;
            const pg = ctx.createRadialGradient(lx, ly, r * 0.1, b.x, b.y, r);
            pg.addColorStop(0, root._a(root._lit(base, 0.55), 1));
            pg.addColorStop(0.6, root._a(base, 1));
            pg.addColorStop(1, root._a(root._dk(base, 0.55), 1));
            ctx.fillStyle = pg;
            ctx.beginPath(); ctx.arc(b.x, b.y, r, 0, 2 * Math.PI); ctx.fill();
            // limbo iluminado (dispersión en el lado que mira al sol)
            ctx.strokeStyle = root._a(root._lit(base, 0.6), 0.45);
            ctx.lineWidth = 1;
            ctx.beginPath(); ctx.arc(b.x, b.y, r, dir - 1.4, dir + 1.4); ctx.stroke();
        }

        // ---------------- Órbitas (trazas casi invisibles en reposo, spec §4.4) ----------------
        function _drawOrbits(ctx, L) {
            for (let i = 0; i < L.bodies.length; i++) {
                const b = L.bodies[i];
                if (b.kind === "agent" && !b.running) continue;
                const rr = Math.hypot(b.x - b.hostx, (b.y - b.hosty) / 0.52);
                _strokeEllipse(ctx, b.hostx, b.hosty, rr, rr * 0.52, 0, 0, 2 * Math.PI,
                               root._a(b.kind === "device" ? root.colPrimary : root.colLaura, 0.035), 1);
            }
        }

        // ---------------- Cinturón circumbinario (spec §2.4 — muy tenue) ----------------
        function _drawBelt(ctx, L) {
            const B = L.belt;
            ctx.save();
            ctx.translate(B.cx, B.cy);
            ctx.rotate(B.tilt);
            for (let i = 0; i < B.n; i++) {
                const a = i / B.n * 2 * Math.PI + B.spin + Math.sin(i * 2.7) * 0.18;
                const jj = 1 + Math.sin(i * 5.3) * 0.09;
                const px = Math.cos(a) * B.rx * jj, py = Math.sin(a) * B.ry * jj;
                ctx.fillStyle = root._a(root._lit(root.colBelt, 0.35), 0.20 + 0.22 * ((i * 7) % 3) / 2);
                const sz = (i % 5 === 0) ? 2.2 : 1.5;
                ctx.fillRect(px - sz / 2, py - sz / 2, sz, sz);
            }
            ctx.restore();
        }
    }

    // ===================== TIC =====================
    // Prohibido FrameAnimation { running: true }. El tic va por Timer gateado a
    // actividad real; en reposo PARA del todo y sólo se repinta al cambiar datos.
    Timer {
        id: ticker
        repeat: true
        running: root.active && root.visible && !root.paused && !root.reduceMotion
        interval: root.fastRate ? 33 : 320       // ~30 fps con música, ~3 fps en reposo
        onRunningChanged: if (!running) root._recompute()   // asienta el último fotograma
        onTriggered: {
            root._t += interval / 1000;
            root._recompute();
        }
    }

    // En reposo: un repintado único al cambiar datos, tamaño o paleta.
    onValuesChanged: if (!ticker.running) _recompute()
    onConfigChanged: if (!ticker.running) _recompute()
    onWidthChanged: { _seedStars(); _recompute(); staticCanvas._repaintStatic(); }
    onHeightChanged: { _seedStars(); _recompute(); staticCanvas._repaintStatic(); }
    onColPrimaryChanged: { _recompute(); staticCanvas._repaintStatic(); }
    onColLauraChanged: _recompute()
    onColVoidChanged: _recompute()
    onColInkChanged: staticCanvas._repaintStatic()

    Component.onCompleted: { _seedStars(); _recompute(); }
}
