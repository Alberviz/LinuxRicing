#version 440

// planet.frag — planetas, lunas y periféricos del sistema solar, diseño D
// «Paleta viva». TODOS los colores entran como uniforms (roles Material del
// tema, en vivo): nada fijo. El item mide 4·R de lado (R = radio del cuerpo),
// así que el espacio local `q` está en unidades de R, y hacia abajo.
//
//   kind 0  Claude   → fn planetClaude()   (mundo con continentes y casquete)
//   kind 1  Gemini   → fn planetGemini()   (gigante con bandas, tormenta y anillo)
//   kind 2  otros    → fn planetOther()    (variante coherente)
//   kind 3  luna de subagente (tertiaryContainer)
//   kind 4  periférico: luna con glifo (glyph 1 ratón · 2 auriculares · 3 genérico)
//                       + arco de batería en primary (batt 0..1)
//
// ► CAMBIAR EL DISEÑO DE UN PROVEEDOR: edita solo su función planetXxx() (devuelve
//   el color del disco SIN sombreado ni borde, y opcionalmente `ring`). El
//   sombreado, el halo, el aro de alerta de contexto (error) y el resto son
//   comunes. Añadir un proveedor = una función más + un `kind` en SolarSystem.qml.
//
// Sin blur: los desenfoques del SVG se sustituyen por smoothstep/exp.
//
// Compilar: /usr/lib/qt6/bin/qsb --qt6 --glsl "100 es,120,150" --hlsl 50 --msl 12 -o planet.frag.qsb planet.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float kind;
    float ctxAlert;   // 0..1 — contexto casi lleno → aro en error
    float batt;       // 0..1 — arco de batería (periféricos)
    float glyph;
    vec4  cPrimary;
    vec4  cSecondary;
    vec4  cTertiary;
    vec4  cPrimaryC;
    vec4  cSecondaryC;
    vec4  cTertiaryC;
    vec4  cSurface;
    vec4  cSurfaceC;
    vec4  cOnSurface;
    vec4  cOutline;
    vec4  cError;
};

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

float hash(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){
    vec2 i = floor(p), f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}
float fbm(vec2 p){ return 0.55*vnoise(p) + 0.3*vnoise(p*2.1+7.3) + 0.15*vnoise(p*4.3+3.1); }

void over(inout vec4 acc, vec3 c, float a){
    a = clamp(a, 0.0, 1.0);
    acc.rgb = c * a + acc.rgb * (1.0 - a);
    acc.a   = a + acc.a * (1.0 - a);
}
float band(float y, float y0, float h, float soft){
    return smoothstep(y0 - soft, y0 + soft, y) * (1.0 - smoothstep(y0 + h - soft, y0 + h + soft, y));
}
float ell(vec2 q, vec2 c, vec2 r){ return 1.0 - smoothstep(0.7, 1.0, length((q - c) / r)); }
float sdRoundBox(vec2 p, vec2 b, float r){ vec2 d = abs(p) - b + r; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r; }
float stroke(float sd, float w, float aa){ return 1.0 - smoothstep(w - aa, w + aa, abs(sd)); }

// colores derivados (mismos mezclas que el diseño D: --pDeep, --sDeep, --tDeep, --oLight)
vec3 deep(vec3 c){ return mix(c, cSurface.rgb, 0.60); }
vec3 oLight(){ return mix(cOnSurface.rgb, cSurface.rgb, 0.35); }

// ============================================================ PROVEEDORES
// Claude y Gemini devuelven el cuerpo COMPLETO ya compuesto (vec4 premultiplicado,
// con sus propios anillos / gemelos / sombreado): así cada diseño es libre de
// cambiar de geometría. Otros proveedores usan el flujo común (planetOther).

vec2 hash22(vec2 p){ p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3))); return fract(sin(p) * 43758.5453); }
// distancia al borde de celda de Voronoi (F2 - F1): 0 sobre las grietas
float voroEdge(vec2 p){
    vec2 ip = floor(p), fp = fract(p);
    float f1 = 8.0, f2 = 8.0;
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash22(ip + g);
            float dd = length(g + o - fp);
            if (dd < f1) { f2 = f1; f1 = dd; } else if (dd < f2) f2 = dd;
        }
    return f2 - f1;
}
// sombreado de esfera en coordenadas locales ql (disco unidad)
vec3 shadeSphere(vec3 col, vec2 ql){
    float sh = length(ql - vec2(-0.28, -0.40)) / 1.8;
    return mix(col, cSurface.rgb, smoothstep(0.4, 1.0, sh) * 0.85);
}
// elipse de anillo girada `deg`: x = trazo (0..1), y = lado (<0 detrás, >0 delante)
vec2 ringE(vec2 q, float rx, float ry, float deg, float hw, float aa){
    float a = radians(deg), c = cos(a), s = sin(a);
    vec2 p = vec2(q.x*c + q.y*s, -q.x*s + q.y*c);
    float e = length(vec2(p.x / rx, p.y / ry));
    vec2 g = vec2(p.x / (rx*rx), p.y / (ry*ry)) / max(e, 1e-4);
    float dist = abs(e - 1.0) / max(length(g), 1e-4);
    return vec2(1.0 - smoothstep(hw - aa, hw + aa, dist), p.y);
}

