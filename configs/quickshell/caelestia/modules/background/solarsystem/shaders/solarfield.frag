#version 440

// solarfield.frag — TODO el fondo del sistema solar v3 (variante D) en la GPU.
//
// Renderiza per-píxel: fondo negro + tinte del disco + campo de estrellas
// procedural (con las cercanas al agujero estiradas en arcos por la lente) +
// resplandor exterior + agujero negro completo (spec §4.1) + los dos soles
// (fotosfera, granulación procedural, cromosfera, corona, prominencias sólo en
// Laura). NO dibuja satélites / cinturón / órbitas: eso es una capa QML fina
// encima (la lleva SolarSystem.qml).
//
// Modo Laura activa (`focusAmt` 0→1): el motor congela `time`; este shader oscurece
// TODO a ~0.18 salvo el sol de Laura, cuya corona/brillo escala con `focusAmt` y
// late con `lauraAmp`.
//
// El cuerpo (entre ===SHADER BODY===) se mantiene idéntico al del harness
// docs/sistema-solar-v3-mockup/harness-blackhole.html (allí con header GLSL ES).
//
// Compilar:  /usr/lib/qt6/bin/qsb --qt6 -o solarfield.frag.qsb solarfield.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;

    float time;         // s (el motor lo congela con focusAmt)
    float music;        // 0..1
    float focusAmt;        // 0..1  (0 normal · 1 foco-Laura: todo oscuro salvo Laura)
    float lauraAmp;     // 0..1  nivel de voz en vivo

    float bhRadius;     // px — radio del horizonte
    float bhSpin;       // rad — giro acumulado del disco (Doppler/beaming)
    float bhTilt;       // rad — inclinación del disco (≈ -0.489)

    float sun0Radius;   // px — Configuración (secundario)
    float sun1Radius;   // px — Laura (primario)

    vec2  resolution;   // px — tamaño del Item (pantalla)
    vec2  bhCenter;     // px — centro del agujero (puede caer fuera de cuadro)
    vec2  binBary;      // px — baricentro del binario (fijo)
    vec2  binSemiAxes;  // px — (aConf, aLaura)
    float binEcc;       // excentricidad
    float binTilt;      // rad — inclinación
    float binOmega;     // 2*PI / periodo

    vec2  beltCenter;  // px — baricentro del binario (fijo)
    vec2  beltRadii;   // px — (rx, ry) de la elipse del cinturón de tareas
    float beltTilt;    // rad
    float beltSpin;    // rad — giro acumulado (derivado de time)
    float beltDensity; // 0..1 — crece con el nº de tareas
    float musicProgress; // 0..1 — progreso de la canción activa (0 = sin canción)
    float musicPulse;    // 0..1 — detector de golpe/beat, decae solo (viene ya envuelto)
    float musicBass;     // 0..1 — energía de graves (desplaza temperatura a rojo)
    float musicTreble;   // 0..1 — energía de agudos (desplaza temperatura a blanco/azul)
    float musicBurstAge; // s — segundos desde último golpe (para ráfagas de acreción)

    vec4  colPrimary;   // rol m3primary  (disco, Configuración)
    vec4  colLaura;     // rol m3tertiaryFixedDim (Laura)
    vec4  colError;     // rol m3error    (borde exterior del disco)
    vec4  colVoid;      // horizonte de sucesos (darker(m3surface,3))
    vec4  colInk;       // rol m3onSurface (estrellas)
    vec4  colBelt;      // rol m3outlineVariant (cinturón)
};

// ===SHADER BODY===
const float PI  = 3.14159265359;
const float TAU = 6.28318530718;

vec3 lit(vec3 c, float k){ return mix(c, vec3(1.0), k); }
vec3 dk (vec3 c, float k){ return c * (1.0 - k); }

