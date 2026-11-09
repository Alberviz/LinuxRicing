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

    const tipo = (panel.payload && panel.payload.tipo) || panel.tipo || "otro";

    switch (tipo) {
    case "imagen": {
        const pw = (panel.payload && panel.payload.w) || 0;
        const ph = (panel.payload && panel.payload.h) || 0;
        const maxW = 0.30 * W;
        const maxH = 0.62 * H;
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
        return { w: Math.round(0.30 * W), h: Math.round(0.74 * H) };
    case "texto":
        return { w: Math.round(0.34 * W), h: Math.round(0.56 * H) };
    case "video":
        return { w: Math.round(0.40 * W), h: Math.round(0.45 * H) };
    case "audio":
        return { w: Math.round(0.30 * W), h: Math.round(0.16 * H) };
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
            // Puntuación: distancia mínima + rnd() * 80
            const score = minDist + random() * 80;
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

    const chosen = best || fallback || candidates[0];
    const rot = (random() * 4 - 2);

    return {
        x: chosen.x,
        y: chosen.y,
        rot: rot
    };
}
