#version 440
// mockB4_geo.frag — PASE GEOMÉTRICO (una sola vez; la geometría solo cambia con tamaño/tilt/cámara).
// Raymarch VOLUMÉTRICO a resolución completa (Schwarzschild, rs=1, a=-1.5 h² x/r^5) a través del
// disco fino con su bruma. Por píxel guarda hasta 3 tramos de rayo dentro del disco:
//   seg k = (r̄, φ̄, espesor fino ∫g·dt, espesor bruma ∫gh·dt)     — RGBA32F
//   flags = (horizonte, dop0, dop1, dop2)                         — RGBA32F
// `outSel` (0..3) elige qué textura emite esta instancia (un ShaderEffect = una salida).
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
const float B_CRIT = 2.598076;
const float R_ISCO = 1.8, R_OUT = 11.0;

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
float smokeS(float rr, vec2 cs){      // estático (el shading añade su propia deriva temporal)
    float n = 0.0, a = 0.5, fr = 0.55, K = 0.9;
    for (int i=0;i<3;i++){ n += a * vnoise3(vec3(cs*K + 31.0, rr*fr)); a *= 0.5; fr *= 2.1; K *= 1.8; }
    return n / 0.875;
}

struct Segs { vec4 P0, P1, P2; vec3 Q0, Q1, Q2; float hit; };

Segs traceRay(vec2 frag)
{
    float R = bhRadius / B_CRIT;
    vec2 rel = frag - bhCenter;
    float ct = cos(-bhTilt), st = sin(-bhTilt);
    vec2 pr = vec2(rel.x*ct - rel.y*st, rel.x*st + rel.y*ct) / R;
    Segs S;
    S.P0 = vec4(0.0); S.P1 = vec4(0.0); S.P2 = vec4(0.0);   // wt, wh, g_pico, r_pico
    S.Q0 = vec3(0.0); S.Q1 = vec3(0.0); S.Q2 = vec3(0.0);   // cosφ, sinφ, dop (pico)
    S.hit = 0.0;
    if (abs(pr.x) < 14.0 && abs(pr.y) < 8.0){
        float ce = cos(elev), se = sin(elev);
        vec3 cdir  = vec3(0.0, se, ce);
        vec3 x = cdir * 30.0 + vec3(1.0,0.0,0.0) * pr.x - vec3(0.0, ce, -se) * pr.y;
        vec3 v = -cdir;
        vec3 h3 = cross(x, v);
        float h2 = dot(h3, h3);
        int run = -1;
        bool was = false;
        for (int i = 0; i < 300; i++){
            float r = length(x);
            if (r < 1.0) { S.hit = 1.0; break; }
            if (r > 34.0 && dot(x, v) > 0.0) break;
            float dt = 0.06 * r + 0.01;
            bool inSlab = false;
            float gt = 0.0, gh = 0.0, dtc = dt;
            bool outFar = true;
            if (r > R_ISCO * 0.9 && r < R_OUT * 1.2){
                float rr = r / 2.54;
                float rho = length(x.xz);
                vec2 cs = x.xz / max(rho, 1e-4);
                float outer = smoothstep(4.0, 11.0, r);
                float smk = outer > 0.0 ? smokeS(rr, cs) : 0.5;
                float H  = 0.0055 * r * (1.0 + 0.9 * outer * smk);
                // bruma en abanico: H(r) creciente con r, densidad baja y suave (espesor propio)
                float Hh = r * (0.014 + 0.05 * smoothstep(2.5, 11.0, r)) * (0.6 + 0.8 * smk) + 1e-3;
                float Hm = max(H, Hh);
                outFar = abs(x.y) > 7.0 * Hm;
                if (abs(x.y) < 3.2 * Hm){
                    inSlab = true;
                    float vy = abs(v.y) + 0.02;
                    dtc = min(dt, max(0.30 * H / vy, 0.012));
                    dtc = min(dtc, max(0.35 * Hh / vy, 0.03));
                    dtc = min(dtc, mix(0.30, 0.10, smoothstep(0.4*R_OUT, 0.8*R_OUT, r)));
                    gt = exp(-0.5 * x.y*x.y / (H*H)) * dtc;
                    gh = exp(-0.5 * x.y*x.y / (Hh*Hh)) * dtc;
                } else {
                    float dy = abs(x.y) - 3.2 * Hm;
                    dtc = min(dt, max(dy / (abs(v.y) + 1e-3) * 0.8, 0.012));
                }
            }
            if (inSlab){
                if (!was){ run++; was = true; }
                vec3 tang = normalize(cross(vec3(0,1,0), vec3(x.x, 0.0, x.z)));
                float dop = dot(tang, -v);
                float rho = max(length(x.xz), 1e-4);
                vec2 cs = x.xz / rho;
                float gp = (gt + 0.25 * gh) / dtc;
                if (run == 0){ S.P0.xy += vec2(gt, gh); if (gp > S.P0.z){ S.P0.z = gp; S.P0.w = r; S.Q0 = vec3(cs, dop);} }
                else if (run == 1){ S.P1.xy += vec2(gt, gh); if (gp > S.P1.z){ S.P1.z = gp; S.P1.w = r; S.Q1 = vec3(cs, dop);} }
                else if (run == 2){ S.P2.xy += vec2(gt, gh); if (gp > S.P2.z){ S.P2.z = gp; S.P2.w = r; S.Q2 = vec3(cs, dop);} }
            } else if (outFar) was = false;
            vec3 acc = -1.5 * h2 * x / (r*r*r*r*r);
            v += acc * dtc;
            v = normalize(v);
            x += v * dtc;
        }
    } else if (length(pr) < B_CRIT) S.hit = 1.0;
    return S;
}

