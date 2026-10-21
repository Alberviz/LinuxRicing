#version 440

// laura_edge.frag — borde «Gemini» de Laura (propuesta E del mockup-barra.html).
// La luz nace en el centro del borde inferior, se abre a los dos lados, sube por
// los laterales y cierra el contorno arriba. Un único ShaderEffect a pantalla
// completa: distancia al borde más cercano + parámetro de recorrido `s` desde el
// centro inferior (simétrico), pintado con una paleta cíclica que fluye.
//
// Compilar: /usr/lib/qt6/bin/qsb --qt6 --glsl "100 es,120,150" --hlsl 50 --msl 12 -o laura_edge.frag.qsb laura_edge.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float progress;   // 0..1 frente de entrada / salida (ya con easing)
    float time;       // s, respiración y ondulaciones
    float flow;       // fase acumulada del flujo de color
    float glow;       // 0..1 amplitud de la voz
    float depth;      // px, profundidad base de la luz hacia dentro
    float comet;      // 0..1 posición del cometa en el contorno
    float cometOn;    // 0|1
    vec2  res;        // px
    vec4  c0;
    vec4  c1;
    vec4  c2;
    vec4  c3;
};

float sst(float a, float b, float x){ float t = clamp((x - a) / (b - a), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }

vec3 palAt(float u){
    u = fract(u) * 4.0;               // 5 paradas cíclicas: c0 c1 c2 c3 c0
    float f = fract(u); f = f * f * (3.0 - 2.0 * f);
    int i = int(floor(u));
    vec3 a = i == 0 ? c0.rgb : i == 1 ? c1.rgb : i == 2 ? c2.rgb : c3.rgb;
    vec3 b = i == 0 ? c1.rgb : i == 1 ? c2.rgb : i == 2 ? c3.rgb : c0.rgb;
    return mix(a, b, f);
}

// perfil de la tira hacia dentro: stops 0:1 .03:.92 .14:.55 .4:.2 1:0
float prof(float u){
    if (u >= 1.0) return 0.0;
    if (u < 0.03) return mix(1.0, 0.92, u / 0.03);
    if (u < 0.14) return mix(0.92, 0.55, (u - 0.03) / 0.11);
    if (u < 0.40) return mix(0.55, 0.20, (u - 0.14) / 0.26);
    return mix(0.20, 0.0, (u - 0.40) / 0.60);
}

// posición (mitad derecha) del punto del contorno a recorrido s
vec2 pathPos(float s, float W, float H){
    float h = W * 0.5;
    if (s < h) return vec2(h + s, H);
    if (s < h + H) return vec2(W, H - (s - h));
    return vec2(W - (s - h - H), 0.0);
}

void main(){
    float k = res.y / 720.0;                 // el mockup está a 1280x720
    float W = res.x / k, H = 720.0;
    vec2 p = qt_TexCoord0 * vec2(W, H);
    float xr = abs(p.x - W * 0.5) + W * 0.5;  // espejo: todo a la mitad derecha
    float db = H - p.y, dr = W - xr, dt = p.y;
    float LTOT = W * 0.5 + H + W * 0.5;
    float e = progress, dd = e * LTOT;
    float breathe = 0.5 + 0.5 * sin(time * 1.5);
    float base = (0.52 + 0.5 * glow) * (0.92 + 0.08 * breathe);

    // Tres tramos (inferior, lateral, superior) con distancia al SEGMENTO: en las
    // esquinas la luz se curva como un arco y los tramos se suman con saturación.
    vec2 q = vec2(xr, p.y);
    vec2 A[3]; vec2 B[3]; float S0[3];
    A[0] = vec2(W * 0.5, H); B[0] = vec2(W, H);   S0[0] = 0.0;
    A[1] = vec2(W, H);       B[1] = vec2(W, 0.0); S0[1] = W * 0.5;
    A[2] = vec2(W, 0.0);     B[2] = vec2(W * 0.5, 0.0); S0[2] = W * 0.5 + H;
    float segLen[3]; segLen[0] = W * 0.5; segLen[1] = H; segLen[2] = W * 0.5;
    float keep = 1.0;
    vec3 rgb = vec3(0.0);
    for (int n = 0; n < 3; n++) {
        vec2 ab = B[n] - A[n];
        float t = clamp(dot(q - A[n], ab) / dot(ab, ab), 0.0, 1.0);
        float dist = length(q - (A[n] + ab * t));
        float s = S0[n] + t * segLen[n];
        float cg = exp(-pow((s - comet * LTOT) / 95.0, 2.0)) * cometOn;
        float f  = 1.0 - sst(dd - 190.0, dd, s);
        float a  = base * f * (0.9 + 0.1 * sin(s * 0.017 - time * 2.2)) + 0.55 * cg * step(0.002, e) * f;
        float f2 = 1.0 - sst(dd - 240.0, dd, s);
        float dep = (84.0 + 190.0 * glow) * (s < W * 0.5 ? 1.2 : 1.0) * (0.28 + 0.72 * f2);
        dep *= 1.0 + 0.16 * glow * sin(s * 0.02 - time * 5.0);
        dep *= 1.0 + 0.5 * cg;
        a = min(1.0, a) * prof(dist / max(dep, 1.0));
        rgb += palAt(s / LTOT * 0.85 - flow) * a * keep;
        keep *= 1.0 - a;
    }
    float al = 1.0 - keep;

    // destello de ignición en el centro inferior
    float ign = max(0.0, 1.0 - e * 2.2);
    if (ign > 0.0) {
        float R = 220.0 * (1.0 + e);
        float r = length(p - vec2(W * 0.5, H)) / R;
        float g = r < 0.35 ? mix(1.0, 0.4, r / 0.35) : mix(0.4, 0.0, (r - 0.35) / 0.65);
        g = r < 1.0 ? g : 0.0;
        float aa = 0.7 * ign * g;
        rgb += palAt(-flow) * aa; al += aa;
    }
    // cabezas luminosas del frente (una por lado, espejadas)
    float head = (1.0 - sst(0.9, 1.0, e)) * step(0.003, e);
    if (head > 0.01) {
        vec2 hp = pathPos(min(dd, LTOT - 1.0), W, H);
        hp += vec2(hp.y == H ? 0.0 : (hp.x == W ? -14.0 : 0.0), hp.y == H ? -10.0 : (hp.y == 0.0 ? 10.0 : 0.0));
        float r = length(vec2(xr, p.y) - hp) / 150.0;
        float g = r < 0.35 ? mix(1.0, 0.4, r / 0.35) : mix(0.4, 0.0, (r - 0.35) / 0.65);
        g = r < 1.0 ? g : 0.0;
        float aa = 0.75 * head * g;
        vec3 hc = mix(palAt(dd / LTOT * 0.85 - flow), vec3(1.0), 0.55);
        rgb += hc * aa; al += aa;
    }
    al = clamp(al, 0.0, 1.0);
    fragColor = vec4(min(rgb, vec3(al)) , al) * qt_Opacity;
}
