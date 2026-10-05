#version 440
// mockA.frag — MOCKUP del agujero negro estilo Gargantua (HDR lineal, SIN tonemap:
// el tonemap ACES va en composite.frag tras el bloom).
// Base: blackHole() de 5fbc679 (LUT de lente real lens_lut_order0/1) pero con UN solo
// disco: LUT orden 0 (cuerpo + banda frontal) y orden 1 (bóveda superior + creciente
// inferior) evalúan la MISMA función de superficie surfaceDisc(rD, phi).
// Compilar:  /usr/lib/qt6/bin/qsb --qt6 -o mockA.frag.qsb mockA.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float time;
    float variantUnused;
    float bhRadius;     // px — radio de la SOMBRA (b_crit)
    float bhTilt;       // rad
    vec2  resolution;
    vec2  bhCenter;
    vec4  colPrimary;   // m3primary
    vec4  colInk;       // m3onSurface (estrellas)
};

layout(binding = 1) uniform sampler2D lutR0;
layout(binding = 2) uniform sampler2D lutAz0;
layout(binding = 3) uniform sampler2D lutR1;
layout(binding = 4) uniform sampler2D lutAz1;

const float PI  = 3.14159265359;
const float TAU = 6.28318530718;
const float B_CRIT = 2.598076;   // sombra en unidades de la LUT
const float LUT_RHO_MAX = 12.0;
const float R_HORIZ = 1.0, R_OUTER = 10.0, R_ISCO = 1.18;

vec3 lit(vec3 c, float k){ return mix(c, vec3(1.0), k); }
vec3 toLin(vec3 c){ return pow(c, vec3(2.2)); }
vec3 dk(vec3 c, float k){ return c * (1.0 - k); }

float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
vec2  hash22(vec2 p){ float n = sin(dot(p, vec2(41.0, 289.0))); return fract(vec2(262144.0, 32768.0)*n); }
float hash31(vec3 p){ p = fract(p*0.1031); p += dot(p, p.zyx+31.32); return fract((p.x+p.y)*p.z); }
float vnoise3(vec3 p){
    vec3 i = floor(p), f = fract(p);
    vec3 u = f*f*(3.0-2.0*f);
    float a = hash31(i),               b = hash31(i+vec3(1,0,0));
    float c = hash31(i+vec3(0,1,0)),   d = hash31(i+vec3(1,1,0));
    float e = hash31(i+vec3(0,0,1)),   g = hash31(i+vec3(1,0,1));
    float h = hash31(i+vec3(0,1,1)),   k = hash31(i+vec3(1,1,1));
    return mix(mix(mix(a,b,u.x), mix(c,d,u.x), u.y), mix(mix(e,g,u.x), mix(h,k,u.x), u.y), u.z);
}

// ------------------------------------------------------------------ estrellas (de solarfield.frag HEAD)
void starfield(inout vec3 acc, vec2 frag, vec2 bhC, float R, vec3 ink){
    vec3 sc = lit(ink, 0.45);
    float cell = 54.0;
    vec2 id = floor(frag / cell);
    for (int oy=-1; oy<=1; oy++)
    for (int ox=-1; ox<=1; ox++){
        vec2 cid = id + vec2(ox, oy);
        vec2 rnd = hash22(cid);
        if (rnd.x > 0.40) continue;
        vec2 spos = (cid + hash22(cid+3.7)) * cell;
        float b = fract(rnd.y * 91.7);
        float pr = distance(frag, spos);
        float s  = b < 0.7 ? 0.9 : 1.7;
        float pt = smoothstep(s, 0.0, pr);
        acc += sc * pt * (0.14 + b*0.55);
    }
}

// ------------------------------------------------------------------ LUT casi de canto (gen_lut_edge.c)
// 4 texturas (r y azimut por orden, 16 bits en R=hi,G=lo). Bilineal manual solo entre
// téxeles válidos; el azimut se interpola como vector (cos,sin): sin costura 0↔1.
struct Lut { float r; vec2 cs; float cov; };
float dec16(vec4 s){ return (s.r*255.0*256.0 + s.g*255.0) / 65535.0; }
Lut lutSample(sampler2D tr, sampler2D taz, vec2 uv){
    const float N = 2048.0;
    vec2 p = uv * N - 0.5;
    ivec2 i0 = ivec2(floor(p));
    vec2 f = p - vec2(i0);
    float rs = 0.0, cov = 0.0; vec2 vs = vec2(0.0);
    for (int j=0;j<2;j++) for (int i=0;i<2;i++){
        ivec2 ip = clamp(i0 + ivec2(i,j), ivec2(0), ivec2(2047));
        float w = (i==0 ? 1.0-f.x : f.x) * (j==0 ? 1.0-f.y : f.y);
        vec2 tc = (vec2(ip) + 0.5) / N;
        vec4 s = texture(tr, tc);
        if (s.r + s.g < 1e-4) continue;
        float phi = dec16(texture(taz, tc)) * TAU - PI;
        rs += w*dec16(s); cov += w; vs += w*vec2(cos(phi), sin(phi));
    }
    Lut o; o.r = cov > 0.0 ? rs/cov : 0.0; o.cs = vs; o.cov = cov;
    if (cov > 0.0) o.cs = vs / max(length(vs), 1e-4);
    return o;
}

// ------------------------------------------------------------------ superficie ÚNICA del disco
// Todas las ramas llaman a surfaceDisc(rD, phi). Kepler ω ∝ r^-1.5 con flow-noise de
// 2 fases cruzadas (nunca se enrolla más de T·ω). Toda la luz sale del tema (colPrimary).
float omegaK(float rD){ return 0.62 * pow(rD / R_ISCO, -1.5); }

