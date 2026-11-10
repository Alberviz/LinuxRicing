.pragma library

// HoloPlacer.js — Algoritmo de colocación y dimensiones para paneles holográficos.
// Todos los cálculos son deterministas si se proporciona una función generadora pseudo-aleatoria (rnd).

/**
 * Calcula el tamaño sugerido para un panel según su tipo y las dimensiones de pantalla.
 * @param {Object} panel - Objeto del panel con kind, payload, etc.
 * @param {number} W - Ancho de la pantalla.
 * @param {number} H - Alto de la pantalla.
 * @returns {{w: number, h: number}}
 */
function size(panel, W, H) {
    if (!panel) {
        return { w: Math.round(0.26 * W), h: Math.round(0.40 * H) };
    }

    if (panel.kind === "lista" || panel.id === "lista") {
        let count = 8;
        if (panel.itemCount !== undefined && typeof panel.itemCount === "number") {
            count = panel.itemCount;
        } else if (Array.isArray(panel.items)) {
            count = panel.items.length;
        } else if (panel.payload && Array.isArray(panel.payload.items)) {
            count = panel.payload.items.length;
        } else if (panel.payload && typeof panel.payload.n === "number") {
            count = panel.payload.n;
        }
        const w = Math.min(460, 0.32 * W);
        const h = 64 + 38 * count;
        return { w: Math.round(w), h: Math.round(h) };
    }

    if (panel.kind === "confirmar") {
        const n = (panel.payload && Array.isArray(panel.payload.items)) ? Math.max(1, panel.payload.items.length) : 1;
        const mas = (panel.payload && panel.payload.mas > 0) ? 22 : 0;
        return { w: 400, h: 46 + 74 + 26 * n + mas + 64 };
    }

    const tipo = (panel.payload && panel.payload.tipo) || panel.tipo || "otro";

    switch (tipo) {
    case "imagen": {
        const pw = (panel.payload && panel.payload.w) || 0;
        const ph = (panel.payload && panel.payload.h) || 0;
        const maxW = 0.26 * W;
        const maxH = 0.54 * H;
        if (pw > 0 && ph > 0) {
            const aspect = pw / ph;
            if (maxW / maxH > aspect) {
                return { w: Math.round(maxH * aspect), h: Math.round(maxH) };
            } else {
                return { w: Math.round(maxW), h: Math.round(maxW / aspect) };
            }
        }
        return { w: Math.round(0.26 * W), h: Math.round(0.50 * H) };
    }
    case "pdf":
        return { w: Math.round(0.24 * W), h: Math.round(0.66 * H) };
    case "texto":
        return { w: Math.round(0.27 * W), h: Math.round(0.42 * H) };
    case "video":
        return { w: Math.round(0.40 * W), h: Math.round(0.45 * H) };
    case "audio":
        return { w: Math.round(0.30 * W), h: Math.round(0.16 * H) };
    case "agenda": {
        const dias = (panel.payload && panel.payload.dias) || [];
        if (panel.payload && panel.payload.vista === "semana")
            return { w: Math.round(Math.min(0.5 * W, 980)), h: Math.round(0.42 * H) };
        const n = dias.length ? (dias[0].eventos || []).length : 0;
        return { w: Math.round(Math.min(0.24 * W, 460)), h: Math.round(Math.min(0.62 * H, 46 + 32 + Math.max(2, n) * 58)) };
    }
    case "tareas":
    case "correo": {
        const n = (panel.payload && panel.payload.items) ? panel.payload.items.length : 3;
        return { w: Math.round(Math.min(0.28 * W, 520)), h: Math.round(Math.min(0.66 * H, 46 + 20 + n * 70)) };
    }
    case "otro":
    default:
        return { w: Math.round(0.22 * W), h: Math.round(0.20 * H) };
    }
}

/**
 * Coloca un panel holográfico sin solaparse con los paneles existentes ni con la píldora.
 * @param {number} W - Ancho de pantalla.
 * @param {number} H - Alto de pantalla.
 * @param {Array<{x: number, y: number, w: number, h: number}>} ocupados - Rectángulos ya ocupados.
 * @param {number} w - Ancho del panel a colocar.
 * @param {number} h - Alto del panel a colocar.
 * @param {Function} [rnd] - Generador aleatorio 0..1 (opcional, por defecto Math.random).
 * @returns {{x: number, y: number, rot: number}}
 */