float ashHeight(vec2 q){
    float w = fbm(q * 1.6 + 4.0);
    float dunes = 0.5 + 0.5 * sin((q.y + 0.35 * q.x) * 11.0 + w * 6.0);
    return clamp(0.6 * dunes + 0.5 * (w - 0.4), 0.0, 1.0);
}

// ---- CLAUDE: doble anillo cruzado sobre un mundo de ceniza volcánica apagada ----
// Roles: secondary / sDeep / outline (capas de ceniza);
// anillos: tertiary / tertiaryContainer / secondary / onSurface.
vec4 planetClaude(vec2 q, float aa){
    vec4 acc = vec4(0.0);
    const float W = 0.045;   // grosor mínimo legible de los trazos finos
    vec2 r1 = ringE(q, 1.50, 0.34, -22.0, 0.060, aa);
    vec2 r1b = ringE(q, 1.38, 0.31, -22.0, W * 0.5, aa);
    vec2 r1c = ringE(q, 1.62, 0.37, -22.0, W * 0.4, aa);
    vec2 r2 = ringE(q, 1.26, 0.29, 22.0, 0.040, aa);
    vec2 r2b = ringE(q, 1.16, 0.27, 22.0, W * 0.4, aa);
    float d = length(q);
    float behind = step(1.0, d);
    // atrás
    over(acc, cTertiary.rgb, r1.x * 0.8 * step(r1.y, 0.0) * behind);
    over(acc, cTertiaryC.rgb, r1b.x * 0.8 * step(r1b.y, 0.0) * behind);
    over(acc, cTertiary.rgb, r1c.x * 0.5 * step(r1c.y, 0.0) * behind);
    over(acc, cSecondary.rgb, r2.x * 0.8 * step(r2.y, 0.0) * behind);
    over(acc, cOnSurface.rgb, r2b.x * 0.55 * step(r2b.y, 0.0) * behind);
    // cuerpo de ceniza
    float body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
    if (body > 0.0) {
        // ceniza volcánica apagada: capas/dunas en secondary · sDeep · outline, grano fino
        // y relieve con LUZ RASANTE (diferencia de altura hacia la luz), no con color.
        float t = clamp(length(q - vec2(-0.28, -0.40)) / 1.7, 0.0, 1.0);
        vec3 col = mix(cSecondary.rgb, deep(cSecondary.rgb), t);
        float h0 = ashHeight(q);
        float h1 = ashHeight(q + vec2(-0.035, -0.045));          // hacia la luz (arriba-izq.)
        float relief = clamp((h1 - h0) * 6.0, -1.0, 1.0);
        col = mix(col, cOutline.rgb, smoothstep(0.35, 0.9, h0) * 0.45);
        col = mix(col, deep(cSecondary.rgb), smoothstep(0.0, 0.35, 0.5 - h0) * 0.35);
        col *= 1.0 + relief * 0.38;
        col *= 0.94 + 0.12 * hash(floor(q * 46.0));              // grano
        col = shadeSphere(col, q);
        // el sombreado oscurece también las grietas del lado nocturno: justo lo esperado
        over(acc, col, body);
    }
    over(acc, cTertiaryC.rgb, 0.55 * (1.0 - smoothstep(0.0, 0.05, abs(d - 1.03))));
    // delante
    over(acc, cTertiary.rgb, r1.x * step(0.0, r1.y));
    over(acc, cTertiaryC.rgb, r1b.x * step(0.0, r1b.y));
    over(acc, cTertiary.rgb, r1c.x * 0.6 * step(0.0, r1c.y));
    over(acc, cSecondary.rgb, r2.x * step(0.0, r2.y));
    over(acc, cOnSurface.rgb, r2b.x * 0.7 * step(0.0, r2b.y));
    return acc;
}

