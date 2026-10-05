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
    float musicLines;    // 0..1 — energía MUY suavizada (ataque rápido, caída lenta) para las líneas finas

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
    bool nearBH = distance(frag, bhC) < R*2.1;
    // 3x3 vecindario para no cortar estrellas en el borde de celda
    for (int oy=-1; oy<=1; oy++)
    for (int ox=-1; ox<=1; ox++){
        vec2 cid = id + vec2(ox, oy);
        vec2 rnd = hash22(cid);
        if (rnd.x > 0.40) continue;                  // densidad
        vec2 spos = (cid + hash22(cid+3.7)) * cell;  // posición de la estrella
        float b = fract(rnd.y * 91.7);               // brillo
        float d = distance(spos, bhC);
        if (nearBH && d > R*0.95 && d < R*1.9) {
            // arco lensado
            float ang = atan(spos.y - bhC.y, spos.x - bhC.x);
            float bend = (R / d) * 0.22;
            float pd  = distance(frag, bhC);
            float pang = atan(frag.y - bhC.y, frag.x - bhC.x);
            float da = abs(mod(pang - ang + PI, TAU) - PI);
            float onArc = smoothstep(bend, 0.0, da) * smoothstep(2.2, 0.0, abs(pd - d));
            over(acc, sc, onArc * (0.06 + b*0.16));
        } else {
            float pr = distance(frag, spos);
            float s  = b < 0.7 ? 0.9 : 1.7;
            float pt = smoothstep(s, 0.0, pr);
            over(acc, sc, pt * (0.14 + b*0.55));
        }
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

// ------------------------------------------------------------------ agujero negro
vec4 blackHole(vec2 frag, vec2 bhC, float R, float tilt, float beam,
               float musicProgress, float musicLines,
               vec3 colP, vec3 colE, vec3 colV)
{
    const float FLAT = 0.14;
    vec3 HOT = lit(colP, 0.86);
    vec3 P = colP, ERR = colE;

    vec2 rel = frag - bhC;
    float dS = length(rel) / R;

    vec4 acc = vec4(0.0);

    // 1. resplandor exterior (estable: sin pulso)
    {
        float g = pow(smoothstep(4.4, 0.75, dS), 1.6) * 0.22;
        vec3 gc = mix(P, lit(P, 0.30), smoothstep(2.4, 0.8, dS));
        over(acc, gc, g);
    }

    // Corte temprano: más allá de ~4.8R no hay disco ni anillo ni jet
    if (dS > 4.8) return acc;

    float ct = cos(-tilt), st = sin(-tilt);
    vec2 pr = vec2(rel.x*ct - rel.y*st, rel.x*st + rel.y*ct);   // marco rotado
    vec2 q  = vec2(pr.x, pr.y / FLAT);                          // espacio-círculo
    float rD = length(q) / R;
    float thetaD = atan(q.y, q.x);

    // 2. borde lejano lensado sobre el horizonte (halo «Gargantua»)
    float aboveH = smoothstep(R*0.16, -R*0.12, pr.y);   // 1 por encima del plano → 0 por debajo
    if (aboveH > 0.001) {
        vec2 qh = vec2(pr.x, (pr.y + R*0.16) / (FLAT*2.4));
        float rh = length(qh) / R;
        float band  = smoothstep(0.16, 0.0, abs(rh - (1.10 + 0.012 * musicLines)));
        float upper = smoothstep(0.0, 0.30, -qh.y / max(length(qh), 1.0));
        // gradiente de temperatura del arco: blanco-caliente dentro → color del tema fuera
        vec3 col = mix(lit(colP, 0.96), P, clamp((rh - 1.02) / 0.20, 0.0, 1.0));
        over(acc, col, band * upper * aboveH * (0.80 + 0.14 * musicLines));
    }

    // temperatura del disco por radio normalizado. Gradiente 100% en el color del tema:
    // blanco-caliente (labio interno) → primario (m3primary) → sombra profunda del tema
    float edgeWarp = fbm(vec2(rD*2.0, (q.y/max(length(q),1.0))*2.5 - time*0.05)) - 0.5;
    float rDw = rD + edgeWarp * 0.28;
    float fN = (rDw - 1.27) / (4.0 - 1.27);
    bool inDisk = (fN > -0.05 && fN < 1.05);
    vec3 tcol; float talpha;
    {
        float f = clamp(fN, 0.0, 1.0);
        vec3 c0=lit(colP,0.98), c1=lit(colP,0.88), c2=lit(P,0.45), c3=P, c4=dk(P,0.28), c5=dk(P,0.55), c6=dk(P,0.82);
        float a0=0.0,a1=1.0,a2=0.98,a3=0.86,a4=0.62,a5=0.34,a6=0.0;
        if (f < 0.05)      { float u=f/0.05;        tcol=mix(c0,c1,u); talpha=mix(a0,a1,u); }
        else if (f < 0.13) { float u=(f-0.05)/0.08; tcol=mix(c1,c2,u); talpha=mix(a1,a2,u); }
        else if (f < 0.42) { float u=(f-0.13)/0.29; tcol=mix(c2,c3,u); talpha=mix(a2,a3,u); }
        else if (f < 0.70) { float u=(f-0.42)/0.28; tcol=mix(c3,c4,u); talpha=mix(a3,a4,u); }
        else if (f < 0.88) { float u=(f-0.70)/0.18; tcol=mix(c4,c5,u); talpha=mix(a4,a5,u); }
        else               { float u=(f-0.88)/0.12; tcol=mix(c5,c6,u); talpha=mix(a5,a6,u); }
    }

    float ql   = max(length(q), 1.0);
    float snAz = q.y / ql;                    // sin(azimut), continuo en todo el disco
    float csAz = q.x / ql;                    // cos(azimut), continuo
    float approach = 0.5 + 0.5*cos(thetaD - beam);
    float beamMul  = mix(0.60, 1.65, pow(approach, 2.0));          // Doppler beaming
    float turb     = fbm(vec2(rD*3.4 + csAz*1.6, snAz*3.0 + time*0.12));
    float rings    = 0.5 + 0.5*sin(rD*23.0 + csAz*1.2 + turb*2.2);
    rings         += 0.25*sin(rD*61.0 - snAz*1.8);
    float turbMul  = clamp(0.70 + 0.11*rings + 0.38*(turb - 0.5), 0.55, 1.45);

    float diskEdge = smoothstep(0.0, 0.10, fN) * smoothstep(1.0, 0.58, fN);
    vec3  emit  = mix(tcol, lit(colP, 0.92), pow(smoothstep(0.18, 0.0, fN), 1.8) * 0.5);

    float diskA = talpha * diskEdge * beamMul * turbMul * 1.02;

    // 3. disco de acreción — UNA sola pasada
    if (inDisk) {
        over(acc, emit, diskA);
    }

    // 4. horizonte de sucesos — negro puro
    over(acc, colV, smoothstep(1.03, 0.985, dS));

    // 5. anillo grande (fotones + halo): circular completo; la parte ya recorrida de la
    //    canción (desde las 12 en punto, sentido horario) es algo más luminosa. Sin pulso.
    {
        float dRot = length(pr) / R;
        float ang = mod(atan(rel.x, -rel.y) + TAU, TAU);       // 0 arriba, horario
        float head = clamp(musicProgress, 0.0, 1.0) * TAU;
        float done = (musicProgress > 0.0005) ? 1.0 - smoothstep(head - 0.05, head + 0.05, ang) : 0.0;
        float k = mix(1.0, 1.55, done);
        over(acc, lit(P, 0.55), smoothstep(0.14, 0.0, abs(dRot - 1.11)) * 0.17 * k);
        over(acc, lit(P, 0.90), smoothstep(0.020, 0.0, abs(dRot - 1.06)) * 0.50 * k);
    }

    // 5b. líneas finas concéntricas: única parte que reacciona a la música,
    //     con energía ya suavizada (sin destellos): opacidad y apertura del arco.
    {
        float dRot = length(pr) / R;
        float aR = mod(atan(rel.y, rel.x) + TAU, TAU);
        float L = musicLines;
        // arco exterior: gira lento, se abre un poco con la música
        float ctr = time * 0.05 + 1.2;
        float dA = abs(mod(aR - ctr + PI, TAU) - PI);
        float open = 1.0 - smoothstep(0.9 + 1.3 * L, 1.3 + 1.3 * L, dA);
        over(acc, lit(P, 0.85), smoothstep(0.011, 0.0, abs(dRot - 1.62)) * open * (0.10 + 0.34 * L));
        // segundo arco, opuesto, más fino y lejano
        float dB = abs(mod(aR - ctr, TAU) - PI);
        float open2 = 1.0 - smoothstep(0.5 + 0.9 * L, 0.9 + 0.9 * L, dB);
        over(acc, lit(P, 0.75), smoothstep(0.008, 0.0, abs(dRot - 2.05)) * open2 * (0.07 + 0.26 * L));
    }

    // 6. labio interior caliente (ISCO), estable
    {
        float hb = 0.5 + 0.5*cos(thetaD - beam);
        float lipA = (0.24 + 0.5*hb) * smoothstep(0.24, 0.0, abs(rD - 1.33));
        over(acc, mix(lit(P,0.45), lit(colP,0.95), hb), lipA * 1.0);
    }

    // 8. jet relativista modulado con los graves
    {
        float jx = smoothstep(R*0.06, 0.0, abs(pr.x));
        float jy = smoothstep(R*0.5, R*0.55, abs(pr.y)) * smoothstep(R*3.4, R*0.6, abs(pr.y));
        over(acc, lit(P, 0.6), jx * jy * (0.10 + 0.12 * musicLines));
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

    // fondo: negro + tinte del disco cerca del agujero
    float tint = pow(smoothstep(max(resolution.x, resolution.y)*0.9, bhRadius*0.5,
                                distance(frag, bhCenter)), 1.3);
    over(acc, dk(P, 0.7), tint * 0.16);

    // estrellas
    starfield(acc, frag, bhCenter, bhRadius, colInk.rgb);

    // cinturón de tareas circumbinario
    belt(acc, frag, beltCenter, beltRadii, beltTilt, beltSpin, beltDensity, colBelt.rgb);

    // agujero negro
    vec4 bh = blackHole(frag, bhCenter, bhRadius, bhTilt, bhSpin,
                        musicProgress, musicLines,
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