float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
vec2  hash22(vec2 p){
    float n = sin(dot(p, vec2(41.0, 289.0)));
    return fract(vec2(262144.0, 32768.0)*n);
}
float vnoise(vec2 p){
    vec2 i = floor(p), f = fract(p);
    vec2 u = f*f*(3.0-2.0*f);
    float a = hash21(i), b = hash21(i+vec2(1,0));
    float c = hash21(i+vec2(0,1)), d = hash21(i+vec2(1,1));
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}
float fbm(vec2 p){
    // 3 octavas: turbulencia del disco / granulación de los soles. Una cuarta
    // octava no se distingue a este tamaño y cuesta un tercio más de ruido.
    float s = 0.0, a = 0.5;
    for(int i=0;i<3;i++){ s += a*vnoise(p); p = p*2.03 + 7.1; a *= 0.5; }
    return s;
}

// over-composite premultiplicado
void over(inout vec4 acc, vec3 lc, float la){
    la = clamp(la, 0.0, 1.0);
    acc.rgb += lc * la * (1.0 - acc.a);
    acc.a   += la * (1.0 - acc.a);
}

// ------------------------------------------------------------------ estrellas
// Campo de estrellas por celdas hash. Las que caen a 0.95R..1.9R del agujero
// se dibujan como arcos cortos centrados en él (lente), no como puntos.
void starfield(inout vec4 acc, vec2 frag, vec2 bhC, float R, vec3 ink){
    vec3 sc = lit(ink, 0.45);
    float cell = 54.0;
    vec2 g = frag / cell;
    vec2 id = floor(g);
    // ¿Está este píxel en la zona donde la lente curva las estrellas? Fuera de
    // ella todas las estrellas van por la rama barata (un punto), sin los dos
    // atan por estrella. Cerca del agujero apenas hay estrellas de fondo, así
    // que esto no se nota.
    // 3x3 vecindario para no cortar estrellas en el borde de celda
    for (int oy=-1; oy<=1; oy++)
    for (int ox=-1; ox<=1; ox++){
        vec2 cid = id + vec2(ox, oy);
        vec2 rnd = hash22(cid);
        if (rnd.x > 0.40) continue;                  // densidad
        vec2 spos = (cid + hash22(cid+3.7)) * cell;  // posición de la estrella
        float b = fract(rnd.y * 91.7);               // brillo
        float d = distance(spos, bhC);

        // Ocluir estrellas que caigan dentro de la silueta del horizonte
        if (d < R * 1.03) continue;

        float pr = distance(frag, spos);
        float s  = b < 0.7 ? 0.9 : 1.7;
        float pt = smoothstep(s, 0.0, pr);
        over(acc, sc, pt * (0.14 + b*0.55));
    }
}

// ------------------------------------------------------------------ cinturón de tareas
// Anillo de polvo circumbinario alrededor del baricentro FIJO (spec §2.4 — muy
// tenue). Procedural, sin bucle de partículas: banda elíptica con grumos de
// ruido que gira lento. Coordenadas continuas (cos/sin del azimut girado), nada
// de `atan` crudo — dejaría un radio-costura. Gateado: fuera de la banda, sale.
void belt(inout vec4 acc, vec2 frag, vec2 c, vec2 rad, float tilt, float spin,
          float density, vec3 col)
{
    if (density <= 0.001) return;
    vec2 rel = frag - c;
    float ct = cos(-tilt), st = sin(-tilt);
    vec2 p  = vec2(rel.x*ct - rel.y*st, rel.x*st + rel.y*ct);
    vec2 q  = vec2(p.x / max(rad.x, 1.0), p.y / max(rad.y, 1.0));
    float rr = length(q);
    float bandv = smoothstep(0.34, 0.02, abs(rr - 1.0));    // hilo fino alrededor de rr≈1
    if (bandv <= 0.001) return;
    // dirección unitaria GIRADA por el spin → al recorrer el anillo traza un
    // círculo en el espacio de ruido: variación suave, sin púas ni costura.
    float cs = cos(spin), sn = sin(spin);
    vec2 d = vec2(q.x*cs - q.y*sn, q.x*sn + q.y*cs) / max(rr, 1e-3);
    float n1 = fbm(vec2(d.x*6.0, d.y*6.0));
    float n2 = fbm(vec2(d.x*17.0 + 3.1, d.y*17.0 - 1.7));
    // perfil radial suave (más denso en el centro del hilo) + grumos de polvo
    float radial = exp(-pow((rr - 1.0) / 0.16, 2.0));
    float dust = radial * (0.30 + 0.70*n1) * (0.35 + 0.65*n2);
    over(acc, lit(col, 0.42), dust * density * 0.085);
}