// ---- GEMINI: doble cuerpo «Reloj de arena» (Ash y Ember Twin) ----
// Gemelo de arena (tertiaryContainer → tDeep, cráteres) + gemelo de roca (primary,
// estratos, borde primary) unidos por una columna de arena (tertiaryContainer).
vec4 planetGemini(vec2 q, float aa){
    vec4 acc = vec4(0.0);
    const float SG = 1.3;                 // escala del conjunto
    vec2 p = q / SG;                      // unidades del diseño (R = 1)
    float aap = aa / SG;
    // columna de arena (detrás de los gemelos): cintura en el centro
    float ax = abs(p.x);
    if (ax < 0.30) {
        float h = 0.05 + 0.13 * pow(ax / 0.30, 1.5);
        float yc = mix(0.0, 0.0, 0.0);
        float dy = abs(p.y - (p.x > 0.0 ? 0.0 : 0.0));
        float core = 1.0 - smoothstep(h - aap, h + aap, dy);
        float soft = 1.0 - smoothstep(h, h + 0.10, dy);
        over(acc, cTertiaryC.rgb, soft * 0.30);
        over(acc, cTertiaryC.rgb, core * 0.65);
    }
    // gemelo de arena (izquierda)
    {
        vec2 c = vec2(-0.58, -0.04); float R = 0.54;
        vec2 ql = (p - c) / R; float dl = length(ql);
        float body = 1.0 - smoothstep(1.0 - aap / R, 1.0 + aap / R, dl);
        if (body > 0.0) {
            float t = clamp(length(ql - vec2(-0.28, -0.40)) / 1.7, 0.0, 1.0);
            vec3 col = mix(cTertiaryC.rgb, deep(cTertiary.rgb), t);
            float rip = 0.5 + 0.5 * sin(ql.x * 7.0 + fbm(ql * 2.0) * 5.0);
            col = mix(col, deep(cTertiary.rgb), rip * 0.18);
            col = mix(col, deep(cTertiary.rgb), ell(ql, vec2(-0.20, 0.20), vec2(0.26, 0.26)) * 0.7);
            col = mix(col, deep(cTertiary.rgb), ell(ql, vec2(0.30, -0.30), vec2(0.14, 0.14)) * 0.6);
            col = shadeSphere(col, ql);
            over(acc, col, body);
        }
    }
    // gemelo de roca (derecha)
    {
        vec2 c = vec2(0.58, 0.05); float R = 0.54;
        vec2 ql = (p - c) / R; float dl = length(ql);
        float body = 1.0 - smoothstep(1.0 - aap / R, 1.0 + aap / R, dl);
        if (body > 0.0) {
            float t = clamp(length(ql - vec2(-0.28, -0.40)) / 1.7, 0.0, 1.0);
            vec3 col = mix(cPrimary.rgb, deep(cPrimary.rgb), t);
            float y = ql.y + (fbm(vec2(ql.x * 2.0, ql.y * 3.0)) - 0.5) * 0.08;
            col = mix(col, cOnSurface.rgb, band(y, -0.40, 0.16, 0.05) * 0.5);
            col = mix(col, cPrimaryC.rgb, band(y, 0.10, 0.22, 0.05) * 0.8);
            col = mix(col, deep(cPrimary.rgb), band(y, 0.50, 0.50, 0.05) * 0.8);
            col = shadeSphere(col, ql);
            over(acc, col, body);
        }
        over(acc, cPrimary.rgb, 0.6 * (1.0 - smoothstep(0.0, 0.07, abs(dl - 1.04))) );
    }
    return acc;
}

vec3 planetOther(vec2 q, float t){
    vec3 col = mix(cTertiary.rgb, deep(cTertiary.rgb), t);
    float y = q.y + (fbm(vec2(q.x * 1.2, q.y * 2.5)) - 0.5) * 0.10;
    col = mix(col, cSecondaryC.rgb, band(y, -0.30, 0.16, 0.06) * 0.55);
    col = mix(col, cPrimaryC.rgb,   band(y,  0.15, 0.22, 0.06) * 0.45);
    col = mix(col, cOnSurface.rgb,  ell(q, vec2(0.0, -0.98), vec2(0.40, 0.16)) * 0.55);
    return col;
}

