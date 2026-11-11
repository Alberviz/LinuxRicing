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
// DERECHO -> Chromecast (Cast), SUPERIOR -> móvil vía Olimpo (`olimpo enviar`): el agujero NEGRO de Warp (docs/WARP.md).
// Además, todo lo que envía el CLI `warp` (atajo Super+Shift+M, Laura, Instinct, texto arrastrado) llega por
// $XDG_RUNTIME_DIR/warp/salidas.jsonl y abre este mismo agujero, que se traga el envío.
// `drag-watch` avisa de un arrastre en curso (DragWatch.qml). Fuera del arrastre: ventana sin
// input, nada visible y NINGUNA animación ni temporizador corriendo (el FrameAnimation solo
// corre mientras `active`). Wayland solo entrega el DnD a la superficie bajo el cursor, por
// eso las bandas de input existen únicamente mientras dura el arrastre.
Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        readonly property bool busy: pRight.phase !== "idle" || pTop.phase !== "idle" || pTop2.phase !== "idle"
        // v2.17 (Olimpo): a quién se puede mandar (móvil, tablet…). Con dos o más, un agujero por dispositivo.
        property var destinos: []
        readonly property bool dos: destinos.length >= 2
        property var topActual: pTop
        function topEn(x: real): var {
            return dos && x > width / 2 ? pTop2 : pTop;
        }
        readonly property bool active: DragWatch.dragging || grace.running || busy || show > 0.002
        readonly property real lx: DragWatch.cx - screen.x
        readonly property real ly: DragWatch.cy - screen.y
        readonly property bool here: lx >= 0 && ly >= 0 && lx <= width && ly <= height
        readonly property real u: width / 1280
        readonly property real band: 140 * u
        readonly property real along: 0.62
        property string olimpo: ""
        property real movilMax: 50 * 1048576   // límite por defecto; `olimpo enviar --limites` lo afina
        property real movilLibre: -1
        property string teleTarget: ""
        property string teleErr0: ""
        property bool teleRunDone: false
        property real teleT0: 0
        property bool cancelled: false
        property bool triedProgreso: false
        property bool sawJson: false
        property var finalMsg: null
        property string sendPath: ""
        property bool warpSending: false
        property bool teleExternalSending: false
        readonly property var mediaExt: ["mp4", "m4v", "mkv", "webm", "avi", "mov", "ts", "mpg", "mpeg", "wmv", "flv", "ogv", "mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "mka"]
        // 0..1 aparición global. Entra con muelle (ease-out) y sale acelerando (~380 ms); es
        // estado continuo, así que invertir a mitad no produce saltos.
        property real show: 0
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
        function fmtSize(b: real): string {
            if (b >= 1073741824)
                return (b / 1073741824).toFixed(1).replace(".", ",") + " GB";
            if (b >= 1048576)
                return (b / 1048576).toFixed(b >= 10485760 ? 0 : 1).replace(".", ",") + " MB";
            return Math.max(1, Math.round(b / 1024)) + " KB";
        }
        function fmtEta(sec: real): string {
            const t = Math.max(0, Math.round(sec));
            return Math.floor(t / 60) + ":" + (t % 60 < 10 ? "0" : "") + (t % 60);
        }
        function baseName(path: string): string {
            const n = path.split("/").pop() || path;
            return decodeURIComponent(n.split("?")[0]);
        }
        function notify(ok: bool, title: string, body: string): void {
            Quickshell.execDetached(["notify-send", "-a", "Portales", "-u", ok ? "normal" : "critical", "-i", ok ? "emblem-ok-symbolic" : "dialog-error-symbolic", title, body]);
        }

        // Aviso previo a soltar: nombre, tamaño y si cabe / se puede reproducir
        function inspect(portal, drag): void {
            if (portal.edge === "top" && !drag.hasUrls && drag.hasText) {   // Warp: texto suelto
                portal.fileName = "Texto";
                portal.bad = "";
                portal.fileLine = "Texto · " + drag.text.length + " caracteres";
                return;
            }
            let t = "";
            if (drag.hasUrls && drag.urls.length > 0)
                t = Cast.normalizeTarget(drag.urls[0].toString());
            else if (drag.hasText)
                t = Cast.normalizeTarget(drag.text);
            if (!t)
                return;
            portal.fileName = baseName(t);
            portal.bad = "";
            portal.fileLine = portal.fileName.length > 38 ? portal.fileName.substring(0, 35) + "…" : portal.fileName;
            if (t.startsWith("http://") || t.startsWith("https://"))
                return;
            if (portal.edge === "right") {
                const ext = (portal.fileName.split(".").pop() || "").toLowerCase();
                if (!mediaExt.includes(ext))
                    portal.bad = "No se puede reproducir en la tele" + (ext && ext !== portal.fileName.toLowerCase() ? " · ." + ext : "");
            }
            statProc.portal = portal;
            statProc.command = ["stat", "-L", "-c", "%s", t];
            statProc.running = true;
        }
        function clearInfo(): void {
            for (const p of [pRight, pTop, pTop2]) {
                if (p.phase === "idle" || p.phase === "ok") {
                    p.bad = "";
                    p.fileLine = "";
                    p.over = false;
                    p.customKicker = "";
                    p.customTitle = "";
                    p.tIcon = "";
                }
            }
        }

        function tick(dtRaw: real): void {
            const dt = Math.min(0.05, dtRaw);
            const on = DragWatch.dragging && here;
            if (on || busy)
                show = Math.min(1, show + (1 - show) * (1 - Math.pow(0.0004, dt)) + 0.0005);
            else
                show = Math.max(0, show - dt / 0.38 * (0.35 + 1.9 * (1 - show)));
            const ps = dos ? [pRight, pTop, pTop2] : [pRight, pTop];
            let armedAny = null;
            for (const p of ps) {
                let target = 0;
                const d = p.edge === "right" ? width - lx : ly;
                const al = p.edge === "right" ? Math.abs(ly - height / 2) / (height / 2) : Math.abs(lx - width * p.posX) / (width / 2);
                if (on) {
                    target = sm(width * 0.55, width * 0.11, d) * (1 - 0.45 * sm(0.55, 1, al));
                    p.over = d < band && al < along && (p.edge === "right" || topEn(lx) === p);
                    p.armed = p.over && p.bad === "";
                    if (p.armed)
                        armedAny = p;
                } else if (!busy) {
                    p.armed = false;
                    p.over = false;
                }
                if (p.armed || p.over)
                    target = 1;
                if (p.phase === "sending")
                    target = 0.4;
                else if (p.phase === "ok" || p.phase === "error")
                    target = 1;
                p.e = lerp(p.e, target, 1 - Math.pow(0.0009, dt));
            }
            for (const p of ps) {
                p.dim = lerp(p.dim, armedAny && armedAny !== p ? 1 : 0, 1 - Math.pow(0.002, dt));
                const Rt = (30 + 26 * sm(0, 0.9, p.e) + (p.hot ? 16 : 0)) * u;
                p.r = lerp(p.r, Rt, 1 - Math.pow(0.0005, dt));
                const out = lerp(-p.r * 1.4, 0, show);
                if (p.edge === "right") {
                    p.cx = width - out;
                    p.cy = height / 2;
                } else {
                    p.cx = width * p.posX;
                    p.cy = out;
                }
                p.vis = show * (1 - 0.55 * p.dim);
                p.spinPhase += (0.25 * (0.3 + 0.7 * show)) * (1 + 1.4 * p.e + (p.armed ? 1 : 0)) * (p.over && p.bad !== "" ? 0.3 : 1) * dt;
                p.pullPhase += (0.35 + 1.5 * p.e + (p.armed ? 0.8 : 0) + (p.phase === "sending" ? 0.5 : 0)) * (0.2 + 0.8 * show) * dt;
                p.phaseT += dt;
                p.pulse = Math.max(0, p.pulse - dt / 0.48);
            }

            // Tele: sigue el estado del helper (preparing -> BUFFERING -> PLAYING / error)
            if (pRight.phase === "sending" && teleTarget) {
                const nm = Cast.selectedDevice?.name ?? "la tele";
                const act = Cast.active;
                if (Cast.error && Cast.error !== teleErr0) {
                    finishTransfer(pRight, false, Cast.error);
                } else if (Date.now() - teleT0 > 120000) {
                    finishTransfer(pRight, false, "Tiempo agotado cargando en " + nm);
                } else if (act && act.source === teleTarget && act.state === "PLAYING" && !act.preparing) {
                    finishTransfer(pRight, true, "Reproduciendo en " + nm);
                } else if (Cast.preparing) {
                    pRight.tText = "Preparando…";
                } else if (act && act.source === teleTarget) {
                    pRight.tText = "Cargando en " + nm + "…";
                } else if (teleRunDone) {
                    pRight.tText = "Cargando en " + nm + "…";
                }
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
                    it.rotation = Math.atan2(f.vy, f.vx) * 180 / Math.PI;
                    it.opacity = Math.max(0, Math.min(1, f.a));
                    it.fragColor = f.c ? Colours.palette.m3tertiary : Colours.palette.m3primary;
                } else {
                    it.opacity = 0;
                }
            }
        }

        function finishTransfer(portal, ok: bool, msg: string, quiet): void {
            const name = portal.tName;
            portal.phase = ok ? "ok" : "error";
            portal.status = msg;
            portal.tText = msg;
            portal.tSub = "";
            if (ok) {
                portal.tProgress = 1;
                portal.pulse = 1;
            }
            teleTarget = portal === pRight ? "" : teleTarget;
            retract.interval = ok ? 2600 : 6500;
            retract.restart();
            if (!quiet)
                notify(ok, msg, name);
        }

        function sendTele(t: string): void {
            pRight.phase = "sending";
            pRight.tName = baseName(t);
            pRight.tProgress = -1;
            pRight.tSub = "";
            pRight.tText = "Preparando…";
            if (!Cast.selectedDevice) {
                finishTransfer(pRight, false, "Sin Chromecast disponible");
                return;
            }
            Cast.cmdError = "";
            teleErr0 = Cast.error;
            teleTarget = t;
            teleRunDone = false;
            teleT0 = Date.now();
            Cast.run(["cast", Cast.selectedDevice.uuid, t], code => {
                if (code !== 0 || Cast.cmdError) {
                    if (pRight.phase === "sending")
                        win.finishTransfer(pRight, false, Cast.cmdError || "Error al enviar");
                } else {
                    win.teleRunDone = true;
                }
            });
        }

        function sendMovil(t: string, portal): void {
            const pt = portal ?? pTop;
            topActual = pt;
            if (!olimpo) {
                pt.phase = "error";
                pt.tName = baseName(t);
                finishTransfer(pt, false, "Olimpo no está instalado");
                return;
            }
            pt.phase = "sending";
            pt.tName = baseName(t);
            pt.tProgress = -1;
            pt.tText = "Enviando…";
            pt.tSub = "";
            sendPath = t;
            cancelled = false;
            triedProgreso = true;
            sawJson = false;
            finalMsg = null;
            olimpoProc.command = [olimpo, "enviar", "--json", "--progreso"].concat(pt.destino ? ["--a", pt.destino] : []).concat([t]);
            olimpoProc.running = true;
        }

        function onOlimpoLine(line: string): void {
            let d;
            try {
                d = JSON.parse(line);
            } catch (e) {
                return;
            }
            sawJson = true;
            if (d.ok !== undefined) {
                finalMsg = d;
                return;
            }
            if (typeof d.progreso === "number") {
                const pr = Math.max(0, Math.min(1, d.progreso > 1 ? d.progreso / 100 : d.progreso));
                topActual.tProgress = pr;
                topActual.tText = Math.round(pr * 100) + " %" + (d.velocidad > 0 ? " · " + fmtSize(d.velocidad) + "/s" : "");
                topActual.tSub = d.total ? fmtSize(d.enviados ?? pr * d.total) + " / " + fmtSize(d.total) + (d.velocidad > 0 ? " · " + fmtEta((d.total - (d.enviados ?? pr * d.total)) / d.velocidad) : "") : "";
            }
        }

        function cancelTransfer(portal): void {
            if (portal.phase !== "sending")
                return;
            if (portal === pTop || portal === pTop2) {
                cancelled = true;
                olimpoProc.signal(15);
                finishTransfer(portal, false, "Envío cancelado");
            } else {
                teleTarget = "";
                teleExternalSending = false;
                teleWatchdog.stop();
                Cast.stop();
                finishTransfer(pRight, false, "Reproducción cancelada");
            }
        }

        function rejectDrop(portal): void {
            portal.phase = "error";
            portal.tName = portal.fileName;
            portal.tProgress = 0;
            finishTransfer(portal, false, portal.bad);
        }

        function startAbsorb(portal, fx, fy): void {
            const sx = fx ?? lx, sy = fy ?? ly;
            const a0 = Math.atan2(sy - portal.cy, sx - portal.cx);
            const r0 = Math.hypot(sx - portal.cx, sy - portal.cy);
            absorb = {
                p: portal,
                t: 0,
                a0: a0,
                r0: r0
            };
        }

        // Warp: el CLI anuncia sus envíos (enviando → ok | error). Los textos no se muestran ni se notifican
        // (pueden ser claves): solo «Texto · N caracteres».
        function onWarpLine(line: string): void {
            let d;
            try {
                d = JSON.parse(line);
            } catch (e) {
                return;
            }
            if (d.destino === "tele" || d.tipo === "spotify") {
                win.onTeleLine(line);
                return;
            }
            const nombre = d.tipo === "texto" ? "Texto · " + (d.fragmento ?? "").length + (d.fragmento?.length >= 140 ? "+" : "") + " caracteres" : (d.nombre ?? "Archivo");
            if (d.fase === "enviando") {
                if (pTop.phase === "sending")
                    return;   // ya hay un envío en curso en el portal: no se pisa
                retract.stop();
                pTop.phase = "sending";
                pTop.tName = nombre;
                pTop.tProgress = -1;
                pTop.tText = "Enviando…";
                pTop.tSub = d.origen && d.origen !== "terminal" ? "por " + d.origen : "";
                warpSending = true;
                icon.text = d.tipo === "texto" ? "content_paste" : "description";
                icon.color = Colours.palette.m3onSurface;
                if (d.origen !== "arrastre")
                    startAbsorb(pTop, width / 2 + 160 * u, height * 0.32);
            } else if ((d.fase === "ok" || d.fase === "error") && warpSending) {
                warpSending = false;
                pTop.tName = nombre;
                // una sola notificación aunque haya varias pantallas (cada una sigue salidas.jsonl)
                finishTransfer(pTop, d.fase === "ok", d.fase === "ok" ? "Enviado a tu móvil" : (d.mensaje || "No se pudo enviar"), modelData.name !== Quickshell.screens[0]?.name);
            }
        }

        Timer {
            id: teleWatchdog

            interval: 15000
            onTriggered: {
                if (pRight.phase === "sending" && win.teleExternalSending)
                    win.finishTransfer(pRight, false, "Tiempo agotado conectando con la tele");
            }
        }

        // Tele / Cast: salidas externas (Spotify Connect, Cast CLI, etc.)
        function onTeleLine(line: string): void {
            let d;
            try {
                d = JSON.parse(line);
            } catch (e) {
                return;
            }
            const esSpotify = d.tipo === "spotify";
            const nombre = d.nombre || (esSpotify ? "Música" : "Vídeo");
            if (d.fase === "enviando") {
                if (pRight.phase === "sending")
                    return;   // ya hay un envío en curso en el portal: no se pisa
                retract.stop();
                teleWatchdog.restart();
                pRight.customKicker = esSpotify ? "TELE · SPOTIFY" : "TELE";
                if (d.tele)
                    pRight.customTitle = d.tele;
                pRight.tIcon = esSpotify ? "music_note" : "cast";
                pRight.phase = "sending";
                pRight.tName = nombre;
                pRight.tProgress = -1;
                pRight.tText = esSpotify ? "Conectando con la tele…" : "Preparando…";
                pRight.tSub = d.artista ? d.artista : (esSpotify ? "Spotify Connect" : "");
                teleExternalSending = true;
                icon.text = esSpotify ? "music_note" : "movie";
                icon.color = esSpotify ? "#1db954" : Colours.palette.m3onSurface;
                startAbsorb(pRight, width * 0.5, height * 0.5);
            } else if ((d.fase === "ok" || d.fase === "error") && teleExternalSending) {
                teleExternalSending = false;
                teleWatchdog.stop();
                pRight.tName = nombre;
                const dev = d.tele || pRight.customTitle || pRight.title;
                const okMsg = esSpotify ? ("Sonando en " + dev) : ("Reproduciendo en " + dev);
                finishTransfer(pRight, d.fase === "ok", d.fase === "ok" ? okMsg : (d.mensaje || "No se pudo reproducir"), modelData.name !== Quickshell.screens[0]?.name);
            }
        }

        // Warp: texto soltado en el portal de arriba → `warp texto -` (por stdin)
        function sendText(texto: string): void {
            if (warpTextProc.running)
                return;
            warpTextProc.pending = texto;
            warpTextProc.running = true;
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
            Region {
                item: pRight.maskItem
            }
            Region {
                item: pTop.maskItem
            }
            Region {
                item: pTop2.maskItem
            }
        }

        onActiveChanged: {
            if (active && !olimpoCheck.running && olimpo === "")
                olimpoCheck.running = true;
            if (active && olimpo !== "" && !limitsProc.running) {
                limitsProc.command = [olimpo, "enviar", "--limites"];
                limitsProc.running = true;
            }
            if (active && olimpo !== "" && !dispProc.running) {
                dispProc.command = [olimpo, "enviar", "--dispositivos"];
                dispProc.running = true;
            }
            if (!active) {
                show = 0;
                frags = [];
                for (const p of [pRight, pTop, pTop2]) {
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
                pTop2.phase = "idle";
                clearInfo();
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

            command: ["sh", "-c", "for p in \"$HOME/.local/bin/olimpo\" \"$(command -v olimpo)\"; do [ -f \"$p\" ] && [ -x \"$p\" ] && echo \"$p\" && exit; done"]
            stdout: StdioCollector {
                onStreamFinished: {
                    win.olimpo = text.trim();
                    if (win.olimpo && win.active) {
                        limitsProc.command = [win.olimpo, "enviar", "--limites"];
                        limitsProc.running = true;
                    }
                }
            }
        }

        Process {
            id: dispProc

            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const d = JSON.parse(text);
                        if (d.ok)
                            win.destinos = d.dispositivos.filter(x => x.id !== "pc");
                    } catch (e) {}
                }
            }
        }

        Process {
            id: olimpoProc

            stdout: SplitParser {
                onRead: line => win.onOlimpoLine(line)
            }
            stderr: StdioCollector {
                id: olimpoErr
            }
            onRunningChanged: {
                // Si el binario no arranca, Process no emite exited: no dejar el portal en «Enviando…».
                if (!running && win.topActual.phase === "sending" && !win.cancelled)
                    olimpoWatchdog.restart();
            }
            onExited: code => {
                olimpoWatchdog.stop();
                if (win.cancelled)
                    return;
                if (code === 2 && win.triedProgreso && !win.sawJson && !win.finalMsg) {
                    // Esta versión de la CLI aún no tiene --progreso: reintenta sin él (indeterminado)
                    win.triedProgreso = false;
                    command = [win.olimpo, "enviar", "--json"].concat(win.topActual.destino ? ["--a", win.topActual.destino] : []).concat([win.sendPath]);
                    running = true;
                    return;
                }
                const r = win.finalMsg;
                if (r && r.ok === true)
                    win.finishTransfer(win.topActual, true, "Enviado a " + (win.topActual.destino ? win.topActual.kicker.toLowerCase() : "tu móvil"));
                else
                    win.finishTransfer(win.topActual, false, r?.error ?? (olimpoErr.text.trim().split("\n").pop() || "Olimpo no responde"));
            }
        }

        // Warp: salidas del CLI (cero coste en reposo: tail bloqueado)
        Process {
            command: ["sh", "-c", "d=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/warp\"; mkdir -p \"$d\"; exec tail -n 0 -F \"$d/salidas.jsonl\" 2>/dev/null"]
            running: true
            stdout: SplitParser {
                onRead: line => win.onWarpLine(line)
            }
        }

        // Tele / Cast: salidas externas (Spotify Connect, cast, etc.)
        Process {
            command: ["sh", "-c", "d=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/cast\"; mkdir -p \"$d\"; exec tail -n 0 -F \"$d/salidas.jsonl\" 2>/dev/null"]
            running: true
            stdout: SplitParser {
                onRead: line => win.onTeleLine(line)
            }
        }

        Process {
            id: warpTextProc

            property string pending: ""

            command: ["sh", "-c", "exec \"$HOME/.local/bin/warp\" texto - --json --origen arrastre"]
            stdinEnabled: true
            onStarted: {
                write(pending);
                stdinEnabled = false;
                pending = "";
            }
            onExited: code => {
                stdinEnabled = true;
                if (code !== 0 && !win.warpSending && pTop.phase === "idle") {
                    pTop.phase = "error";
                    pTop.tName = "Texto";
                    win.finishTransfer(pTop, false, "No se pudo lanzar «warp»");
                }
            }
        }

        Timer {
            id: olimpoWatchdog

            interval: 1500
            onTriggered: {
                if (win.topActual.phase === "sending" && !olimpoProc.running)
                    win.finishTransfer(win.topActual, false, "No se pudo lanzar «olimpo enviar»");
            }
        }

        // Tamaño del archivo arrastrado (para avisar antes de soltar)
        Process {
            id: statProc

            property var portal: null

            stdout: StdioCollector {
                onStreamFinished: {
                    const b = parseInt(text.trim());
                    const p = statProc.portal;
                    if (!p || isNaN(b))
                        return;
                    p.fileLine = p.fileName.length > 30 ? p.fileName.substring(0, 27) + "… · " + win.fmtSize(b) : p.fileName + " · " + win.fmtSize(b);
                    if (p.edge === "top") {
                        const mx = win.movilMax, libre = win.movilLibre;
                        if (b > mx)
                            p.bad = "Demasiado grande para el móvil · " + win.fmtSize(b) + " / máx. " + win.fmtSize(mx);
                        else if (libre >= 0 && b > libre)
                            p.bad = "No cabe en el móvil · " + win.fmtSize(b) + " / libre " + win.fmtSize(libre);
                    }
                }
            }
        }

        // Límites del móvil (cuando la CLI los exponga): {ok, archivo_max, libre}
        Process {
            id: limitsProc

            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const d = JSON.parse(text.trim().split("\n").pop());
                        if (d.archivo_max > 0)
                            win.movilMax = d.archivo_max;
                        if (d.libre >= 0)
                            win.movilLibre = d.libre;
                    } catch (e) {}
                }
            }
        }

        // Prueba de estados sin arrastrar: qs -c caelestia ipc call portals demo <bad|progress|tele|ok|error>
        IpcHandler {
            function demo(kind: string): void {
                if (kind === "bad") {
                    pTop.bad = "Demasiado grande para el móvil · 13,9 GB / máx. 50 MB";
                    pTop.fileLine = "Wicked Part Uno (2025).mkv · 13,9 GB";
                } else if (kind === "good") {
                    pTop.bad = "";
                    pTop.fileLine = "Atardecer Tarifa.jpg · 4,2 MB";
                    pRight.bad = "";
                    pRight.fileLine = "Wicked Part Uno (2025).mkv · 13,9 GB";
                } else if (kind === "progress") {
                    pTop.phase = "sending";
                    pTop.tName = "Apuntes Redes T4.pdf";
                    pTop.tProgress = 0.37;
                    pTop.tText = "37 % · 4,2 MB/s";
                    pTop.tSub = "18 / 49 MB · 0:07";
                } else if (kind === "tele") {
                    pRight.phase = "sending";
                    pRight.tName = "Wicked Part Uno (2025).mkv";
                    pRight.tProgress = -1;
                    pRight.tText = "Cargando en Гостиная…";
                } else if (kind === "spotify") {
                    win.onTeleLine(JSON.stringify({
                        fase: "enviando",
                        tipo: "spotify",
                        nombre: "Dakiti",
                        artista: "Bad Bunny",
                        tele: "Tele Salón"
                    }));
                } else if (kind === "spotifyOk") {
                    win.onTeleLine(JSON.stringify({
                        fase: "ok",
                        tipo: "spotify",
                        nombre: "Dakiti",
                        artista: "Bad Bunny",
                        tele: "Tele Salón"
                    }));
                } else if (kind === "ok") {
                    pTop.phase = "sending";
                    pTop.tName = "Apuntes Redes T4.pdf";
                    win.finishTransfer(pTop, true, "Enviado a tu móvil");
                } else if (kind === "error") {
                    pTop.phase = "sending";
                    pTop.tName = "Wicked Part Uno (2025).mkv";
                    win.finishTransfer(pTop, false, "Olimpo: archivo demasiado grande (límite 50 MB)");
                }
            }

            function teleEvent(jsonStr: string): void {
                win.onTeleLine(jsonStr);
            }

            target: "portals"
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
                    onEntered: drag => win.inspect(pRight, drag)
                    onExited: {
                        if (pRight.phase === "idle") {
                            pRight.bad = "";
                            pRight.fileLine = "";
                        }
                    }
                    onDropped: drop => {
                        const t = win.targetOf(drop);
                        if (!t || pRight.phase !== "idle")
                            return;
                        if (pRight.bad) {
                            win.rejectDrop(pRight);
                            return;
                        }
                        icon.text = "movie";
                        icon.color = Colours.palette.m3onSurface;
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
                    onEntered: drag => win.inspect(win.topEn(tBand.x + drag.x), drag)
                    onPositionChanged: drag => {
                        const p = win.topEn(tBand.x + drag.x);
                        if (p.fileLine === "")
                            win.inspect(p, drag);
                    }
                    onExited: {
                        for (const p of [pTop, pTop2])
                            if (p.phase === "idle") {
                                p.bad = "";
                                p.fileLine = "";
                            }
                    }
                    onDropped: drop => {
                        if (!drop.hasUrls && drop.hasText && pTop.phase === "idle") {   // Warp: texto
                            icon.text = "content_paste";
                            win.startAbsorb(pTop);
                            win.sendText(drop.text);
                            return;
                        }
                        const t = win.targetOf(drop);
                        const pt = win.topEn(tBand.x + drop.x);
                        if (!t || pt.phase !== "idle" || win.busy && win.topActual.phase === "sending")
                            return;
                        icon.text = "description";
                        if (pt.bad) {
                            win.rejectDrop(pt);
                            return;
                        }
                        win.startAbsorb(pt);
                        win.sendMovil(t, pt);
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
                onCancel: win.cancelTransfer(pRight)
            }

            Portal {
                id: pTop

                edge: "top"
                winW: win.width
                winH: win.height
                u: win.u
                posX: win.dos ? 0.36 : 0.5
                destino: win.dos ? win.destinos[0].id : ""
                kicker: win.dos ? win.destinos[0].nombre.toUpperCase() : "MÓVIL"
                title: "Olimpo"
                detail: win.dos ? "Solo a este dispositivo" : "Bandeja «Desde el PC»"
                cta: "Suelta para enviar"
                onCancel: win.cancelTransfer(pTop)
            }

            Portal {
                id: pTop2

                visible: win.dos
                edge: "top"
                posX: 0.64
                winW: win.width
                winH: win.height
                u: win.u
                destino: win.dos ? win.destinos[1].id : ""
                kicker: win.dos ? win.destinos[1].nombre.toUpperCase() : ""
                title: "Olimpo"
                detail: "Solo a este dispositivo"
                cta: "Suelta para enviar"
                onCancel: win.cancelTransfer(pTop2)
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

                    transformOrigin: Item.Right
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