// ------------------------------------------------------------------ función de muestreo de disco de acreción (Gargantua)
vec4 sampleDisk(float rD, float phi, float approach,
                float time, float music, float musicProgress,
                float musicPulse, float musicBass, float musicTreble,
                float musicBurstAge, vec3 colP, vec3 colE)
{
    float rHorizon = 1.00; // Horizonte de sucesos
    float rISCO    = 1.18; // Radio interior orbital estable (ISCO)
    float rOuter   = 2.90; // Radio exterior del disco con disolución sedosa

    if (rD < rHorizon || rD > rOuter) return vec4(0.0);

    // Fracción en el disco principal estable [0.0 en ISCO, 1.0 en rOuter]
    float fN = clamp((rD - rISCO) / (rOuter - rISCO), 0.0, 1.0);

    // Fracción en la zona de caída en picado (plunging region) [0.0 en horizonte, 1.0 en ISCO]
    float plunge = clamp((rD - rHorizon) / (rISCO - rHorizon), 0.0, 1.0);

    // Corrimiento al rojo gravitacional (Gravitational Redshift) en caída hacia el horizonte
    float zGrav = sqrt(plunge);

    // Paleta cromática térmica de acreción cinematográfica (Gargantua)
    vec3 cWhite  = vec3(1.0, 0.98, 0.92);
    vec3 cBright = lit(colP, 0.90);
    vec3 cGold   = colP;
    vec3 cAmber  = mix(colP, colE, 0.55);
    vec3 cFire   = mix(colE, vec3(0.85, 0.22, 0.04), 0.65);
    vec3 cSmoke  = mix(dk(colE, 0.65), vec3(0.18, 0.03, 0.01), 0.60);

    // Variación térmica por audio (agudos = blanco/azul, graves = rojo denso)
    float tShift = clamp(musicTreble * 0.85, 0.0, 1.0);
    float bShift = clamp(musicBass * 0.50, 0.0, 1.0);
    vec3 cCyanWhite = lit(vec3(colP.b, colP.g, colP.r), 0.92);
    cWhite = mix(cWhite, cCyanWhite, tShift * 0.4);
    cBright = mix(cBright, cCyanWhite, tShift * 0.7);
    cFire  = mix(cFire, dk(colE, 0.55), bShift);

    vec3 tcol;
    float talpha;
    if (fN < 0.04) {
        float u = fN / 0.04;
        tcol = mix(cWhite, cBright, u);
        talpha = 1.0;
    } else if (fN < 0.16) {
        float u = (fN - 0.04) / 0.12;
        tcol = mix(cBright, cGold, u);
        talpha = 0.98;
    } else if (fN < 0.40) {
        float u = (fN - 0.16) / 0.24;
        tcol = mix(cGold, cAmber, u);
        talpha = 0.95;
    } else if (fN < 0.65) {
        float u = (fN - 0.40) / 0.25;
        tcol = mix(cAmber, cFire, u);
        talpha = mix(0.95, 0.55, u);
    } else {
        float u = (fN - 0.65) / 0.35;
        tcol = mix(cFire, cSmoke, u);
        talpha = mix(0.55, 0.0, u * u);
    }

    // Enfriamiento térmico en la zona de caída libre: de oro/blanco a brasas carmesí oscuras
    if (plunge < 1.0) {
        vec3 cEmbers = mix(vec3(0.20, 0.025, 0.005), cAmber, plunge * plunge);
        tcol = mix(cEmbers, tcol, zGrav);
        talpha *= mix(0.20, 1.0, zGrav);
    }

    // =========================================================================
    // DINÁMICA DE FLUIDOS RELATIVISTA: CORRIENTES Y FILAMENTOS DE PLASMA
    // =========================================================================
    // En la zona de caída libre, la cizalla angular se acelera intensamente:
    // los filamentos se enrollan en espiral hacia adentro abrazando la sombra
    float spiralIn = (1.0 - plunge) * (1.0 - plunge) * 3.6;
    float shearBase = 2.6 / (fN + 0.16) + spiralIn - time * 0.055;
    float phiSheared = phi + shearBase;

    // Distorsión turbulenta orgánica (Domain Warping suave):
    vec2 warpUV = vec2(cos(phiSheared), sin(phiSheared)) * (fN * 3.5 + 1.2);
    float warp = (fbm(warpUV + vec2(time * 0.02, 0.0)) - 0.5) * 0.45;
    float phiWarped = phiSheared + warp;
    vec2 dir = vec2(cos(phiWarped), sin(phiWarped));

    // 1. Corrientes principales de plasma (Macro-ríos de gas)
    vec2 uvMacro = dir * (fN * 5.2 + 2.0);
    float nMacro = fbm(uvMacro);
    float ridgeMacro = 1.0 - abs(2.0 * nMacro - 1.0);
    ridgeMacro = pow(ridgeMacro, 1.8);

    // 2. Filamentos afilados de alta velocidad (Micro-estrías)
    float shearFine = 3.4 / (fN + 0.12) + spiralIn * 1.3 - time * 0.08;
    float phiFine = phi + shearFine + warp * 0.7;
    vec2 dirFine = vec2(cos(phiFine), sin(phiFine));
    vec2 uvFine = dirFine * (fN * 12.0 + 4.5);
    float nFine = fbm(uvFine);
    float ridgeFine = 1.0 - abs(2.0 * nFine - 1.0);
    ridgeFine = pow(ridgeFine, 2.8); // Cresta estrecha y afilada

    // Difuminado progresivo hacia el borde exterior:
    float fineWeight = smoothstep(0.85, 0.30, fN);
    float density = mix(0.70, 1.30, ridgeMacro) * mix(1.0 - 0.20 * fineWeight, 1.0 + 0.20 * fineWeight, ridgeFine);

    // Envolvente radial: extinción suave en el horizonte y desvanecimiento cúbico ultradifuminado al negro
    float innerLip = smoothstep(0.0, 0.18, plunge);
    float outerSmoke = pow(clamp(1.0 - smoothstep(0.35, 1.0, fN), 0.0, 1.0), 1.8);
    float radialEdge = innerLip * outerSmoke;

    // Beaming relativista (Doppler boosting ~0.5c)
    float beamMul = mix(0.48, 2.35, pow(approach, 2.2));

    // Modulación térmica local:
    vec3 plasmaCol = mix(cSmoke * 1.35, tcol, mix(0.45, 1.0, ridgeMacro));
    plasmaCol = mix(plasmaCol, cBright, ridgeFine * 0.65 * smoothstep(0.2, 0.9, ridgeMacro) * zGrav);

    // Spine Incandescence:
    float spine = pow(ridgeFine, 3.2) * smoothstep(0.35, 0.95, ridgeMacro);
    float spineGlow = spine * (0.25 + 1.45 * pow(approach, 1.8)) * smoothstep(0.65, 0.0, fN) * zGrav;
    vec3 emit = mix(plasmaCol, vec3(1.0), clamp(spineGlow, 0.0, 1.0));

    // Bloom/sobreexposición blanca en el labio ISCO (atenuado en la zona de caída por redshift)
    float iscoBloom = pow(smoothstep(0.12, 0.0, fN), 2.4) * (0.85 + approach * 0.40) * zGrav;
    emit = mix(emit, vec3(1.0), clamp(iscoBloom, 0.0, 1.0));

    // Fogonazo en el labio interior al ritmo de la música
    emit = mix(emit, vec3(1.0), musicPulse * smoothstep(0.18, 0.0, fN) * 0.6 * zGrav);
    float alpha = clamp(talpha * radialEdge * density * beamMul * 1.32, 0.0, 1.0);

    // Arco de progreso de la música
    if (musicProgress > 0.0) {
        const float topAngle = -1.0708;
        float sweep = mod(phi - topAngle + TAU, TAU);
        float headEdge = musicProgress * TAU;
        float head = (headEdge >= TAU) ? 1.0 : (1.0 - smoothstep(headEdge - 0.03, headEdge + 0.03, sweep));
        float inProgress = head;
        emit  = mix(emit, lit(colP, 0.95), inProgress * 0.5);
        alpha = mix(alpha, clamp(alpha * 1.35 + 0.15, 0.0, 1.0), inProgress * 0.7);
    }

    // Ráfagas de acreción por pulsos de bombo (inyección de masa hacia el horizonte)
    if (musicBurstAge >= 0.0 && musicBurstAge < 1.4) {
        float p = clamp(musicBurstAge / 1.4, 0.0, 1.0);
        float rr = mix(rOuter * 0.95, rHorizon * 1.02, p * p);
        float dR = abs(rD - rr);
        float blobA = smoothstep(0.20, 0.0, dR) * (1.0 - p) * 0.65;
        vec3 blobCol = mix(lit(colP, 0.98), lit(colP, 0.60), p);
        emit = mix(emit, blobCol, clamp(blobA * 1.2, 0.0, 1.0));
        alpha = clamp(alpha + blobA * (1.0 - alpha * 0.5), 0.0, 1.0);
    }

    return vec4(emit, alpha);
}