// ============================================================ GLIFOS (periféricos)
float glyphAlpha(vec2 p, float g, float aa){
    p /= 0.85;
    float a = 0.0;
    if (g < 1.5) {            // ratón
        a = stroke(sdRoundBox(p, vec2(0.22, 0.34), 0.22), 0.05, aa);
        a = max(a, stroke(p.x, 0.03, aa) * step(p.y, -0.08) * step(-0.34, p.y));
        a = max(a, stroke(p.y + 0.08, 0.025, aa) * step(abs(p.x), 0.22));
        a = max(a, 1.0 - smoothstep(0.0, aa * 2.0, sdRoundBox(p - vec2(0.0, -0.21), vec2(0.03, 0.06), 0.03)));
    } else if (g < 2.5) {     // auriculares
        float arc = abs(length(p - vec2(0.0, -0.02)) - 0.34);
        a = (1.0 - smoothstep(0.04, 0.04 + aa, arc)) * step(p.y, -0.02);
        a = max(a, (1.0 - smoothstep(0.04, 0.04 + aa, abs(abs(p.x) - 0.34))) * step(-0.02, p.y) * step(p.y, 0.10));
        vec2 pp = vec2(abs(p.x) - 0.35, p.y - 0.20);
        a = max(a, 1.0 - smoothstep(0.0, aa * 2.0, sdRoundBox(pp, vec2(0.09, 0.16), 0.07)));
    } else {                  // genérico: teclado
        a = stroke(sdRoundBox(p, vec2(0.40, 0.26), 0.07), 0.04, aa);
        vec2 cell = vec2(0.20, 0.17);
        vec2 gp = (p - vec2(0.0, -0.08)) / cell;
        vec2 f = abs(fract(gp + 0.5) - 0.5) * cell;
        float dots = (1.0 - smoothstep(0.03, 0.03 + aa, length(f))) * step(abs(gp.x), 1.6) * step(abs(gp.y), 0.6);
        a = max(a, dots);
        a = max(a, 1.0 - smoothstep(0.0, aa * 2.0, sdRoundBox(p - vec2(0.0, 0.14), vec2(0.20, 0.025), 0.02)));
    }
    return a;
}

void main(){
    vec2 q = (qt_TexCoord0 - 0.5) * 4.0;
    float d = length(q);
    float aa = 1.5 * fwidth(d);
    vec4 acc = vec4(0.0);
    vec2 hp = vec2(-0.28, -0.40);
    float t = clamp(length(q - hp) / 1.7, 0.0, 1.0);

    int k = int(kind + 0.5);
    vec3 col;
    if (k == 0 || k == 1) {
        acc = (k == 0) ? planetClaude(q, aa) : planetGemini(q, aa);
        // aro de contexto casi lleno (error), común a los dos
        if (ctxAlert > 0.001) over(acc, cError.rgb, stroke(d - (k == 1 ? 1.75 : 1.28), 0.06, aa) * ctxAlert * 0.9);
        fragColor = acc * qt_Opacity;
        return;
    }
    if (k == 2)      col = planetOther(q, t);
    else if (k == 3) col = mix(cTertiaryC.rgb, deep(cTertiary.rgb), t);
    else             col = mix(oLight(), cSurfaceC.rgb, t);


    float body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
    // sombreado (terminador) → hacia surface
    float sh = length(q - hp) / 1.8;
    float shadeA = smoothstep(0.4, 1.0, sh) * 0.85;
    col = mix(col, cSurface.rgb, shadeA);
    over(acc, col, body);

    // borde luminoso (atmósfera) con el color del rol del cuerpo
    vec3 rim = (k == 0) ? cSecondary.rgb : (k == 1) ? cPrimary.rgb : (k == 2) ? cTertiary.rgb
             : (k == 3) ? cTertiaryC.rgb : oLight();
    float ra = (k >= 3 ? 0.7 : 0.6) * (1.0 - smoothstep(0.0, 0.05, abs(d - 1.03)));
    over(acc, rim, ra);

    // glifo + arco de batería (periféricos)
    if (k == 4) {
        float ga = glyphAlpha(q, glyph, aa) * body;
        over(acc, cOnSurface.rgb, ga);
        float rr = 1.36, hw = 0.075;
        float st = stroke(d - rr, hw, aa);
        float ang = mod(atan(q.x, -q.y) + TAU, TAU) / TAU;
        over(acc, cOutline.rgb, st * 0.30);
        over(acc, cPrimary.rgb, st * step(ang, clamp(batt, 0.0, 1.0)));
    }

    // aro de contexto casi lleno (planetas de IA) en error
    if (k <= 2 && ctxAlert > 0.001) {
        float st = stroke(d - 1.28, 0.06, aa);
        over(acc, cError.rgb, st * ctxAlert * 0.9);
    }

    fragColor = acc * qt_Opacity;
}