float streak(float rD, vec2 cs, float seed){
    float n = 0.0, a = 0.5, fr = 2.4, K = 1.2;
    for (int i=0;i<3;i++){
        n += a * vnoise3(vec3(cs*K + seed*13.7, rD*fr + seed*5.1));
        a *= 0.75; fr *= 2.4; K *= 1.6;
    }
    return n / (0.5 + 0.375 + 0.28125);
}

float flowNoise(float rD, float phi){
    const float T = 16.0;
    float acc = 0.0, w2 = 0.0;
    for (int k=0;k<2;k++){
        float ph = fract(time / T + 0.5*float(k));
        float w  = 1.0 - abs(2.0*ph - 1.0);
        float a  = phi - omegaK(rD) * (ph - 0.5) * T;
        acc += w * (streak(rD, vec2(cos(a), sin(a)), float(k)) - 0.5);
        w2  += w*w;
    }
    return 0.5 + acc / sqrt(w2);
}

// humo exterior: fbm de baja frecuencia (disco difuso, tipo HEAD edgeWarp)
float smokeNoise(float rD, vec2 cs){
    float n = 0.0, a = 0.5, fr = 0.55, K = 0.9;
    for (int i=0;i<3;i++){
        n += a * vnoise3(vec3(cs*K + 31.0, rD*fr + time*0.02));
        a *= 0.5; fr *= 2.1; K *= 1.8;
    }
    return n / 0.875;
}

// rampa de temperatura, solo roles del tema: lit(P,.95) labio caliente → P → dk(P)
vec3 ramp(float x){
    vec3 P = toLin(colPrimary.rgb);
    vec3 c4 = lit(P, 0.95);
    vec3 c2 = P;
    vec3 c0 = dk(P, 0.62);
    if (x < 0.5) return mix(c0, c2, x/0.5);
    return mix(c2, c4, (x-0.5)/0.5);
}

// devuelve (rgb HDR emitido, alfa de ocultación)
vec4 surfaceDisc(float rD, vec2 cs, float uScreen){
    float phi = atan(cs.y, cs.x);
    float rl  = (rD - R_ISCO);
    float fN  = clamp(rl / (R_OUTER - R_ISCO), 0.0, 1.0);

    float n    = flowNoise(rD, phi);
    float smk  = smokeNoise(rD, cs);
    float veins = 0.16 + 1.75 * smoothstep(0.22, 0.80, n);
    // hacia fuera las vetas se funden en humo
    float outerMix = smoothstep(0.10, 0.55, fN);
    float dens = mix(veins, 0.25 + 1.6 * smoothstep(0.25, 0.75, smk) * (0.6 + 0.8*n), outerMix);

    // Doppler suave: izquierda (se acerca) más brillante, mismo tono
    float approach = 0.5 - 0.5 * uScreen / (abs(uScreen) + 3.0);
    float beam = mix(0.75, 1.40, approach);

    float I0 = 4.2 * exp(-1.9*rl) + 1.5 * pow(rD / R_ISCO, -1.35);
    float rW = rD + (smk - 0.5) * 2.4 * outerMix;          // borde exterior irregular
    float outerFade = smoothstep(R_OUTER, 2.0, rW);
    float innerLip  = smoothstep(R_ISCO - 0.02, R_ISCO + 0.20, rD);
    float I = I0 * dens * beam;

    float heat = clamp(0.95*exp(-0.85*rl) + 0.18*(dens - 1.0) + 0.10*(beam - 1.0), 0.0, 1.0);
    vec3 chroma = ramp(heat);

    float alpha = outerFade * innerLip * clamp(0.45 + 0.55*dens, 0.0, 1.0);
    return vec4(chroma * I, alpha);
}

// ------------------------------------------------------------------ agujero
// acumula front-to-back: orden 0 delante, luego orden 1, la sombra opaca detrás de todo
vec3 blackHole(vec2 frag, vec3 bg)
{
    float R = bhRadius / B_CRIT;
    vec2 rel = frag - bhCenter;
    float ct = cos(-bhTilt), st = sin(-bhTilt);
    vec2 pr = vec2(rel.x*ct - rel.y*st, rel.x*st + rel.y*ct);
    float rho = length(pr) / R;
    if (rho > LUT_RHO_MAX * 0.97) return bg;

    float u = pr.x / R;
    vec2 uv = pr / (R * 2.0 * LUT_RHO_MAX) + 0.5;

    vec3 E = vec3(0.0);
    float Tr = 1.0;

    Lut l0 = lutSample(lutR0, lutAz0, uv);
    if (l0.cov > 0.001){
        float rD = mix(R_HORIZ, R_OUTER, l0.r);
        vec4 s = surfaceDisc(rD, l0.cs, u);
        float a = s.a * l0.cov;
        E += Tr * s.rgb * a; Tr *= 1.0 - a;
    }
    Lut l1 = lutSample(lutR1, lutAz1, uv);
    if (l1.cov > 0.001){
        float rD = mix(R_HORIZ, R_OUTER, l1.r);
        vec4 s = surfaceDisc(rD, l1.cs, u);
        s.rgb *= 0.55;                       // imagen de 2.º orden: más tenue
        float a = s.a * l1.cov;
        E += Tr * s.rgb * a; Tr *= 1.0 - a;
    }
    // sombra: negro puro y opaco
    float shadow = smoothstep(B_CRIT + 0.012, B_CRIT - 0.012, rho);
    return E + Tr * (1.0 - shadow) * bg;
}

void main(){
    vec2 frag = qt_TexCoord0 * resolution;
    vec3 stars = vec3(0.0);
    starfield(stars, frag, bhCenter, bhRadius, colInk.rgb);
    vec3 bg = toLin(min(stars, vec3(1.0)));
    vec3 col = blackHole(frag, bg);
    fragColor = vec4(col, 1.0);
}
