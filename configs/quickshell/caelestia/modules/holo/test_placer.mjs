// test_placer.mjs — Prueba qml-free de HoloPlacer.js
// Verifica que 8 colocaciones consecutivas en 2560x1440 no se solapan entre sí ni con la píldora.

import fs from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Leer HoloPlacer.js y omitir la directiva .pragma library de QML
const rawCode = fs.readFileSync(join(__dirname, "HoloPlacer.js"), "utf8");
const cleanCode = rawCode.replace(/^\s*\.pragma\s+library\s*/m, "");

const sandbox = { console, Math };
vm.createContext(sandbox);
vm.runInContext(cleanCode, sandbox);

const { place, size } = sandbox;

if (typeof place !== "function" || typeof size !== "function") {
    console.error("ERROR: No se pudieron cargar las funciones place y size desde HoloPlacer.js");
    process.exit(1);
}

const W = 2560;
const H = 1440;
const margin = 48;

// Píldora de Laura: centrada abajo, 30% ancho x 12% alto
const pillW = 0.30 * W;
const pillH = 0.12 * H;
const pill = {
    x: (W - pillW) / 2,
    y: H - pillH,
    w: pillW,
    h: pillH
};

// Generador pseudo-aleatorio determinista para pruebas reproducibles
let seed = 42;
const SEMILLAS = [1, 7, 42, 99, 123, 555, 1000, 4242];
function prng() {
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
}

// lista + 4 visores con dimensiones realistas representativas de los paneles holográficos
const panelesTest = [
    { tipo: "lista", kind: "lista", itemCount: 8 },
    { tipo: "imagen", payload: { tipo: "imagen", w: 520, h: 380 } },
    { tipo: "texto", payload: { tipo: "texto" }, w: 480, h: 320 },
    { tipo: "otro", payload: { tipo: "otro" } }, // ~563x288
    { tipo: "audio", payload: { tipo: "audio" } } // ~768x230
];

function correr(semilla) {
    seed = semilla;
    const ocupados = [];
    const resultados = [];

    for (let i = 0; i < panelesTest.length; i++) {
        const p = panelesTest[i];
        let w, h;
        if (i === 0 && p.kind === "lista") {
            const sz = size(p, W, H);
            w = sz.w;
            h = sz.h;
            const lx = Math.round(0.08 * W);
            const ly = Math.round((H - h) / 2);
            ocupados.push({ x: lx, y: ly, w, h });
            resultados.push({ id: "lista", x: lx, y: ly, w, h, rot: 0 });
            continue;
        }

        if (p.w && p.h) {
            w = p.w;
            h = p.h;
        } else {
            const sz = size(p, W, H);
            w = sz.w;
            h = sz.h;
        }

        const pos = place(W, H, ocupados, w, h, prng);
        ocupados.push({ x: pos.x, y: pos.y, w, h });
        resultados.push({ id: `p${i}`, x: pos.x, y: pos.y, w, h, rot: pos.rot });
    }


    function interseccion(a, b) {
        return (
            a.x < b.x + b.w &&
            a.x + a.w > b.x &&
            a.y < b.y + b.h &&
            a.y + a.h > b.y
        );
    }

    let errores = 0;

    for (let i = 0; i < ocupados.length; i++) {
        const a = ocupados[i];

        // Verificar límites de pantalla considerando margen
        if (a.x < margin || a.y < margin || a.x + a.w > W - margin || a.y + a.h > H - margin) {
            console.error(`ERROR: Panel ${i} se sale de los márgenes:`, a);
            errores++;
        }

        // Verificar colisión con la píldora
        if (interseccion(a, pill)) {
            console.error(`ERROR: Panel ${i} colisiona con la píldora:`, a, pill);
            errores++;
        }

        // Verificar colisión con los otros paneles
        for (let j = i + 1; j < ocupados.length; j++) {
            const b = ocupados[j];
            if (interseccion(a, b)) {
                console.error(`ERROR: Colisión entre panel ${i} y panel ${j}:`, a, b);
                errores++;
            }
        }
    }

    return errores;

}

console.log(`Verificando ${panelesTest.length} colocaciones en ${W}x${H} con ${SEMILLAS.length} semillas...`);
let total = 0;
for (const s of SEMILLAS) {
    const e = correr(s);
    if (e) console.error(`  semilla ${s}: ${e} errores`);
    total += e;
}
const sc = size({ kind: "confirmar", payload: { items: [1, 2, 3], mas: 0 } }, W, H);
if (sc.w !== 400 || sc.h !== 46 + 74 + 78 + 64) {
    console.error("ERROR: tamaño del panel de confirmación", sc);
    total++;
}
if (total === 0) {
    console.log("OK: sin solapes ni colisión con la píldora en ninguna semilla.");
    process.exit(0);
}
console.error(`FALLO: ${total} errores de colocación.`);
process.exit(1);
