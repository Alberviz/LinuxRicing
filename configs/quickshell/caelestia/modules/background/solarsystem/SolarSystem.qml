pragma ComponentBehavior: Bound

// SolarSystem.qml — la VISTA. Un solo Canvas que pinta lo que el motor puro
// (Sim.js) calcula a partir de `config` (la disposición) y `values` (las señales
// de los adaptadores). No lee servicios directamente ni colores fijos: la paleta
// entra como propiedad. Ver docs/sistema-solar-binario.md.

import QtQuick
import "Sim.js" as Sim

Item {
    id: root

    // --- Entradas (se inyectan desde fuera) ---
    property var config: ({ anchors: [], bodies: [] })
    property var values: ({})
    // Paleta: en Caelestia se ata a Colours.palette (extraída del wallpaper).
    // Cada rol es un color; el motor nunca ve un hex fijo.
    property color colAnchorPrimary: "#8ab4ff"
    property color colAnchorSecondary: "#c7a9ff"
    property color colBody: "#6ce0c4"
    property color colBodyAlt: "#e0a878"
    property color colAlert: "#ff5a78"
    property color colBelt: "#cdd2e1"
    // Horizonte de sucesos del agujero negro. Nunca un hex fijo: se ata desde
    // fuera a una versión muy oscura del rol de fondo de la paleta.
    property color colVoid: "#04040a"

    property bool paused: false
    // Se ata a la preferencia real del sistema desde la capa; por defecto no
    // reduce. Cuando es true la animación se detiene igual que con `paused`.
    property bool reduceMotion: false

    // Dónde cae el baricentro dentro del Item (fracción 0..1).
    property real centerFracX: 0.5
    property real centerFracY: 0.5
    function _geom() {
        return {
            w: width, h: height,
            cx: width * centerFracX, cy: height * centerFracY
        };
    }

    // Mapa id-de-ancla -> color de rol. Config puede fijar `color: "primary"|...`.
    function _anchorColor(a) {
        const roleFor = {};
        for (const c of (root.config.anchors || []))
            roleFor[c.id] = c.color || "primary";
        const role = roleFor[a.id] || "primary";
        return role === "secondary" ? root.colAnchorSecondary : root.colAnchorPrimary;
    }
    function _bodyColor(b) {
        if (b.alert > 0.5)
            return root.colAlert;
        const kindColor = {};
        for (const c of (root.config.bodies || []))
            kindColor[c.id] = c.color;
        const want = kindColor[b.id];
        if (want === "alt") return root.colBodyAlt;
        if (want === "belt") return root.colBelt;
        if (want === "secondary") return root.colAnchorSecondary;
        return root.colBody;
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        antialiasing: true

        property var layout: null

        // --- helpers de color (todo deriva de la paleta inyectada) ---
        function _a(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
        function _lit(c, k) { return Qt.rgba(c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, 1); }
        function _dk(c, k) { return Qt.rgba(c.r * (1 - k), c.g * (1 - k), c.b * (1 - k), 1); }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const L = layout;
            if (!L)
                return;
            const S = L.scale;

            // 1. Órbitas — trazas muy tenues.
            ctx.lineWidth = 1;
            for (const a of L.anchors) {
                const m = _motionOf(a.id);
                if (m && m.kind === "orbit") {
                    const base = _anchorPos(L, m.around) || L.barycenter;
                    const rx = (m.orbit || 40) * S;
                    const ry = rx * (1 - (m.ecc != null ? m.ecc : 0.5));
                    _ellipse(ctx, base.x, base.y, rx, ry, _a(root._anchorColor(a), 0.10));
                }
            }
            for (const b of L.bodies) {
                if (b.kind === "belt")
                    continue;
                const host = _anchorPos(L, b.anchor) || L.barycenter;
                const cb = _cfgBody(b.id);
                const rx = (cb && cb.orbit ? cb.orbit : 40) * S;
                const ry = rx * (1 - (cb && cb.ecc != null ? cb.ecc : 0.5));
                _ellipse(ctx, host.x, host.y, rx, ry, _a(root._bodyColor(b), 0.08 * (0.4 + 0.6 * b.activity)));
            }

            // 2. Cinturón circumbinario — partículas, no una línea.
            for (const b of L.bodies) {
                if (b.kind !== "belt")
                    continue;
                const host = _anchorPos(L, b.anchor) || L.barycenter;
                const cb = _cfgBody(b.id);
                const rx = (cb && cb.orbit ? cb.orbit : 120) * S;
                const ry = rx * (1 - (cb && cb.ecc != null ? cb.ecc : 0.5));
                _belt(ctx, host.x, host.y, rx, ry, root._bodyColor(b), b.activity, S, L.t);
            }

            // 3. Planetas.
            for (const b of L.bodies) {
                if (b.kind === "belt")
                    continue;
                _planet(ctx, b, root._bodyColor(b), S);
            }

            // 4. Anclas: soles y agujero negro, encima de todo.
            for (const a of L.anchors) {
                if (a.kind === "blackhole")
                    _blackhole(ctx, a, root._anchorColor(a), S, L.t);
                else
                    _sun(ctx, a, root._anchorColor(a), S, L.t);
            }
        }

        function _ellipse(ctx, cx, cy, rx, ry, stroke) {
            ctx.strokeStyle = stroke;
            ctx.beginPath();
            ctx.ellipse(cx - rx, cy - ry, rx * 2, ry * 2);
            ctx.stroke();
        }

        // Resplandor radial barato (nada de shadowBlur — gaussian por-píxel).
        function _glow(ctx, x, y, inner, outer, color, a0) {
            const g = ctx.createRadialGradient(x, y, inner, x, y, outer);
            g.addColorStop(0, _a(color, a0));
            g.addColorStop(1, _a(color, 0));
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(x, y, outer, 0, 2 * Math.PI);
            ctx.fill();
        }

        function _sun(ctx, a, col, S, t) {
            const op = 1 - a.dim;
            const r = a.r;
            const breath = 1 + 0.06 * a.pulse;
            // corona exterior + media
            _glow(ctx, a.x, a.y, r * 0.4, r * 4.2 * breath, col, 0.16 * op);
            _glow(ctx, a.x, a.y, r * 0.3, r * 1.9 * breath, col, 0.42 * op);
            // fulguraciones: radios finos que giran despacio
            ctx.save();
            ctx.strokeStyle = _a(canvas._lit(col, 0.3), 0.4 * op);
            ctx.lineWidth = 1;
            const spin = t * 0.04;
            for (let i = 0; i < 8; i++) {
                const ang = i * Math.PI / 4 + spin;
                const len = r * (2.3 + (i % 2 ? 0.7 : 0) + a.pulse * 0.3);
                ctx.beginPath();
                ctx.moveTo(a.x + Math.cos(ang) * r * 1.2, a.y + Math.sin(ang) * r * 1.2);
                ctx.lineTo(a.x + Math.cos(ang) * len, a.y + Math.sin(ang) * len);
                ctx.stroke();
            }
            ctx.restore();
            // cuerpo: gradiente de núcleo caliente a borde con color
            const bg = ctx.createRadialGradient(a.x - r * 0.3, a.y - r * 0.3, r * 0.1, a.x, a.y, r);
            bg.addColorStop(0, _a(canvas._lit(col, 0.85), op));
            bg.addColorStop(0.55, _a(canvas._lit(col, 0.25), op));
            bg.addColorStop(1, _a(canvas._dk(col, 0.15), op));
            ctx.fillStyle = bg;
            ctx.beginPath();
            ctx.arc(a.x, a.y, r, 0, 2 * Math.PI);
            ctx.fill();
            // borde de cromosfera
            ctx.strokeStyle = _a(canvas._lit(col, 0.4), 0.5 * op);
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.arc(a.x, a.y, r + 0.5, 0, 2 * Math.PI);
            ctx.stroke();
        }

        function _blackhole(ctx, a, col, S, t) {
            const r = a.r;
            // luz del disco filtrándose
            _glow(ctx, a.x, a.y, r * 0.8, r * 3.4, col, 0.14);
            // disco de acreción: elipse inclinada, brillo que rota (beaming)
            ctx.save();
            ctx.translate(a.x, a.y);
            ctx.rotate(-0.32);
            const rx = r * 1.9, ry = r * 0.62;
            const ph = Math.cos(t * 0.6);
            const dg = ctx.createLinearGradient(-rx, 0, rx, 0);
            dg.addColorStop(0.0, _a(canvas._lit(col, 0.7), 0.6 + 0.35 * ph));
            dg.addColorStop(0.5, _a(col, 0.3));
            dg.addColorStop(1.0, _a(canvas._lit(col, 0.7), 0.6 - 0.35 * ph));
            ctx.strokeStyle = dg;
            ctx.lineWidth = Math.max(2, r * 0.5);
            ctx.beginPath();
            ctx.ellipse(-rx, -ry, rx * 2, ry * 2);
            ctx.stroke();
            ctx.restore();
            // anillo de fotones
            ctx.strokeStyle = _a(canvas._lit(col, 0.85), 0.9);
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.arc(a.x, a.y, r, 0, 2 * Math.PI);
            ctx.stroke();
            // horizonte de sucesos
            ctx.fillStyle = root.colVoid;
            ctx.beginPath();
            ctx.arc(a.x, a.y, r * 0.82, 0, 2 * Math.PI);
            ctx.fill();
        }

        function _planet(ctx, b, col, S) {
            const r = b.r;
            if (b.alert > 0.5) {
                ctx.strokeStyle = _a(col, 0.3 + 0.5 * b.pulse);
                ctx.lineWidth = 1.5;
                ctx.beginPath();
                ctx.arc(b.x, b.y, r + 3 * S, 0, 2 * Math.PI);
                ctx.stroke();
            }
            if (b.ring) {
                // terminal en curso: halo suave + aro fino
                _glow(ctx, b.x, b.y, r * 0.5, r * 2.6, col, 0.3 + 0.25 * b.pulse);
                ctx.strokeStyle = _a(canvas._lit(col, 0.3), 0.55);
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.ellipse(b.x - r * 1.7, b.y - r * 0.7, r * 3.4, r * 1.4);
                ctx.stroke();
            }
            // cuerpo con lado iluminado
            const pg = ctx.createRadialGradient(b.x - r * 0.45, b.y - r * 0.45, r * 0.1, b.x, b.y, r);
            pg.addColorStop(0, canvas._lit(col, 0.55));
            pg.addColorStop(0.6, col);
            pg.addColorStop(1, canvas._dk(col, 0.55));
            ctx.fillStyle = pg;
            ctx.beginPath();
            ctx.arc(b.x, b.y, r, 0, 2 * Math.PI);
            ctx.fill();
            // filo brillante
            ctx.strokeStyle = _a(canvas._lit(col, 0.6), 0.5);
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.arc(b.x, b.y, r, Math.PI * 1.05, Math.PI * 1.75);
            ctx.stroke();
        }

        function _belt(ctx, cx, cy, rx, ry, col, activity, S, t) {
            const n = Math.round(18 + activity * 26);
            const spin = t * 0.03;
            for (let i = 0; i < n; i++) {
                const ang = (i / n) * 2 * Math.PI + spin + Math.sin(i * 2.7) * 0.12;
                const jitter = 1 + Math.sin(i * 5.3) * 0.05;
                const x = cx + Math.cos(ang) * rx * jitter;
                const y = cy + Math.sin(ang) * ry * jitter;
                ctx.fillStyle = _a(col, 0.22 + 0.3 * ((i * 7) % 3) / 2);
                const sz = (i % 4 === 0 ? 1.8 : 1.1) * S;
                ctx.fillRect(x - sz / 2, y - sz / 2, sz, sz);
            }
        }

        function _motionOf(id) {
            for (const a of (root.config.anchors || []))
                if (a.id === id) return a.motion;
            return null;
        }
        function _cfgBody(id) {
            for (const b of (root.config.bodies || []))
                if (b.id === id) return b;
            return null;
        }
        function _anchorPos(L, id) {
            if (!id || id === "barycenter") return L.barycenter;
            for (const a of L.anchors)
                if (a.id === id) return { x: a.x, y: a.y };
            return null;
        }
    }

    // ¿Hay algo que animar? Si no, la animación PARA del todo — Quickshell fuga
    // los FrameAnimation en cada hot-reload y un loop zombi a 60fps clava un
    // núcleo. En reposo dejamos un fotograma quieto y recalculamos solo cuando
    // cambian los datos.
    // ¿Animar de forma continua? Solo cuando merece los fotogramas (música
    // sonando). En reposo el sistema queda quieto y solo se repinta al cambiar
    // los datos. El tic va por Timer, no FrameAnimation: Quickshell fuga los
    // FrameAnimation en cada hot-reload y un loop zombi clava un núcleo.
    property bool active: false
    property bool fastRate: false

    property real _t: 0

    function _recompute() {
        canvas.layout = Sim.computeLayout({
            t: root._t,
            values: root.values,
            config: root.config
        }, root._geom());
        canvas.requestPaint();
    }

    Timer {
        id: ticker
        repeat: true
        running: root.active && root.visible && !root.paused && !root.reduceMotion
        // ~30 fps solo con música (cava). Sin música el sistema está "calmo":
        // 4 fps bastan para la deriva lenta y el pulso de los anillos de agente,
        // y un Canvas FBO a pantalla completa a 8 fps ya costaba ~20 % de CPU.
        interval: root.fastRate ? 33 : 250
        onRunningChanged: if (!running) root._recompute()   // asienta el último fotograma
        onTriggered: {
            root._t += interval / 1000;
            root._recompute();
        }
    }

    // En reposo, un repintado único cuando cambian datos o tamaño (aparece un
    // terminal, cambia la batería, se redimensiona la pantalla).
    onValuesChanged: if (!ticker.running) _recompute()
    onConfigChanged: if (!ticker.running) _recompute()
    onWidthChanged: _recompute()
    onHeightChanged: _recompute()

    Component.onCompleted: _recompute()
}