// ------------------------------------------------------------------ agujero negro estilo Gargantua
vec4 blackHole(vec2 frag, vec2 bhC, float R, float tilt, float beam,
               float music, float musicProgress, float musicPulse,
               float musicBass, float musicTreble, float musicBurstAge,
               vec3 colP, vec3 colE, vec3 colV)
{
    const float FLAT = 0.20; // Inclinación casi de canto (~78°)
    vec3 P = colP, ERR = colE;

    vec2 rel = frag - bhC;
    float dS = length(rel) / R;

    vec4 acc = vec4(0.0);

    // Corte temprano fuera del radio de influencia del disco
    if (dS > 3.8) return acc;

    float ct = cos(-tilt), st = sin(-tilt);
    vec2 pr = vec2(rel.x*ct - rel.y*st, rel.x*st + rel.y*ct); // Marco rotado (X ecuatorial, Y eje menor)

    float rho = max(length(pr) / R, 1e-3);
    float cosScreen = clamp(pr.x / (rho * R), -1.0, 1.0);

    // ==================================================================
    // ORDEN FRONT-TO-BACK: El primer elemento en llamar a over() va DELANTE
    // ==================================================================

    // ------------------------------------------------------------------
    // 1. SECTOR DELANTERO DEL DISCO ECUATORIAL (Direct Front Disk)
    // Pasa POR DELANTE de la sombra del agujero negro cortándola horizontalmente.
    // Proyección elíptica simple (FLAT) + sampleDisk(): opaca cerca del ecuador,
    // lo que bloquea por composición el solape del arco superior (más abajo) con
    // esta misma zona — necesario para que no se vean dos texturas cruzadas.
    // ------------------------------------------------------------------
    if (pr.y >= -0.04 * R) {
        float yDisk = pr.y / FLAT;
        float rD = length(vec2(pr.x, yDisk)) / R;

        float phi = -acos(clamp(pr.x / max(rD * R, 1e-3), -1.0, 1.0));
        float approach = 0.5 - 0.5 * cos(phi);

        vec4 colFront = sampleDisk(rD, phi, approach, time, music, musicProgress,
                                   musicPulse, musicBass, musicTreble, musicBurstAge, P, ERR);

        float frontTransition = smoothstep(-0.04 * R, 0.04 * R, pr.y);
        over(acc, colFront.rgb, colFront.a * frontTransition);
    }

    // ------------------------------------------------------------------
    // 2. HORIZONTE DE SUCESOS (La Sombra Central Negra)
    // Ocluye todo lo que esté detrás de él (arcos lensados y fondo)
    // Se divide naturalmente en la bóveda superior y el creciente inferior
    // porque el haz frontal ya está pintado por delante con opacidad sólida.
    // ------------------------------------------------------------------
    float shadowMask = smoothstep(1.006, 0.990, dS);
    over(acc, colV, shadowMask);

    // ------------------------------------------------------------------
    // 3. ANILLO DE FOTONES (Photon Ring en la Esfera de Fotones)
    // Círculo fino hiperbrillante con Doppler boosting en el limbo del horizonte
    // ------------------------------------------------------------------
    {
        float ringDist = abs(dS - 1.006);
        float ringAlpha = smoothstep(0.009, 0.0, ringDist) * 0.95;
        float dop = 0.5 - 0.5 * (pr.x / (rho * R)); // Más brillante en el lado izquierdo
        vec3 ringCol = mix(lit(P, 0.75), vec3(1.0), dop * 0.90);
        ringCol = mix(ringCol, vec3(1.0), musicPulse * 0.9);
        // El anillo de fotones se intensifica donde los arcos gravíticos abrazan la silueta
        float polarBoost = smoothstep(0.05, 0.75, abs(pr.y / (R * rho)));
        over(acc, ringCol, ringAlpha * (0.45 + dop * 0.45 + polarBoost * 0.35 + musicPulse * 0.4));
    }

    // ------------------------------------------------------------------
    // 4. SECTOR TRASERO LENSADO (Top Arch y Bottom Arch)
    // Luz curvada por la gravedad desde detrás de la singularidad
    // ------------------------------------------------------------------
    // --- 4a. Arco Superior (Primary image que envuelve por arriba, pr.y < 0.15 R) ---
    if (pr.y <= 0.15 * R) {
        float s = clamp(-pr.y / (R * rho), 0.0, 1.0);
        float sCurv = pow(s, 0.75);

        // Mapeo continuo sin hueco muerto: abraza directamente el borde del horizonte
        float rhoInTop  = mix(1.005, 1.001, sCurv);
        float rhoOutTop = mix(2.90, 1.95,  sCurv);

        if (rho >= rhoInTop && rho <= rhoOutTop) {
            float f = (rho - rhoInTop) / max(rhoOutTop - rhoInTop, 0.01);
            float rD = 1.00 + f * (2.90 - 1.00);

            // Azimut en el hemisferio trasero (phi en [0, PI])
            float phi = acos(cosScreen);
            float approach = 0.5 - 0.5 * cos(phi);

            vec4 colTop = sampleDisk(rD, phi, approach, time, music, musicProgress,
                                     musicPulse, musicBass, musicTreble, musicBurstAge, P, ERR);

            // Atenuación suave en los extremos para fusión continua con el ecuador
            float archMask = smoothstep(0.15 * R, -0.02 * R, pr.y);
            over(acc, colTop.rgb, colTop.a * archMask);
        }
    }

    // --- 4b. Arco Inferior (Secondary image bajo la sombra, pr.y > 0.15 R) ---
    if (pr.y >= 0.15 * R) {
        float s = clamp(pr.y / (R * rho), 0.0, 1.0);
        float sCurv = pow(s, 0.80);

        // Mapeo continuo sin hueco muerto abrazando el borde inferior
        float rhoInBot  = mix(1.005, 1.001, sCurv);
        float rhoOutBot = mix(2.90, 1.40,  sCurv);

        if (rho >= rhoInBot && rho <= rhoOutBot) {
            float f = (rho - rhoInBot) / max(rhoOutBot - rhoInBot, 0.01);
            float rD = 1.00 + f * (2.90 - 1.00);

            float phi = acos(cosScreen);
            float approach = 0.5 - 0.5 * cos(phi);

            vec4 colBot = sampleDisk(rD, phi, approach, time, music, musicProgress,
                                     musicPulse, musicBass, musicTreble, musicBurstAge, P, ERR);

            float archMask = smoothstep(0.15 * R, 0.28 * R, pr.y);
            // Imagen secundaria con intensidad física (~0.80 de la primaria)
            over(acc, colBot.rgb, colBot.a * archMask * 0.80);
        }
    }

    // ------------------------------------------------------------------
    // 5. CORONA DIFUSA SEDOSA DEL DISCO (Interstellar Corona)
    // El brillo de convergencia en el limbo izquierdo emerge solo del beaming
    // relativista de sampleDisk() (pow(approach, ~2.2)) — no hace falta un
    // parche de brillo en una posición fija.
    // ------------------------------------------------------------------
    {
        float yHaze = pr.y / (FLAT * 2.5);
        float rHaze = length(vec2(pr.x, yHaze)) / R;
        float coronalA = pow(smoothstep(3.2, 1.1, rHaze), 2.5) * 0.07;
        vec3 coronalCol = mix(vec3(0.28, 0.07, 0.01), lit(P, 0.22), smoothstep(2.6, 1.0, rHaze));
        over(acc, coronalCol, coronalA);
    }

    return acc;
}

