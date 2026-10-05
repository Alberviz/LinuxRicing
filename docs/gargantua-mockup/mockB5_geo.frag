#version 440
// mockB5_geo.frag — PASE GEOMÉTRICO (una sola vez). Un rayo por píxel (2x2 supersampleado, con
// jitter de paso) contra UN solo disco: capa fina + bruma gaussiana que se ensancha con r.
//
// Gravedad: geodésica nula de Schwarzschild en forma de Binet, x'' = -K h² x / r^5
// (u'' + u = K u²): órbita de fotones en r = K, b_crit = √3·K. Con K = 1.68 y r_isco = 1.8 el
// borde interior queda a 1.07·r_fotón, como el lado progrado de un Kerr rápido: las imágenes
// casi críticas (anillo de fotones) salen de los rayos que dan la vuelta y tocan el disco y
// quedan pegadas al borde de la sombra. Nada se dibuja aparte.
//
// Salidas (outSel elige; 3 texturas RGBA32F, cada una un pase):
//   0, 1  tramo k de la capa fina = (r̄, φ̄, ∫ρ_fina·dt, Doppler cosθ)   (k=1: imágenes casi críticas)
//   2     bruma = (r̄, φ̄, luminancia ∫ j·T dt, y/H + 10·nº de submuestras que caen al horizonte)
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float outSel;
    float elev;
    float bhRadius;
    float bhTilt;
    vec2  resolution;
    vec2  bhCenter;
};
const float KG = 1.68;
const float B_CRIT = 2.9098;          // √3·KG
const float R_ISCO = 1.8;
const float R_OUT_T = 8.0;           // capa fina
const float R_OUT_H = 30.0;           // bruma
const float K_THIN = 60.0;            // opacidad estática de la capa fina (igual que el sombreado)

float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

float Ht(float r){ return 0.006 * r; }
float Hh(float r){ return 0.009 * pow(r, 1.3); }
// densidad superficial de la capa fina (perfil radial suave)
float sigT(float r){ return smoothstep(R_ISCO * 0.97, R_ISCO * 1.08, r) * (1.0 - smoothstep(0.55 * R_OUT_T, R_OUT_T, r)); }
// densidad de la bruma: polvo exterior ensanchado (r > ~6), cola larga decreciente; dentro
// la barre el disco caliente y solo queda la capa fina
float rhoH(float r){
    return smoothstep(5.0, 10.0, r) * pow(r / 10.0, -1.1) * (1.0 - smoothstep(0.55 * R_OUT_H, R_OUT_H, r));
}
// iluminación de la bruma (luz central dispersada) con Doppler suave g^3
// fase Henyey-Greenstein: la bruma delante del agujero dispersa hacia la cámara (brilla),
// la de detrás retrodispersa (tenue). cosS = coseno entre luz saliente del centro y la cámara.
float illumH(float r, float dop, float cosS){
    float beta = 0.42 * sqrt(R_ISCO / r);
    float g = 1.0 / (inversesqrt(1.0 - beta*beta) * (1.0 - beta * dop));
    const float G = 0.6;
    float hg = (1.0 - G*G) / pow(1.0 + G*G - 2.0*G*cosS, 1.5);
    return pow(r / 10.0, -1.0) * g*g*g * hg;
}

struct Segs { vec4 P0, P1, P2; vec3 Q0, Q1, Q2; vec4 H; vec2 HQ; float hit; float Hj2; float Hy; };

