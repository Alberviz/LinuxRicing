#version 440
// mockB.frag — Gargantua por RAYMARCHING real (sin LUT, sin capas): cada rayo de pantalla
// integra la geodésica nula de Schwarzschild (rs=1, a = -1.5 h² x / |x|^5) y atraviesa UN
// solo disco-volumen fino (r_isco..r_out, H(r) pequeño). Bóveda, franja frontal y creciente
// salen de la física. Salida HDR lineal; bloom + ACES en bloom.frag/composite.frag.
// Compilar:  /usr/lib/qt6/bin/qsb --qt6 -o mockB.frag.qsb mockB.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float time;
    float elev;         // rad — elevación de la cámara sobre el plano del disco
    float bhRadius;     // px — radio de la SOMBRA (b_crit = 2.598 rs)
    float bhTilt;       // rad — rotación de pantalla
    vec2  resolution;
    vec2  bhCenter;
    vec4  colPrimary;   // m3primary
    vec4  colInk;       // m3onSurface (estrellas)
};
const float PI  = 3.14159265359;
const float TAU = 6.28318530718;
const float B_CRIT = 2.598076;
const float R_ISCO = 3.0, R_OUT = 11.0;
const float R_IA = 1.18;      // equivalencia con los parámetros de textura de A3 (rr = r/2.54)
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

// ------------------------------------------------------------------ raymarching
vec4 trace(vec2 pr)   // pr en unidades de rs (x derecha, y ABAJO en pantalla)
{
    float ce = cos(elev), se = sin(elev);
    vec3 cdir  = vec3(0.0, se, ce);
    vec3 right = vec3(1.0, 0.0, 0.0);
    vec3 up    = vec3(0.0, ce, -se);
    vec3 x = cdir * 30.0 + right * pr.x - up * pr.y;
    vec3 v = -cdir;
    vec3 h3 = cross(x, v);
    float h2 = dot(h3, h3);

    vec3 E = vec3(0.0);
    float Tr = 1.0;
    bool hit = false;
    float smkCache = 0.0;
    float jit = hash21(pr * 91.7 + time);
    vec3 xp = x;
    for (int i = 0; i < 120; i++){
        float r = length(x);
        if (r < 1.0) { hit = true; break; }
        if (r > 34.0 && dot(x, v) > 0.0) break;
        float dt = 0.11 * r + 0.02;

        // cruce del plano del disco (cara fina): una sola evaluación por cruce, con
        // el espesor integrado analíticamente: τ = κ·ρ·H·2.5/|v_y|
        if (i > 0 && (xp.y > 0.0) != (x.y > 0.0)){
            float tc = xp.y / (xp.y - x.y);
            vec3 xc = mix(xp, x, tc);
            float rc = length(xc);
            if (rc > R_ISCO * 0.9 && rc < R_OUT * 1.1){
                float rr = rc / 2.54;
                float rho = length(xc.xz);
                vec2 cs = xc.xz / max(rho, 1e-4);
                float phi = atan(cs.y, cs.x);
                float outer = smoothstep(4.0, 11.0, rc);
                float smk = outer > 0.0 ? smokeN(rr, cs) : 0.5;
                float H = 0.0035 * rc * (1.0 + 0.8 * outer * smk);
                float fN = clamp((rr - R_IA) / (R_OUT/2.54 - R_IA), 0.0, 1.0);
                float rl = rr - R_IA;
                float n = flowNoise(rr, phi);
                float D = smoothstep(0.32 * R_OUT, 0.8 * R_OUT, rc);        // 0 = vetas lisas · 1 = polvo
                float veins = 0.12 + 1.9 * smoothstep(0.22, 0.80, n);
                float outerMix = smoothstep(0.10, 0.55, fN);
                float dust0 = 0.25 + 1.6 * smoothstep(0.25, 0.75, smk) * (0.6 + 0.8*n);
                float dens = mix(veins, dust0, outerMix);
                float absorb = 1.0, grainB = 1.0, grain = 0.5;
                if (D > 0.0){
                    float rj = rr + (jit - 0.5) * 0.03;
                    grain = 0.6 * vnoise3(vec3(cs * 7.0 + 3.0, rj * 26.0)) + 0.4 * vnoise3(vec3(cs * 16.0 + 9.0, rj * 60.0));
                    float clump = vnoise3(vec3(cs * 3.5 + 13.0, rj * 8.0));
                    float lane  = smoothstep(0.52, 0.80, vnoise3(vec3(cs * 1.3 + 7.0, rr * 16.0 + 3.0)));
                    absorb = 1.0 - 0.95 * lane * D;
                    dens *= mix(1.0, 0.25 + 1.9 * smoothstep(0.22, 0.80, 0.55*clump + 0.55*grain), D);
                    grainB = mix(1.0, 0.45 + 1.3 * grain, D);
                }
                vec3 tang = normalize(cross(vec3(0,1,0), vec3(xc.x, 0.0, xc.z)));
                float beta = sqrt(0.5 / rc);
                float dop = 1.0 / (1.0 - beta * dot(tang, -v));
                float beam = clamp(pow(dop, 1.3), 0.6, 1.9);

                float I0 = 4.2 * exp(-1.9*rl) + 2.0 * pow(rr / R_IA, -1.05);
                float edgeT = (R_OUT * 0.95 - rc) / (0.7 * R_OUT);
                float outerFade = smoothstep(0.0, 0.45, edgeT + (grain - 0.5) * 2.0 * D + (smk - 0.5) * 0.5 * outerMix);
                outerFade *= smoothstep(-0.12, 0.12, edgeT);
                float innerLip = smoothstep(R_ISCO * 0.93, R_ISCO * 1.12, rc);
                float path = min(2.5 * H / (abs(v.y) + 1e-3), 6.0);
                float dtau = 18.0 * (1.0 + 3.0 * (1.0 - D)) * dens * outerFade * innerLip * absorb * path;
                float a = 1.0 - exp(-dtau);

                float heat = clamp(0.9*exp(-0.85*rl) + 0.18*(dens - 1.0) + 0.10*(beam - 1.0), 0.0, 1.0);
                vec3 S = ramp(heat) * I0 * dens * beam * grainB * absorb;
                E += Tr * a * S / pow(max(dens, 0.2), 0.35);
                Tr *= 1.0 - a;
                if (Tr < 0.01) break;
            }
        }
        xp = x;
        vec3 acc = -1.5 * h2 * x / (r*r*r*r*r);
        v += acc * dt;
        v = normalize(v);
        x += v * dt;
    }
    return vec4(E, hit ? 0.0 : Tr);   // rgb = emisión, a = transmitancia hacia el fondo (0 = horizonte)
}

// Capa del agujero: se renderiza a MEDIA resolución (el coste es el raymarching) y
// bhcomp.frag la compone a resolución completa sobre las estrellas.
void main(){
    vec2 frag = qt_TexCoord0 * resolution;
    float R = bhRadius / B_CRIT;                 // px por rs
    vec2 rel = frag - bhCenter;
    float ct = cos(-bhTilt), st = sin(-bhTilt);
    vec2 pr = vec2(rel.x*ct - rel.y*st, rel.x*st + rel.y*ct) / R;
    vec4 L = vec4(0.0, 0.0, 0.0, 1.0);
    if (abs(pr.x) < 12.5 && abs(pr.y) < 7.5) L = trace(pr);
    else if (length(pr) < B_CRIT) L.a = 0.0;
    fragColor = L;
}