// acumula un sub-muestreo en la suma ponderada (r y φ/dop se ponderan por el espesor)
void acc4(inout vec4 Pm, inout vec3 Qm, vec4 P, vec3 Q){
    float w = P.x + P.y;
    Pm.x += P.x; Pm.y += P.y; Pm.w += w * P.w;
    Qm += w * Q;
    Pm.z += w;                      // Σw (peso total)
}

void main(){
    vec2 frag = qt_TexCoord0 * resolution;
    // supermuestreo 2x2 SOLO en la caché (suaviza el cruce franja-lóbulo)
    vec4 P0 = vec4(0.0), P1 = vec4(0.0), P2 = vec4(0.0);
    vec3 Q0 = vec3(0.0), Q1 = vec3(0.0), Q2 = vec3(0.0);
    float hit = 0.0;
    for (int j = 0; j < 2; j++) for (int i = 0; i < 2; i++){
        Segs S = traceRay(frag + vec2(float(i) - 0.5, float(j) - 0.5) * 0.5);
        acc4(P0, Q0, S.P0, S.Q0); acc4(P1, Q1, S.P1, S.Q1); acc4(P2, Q2, S.P2, S.Q2);
        hit += S.hit * 0.25;
    }
    vec4 o;
    if (outSel < 0.5)      o = P0.z > 0.0 ? vec4(P0.w / P0.z, atan(Q0.y, Q0.x), P0.x * 0.25, P0.y * 0.25) : vec4(0.0);
    else if (outSel < 1.5) o = P1.z > 0.0 ? vec4(P1.w / P1.z, atan(Q1.y, Q1.x), P1.x * 0.25, P1.y * 0.25) : vec4(0.0);
    else if (outSel < 2.5) o = P2.z > 0.0 ? vec4(P2.w / P2.z, atan(Q2.y, Q2.x), P2.x * 0.25, P2.y * 0.25) : vec4(0.0);
    else                   o = vec4(hit, Q0.z / max(P0.z, 1e-6), Q1.z / max(P1.z, 1e-6), Q2.z / max(P2.z, 1e-6));
    fragColor = o;
}
