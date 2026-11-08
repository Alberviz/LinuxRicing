#version 440
// portal.frag — mini Gargantua «clavado en el borde» (variante B del mockup de portales).
// Un solo quad por portal, centrado en el agujero (coordenadas en px relativas al centro):
// resplandor, corrientes de succión en espiral, disco fino inclinado -17° visto casi de canto
// con Doppler, halo lensado del disco trasero + arco secundario, sombra, anillo de fotones,
// disco delantero, onda de absorción y el arco del borde de pantalla que rodea el agujero.
// Todo procedural: sin partículas en CPU. Recompilar:
//   /usr/lib/qt6/bin/qsb --qt6 -o portal.frag.qsb portal.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  size;      // px del quad
    vec2  outward;   // normal del borde hacia fuera de la pantalla
    vec4  tint;      // rgb: mezcla suave con el tema para el disco (a = fuerza 0..1)
    float rad;       // radio de la sombra en px
    float upx;       // px por «px de mockup» (ancho/1280)
    float en;        // energía 0..1
    float vis;       // visibilidad 0..1
    float armed;     // 0/1
    float pulse;     // 1 -> 0 tras la absorción
    float spin;      // fase acumulada del disco
    float pull;      // fase acumulada de la succión
};

#define R rad
#define U upx
const float TILT = -0.29670597;
const float INC  = 0.17;

