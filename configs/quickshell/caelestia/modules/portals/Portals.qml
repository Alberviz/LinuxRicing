pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

// Portales de arrastre, variante B «clavado en el borde» (mockup portales-mockup.html).
// DERECHO -> Chromecast (Cast), SUPERIOR -> móvil vía Olimpo (`olimpo enviar`).
// `drag-watch` avisa de un arrastre en curso (DragWatch.qml). Fuera del arrastre: ventana sin
// input, nada visible y NINGUNA animación ni temporizador corriendo (el FrameAnimation solo
// corre mientras `active`). Wayland solo entrega el DnD a la superficie bajo el cursor, por
// eso las bandas de input existen únicamente mientras dura el arrastre.
Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        readonly property bool busy: pRight.phase !== "idle" || pTop.phase !== "idle"
        readonly property bool active: DragWatch.dragging || grace.running || busy
        readonly property real lx: DragWatch.cx - screen.x
        readonly property real ly: DragWatch.cy - screen.y
        readonly property bool here: lx >= 0 && ly >= 0 && lx <= width && ly <= height
        readonly property real u: width / 1280
        readonly property real band: 140 * u
        readonly property real along: 0.62
        property string olimpo: ""
        property real latent: 0
        property var frags: []
        property var absorb: null
        property real trailK: 0
        property real trailAng: 0

        function sm(a: real, b: real, x: real): real {
            const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
            return t * t * (3 - 2 * t);
        }
        function lerp(a: real, b: real, t: real): real {
            return a + (b - a) * t;
        }

        function tick(dtRaw: real): void {
            const dt = Math.min(0.05, dtRaw);
            const on = DragWatch.dragging && here;
            latent = Math.max(0, Math.min(1, latent + ((on || busy) ? 1 : -1) * dt / 0.32));
            const ps = [pRight, pTop];
            let armedAny = null;
            for (const p of ps) {
                let target = 0;
                const d = p.edge === "right" ? width - lx : ly;
                const al = p.edge === "right" ? Math.abs(ly - height / 2) / (height / 2) : Math.abs(lx - width / 2) / (width / 2);
                if (on) {
                    target = sm(width * 0.55, width * 0.11, d) * (1 - 0.45 * sm(0.55, 1, al));
                    p.armed = d < band && al < along;
                    if (p.armed)
                        armedAny = p;
                } else if (!busy) {
                    p.armed = false;
                }
                if (p.armed || p.phase !== "idle")
                    target = 1;
                p.e = lerp(p.e, target, 1 - Math.pow(0.0009, dt));
            }
            for (const p of ps) {
                p.dim = lerp(p.dim, armedAny && armedAny !== p ? 1 : 0, 1 - Math.pow(0.002, dt));
                const show = 1 - Math.pow(1 - latent, 3);
                const Rt = (30 + 26 * sm(0, 0.9, p.e) + (p.hot ? 16 : 0)) * u;
                p.r = lerp(p.r, Rt, 1 - Math.pow(0.0005, dt));
                const out = lerp(-p.r * 1.4, 0, show);
                if (p.edge === "right") {
                    p.cx = width - out;
                    p.cy = height / 2;
                } else {
                    p.cx = width / 2;
                    p.cy = out;
                }
                p.vis = show * (1 - 0.55 * p.dim);
                p.spinPhase += 0.25 * (1 + 1.4 * p.e + (p.armed ? 1 : 0)) * dt;
                p.pullPhase += (0.35 + 1.5 * p.e + (p.armed ? 0.8 : 0)) * dt;
                p.pulse = Math.max(0, p.pulse - dt / 0.48);
            }

            // Absorción: el icono cae en espiral (1,25 vueltas, 720 ms) y se espaguetiza
            if (absorb) {
                absorb.t += dt;
                const k = Math.min(1, absorb.t / 0.72), e3 = k * k * k, p = absorb.p;
                const ang = absorb.a0 + 1.25 * 2 * Math.PI * e3;
                const rr = lerp(absorb.r0, p.r * 0.15, e3);
                icon.x = p.cx + Math.cos(ang) * rr - icon.width / 2;
                icon.y = p.cy + Math.sin(ang) * rr * lerp(1, 0.55, e3) - icon.height / 2;
                icon.rotation = ang * 180 / Math.PI * 0.3;
                icon.scale = lerp(1, 0.12, e3);
                icon.opacity = 1 - Math.pow(k, 4);
                if (k >= 1) {
                    p.pulse = 1;
                    absorb = null;
                    icon.opacity = 0;
                }
            }

            // Espaguetización del cursor: estela estirada hacia el agujero más cercano + fragmentos
            let best = null, bt = 0;
            if (on && !absorb) {
                for (const p of ps) {
                    const d = Math.hypot(lx - p.cx, ly - p.cy);
                    const tf = sm(width * 0.5, p.r * 1.6, d) * p.vis;
                    if (tf > bt) {
                        bt = tf;
                        best = p;
                    }
                }
            }
            const k2 = bt * bt;
            trailK = k2;
            if (best) {
                trailAng = Math.atan2(best.cy - ly, best.cx - lx);
                const spawn = Math.floor(k2 * 90 * dt + Math.random());
                for (let i = 0; i < spawn && frags.length < 36; i++)
                    frags.push({
                        x: lx + (Math.random() - 0.5) * 140 * u,
                        y: ly + (Math.random() - 0.5) * 80 * u,
                        p: best,
                        life: 0,
                        c: Math.random() < 0.5
                    });
            }
            const keep = [];
            for (const f of frags) {
                const p = f.p, dx = p.cx - f.x, dy = p.cy - f.y, d = Math.hypot(dx, dy) || 1;
                if (d < p.r * 0.95 || f.life > 3)
                    continue;
                const sp = lerp(70, 1100, sm(width * 0.55, p.r, d)) * u;
                const sw = 0.65 * sm(p.r * 5, p.r * 1.2, d);
                const ux = dx / d, uy = dy / d;
                f.vx = (ux * Math.cos(sw) - uy * Math.sin(sw)) * sp;
                f.vy = (ux * Math.sin(sw) + uy * Math.cos(sw)) * sp;
                f.x += f.vx * dt;
                f.y += f.vy * dt;
                f.life += dt;
                f.a = 0.85 * sm(p.r * 0.9, p.r * 2.2, d);
                f.w = Math.max(1, 2 * u * (1 - 0.5 * sm(p.r * 6, p.r, d)));
                keep.push(f);
            }
            frags = keep;
            for (let i = 0; i < fragRep.count; i++) {
                const it = fragRep.itemAt(i);
                if (!it)
                    continue;
                const f = keep[i];
                if (f) {
                    const l = Math.hypot(f.vx, f.vy) * 0.045 + 3;
                    it.x = f.x - l;
                    it.y = f.y - f.w / 2;
                    it.width = l;
                    it.height = f.w;
                    it.transformOriginX = l;
                    it.rotation = Math.atan2(f.vy, f.vx) * 180 / Math.PI;
                    it.opacity = Math.max(0, Math.min(1, f.a));
                    it.fragColor = f.c ? Colours.palette.m3tertiary : Colours.palette.m3primary;
                } else {
                    it.opacity = 0;
                }
            }
        }

        function finish(portal, ok: bool, msg: string): void {
            portal.phase = ok ? "ok" : "error";
            portal.status = msg;
            retract.restart();
        }

        function sendTele(t: string): void {
            pRight.phase = "sending";
            pRight.status = "Enviando…";
            if (!Cast.selectedDevice) {
                finish(pRight, false, "Sin Chromecast disponible");
                return;
            }
            Cast.cmdError = "";
            Cast.run(["cast", Cast.selectedDevice.uuid, t], code => {
                const ok = code === 0 && !Cast.cmdError;
                win.finish(pRight, ok, ok ? "Enviado a la tele" : (Cast.cmdError || "Error al enviar"));
            });
        }

        function sendMovil(t: string): void {
            if (!olimpo) {
                pTop.phase = "unavail";
                pTop.status = "Envío al móvil aún no disponible";
                retract.restart();
                return;
            }
            pTop.phase = "sending";
            pTop.status = "Enviando…";
            olimpoProc.command = [olimpo, "enviar", t];
            olimpoProc.running = true;
        }

        function startAbsorb(portal): void {
            const a0 = Math.atan2(ly - portal.cy, lx - portal.cx);
            const r0 = Math.hypot(lx - portal.cx, ly - portal.cy);
            absorb = {
                p: portal,
                t: 0,
                a0: a0,
                r0: r0
            };
        }

        function targetOf(drop): string {
            if (drop.hasUrls && drop.urls.length > 0)
                return Cast.normalizeTarget(drop.urls[0].toString());
            if (drop.hasText)
                return Cast.normalizeTarget(drop.text);
            return "";
        }

        screen: modelData
        name: "portals"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        mask: Region {
            Region {
                item: rBand
            }
            Region {
                item: tBand
            }
        }

        onActiveChanged: {
            if (active && !olimpoCheck.running && olimpo === "")
                olimpoCheck.running = true;
            if (!active) {
                latent = 0;
                frags = [];
                for (const p of [pRight, pTop]) {
                    p.vis = 0;
                    p.e = 0;
                    p.dim = 0;
                    p.armed = false;
                }
            }
        }

        Connections {
            target: DragWatch

            function onDraggingChanged() {
                if (!DragWatch.dragging && !win.busy)
                    grace.restart();
            }
        }

        // Margen tras soltar: el fin del arrastre (evdev) puede llegar antes que el drop,
        // y deja correr el fundido de salida (320 ms).
        Timer {
            id: grace

            interval: 700
        }

        Timer {
            id: retract

            interval: 2000
            onTriggered: {
                pRight.phase = "idle";
                pTop.phase = "idle";
                grace.restart();
            }
        }

        // El único «reloj»: solo mientras hay arrastre, absorción o fundido.
        FrameAnimation {
            running: win.active
            onTriggered: win.tick(frameTime)
        }

        Process {
            id: olimpoCheck

            command: ["sh", "-c", "for p in \"$HOME/proyectos/olimpo/cli/olimpo\" \"$HOME/.local/bin/olimpo\"; do [ -x \"$p\" ] && echo \"$p\" && exit; done"]
            stdout: StdioCollector {
                onStreamFinished: win.olimpo = text.trim()
            }
        }

        Process {
            id: olimpoProc

            stdout: StdioCollector {
                id: olimpoOut
            }
            onExited: code => {
                let ok = false, msg = "";
                try {
                    const r = JSON.parse(olimpoOut.text.trim().split("\n").pop());
                    ok = r.ok === true;
                    msg = ok ? "Enviado al móvil" : (r.error ?? "Error al enviar");
                } catch (e) {
                    msg = "Olimpo no responde";
                }
                win.finish(pTop, ok, msg);
            }
        }

        Item {
            anchors.fill: parent
            visible: win.active

            // Bandas de input (y de drop) reales; vacías si no hay arrastre.
            Item {
                id: rBand

                anchors.right: parent.right
                y: parent.height * (1 - win.along) / 2
                width: win.active ? win.band : 0
                height: win.active ? parent.height * win.along : 0

                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list", "text/plain"]
                    onDropped: drop => {
                        const t = win.targetOf(drop);
                        if (!t || pRight.phase !== "idle")
                            return;
                        win.startAbsorb(pRight);
                        win.sendTele(t);
                    }
                }
            }

            Item {
                id: tBand

                anchors.top: parent.top
                x: parent.width * (1 - win.along) / 2
                width: win.active ? parent.width * win.along : 0
                height: win.active ? win.band : 0

                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list", "text/plain"]
                    onDropped: drop => {
                        const t = win.targetOf(drop);
                        if (!t || pTop.phase !== "idle")
                            return;
                        win.startAbsorb(pTop);
                        win.sendMovil(t);
                    }
                }
            }

            Portal {
                id: pRight

                edge: "right"
                winW: win.width
                winH: win.height
                u: win.u
                kicker: "TELE"
                title: Cast.selectedDevice?.name ?? "Sin Chromecast"
                detail: Cast.selectedDevice ? (Cast.selectedDevice.model ?? "") + " · " + (Cast.selectedDevice.host ?? "") : "no hay dispositivos"
                cta: "Suelta para reproducir"
            }

            Portal {
                id: pTop

                edge: "top"
                winW: win.width
                winH: win.height
                u: win.u
                kicker: "MÓVIL"
                title: "Olimpo"
                detail: "Bandeja «Desde el PC»"
                cta: "Suelta para enviar"
            }

            // Estela estirada del cursor hacia el agujero más cercano (el icono real lo pinta el compositor)
            Rectangle {
                readonly property real len: (30 + 300 * win.trailK) * win.u

                visible: win.trailK > 0.01 && DragWatch.dragging
                x: win.lx
                y: win.ly - height / 2
                width: len
                height: Math.max(2, (7 * (1 - 0.5 * win.trailK)) * win.u)
                radius: height / 2
                transformOrigin: Item.Left
                rotation: win.trailAng * 180 / Math.PI
                opacity: Math.min(0.85, win.trailK * 1.4)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 0.3
                        color: Qt.alpha(Colours.palette.m3tertiary, 0.8)
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }

            Repeater {
                id: fragRep

                model: 36

                Rectangle {
                    property color fragColor: Colours.palette.m3primary

                    radius: height / 2
                    opacity: 0
                    color: fragColor
                }
            }

            // Archivo cayendo en espiral al soltar
            MaterialIcon {
                id: icon

                text: "description"
                color: Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.large
                opacity: 0
            }
        }
    }
}