// ------------------------------------------------------------------ soles
// sun(): fotosfera con gradiente descentrado + granulación fbm que hierve
// lentísimo + cromosfera/limbo + corona. `promin` activa las prominencias
// (sólo Laura). `boost` sube el brillo (modo foco-Laura + voz).
vec4 sun(vec2 frag, vec2 c, float r, vec3 col, bool promin, float boost, float tm)
{
    vec2 rel = frag - c;
    float d  = length(rel);
    float rn = d / r;
    vec4 acc = vec4(0.0);

    // Corte temprano: los soles son diminutos (r ≈ 40-50 px) y su corona muere
    // a ~3.2r. Fuera de eso NADA de este sol contribuye — pero sin este return
    // el bucle de prominencias + los pow de corona se ejecutaban para CADA píxel
    // de la pantalla, dos veces (un sol cada uno). Es el mayor ahorro del shader.
    if (rn > 3.4) return acc;

    vec3 HOT = lit(col, 0.85);
    float ang = atan(rel.y, rel.x);

    // corona (dos capas radiales)
    float breath = 1.0 + 0.03*sin(tm*0.35);
    float co1 = pow(smoothstep(3.2*breath, 0.35, rn), 1.7) * (0.12 + 0.7*boost);
    float co2 = pow(smoothstep(1.7*breath, 0.40, rn), 2.0) * (0.30 + 0.6*boost);
    over(acc, col, co1);
    over(acc, col, co2);

    // prominencias — sólo Laura. Dos bucles finos, muy localizados, que se elevan
    // del limbo y vuelven dentro de un sector angular ESTRECHO. Ciclo ~40 s y
    // desfasadas → casi siempre se ve 0-1, nunca un anillo.
    if (promin) {
        for (int i=0;i<2;i++){
            float fi = float(i);
            float a0   = 1.4 + fi*3.1 + tm*0.02;               // dos sitios opuestos, derivan lento
            float ph   = 0.5 + 0.5*sin(tm*(TAU/40.0) + fi*3.7);
            float life = smoothstep(0.35, 0.85, ph);           // ventana corta de visibilidad
            if (life < 0.02) continue;
            float span = 0.20;
            float da   = abs(mod(ang - a0 + PI, TAU) - PI);
            if (da > span) continue;                           // NADA fuera del sector estrecho
            float u    = da / span;
            float loopR = 1.0 + (0.34 + 0.30*life) * pow(1.0 - u*u, 0.7);
            float thin  = smoothstep(0.06, 0.0, abs(rn - loopR)) * smoothstep(0.0, 0.10, rn - 0.99);
            over(acc, lit(col, 0.62), thin * (1.0 - u*u) * 0.8 * life);
        }
    }

    if (rn <= 1.03) {
        // fotosfera: gradiente radial descentrado (luz arriba-izquierda)
        vec2 lp = (rel + vec2(-0.35, -0.35)*r) / r;
        float sh = clamp(1.0 - length(lp)*0.95, 0.0, 1.0);
        vec3 body = mix(dk(col, 0.26), mix(col, HOT, sh*sh), smoothstep(0.0, 1.0, sh));
        // granulación fbm que hierve muy despacio (bajo contraste)
        vec2 gp = rel / r * 7.0;
        float gran = fbm(gp + vec2(tm*0.03, -tm*0.021));
        gran += 0.5*fbm(gp*2.3 - vec2(tm*0.018, tm*0.026));
        body *= 0.94 + 0.12*(gran - 0.75);
        float disc = smoothstep(1.03, 0.985, rn);
        over(acc, body * (1.0 + 0.35*boost), disc);
        // cromosfera / limbo: aro fino y suave, más marcado en el lado iluminado
        float limb = smoothstep(0.045, 0.0, abs(rn - 1.0));
        float litSide = 0.55 + 0.45*sh;
        over(acc, lit(col, 0.5), limb * 0.34 * litSide * (1.0 + 0.6*boost));
    }
    return acc;
}

