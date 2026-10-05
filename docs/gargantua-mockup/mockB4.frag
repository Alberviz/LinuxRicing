#version 440
// mockB4.frag — PASE DE SOMBREADO (por frame, resolución completa). Lee el búfer geométrico
// (mockB3_geo.frag: hasta 3 tramos de rayo por píxel: r, φ, espesor fino, espesor de bruma, Doppler,
// flag de horizonte) y aplica vetas laminares → polvo (según r), rotación kepleriana, Doppler,
// absorción y bruma. Salida HDR lineal; bloom + ACES en bloom.frag / composite.frag.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float time;
    float bhRadius;
    float bhTilt;
    vec2  resolution;
    vec2  bhCenter;
    vec4  colPrimary;   // m3primary
    vec4  colInk;       // m3onSurface
};
layout(binding = 1) uniform sampler2D geoA;
layout(binding = 2) uniform sampler2D geoB;
layout(binding = 3) uniform sampler2D geoC;
layout(binding = 4) uniform sampler2D geoF;
const float PI  = 3.14159265359;
const float TAU = 6.28318530718;
const float B_CRIT = 2.598076;
const float R_ISCO = 1.8, R_OUT = 11.0;
const float R_IA = 1.18;
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


float starsHash(vec2 p){ return hash21(p); }
void starfield(inout vec3 acc, vec2 frag, vec3 ink){
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
        acc += sc * smoothstep(s, 0.0, pr) * (0.14 + b*0.55);
    }
}
float omegaK(float rD){ return 0.62 * pow(rD / R_IA, -1.5); }

