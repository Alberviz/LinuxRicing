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
    vec4  cClaude;    // color elegido en vivo para Claude
    vec4  cGemini;    // color elegido en vivo para Gemini
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

// bola de luz simple (misma familia que los soles): núcleo claro, borde en el color
// del proveedor y halo suave. Premultiplicado. ql en unidades del orbe (R = 1).
vec4 lightOrb(vec2 ql, vec3 c, float aaq){
    vec4 o = vec4(0.0);
    float d = length(ql);
    float halo = exp(-max(d - 1.0, 0.0) * 3.4) * step(1.0, d + 0.5);
    over(o, c, halo * 0.42);
    float body = 1.0 - smoothstep(1.0 - aaq, 1.0 + aaq, d);
    vec3 col = mix(mix(c, vec3(1.0), 0.80), c, smoothstep(0.0, 0.95, d));
    over(o, col, body);
    return o;
}

// ---- CLAUDE: orbe de luz con la CRUZ de doble anillo ----
// Color: cClaude (lo elige SolarSystem.qml en vivo del tema, ver pickProviderColors).
vec4 planetClaude(vec2 q, float aa){
    vec4 acc = vec4(0.0);
    vec3 c = cClaude.rgb;
    vec3 rc = mix(c, vec3(1.0), 0.45);
    vec2 r1 = ringE(q, 1.50, 0.34, -22.0, 0.035, aa);
    vec2 r1g = ringE(q, 1.50, 0.34, -22.0, 0.10, aa);
    vec2 r2 = ringE(q, 1.28, 0.29, 22.0, 0.030, aa);
    vec2 r2g = ringE(q, 1.28, 0.29, 22.0, 0.09, aa);
    float d = length(q);
    float behind = step(1.0, d);
    over(acc, c, (r1g.x * 0.14 + r1.x * 0.45) * step(r1.y, 0.0) * behind);
    over(acc, c, (r2g.x * 0.14 + r2.x * 0.45) * step(r2.y, 0.0) * behind);
    vec4 orb = lightOrb(q, c, aa);
    over(acc, orb.rgb / max(orb.a, 1e-4), orb.a);
    over(acc, rc, (r1g.x * 0.18 + r1.x * 0.90) * step(0.0, r1.y));
    over(acc, rc, (r2g.x * 0.18 + r2.x * 0.90) * step(0.0, r2.y));
    return acc;
}

// ---- GEMINI: dos orbes de luz gemelos muy juntos ----
// Color: cGemini (distinto de Claude; ver pickProviderColors).
vec4 planetGemini(vec2 q, float aa){
    vec4 acc = vec4(0.0);
    const float SG = 1.3;
    vec2 p = q / SG;
    float aap = aa / SG;
    vec3 c = cGemini.rgb;
    // puente de luz entre los gemelos
    float ax = abs(p.x);
    if (ax < 0.30) {
        float h = 0.05 + 0.13 * pow(ax / 0.30, 1.5);
        float dy = abs(p.y);
        over(acc, c, (1.0 - smoothstep(h, h + 0.14, dy)) * 0.30);
    }
    float R = 0.54;
    vec2 cl = vec2(-0.58, -0.03), cr = vec2(0.58, 0.04);
    vec4 oa = lightOrb((p - cl) / R, c, aap / R);
    vec4 ob = lightOrb((p - cr) / R, mix(c, vec3(1.0), 0.18), aap / R);
    over(acc, oa.rgb / max(oa.a, 1e-4), oa.a);
    over(acc, ob.rgb / max(ob.a, 1e-4), ob.a);
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