function place(W, H, ocupados, w, h, rnd) {
    const random = typeof rnd === "function" ? rnd : Math.random;
    const margin = 48;
    const gap = 24;

    // Obstáculo de la píldora de Laura: centrada abajo, 30% ancho x 12% alto
    const pillW = 0.30 * W;
    const pillH = 0.12 * H;
    const pill = {
        x: (W - pillW) / 2,
        y: H - pillH,
        w: pillW,
        h: pillH
    };

    const allObstacles = (ocupados || []).slice();
    let hasPill = false;
    for (let i = 0; i < allObstacles.length; i++) {
        const ob = allObstacles[i];
        if (Math.abs(ob.x - pill.x) < 1 && Math.abs(ob.y - pill.y) < 1) {
            hasPill = true;
            break;
        }
    }
    if (!hasPill) {
        allObstacles.push(pill);
    }

    // Rejilla de muestreo 12x8
    const cols = 12;
    const rows = 8;
    const usableW = W - 2 * margin;
    const usableH = H - 2 * margin;
    const cellW = usableW / cols;
    const cellH = usableH / rows;

    const candidates = [];
    const seen = {};

    function addCandidate(cx, cy) {
        const rx = Math.round(cx);
        const ry = Math.round(cy);
        const key = `${rx},${ry}`;
        if (!seen[key] && rx >= margin && ry >= margin && rx + w <= W - margin && ry + h <= H - margin) {
            seen[key] = true;
            candidates.push({ x: rx, y: ry });
        }
    }

    // 1. Probar esquinas de celdas de la rejilla 12x8
    for (let c = 0; c < cols; c++) {
        for (let r = 0; r < rows; r++) {
            addCandidate(margin + c * cellW, margin + r * cellH);
        }
    }

    // 2. Asegurar opciones alineadas a los bordes derecho e inferior utilizables
    for (let c = 0; c < cols; c++) {
        addCandidate(margin + c * cellW, H - margin - h);
    }
    for (let r = 0; r < rows; r++) {
        addCandidate(W - margin - w, margin + r * cellH);
    }
    addCandidate(W - margin - w, H - margin - h);

    // 3. Opciones adyacentes a obstáculos existentes (con holgura gap)
    for (let i = 0; i < allObstacles.length; i++) {
        const ob = allObstacles[i];
        for (let r = 0; r < rows; r++) {
            addCandidate(ob.x + ob.w + gap, margin + r * cellH);
            addCandidate(ob.x - w - gap, margin + r * cellH);
        }
        for (let c = 0; c < cols; c++) {
            addCandidate(margin + c * cellW, ob.y + ob.h + gap);
            addCandidate(margin + c * cellW, ob.y - h - gap);
        }
    }

    // Si por algún motivo ninguna cabe dentro del margen (panel muy grande), relajar margen
    if (candidates.length === 0) {
        candidates.push({
            x: Math.max(0, Math.round((W - w) / 2)),
            y: Math.max(0, Math.round((H - h) / 2))
        });
    }

    let best = null;
    let bestScore = -Infinity;
    let leastOverlap = Infinity;
    let fallback = null;

    for (let i = 0; i < candidates.length; i++) {
        const cand = candidates[i];
        let hit = false;
        let minDist = Infinity;
        let totalOverlap = 0;

        for (let j = 0; j < allObstacles.length; j++) {
            const ob = allObstacles[j];

            // Comprobación de intersección con separación de 24 px
            const collides = (
                cand.x - gap < ob.x + ob.w &&
                cand.x + w + gap > ob.x &&
                cand.y - gap < ob.y + ob.h &&
                cand.y + h + gap > ob.y
            );

            if (collides) {
                hit = true;
                const ox1 = Math.max(cand.x - gap, ob.x);
                const ox2 = Math.min(cand.x + w + gap, ob.x + ob.w);
                const oy1 = Math.max(cand.y - gap, ob.y);
                const oy2 = Math.min(cand.y + h + gap, ob.y + ob.h);
                if (ox2 > ox1 && oy2 > oy1) {
                    totalOverlap += (ox2 - ox1) * (oy2 - oy1);
                }
            }

            // Distancia mínima Euclídea hacia el obstáculo
            const dx = Math.max(0, Math.max(ob.x - (cand.x + w), cand.x - (ob.x + ob.w)));
            const dy = Math.max(0, Math.max(ob.y - (cand.y + h), cand.y - (ob.y + ob.h)));
            const d = Math.hypot(dx, dy);
            if (d < minDist) {
                minDist = d;
            }
        }

        if (!hit) {
            // Puntuación: agrupar los hologramas de forma orgánica alrededor del centro
            // (cerca, pero con aire), con azar suficiente para que nunca caigan igual.
            const cx = cand.x + w / 2 - W / 2;
            const cy = cand.y + h / 2 - H * 0.44;
            const centro = Math.hypot(cx, cy * 1.4);
            const aire = Math.min(minDist, 90);
            const score = aire * 0.6 - centro * 0.22 + random() * 150;
            if (score > bestScore) {
                bestScore = score;
                best = cand;
            }
        } else {
            if (totalOverlap < leastOverlap) {
                leastOverlap = totalOverlap;
                fallback = cand;
            }
        }
    }

    // Sin hueco en la rejilla gruesa: barrido fino (cada 16 px) antes de aceptar un solape
    if (!best) {
        let mejorHueco = -Infinity;
        for (let y = margin; y + h <= H - margin; y += 16) {
            for (let x = margin; x + w <= W - margin; x += 16) {
                let libre = true;
                let minD = Infinity;
                for (let j = 0; j < allObstacles.length; j++) {
                    const ob = allObstacles[j];
                    if (x - gap < ob.x + ob.w && x + w + gap > ob.x && y - gap < ob.y + ob.h && y + h + gap > ob.y) {
                        libre = false;
                        break;
                    }
                    const dx = Math.max(0, Math.max(ob.x - (x + w), x - (ob.x + ob.w)));
                    const dy = Math.max(0, Math.max(ob.y - (y + h), y - (ob.y + ob.h)));
                    minD = Math.min(minD, Math.hypot(dx, dy));
                }
                if (!libre)
                    continue;
                const s = Math.min(minD, 90) * 0.6 - Math.hypot(x + w / 2 - W / 2, (y + h / 2 - H * 0.44) * 1.4) * 0.22 + random() * 150;
                if (s > mejorHueco) {
                    mejorHueco = s;
                    best = { x: x, y: y };
                }
            }
        }
    }

    const chosen = best || fallback || candidates[0];
    // Giro leve (±1,3°): suelto como un holograma, pero sin emborronar el texto
    const rot = (random() * 2.6 - 1.3);

    return {
        x: chosen.x,
        y: chosen.y,
        rot: rot,
        libre: !!best
    };
}