// ------------------------------------------------------------------ main
vec4 render(vec2 frag)
{
    vec3 P = colPrimary.rgb;
    vec4 acc = vec4(0.0);

    // fondo: negro espacial puro y profundo (máximo contraste cinematográfico)

    // estrellas
    starfield(acc, frag, bhCenter, bhRadius, colInk.rgb);

    // cinturón de tareas circumbinario
    belt(acc, frag, beltCenter, beltRadii, beltTilt, beltSpin, beltDensity, colBelt.rgb);

    // agujero negro
    vec4 bh = blackHole(frag, bhCenter, bhRadius, bhTilt, bhSpin,
                        music, musicProgress, musicPulse,
                        musicBass, musicTreble, musicBurstAge,
                        P, colError.rgb, colVoid.rgb);
    over(acc, bh.rgb / max(bh.a, 1e-4), bh.a);

    // modo foco-Laura: oscurecer TODO lo anterior (fondo + agujero) a ~0.18
    float dimK = mix(1.0, 0.18, clamp(focusAmt, 0.0, 1.0));
    acc.rgb *= dimK;
    acc.a   *= mix(1.0, 0.5, clamp(focusAmt, 0.0, 1.0));

    // Calcular posiciones de los soles desde el tiempo (binOmega * time)
    float ang = binOmega * time;
    float ct = cos(binTilt);
    float st = sin(binTilt);

    float rx0 = binSemiAxes.x;
    float ry0 = rx0 * (1.0 - binEcc);
    float lx0 = cos(ang) * rx0;
    float ly0 = sin(ang) * ry0;
    vec2 sun0Pos = binBary + vec2(lx0 * ct - ly0 * st, lx0 * st + ly0 * ct);

    float rx1 = binSemiAxes.y;
    float ry1 = rx1 * (1.0 - binEcc);
    float lx1 = cos(ang + PI) * rx1;
    float ly1 = sin(ang + PI) * ry1;
    vec2 sun1Pos = binBary + vec2(lx1 * ct - ly1 * st, lx1 * st + ly1 * ct);

    // Configuración (secundario, calmo) — también se oscurece con focusAmt
    vec4 s0 = sun(frag, sun0Pos, sun0Radius, colPrimary.rgb, false, 0.0, time);
    s0.rgb *= dimK;
    over(acc, s0.rgb / max(s0.a, 1e-4), s0.a);

    // Laura (primario) — NO se oscurece; su brillo escala con focusAmt + voz
    float lb = focusAmt * (0.35 + 0.65*clamp(lauraAmp, 0.0, 1.0));
    vec4 s1 = sun(frag, sun1Pos, sun1Radius, colLaura.rgb, true, lb, time);
    over(acc, s1.rgb / max(s1.a, 1e-4), s1.a);

    return acc;
}
// ===SHADER BODY===

void main(){
    // origen arriba-izquierda como el Canvas / Qt
    vec2 frag = vec2(qt_TexCoord0.x, qt_TexCoord0.y) * resolution;
    vec4 c = render(frag);
    fragColor = vec4(c.rgb, c.a) * qt_Opacity;   // premultiplicado
}