Segs traceRay(vec2 frag, float jit)
{
    float R = bhRadius / B_CRIT;
    vec2 rel = frag - bhCenter;
    float ct = cos(-bhTilt), st = sin(-bhTilt);
    vec2 pr = vec2(rel.x*ct - rel.y*st, rel.x*st + rel.y*ct) / R;
    Segs S;
    S.P0 = vec4(0.0); S.P1 = vec4(0.0); S.P2 = vec4(0.0);   // Σρ·r, —, Σρ, Th_delante
    S.Q0 = vec3(0.0); S.Q1 = vec3(0.0); S.Q2 = vec3(0.0);   // Σρ·cosφ, Σρ·sinφ, Σρ·dop
    S.H = vec4(0.0); S.HQ = vec2(0.0); S.Hj2 = 0.0; S.Hy = 0.0;                      // Σj·r, Σj, E, — ; Σj·cs
    S.hit = 0.0;
    float Th = 1.0, Tt = 1.0;              // transmitancias: bruma, capa fina (estática)
    if (abs(pr.x) < 26.0 && abs(pr.y) < 14.0){
        float ce = cos(elev), se = sin(elev);
        vec3 cdir = vec3(0.0, se, ce);
        vec3 x = cdir * 44.0 + vec3(1.0,0.0,0.0) * pr.x - vec3(0.0, ce, -se) * pr.y;
        vec3 v = -cdir;
        vec3 h3 = cross(x, v);
        float h2 = dot(h3, h3);
        int run = -1;
        bool was = false;
        bool first = true;
        for (int i = 0; i < 900; i++){
            float r = length(x);
            if (r < 0.7 * KG) { S.hit = 1.0; break; }
            if (r > 46.0 && dot(x, v) > 0.0) break;
            if (Th * Tt < 0.004) break;
            float sp = length(v);
            vec3 u = v / sp;
            // paso espacial
            float ds = 0.05 * r + 0.008;
            float ht = Ht(r), hh = Hh(r);
            float ay = abs(x.y);
            bool nearT = r > R_ISCO * 0.95 && r < R_OUT_T * 1.05 && ay < 3.5 * ht;
            bool nearH = r > 2.0 && r < R_OUT_H * 1.05 && ay < 3.2 * hh;
            if (nearT) ds = min(ds, max(0.35 * ht / (abs(u.y) + 0.02), 0.006));
            if (nearH) ds = min(ds, clamp(0.6 * hh / (abs(u.y) + 1e-3), 0.05, 0.3 + 0.02 * r));
            if (!nearT){                     // acercarse a la capa fina sin saltársela
                float dy = ay - 3.5 * ht;
                if (r > R_ISCO * 0.9 && r < R_OUT_T * 1.1 && dy > 0.0)
                    ds = min(ds, max(dy / (abs(u.y) + 1e-3) * 0.7, 0.006));
            }
            if (!nearH && r < R_OUT_H * 1.1 && r > 2.0){
                float dy = ay - 3.2 * hh;
                if (dy > 0.0) ds = min(ds, max(dy / (abs(u.y) + 1e-3) * 0.7, 0.02));
            }
            if (first){ ds *= jit; first = false; }   // jitter del primer paso: rompe las cortinas

            if (nearT || nearH){
                vec2 cs = x.xz / max(length(x.xz), 1e-4);
                vec3 tang = vec3(-cs.y, 0.0, cs.x);
                float dop = dot(tang, -u);
                if (nearT){
                    float rt = sigT(r) * exp(-0.5 * ay*ay / (ht*ht)) / ht * 0.006 * ds;
                    if (rt > 0.0){
                        if (!was){ run++; was = true;
                            if (run == 0) S.P0.w = Th; else if (run == 1) S.P1.w = Th; else if (run == 2) S.P2.w = Th; }
                        vec4 a = vec4(rt * r, 0.0, rt, 0.0);
                        vec3 q = rt * vec3(cs, dop);
                        if (run == 0){ S.P0.xyz += a.xyz; S.Q0 += q; }
                        else if (run == 1){ S.P1.xyz += a.xyz; S.Q1 += q; }
                        else if (run == 2){ S.P2.xyz += a.xyz; S.Q2 += q; }
                        Tt *= exp(-K_THIN * rt);
                    }
                }
                if (nearH){
                    float rh = rhoH(r) * exp(-0.5 * ay*ay / (hh*hh)) * ds;
                    if (rh > 0.0){
                        float j = rh * illumH(r, dop, dot(x / r, -u)) * Th * Tt;
                        S.H.x += j * r; S.Hj2 += j; S.H.y += j; S.HQ += j * cs; S.Hy += j * x.y / hh;
                        Th *= exp(-0.04 * rh);
                    }
                }
            }
            if (!nearT) was = false;

            // leapfrog en el parámetro afín (|v| no se normaliza: la forma de Binet lo exige)
            float dl = ds / sp;
            vec3 acc = -KG * h2 * x / (r*r*r*r*r);
            v += acc * 0.5 * dl;
            x += v * dl;
            float r2 = length(x);
            v += (-KG * h2 * x / (r2*r2*r2*r2*r2)) * 0.5 * dl;
        }
    } else if (length(pr) < B_CRIT) S.hit = 1.0;
    S.H.z = Th;
    return S;
}

void main(){
    vec2 frag = qt_TexCoord0 * resolution;
    vec4 A0 = vec4(0.0), A1 = vec4(0.0);
    vec3 B0 = vec3(0.0), B1 = vec3(0.0);
    vec4 HH = vec4(0.0); vec2 HQ = vec2(0.0);
    float hj = 0.0, hy = 0.0, hit = 0.0;
    for (int j = 0; j < 2; j++) for (int i = 0; i < 2; i++){
        vec2 o = vec2(float(i) - 0.5, float(j) - 0.5) * 0.5;
        float jit = 0.15 + 0.85 * hash12(frag * 1.37 + o * 17.0 + 3.1);
        Segs S = traceRay(frag + o, jit);
        A0.xyz += S.P0.xyz; B0 += S.Q0;
        A1.xyz += S.P1.xyz; B1 += S.Q1;
        HH.xy += S.H.xy; HQ += S.HQ; hj += S.Hj2; hy += S.Hy;
        hit += S.hit;                                  // 0..4 (entero)
    }
    vec4 o;
    if (outSel < 0.5)      o = A0.z > 0.0 ? vec4(A0.x / A0.z, atan(B0.y, B0.x), A0.z * 0.25, B0.z / A0.z) : vec4(0.0);
    else if (outSel < 1.5) o = A1.z > 0.0 ? vec4(A1.x / A1.z, atan(B1.y, B1.x), A1.z * 0.25, B1.z / A1.z) : vec4(0.0);
    else {
        float yn = hj > 0.0 ? clamp(hy / hj, -4.5, 4.5) : 0.0;
        o = vec4(hj > 0.0 ? HH.x / hj : 0.0, atan(HQ.y, HQ.x), HH.y * 0.25, yn + 10.0 * hit);
    }
    fragColor = o;
}
