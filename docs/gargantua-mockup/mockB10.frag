#version 440
// mockB10.frag — PASE DE SOMBREADO (por frame) sobre la caché mockB10_geo (r_out variable). La física da la FORMA;
// la LUZ es artística (caída suave a ojo). Anillo de fotones fino a b_crit, detrás de la franja.
// vetas concéntricas finas, motas de polvo de absorción, bordes que se deshacen en partículas,
// rampa de 5 roles del tema. La caché (geometría) es la de B7, sin tocar.
//   geoA/B: tramos de la capa fina (r̄, φ̄, ∫ρ dt, Doppler cosθ)
//   geoH: bruma (r̄, φ̄, luminancia, y/H + 10·submuestras en el horizonte)
// Física del brillo: T(r) ∝ r^-3/4 con labio interior, Doppler g = 1/(γ(1-β·cosθ)) con
// β ∝ r^-1/2, intensidad ∝ g³·T⁴ y color de la rampa del tema por T_obs = g·T.
// Grano y carriles: ruido anisótropo de textura periódica (noise5), estirado en la dirección orbital, advectado con
// rotación kepleriana (dos fases cruzadas para que la cizalla no crezca sin fin).
// Salida HDR lineal; alfa = máscara de bloom (0 en sombra pura).
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
    vec4  colOnPC;      // m3onPrimaryContainer
    vec4  colPC;        // m3primaryContainer
    vec4  colTert;      // m3tertiary
    float dbg;          // 0 normal · 1 solo capa fina · 2 solo bruma · 3 datos de caché
    float rOut;
};
layout(binding = 1) uniform sampler2D geoA;
layout(binding = 2) uniform sampler2D geoB;
layout(binding = 3) uniform sampler2D geoH;
layout(binding = 4) uniform sampler2D noiseTex;
const float KG = 1.68;
const float R_ISCO = 1.95;
#define R_OUT_T rOut
const float B_CRIT = 2.9098;
const float K_THIN = 60.0;
const float TAU = 6.28318530718;

vec3 lit(vec3 c, float k){ return mix(c, vec3(1.0), k); }
vec3 dk(vec3 c, float k){ return c * (1.0 - k); }
vec3 toLin(vec3 c){ return pow(c, vec3(2.2)); }

float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
vec2  hash22(vec2 p){ float n = sin(dot(p, vec2(41.0, 289.0))); return fract(vec2(262144.0, 32768.0)*n); }
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