float streak(float rD, vec2 cs, float seed){
    float n = 0.0, a = 0.5, fr = 4.5, K = 3.0;
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


// ------------------------------------------------------------------ disco (volumen fino)
float smokeN(float rr, vec2 cs){
    float n = 0.0, a = 0.5, fr = 0.55, K = 0.9;
    for (int i=0;i<3;i++){
        n += a * vnoise3(vec3(cs*K + 31.0, rr*fr + time*0.02));
        a *= 0.5; fr *= 2.1; K *= 1.8;
    }
    return n / 0.875;
}


// un tramo de rayo → (rgb emitido, opacidad)
float gHazeSh = 1.0;
vec4 shadeSeg(vec4 s, float dop, float jit, float shFade)
{
    float rc = s.x;
    vec2 cs = vec2(cos(s.y), sin(s.y));
    float rr = rc / 2.54;
    float phi = s.y;
    float wt = s.z, wh = s.w;
    float outer = smoothstep(4.0, 11.0, rc);
    float smk = outer > 0.0 ? smokeN(rr, cs) : 0.5;
    float fN = clamp((rc - R_ISCO) / (R_OUT - R_ISCO), 0.0, 1.0);
    float rl = (rc - R_ISCO) / 2.54;
    float n = flowNoise(rr, phi);
    float D = smoothstep(0.32 * R_OUT, 0.85 * R_OUT, rc);        // 0 = vetas lisas · 1 = polvo

    // densidad: vetas laminares dentro, humo/polvo fuera
    float veins = 0.12 + 1.9 * smoothstep(0.22, 0.80, n);
    float outerMix = smoothstep(0.10, 0.55, fN);
    float dust0 = 0.25 + 1.6 * smoothstep(0.25, 0.75, smk) * (0.6 + 0.8*n);
    float dens = mix(veins, dust0, outerMix);

    // polvo SUAVE: grano fino estirado en dirección orbital, grumos, carriles de absorción
    float absorb = 1.0, grainB = 1.0, grain = 0.5, hazeMod = 1.0;
    if (D > 0.0){
        float rj = rr + (jit - 0.5) * 0.0004;
        float g1 = vnoise3(vec3(cs * 5.0 + 3.0,  rj * 34.0));
        float g2 = vnoise3(vec3(cs * 8.0 + 9.0, rj * 46.0 + time * 0.03));
        grain = 0.6 * g1 + 0.4 * g2;
        float clump = vnoise3(vec3(cs * 2.6 + 13.0, rj * 6.0));
        float lane  = smoothstep(0.35, 0.85, vnoise3(vec3(cs * 1.2 + 7.0, rr * 14.0 + 3.0)));
        absorb = 1.0 - 0.90 * lane * D;
        dens *= mix(1.0, 0.35 + 1.25 * smoothstep(0.10, 0.95, 0.5*clump + 0.6*grain), D);
        grainB = mix(1.0, 0.15 + 2.2 * grain * grain, D);
        float brush = 0.65 * vnoise3(vec3(cs * 2.2 + 5.0, rj * 30.0)) + 0.35 * vnoise3(vec3(cs * 5.0 + 11.0, rj * 70.0));
        hazeMod = 0.10 + 2.4 * smoothstep(0.25, 0.80, brush) * (0.35 + clump);
    }
    float beam = clamp(pow(1.0 / (1.0 - sqrt(0.5 / rc) * dop), 2.0), 0.45, 2.6);

    float I0 = 16.0 * exp(-3.0*rl) + 3.0 * exp(-0.5*rl) * pow(rc / R_ISCO, -0.9);
    float edgeT = (R_OUT * 0.95 - rc) / (0.7 * R_OUT);
    float outerFade = smoothstep(0.0, 0.8, edgeT + (grain - 0.5) * 0.6 * D + (smk - 0.5) * 0.5 * outerMix);
    float innerLip = smoothstep(R_ISCO * 0.93, R_ISCO * 1.12, rc);

    // capa fina (vetas) + bruma volumétrica tenue (más gruesa hacia fuera)
    float tauT = 18.0 * (1.0 + 0.6 * (1.0 - D)) * dens * outerFade * innerLip * absorb * wt;
    float hazeFade = smoothstep(R_OUT * 1.15, R_OUT * 0.45, rc);
    float tauH = gHazeSh * 4.0 * hazeMod * hazeFade * innerLip * smoothstep(2.5, 6.0, rc) * wh * (0.5 + 0.5 * absorb);
    float tau = tauT + tauH;
    if (tau < 1e-5) return vec4(0.0);
    float heat = clamp(0.9*exp(-0.85*rl) + 0.18*(dens - 1.0) + 0.10*(beam - 1.0), 0.0, 1.0);
    vec3 St = ramp(heat) * I0 * dens * beam * grainB * absorb / pow(max(dens, 0.2), 0.35);
    vec3 Sh = ramp(0.45 + heat * 0.5) * (1.5 + I0 * 0.6) * beam * grainB;
    vec3 S = (St * tauT + Sh * tauH) / tau;
    return vec4(S, (1.0 - exp(-tau)) * shFade);
}

void main(){
    vec2 frag = qt_TexCoord0 * resolution;
    float R = bhRadius / B_CRIT;
    vec2 rel = frag - bhCenter;
    float ct = cos(-bhTilt), st = sin(-bhTilt);
    vec2 pr = vec2(rel.x*ct - rel.y*st, rel.x*st + rel.y*ct) / R;
    float rho = length(pr);

    vec3 stars = vec3(0.0);
    starfield(stars, frag, colInk.rgb);
    vec3 bg = toLin(min(stars, vec3(1.0)));

    vec4 f = texture(geoF, qt_TexCoord0);
    float jit = 0.5;
    // el disco lensado DENTRO del círculo de la sombra se apaga (sombra negra); el lado cercano (franja) no
    float inSh = f.x > 0.5 ? smoothstep(B_CRIT * 0.80, B_CRIT * 1.0, rho) : 1.0;
gHazeSh = inSh;
#define sf0(s) (sin((s).y) > 0.1 ? 1.0 : inSh)
#define sf(s) inSh
    vec3 E = vec3(0.0);
    float Tr = 1.0;
    vec4 s0 = texture(geoA, qt_TexCoord0);
    if (s0.z + s0.w > 1e-5){
        vec4 c = shadeSeg(s0, f.y, jit, sf0(s0));
        E += Tr * c.a * c.rgb; Tr *= 1.0 - c.a;
    }
    vec4 s1 = texture(geoB, qt_TexCoord0);
    if (Tr > 0.01 && s1.z + s1.w > 1e-5){
        vec4 c1 = shadeSeg(s1, f.z, jit, sf(s1));
        E += Tr * c1.a * c1.rgb; Tr *= 1.0 - c1.a;
    }
    vec4 s2 = texture(geoC, qt_TexCoord0);
    if (Tr > 0.01 && s2.z + s2.w > 1e-5){
        vec4 c2 = shadeSeg(s2, f.w, jit, sf(s2));
        E += Tr * c2.a * c2.rgb; Tr *= 1.0 - c2.a;
    }
    // anillo de fotones fino (imagen lensada del disco, circular en pantalla)
    float ring = exp(-0.5 * pow((rho - B_CRIT) / 0.010, 2.0));
    float ringDop = 0.75 + 0.5 * clamp(0.5 - 0.5 * pr.x / max(rho, 1e-3), 0.0, 1.0);
    vec3 ringCol = lit(toLin(colPrimary.rgb), 0.55) * 2.2 * ringDop;
    E += Tr * ring * ringCol;

    vec3 col = E + (f.x > 0.5 ? vec3(0.0) : Tr * bg);
    // alpha = 0 solo en la sombra pura (horizonte sin disco delante): el bloom no entra ahí
    float pure = (f.x > 0.5 && Tr > 0.995) ? 0.0 : 1.0;
    fragColor = vec4(col, pure);
}
