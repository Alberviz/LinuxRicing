#version 440
// whitehole.frag — agujero BLANCO clavado en el borde superior (inverso de los portales).
// Núcleo blanco incandescente (no sombra), disco fino frío blanco-azulado inclinado -17° con Doppler,
// chorro relativista hacia el interior de la pantalla con pulsos que se alejan, onda de destello.
// Procedural; sin partículas en CPU. Recompilar: /usr/lib/qt6/bin/qsb --qt6 -o whitehole.frag.qsb whitehole.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  size;
    vec4  tint;     // color del tema para el tinte frío (rgb premultiplicado; a = fuerza)
    float rad;      // radio del núcleo en px
    float upx;      // px por «px de mockup»
    float en;       // energía 0..1 (envolvente de las expulsiones)
    float vis;      // presencia 0..1 (entrada/salida)
    float phase;    // 0..1 cíclico (pulsos del chorro y giro del disco)
    float pulse;    // 1 -> 0: onda de destello
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
vec3 cool(float t, float dop){
    vec3 c = mix(vec3(1.0, 1.0, 1.0), vec3(0.42, 0.62, 1.0), clamp(t - (dop - 1.0) * 0.3, 0.0, 1.0));
    return mix(c, c * (0.5 + tint.rgb * 1.2), tint.a * 0.5);
}

void main(){
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    vec2 s = p / R;
    float r = length(s);
    float amp = vis * (0.35 + 0.65 * en);
    vec3 add = vec3(0.0);
    float a = 0.0;

    // resplandor frío
    add += mix(vec3(0.55, 0.72, 1.0), vec3(1.0), 0.4) * 0.22 * amp * exp(-max(r - 0.8, 0.0) * 0.55);

    // chorro relativista (hacia +y: dentro de la pantalla)
    if (s.y > 0.6){
        float y = s.y;
        float w = 0.28 + 0.10 * y;
        float core = exp(-pow(abs(s.x) / w, 2.0));
        float len = (6.0 + 4.0 * en);
        float fade = sm(len, 1.0, y) * sm(0.6, 1.4, y);
        float flow = y * 1.4 - phase * 6.2831853 * 2.0;                  // avanza hacia fuera
        float puls = 0.55 + 0.45 * sin(flow) * (0.6 + 0.4 * vn(vec2(s.x * 3.0, y * 0.8 - phase * 8.0)));
        float streak = 0.6 + 0.8 * vn(vec2(s.x * 9.0 / (w + 0.2), y * 2.0 - phase * 14.0));
        float jet = core * fade * puls * streak * amp * 2.8;
        add += mix(vec3(0.5, 0.7, 1.0), vec3(1.0), core * core) * jet;
        // halo exterior del chorro
        add += vec3(0.4, 0.6, 1.0) * exp(-pow(abs(s.x) / (w * 3.0), 2.0)) * fade * 0.12 * amp;
    }

    // disco fino frío (marco inclinado)
    vec2 q = vec2(s.x * cos(TILT) + s.y * sin(TILT), -s.x * sin(TILT) + s.y * cos(TILT));
    float yd = q.y / INC;
    float rho = length(vec2(q.x, yd));
    float th = atan(yd, q.x);
    if (rho > 1.25 && rho < 4.3){
        float rn = (rho - 1.25) / 3.05;
        float dop = 1.0 + 0.8 * cos(th) * pow(1.25 / rho, 0.5);
        float edge = sm(1.25, 1.5, rho) * (1.0 - sm(3.9, 4.3, rho));
        float ang = th + phase * 6.2831853 * pow(rho / 1.25, -1.5) * 2.0;
        float g = vn(vec2(cos(ang), sin(ang)) * 10.0 + rho * 6.0) * 0.55 + vn(vec2(cos(ang), sin(ang)) * 28.0 + rho * 17.0) * 0.45;
        float ink = 0.15 + 1.6 * smoothstep(0.38, 0.8, g);
        add += cool(rn, dop) * amp * pow(dop, 2.0) * (1.0 - rn * 0.5) * 0.9 * ink * edge;
    }

    // núcleo incandescente
    float core = 1.0 - smoothstep(0.85, 1.05, r);
    add += vec3(1.0) * core * (0.7 + 0.6 * en) * vis;
    a = max(a, core * vis * 0.0);
    // anillo brillante
    float lw = max(1.0, (1.0 + 1.5 * en) * U);
    add += vec3(0.85, 0.93, 1.0) * vis * (0.4 + 0.6 * en) * (1.0 - smoothstep(lw * 0.5, lw * 0.5 + 1.5, abs(r - 1.08) * R));

    // onda de destello
    if (pulse > 0.0){
        float k = 1.0 - pulse;
        float w1 = 2.5 * U * pulse + 0.7;
        add += vec3(0.9, 0.95, 1.0) * pulse * (1.0 - smoothstep(w1 * 0.5, w1 * 0.5 + 2.0, abs(r - (1.1 + k * 6.0)) * R)) * 0.9;
        add += vec3(1.0) * pulse * pulse * exp(-r * r * 0.35) * 0.7;
    }

    // línea del borde de pantalla iluminada alrededor del agujero
    if (s.y > -0.02){
        float edgeLine = (1.0 - smoothstep(0.6 * U, 0.6 * U + 1.2, abs(p.y))) * exp(-abs(s.x) * 0.25);
        add += vec3(0.8, 0.9, 1.0) * edgeLine * amp * 0.5;
    }

    fragColor = vec4(add, a) * qt_Opacity;
}