// rampa de temperatura, solo roles del tema: dk(P) frío → P → lit(P) caliente
// rampa de color (solo tono; el brillo lo pone la física): cada rol normalizado en luminancia.
// casi blanco (labio) → onPrimaryContainer → primaryContainer → primary → tertiary (polvo lejano)
float luma(vec3 c){ return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 nrm(vec3 c){ return mix(c * (0.75 / max(luma(c), 1e-3)), vec3(0.75), 0.45); }   // mismo brillo, algo desaturado
vec3 ramp(float x){
    vec3 c5 = nrm(lit(toLin(colOnPC.rgb), 0.75));
    vec3 c4 = nrm(toLin(colOnPC.rgb));
    vec3 c3 = nrm(toLin(colPC.rgb));
    vec3 c2 = nrm(toLin(colPrimary.rgb));
    vec3 c1 = nrm(toLin(colTert.rgb));
    if (x > 0.85) return mix(c4, c5, (x - 0.85) / 0.15);
    if (x > 0.65) return mix(c3, c4, (x - 0.65) / 0.20);
    if (x > 0.45) return mix(c2, c3, (x - 0.45) / 0.20);
    if (x > 0.20) return mix(c1, c2, (x - 0.20) / 0.25);
    return c1 * smoothstep(0.0, 0.20, x);                 // → negro
}

float omegaK(float r){ return 0.55 * pow(r / R_ISCO, -1.5); }

// textura advectada (muestrea noise5: periódica en φ, un fetch por octava):
// x = vetas (capa fina), y = grano anisótropo (largo en φ, fino en r), z = carriles, w = grumos.
// u = φ/2π·m con m entero (sin costura); yn = altura media y/H de la bruma (rompe las horquillas).
vec4 flowTex(float r, float phi, float seed, bool full, float yn, float rsc){
    const float T = 18.0;
    vec4 acc = vec4(0.0); float w2 = 0.0;
    float rr = r / 2.54;
    float v = rr / 16.0 * rsc;            // rsc < 1: menos dependencia de r (cola: sin espigas)
    for (int k = 0; k < 2; k++){
        float ph = fract(time / T + 0.5 * float(k) + seed * 0.37);
        float w  = 1.0 - abs(2.0 * ph - 1.0);
        float u  = (phi - omegaK(r) * (ph - 0.5) * T) / TAU;
        float s  = float(k) * 0.37 + seed * 0.21;
        vec2 ys = yn * vec2(0.13, 0.07);
        vec4 n;
        n.x = full ? (0.55 * texture(noiseTex, vec2(u + s,        v * 9.0 + s)).r
                    + 0.45 * texture(noiseTex, vec2(2.0*u + s + 0.3, v * 26.0)).r) : 0.5;
        n.y = 0.6 * texture(noiseTex, vec2(4.0*u + s + ys.x * 2.0, v * 22.0 + ys.y * 2.0)).g
            + 0.4 * texture(noiseTex, vec2(6.0*u + s + 0.5 + ys.x * 3.5, v * 38.0 + ys.y * 3.5)).g;
        n.z = texture(noiseTex, vec2(u + s + 0.7 + ys.x, v * 5.0 + ys.y)).b;
        n.w = texture(noiseTex, vec2(u + s + 0.2 + ys.x * 0.8, v * 3.0)).a;
        acc += w * (n - 0.5);
        w2 += w * w;
    }
    return 0.5 + acc / sqrt(w2);
}

float dopplerG(float r, float dop){
    float beta = 0.42 * sqrt(R_ISCO / r);
    float gam = inversesqrt(1.0 - beta * beta);
    float grav = mix(1.0, sqrt(max(1.0 - (KG / 1.5) / r, 0.05)), 0.3);
    return grav / (gam * (1.0 - beta * dop));
}

// un tramo de la capa fina → (rgb emitido, opacidad)
// celdas en (r, φ) del disco, ~cuadradas en el plano: nº de celdas por anillo entero → sin costura
// devuelve (id de celda, coords locales 0..1)
vec4 diskCell(float r, float phi, float Nr){
    float ir = floor(r * Nr);
    float nphi = max(floor(6.2831853 * (ir + 0.5)), 3.0);
    float u = fract(phi / 6.2831853) * nphi;
    return vec4(ir, floor(u), fract(r * Nr), fract(u));
}
float h12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
// motas de absorción: 3 tamaños, presencia según densidad local `dd`
float speckLayer(float r, float phi, float Nr, float dd, float seed){
    vec4 c = diskCell(r, phi, Nr);
    float h = h12(c.xy + seed * 17.0);
    if (h > dd) return 0.0;
    vec2 ctr = vec2(h12(c.xy + seed * 5.0 + 1.3), h12(c.xy + seed * 9.0 + 7.1)) * 0.5 + 0.25;
    float rad = 0.12 + 0.22 * h12(c.xy + seed * 3.0 + 2.9);
    float d = length(c.zw - ctr);
    return 1.0 - smoothstep(rad * 0.55, rad, d);
}
// motas FIJAS en el disco (r, φ): cada fila de celdas gira rígida a su velocidad kepleriana (no se
// deforman). Su forma se mide en PÍXELES con el jacobiano ∂(r,φ)/∂(x,y) → redondas pese al escorzo.
float speckLayer(float r, float phi, vec4 J, float Nr, float prob, float rmin, float rmax, float seed){
    float ir = floor(r * Nr);
    float rowR = (ir + 0.5) / Nr;
    float nphi = max(floor(TAU * rowR * Nr * 3.0), 3.0);
    float a = phi - omegaK(rowR) * time * 0.25;
    float u = fract(a / TAU) * nphi;
    vec2 id = vec2(ir, floor(u));
    if (h12(id + seed) > prob) return 0.0;
    vec2 c = vec2(0.25 + 0.5 * h12(id + seed + 1.3), 0.25 + 0.5 * h12(id + seed + 7.1));
    float dr = (fract(r * Nr) - c.x) / Nr;
    float dp = (fract(u) - c.y) / nphi * TAU;
    float det = J.x * J.w - J.y * J.z;
    if (abs(det) < 1e-12) return 0.0;
    vec2 d = vec2(J.w * dr - J.y * dp, -J.z * dr + J.x * dp) / det;      // offset en píxeles
    float cellR = (0.5 / Nr) / max(length(J.xy), 1e-6);
    float cellP = (3.1416 / nphi) / max(length(J.zw), 1e-6);
    float rad = min(mix(rmin, rmax, h12(id + seed + 5.3)), 0.8 * min(cellR, cellP));
    return 1.0 - smoothstep(rad - 0.6, rad + 0.5, length(d));
}
float specks(float r, float phi, vec4 J, float dd){
    return max(speckLayer(r, phi, J, 1.6, 0.18 * dd, 2.0, 4.5, 1.0),
           max(speckLayer(r, phi, J, 3.5, 0.35 * dd, 1.1, 2.4, 2.0), speckLayer(r, phi, J, 8.0, 0.6 * dd, 0.6, 1.3, 3.0)));
}

vec4 shadeThin(vec4 s, float dop, float seed, vec4 J){
    float rc = max(s.x, R_ISCO * 0.95);
    float wt = s.z;
    vec4 n = flowTex(rc, s.y, seed, true, 0.0, 1.0);
    // vetas concéntricas muy finas
    float uf = (s.y - 0.02 * time) / TAU;
    float vf = rc / 2.54 / 16.0;
    float fv = 0.6 * texture(noiseTex, vec2(3.0 * uf + seed * 0.3, vf * 70.0)).r
             + 0.4 * texture(noiseTex, vec2(5.0 * uf + 0.37, vf * 150.0)).g;
    float vein = 0.6 + 0.8 * smoothstep(0.22, 0.80, fv) * (0.85 + 0.3 * n.x);
    float dens = 0.9 + 0.2 * n.w;
    float tau = K_THIN * dens * wt;
    if (tau < 1e-5) return vec4(0.0);
    float lip = smoothstep(R_ISCO * 0.97, R_ISCO * 1.12, rc);
    float g = dopplerG(rc, dop);
    float gS = pow(g, 1.5);
    // LUZ ARTÍSTICA: caída suave a ojo (∝ r^-0.9) + resplandor del labio interior; Doppler suavizado
    float rn = clamp((rc - R_ISCO) / (R_OUT_T - R_ISCO), 0.0, 1.0);
    // gradiente de dentro a fuera a ojo: muy brillante junto al agujero, cae suave y no llega a negro
    float I = lip * gS * ((1.5 * exp(-4.0 * rn) + 0.16) * vein * (0.85 + 0.3 * n.y) + 0.9 * exp(-(rc - R_ISCO) * 2.5));
    vec3 col = ramp(clamp(1.0 - pow(rn, 0.6) + 0.15 * (g - 1.0), 0.0, 1.0)) * I;
    // polvo: motas fijas en el disco, en bandas radiales de grano fino
    float band = smoothstep(0.40, 0.70, texture(noiseTex, vec2(0.13, vf * 40.0)).b);
    float dd = (0.6 + 0.5 * smoothstep(0.6, 0.95, rn)) * smoothstep(0.25, 0.6, rn) * (0.25 + 1.0 * band) * (0.6 + 0.8 * n.w);
    col *= 1.0 - 0.92 * specks(rc, s.y, J, dd);
    // borde exterior que se deshace en partículas
    float fade = 1.0 - smoothstep(0.6 * R_OUT_T, R_OUT_T, rc + (n.w - 0.5) * 0.3 * R_OUT_T);
    vec4 pc = diskCell(rc, s.y - 0.02 * time, 38.0);
    float ph = h12(pc.xy + 4.7);
    float part = smoothstep(ph - 0.10, ph + 0.10, fade * 1.7) * (0.7 + 0.6 * h12(pc.xy + 9.1));
    fade = mix(part * fade * 1.4, fade, smoothstep(0.12, 0.40, fade));
    return vec4(col, (1.0 - exp(-tau)) * fade);
}

// jacobiano ∂(r,φ)/∂(x,y) de un tramo (φ por su vector unitario: sin salto en ±π)
vec4 jac(vec4 s){
    vec2 cs = vec2(cos(s.y), sin(s.y));
    vec2 dcx = dFdx(cs), dcy = dFdy(cs);
    return vec4(dFdx(s.x), dFdy(s.x), cs.x * dcx.y - cs.y * dcx.x, cs.x * dcy.y - cs.y * dcy.x);
}

void main(){
    vec2 frag = qt_TexCoord0 * resolution;
    vec4 hz = texture(geoH, qt_TexCoord0);
    float hq = floor((hz.w + 5.0) / 10.0);
    float hit = hq * 0.25;                 // fracción de submuestras que caen al horizonte
    float yn = hz.w - 10.0 * hq;
    vec3 E = vec3(0.0);
    float Tr = 1.0;
    vec4 s0 = texture(geoA, qt_TexCoord0);
    vec4 s1 = texture(geoB, qt_TexCoord0);
    vec4 J0 = jac(s0), J1 = jac(s1);
    if (s0.z > 1e-6){
        vec4 c = shadeThin(s0, s0.w, 0.0, J0);
        E += c.a * c.rgb; Tr *= 1.0 - c.a;
    }
    if (Tr > 0.01 && s1.z > 1e-6){
        vec4 c = shadeThin(s1, s1.w, 1.0, J1);
        E += Tr * c.a * c.rgb; Tr *= 1.0 - c.a;
    }
    // anillo de fotones (ARTÍSTICO): círculo fino (σ≈0.8 px) a 0.9·b_crit, dentro de la sombra, para
    // leer disco → hueco oscuro → anillo como en la referencia; va DETRÁS de la franja (×Tr)
    {
        float Rp = bhRadius / B_CRIT;
        float dpx = length(frag - bhCenter) - 0.9 * B_CRIT * Rp;
        float ring = exp(-0.5 * dpx * dpx / 0.64);
        E += Tr * ring * ramp(1.0) * 3.0;
    }
    // bruma (ya integrada y ocluida en la caché): grano rayado + carriles oscuros + grumos
    if (hz.z > 1e-6 && (dbg < 0.5 || dbg > 1.5)){
        vec4 n = flowTex(max(hz.x, 2.0), hz.y, 3.0, false, yn, 1.0);
        float grain = 0.12 + 2.2 * n.y * n.y;
        float lane  = 1.0 - 0.9 * smoothstep(0.40, 0.72, n.z);
        float clump = 0.45 + 1.1 * smoothstep(0.2, 0.85, n.w);
        float x = clamp(0.10 + 0.30 * pow(5.0 / max(hz.x, 2.0), 0.75) + 0.15 * (n.y - 0.5), 0.0, 1.0);
        E += ramp(x) * hz.z * 0.06 * grain * lane * clump;
    }
    // estrellas solo donde se ve el fondo
    float vis = (1.0 - hit) * Tr * exp(-4.0 * hz.z);
    vec3 bg = vec3(0.0);
    if (vis > 0.01){ vec3 st = vec3(0.0); starfield(st, frag, colInk.rgb); bg = toLin(min(st, vec3(1.0))); }
    vec3 col = E + vis * bg;
    if (dbg > 2.5) col = vec3(s0.x / 12.0, hz.z * 3.0, 0.5 + 0.1 * yn);
    else if (dbg > 1.5) col = vec3(hz.z * 2.0);
    // máscara de bloom SUAVE: solo se apaga donde se ve el horizonte sin nada delante
    float bm = 1.0 - hit * Tr * exp(-8.0 * dot(E, vec3(0.2126, 0.7152, 0.0722)));
    fragColor = vec4(col, bm);
}
