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
// Cada función recibe q (unidades de R) y devuelve el color base del disco.
// `ringBack/ringFront` (solo Gemini) los rellena planetGemini.
float gRingBack = 0.0, gRingFront = 0.0;

vec3 planetClaude(vec2 q, float t){
    vec3 col = mix(cSecondary.rgb, deep(cSecondary.rgb), t);
    float cont = smoothstep(0.52, 0.64, fbm(q * 1.7 + 2.0));
    col = mix(col, cSecondaryC.rgb, cont * 0.85);
    col = mix(col, cTertiaryC.rgb, exp(-pow((q.y + 0.08) / 0.09, 2.0)) * 0.22);
    col = mix(col, cOnSurface.rgb, ell(q, vec2(-0.04, -0.98), vec2(0.48, 0.19)) * 0.75);
    float cr = 1.0 - smoothstep(0.0, 0.03, abs(length(q - vec2(0.30, -0.26)) - 0.07));
    cr += 1.0 - smoothstep(0.0, 0.03, abs(length(q - vec2(-0.44, 0.48)) - 0.05));
    col = mix(col, deep(cSecondary.rgb), clamp(cr, 0.0, 1.0) * 0.7);
    return col;
}

vec3 planetGemini(vec2 q, float t){
    vec3 col = mix(cPrimary.rgb, deep(cPrimary.rgb), t);
    float y = q.y + (fbm(vec2(q.x * 1.3, q.y * 3.0)) - 0.5) * 0.06;
    float sf = 0.05;
    col = mix(col, cPrimaryC.rgb,   band(y,-1.00,0.22,sf) * 0.80);
    col = mix(col, cOnSurface.rgb,  band(y,-0.78,0.14,sf) * 0.60);
    col = mix(col, cSecondary.rgb,  band(y,-0.64,0.26,sf) * 0.60);
    col = mix(col, cTertiaryC.rgb,  band(y,-0.38,0.12,sf) * 0.60);
    col = mix(col, cOnSurface.rgb,  band(y,-0.04,0.14,sf) * 0.55);
    col = mix(col, cPrimaryC.rgb,   band(y, 0.10,0.24,sf) * 0.80);
    col = mix(col, cSecondary.rgb,  band(y, 0.34,0.16,sf) * 0.60);
    col = mix(col, deep(cPrimary.rgb), band(y, 0.50,0.50,sf) * 0.85);
    float st = ell(q, vec2(-0.28, 0.26), vec2(0.24, 0.11));
    col = mix(col, cTertiary.rgb, st * 0.9);
    col = mix(col, cOnSurface.rgb, stroke(length((q - vec2(-0.28, 0.26)) / vec2(0.24, 0.11)) - 1.0, 0.08, 0.04) * 0.45);
    // anillo (elipse inclinada -18°)
    float ca = cos(radians(18.0)), sa = sin(radians(18.0));
    vec2 qr = vec2(q.x*ca - q.y*sa, q.x*sa + q.y*ca);
    float e = length(vec2(qr.x/1.58, qr.y/0.30));
    vec2 g = vec2(qr.x/(1.58*1.58), qr.y/(0.30*0.30)) / max(e, 1e-4);
    float dist = abs(e - 1.0) / max(length(g), 1e-4);
    float s = 1.0 - smoothstep(0.03, 0.04, dist);
    gRingBack  = s * 0.50 * step(qr.y, 0.0);
    gRingFront = s * 0.85 * step(0.0, qr.y);
    return col;
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
    if (k == 0)      col = planetClaude(q, t);
    else if (k == 1) col = planetGemini(q, t);
    else if (k == 2) col = planetOther(q, t);
    else if (k == 3) col = mix(cTertiaryC.rgb, deep(cTertiary.rgb), t);
    else             col = mix(oLight(), cSurfaceC.rgb, t);

    if (k == 1) over(acc, cSecondary.rgb, gRingBack * step(1.0, d));

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

    if (k == 1) over(acc, cSecondary.rgb, gRingFront);

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