float sm(float a, float b, float x){ float t = clamp((x - a) / (b - a), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){
    vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
vec3 tempColor(float rn, float dop){
    float t = clamp(rn - (dop - 1.0) * 0.35, 0.0, 1.0);
    vec3 c = vec3(1.0, mix(0.957, 0.47, t), mix(0.863, 0.157, pow(t, 0.7)));
    return mix(c, c * mix(vec3(1.0), tint.rgb * 1.6, 0.5), tint.a);
}
// estriado giratorio del disco (sustituye a ~900 partículas)
float streaks(float th, float rho, float rn){
    float w = pow(rho / 1.55, -1.5);
    float a = th - spin * w;
    vec2 e = vec2(cos(a), sin(a));
    float g = vn(e * 9.0 + vec2(rho * 7.0, 0.0)) * 0.6 + vn(e * 26.0 + vec2(0.0, rho * 19.0)) * 0.4;
    return 0.15 + 1.6 * smoothstep(0.38, 0.8, g);
}

void main(){
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    vec2 s = p / R;
    float r = length(s);
    float c = cos(TILT), sn = sin(TILT);
    vec2 q = vec2(s.x * c + s.y * sn, -s.x * sn + s.y * c);   // marco del disco
    float bright = vis * (0.45 + 0.75 * en + 0.25 * armed);
    vec3 back = vec3(0.0), front = vec3(0.0);

    // --- resplandor
    {
        float g0 = 0.13 * vis * (0.4 + en), g1 = 0.035 * vis * (0.4 + en);
        float t = (r - 0.8) / 6.2;
        float gv = r < 0.8 ? g0 : (t < 0.35 ? mix(g0, g1, t / 0.35) : mix(g1, 0.0, clamp((t - 0.35) / 0.65, 0.0, 1.0)));
        vec3 gc = t < 0.35 ? mix(vec3(1.0, 0.667, 0.353), vec3(1.0, 0.47, 0.235), clamp(t / 0.35, 0.0, 1.0)) : vec3(1.0, 0.47, 0.235);
        gc = mix(gc, mix(gc, tint.rgb * 1.4, 0.5), tint.a * 0.6);
        back += gc * gv + gc * 0.5 * pulse * exp(-r * r * 0.5);
    }

    // --- corrientes de succión (polvo frío -> caliente al caer)
    {
        float rr = length(q);
        float f = mix(1.0, INC, sm(5.5, 1.6, rr));
        float rho = length(vec2(q.x, q.y / f));
        f = mix(1.0, INC, sm(5.5, 1.6, rho));
        vec2 qd = vec2(q.x, q.y / f);
        rho = length(qd);
        if (rho > 1.04 && rho < 7.5){
            float a = atan(qd.y, qd.x);
            float sarm = a + 4.68 * log(rho);
            const float N = 14.0;
            float arm = 0.5 + 0.5 * cos(N * sarm);
            float idx = mod(floor(N * sarm / 6.2831853 + 0.5), N);
            float m = pow(rho, 1.5) / 2.31 + pull;
            float blob = smoothstep(0.5, 0.9, vn(vec2(m * 1.7, idx * 7.31)));
            float heat = sm(6.0, 1.6, rho);
            float al = vis * (0.12 + 0.5 * en) * sm(7.5, 4.5, rho) * (0.5 + heat) * pow(arm, 12.0) * blob * 1.1;
            vec3 col = mix(vec3(0.588, 0.686, 1.0), vec3(1.0, 0.784, 0.47), heat);
            col = mix(col, mix(col, tint.rgb * 1.5, 0.5), tint.a * heat);
            back += col * al;
        }
    }

    // --- disco fino (marco inclinado, casi de canto)
    float yd = q.y / INC;
    float rho = length(vec2(q.x, yd));
    float th = atan(yd, q.x);
    if (rho > 1.55 && rho < 4.45){
        float rn = (rho - 1.55) / 2.9;
        float dop = 1.0 + 0.8 * cos(th) * pow(1.55 / rho, 0.5);
        float edge = sm(1.55, 1.75, rho) * (1.0 - sm(4.1, 4.45, rho));
        float a = bright * pow(dop, 2.2) * (1.0 - rn * 0.55) * 0.5 * streaks(th, rho, rn) * edge;
        vec3 col = tempColor(rn, dop) * a;
        if (q.y < 0.0) back += col; else front += col;
    }

    // --- halo lensado del disco trasero (arco sobre la sombra)
    {
        float qy = (-q.y - 0.02) / 0.92;
        if (qy > 0.0){
            float rh = length(vec2(q.x, qy));
            if (rh > 1.12 && rh < 2.07){
                float rn = (rh - 1.12) / 0.95;
                float cth = q.x / rh;
                float dop = 1.0 + 0.8 * cth * pow(1.55 / (1.55 + rn * 2.9), 0.5);
                float edge = sm(1.12, 1.2, rh) * (1.0 - sm(1.95, 2.07, rh));
                float thh = atan(qy, q.x);
                float a = bright * pow(dop, 2.2) * (1.0 - rn * 0.55) * 0.5 * 0.7 * streaks(thh, 1.55 + rn * 2.9, rn) * edge;
                back += tempColor(rn, dop) * a;
            }
        }
        // arco secundario tenue por debajo
        float qu = q.y / 0.9;
        if (qu > 0.0){
            float ru = length(vec2(q.x, qu));
            if (ru > 1.05 && ru < 1.30){
                float rn = (ru - 1.05) / 0.25;
                float dop = 1.0 + 0.8 * (q.x / ru) * pow(1.55 / (1.55 + rn * 2.9), 0.5);
                float edge = sm(1.05, 1.1, ru) * (1.0 - sm(1.22, 1.30, ru));
                back += tempColor(rn, dop) * bright * pow(dop, 2.2) * 0.5 * 0.35 * edge;
            }
        }
    }

    // --- sombra
    float sa = vis * (1.0 - smoothstep(0.9, 1.08, r));

    // --- anillo de fotones (+ halo azul fino) y onda de absorción
    {
        float lw = max(0.7, (1.0 + en) * U);
        float d = abs(r - 1.03) * R;
        front += vec3(1.0, 0.925, 0.804) * vis * (0.35 + 0.6 * en) * (1.0 - smoothstep(lw * 0.5, lw * 0.5 + 1.2, d));
        float lw2 = max(0.5, 0.6 * U);
        float d2 = abs(r - 1.1) * R;
        front += vec3(0.627, 0.725, 1.0) * vis * 0.25 * en * (1.0 - smoothstep(lw2 * 0.5, lw2 * 0.5 + 1.2, d2));
        if (pulse > 0.0){
            float k = 1.0 - pulse;
            float w1 = 2.0 * U * pulse + 0.5;
            front += vec3(1.0, 0.9, 0.745) * pulse * 0.9 * (1.0 - smoothstep(w1 * 0.5, w1 * 0.5 + 1.5, abs(r - (1.05 + k * 5.0)) * R));
            front += vec3(0.627, 0.745, 1.0) * pulse * 0.5 * (1.0 - smoothstep(w1 * 0.5, w1 * 0.5 + 1.5, abs(r - (1.05 + k * 3.2)) * R));
        }
    }

    // --- borde de pantalla curvado alrededor del agujero (solo el arco; el tramo recto lo pone QML)
    {
        float Rr = R * (1.45 + 0.25 * en) * vis;
        if (dot(p, outward) <= 0.0 && Rr > 1.0){
            float dd = abs(length(p) - Rr);
            vec3 rc = vec3(1.0, 0.871, 0.725);
            float amp = vis * (0.35 + 0.65 * en);
            front += rc * amp * 0.06 * (1.0 - smoothstep(2.5 * U, 2.5 * U + 2.0, dd));
            front += rc * amp * 0.45 * (1.0 - smoothstep(0.7 * U, 0.7 * U + 1.2, dd));
        }
    }

    vec3 rgb = back * (1.0 - sa) + front;
    fragColor = vec4(rgb, sa) * qt_Opacity;
}
