#version 440

// planet.frag — planeta de sesión de IA (dirección A del mockup «Arquetipos»),
// portado de SVG a GPU. Un ShaderEffect por planeta; el item mide 4·R de lado
// (R = radio del planeta), así que el espacio local `q` está en unidades de R.
//
//   kind 0  Claude  — mundo terroso cálido con atmósfera ámbar y casquete polar
//   kind 1  Gemini  — gigante gaseoso con bandas azul-lila, tormenta y anillo
//   kind 2  otros   — mundo helado/bandeado teñido con `tint`
//
// El % de contexto NO se pinta aquí: lo expresa el TAMAÑO del planeta (Sim.js).
// Sin blur en tiempo real: los desenfoques del SVG se
// sustituyen por smoothstep/exp (coste constante por píxel, sin pasadas).
//
// Compilar: /usr/lib/qt6/bin/qsb --qt6 --glsl "100 es,120,150" --hlsl 50 --msl 12 -o planet.frag.qsb planet.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float kind;
    float unused0;
    float unused1;
    vec4  tint;
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

// composición premultiplicada
void over(inout vec4 acc, vec3 c, float a){
    a = clamp(a, 0.0, 1.0);
    acc.rgb = c * a + acc.rgb * (1.0 - a);
    acc.a   = a + acc.a * (1.0 - a);
}
vec3 ramp4(float t, vec3 a, vec3 b, vec3 c, vec3 d){
    if (t < 0.4) return mix(a, b, t/0.4);
    if (t < 0.8) return mix(b, c, (t-0.4)/0.4);
    return mix(c, d, clamp((t-0.8)/0.2, 0.0, 1.0));
}
float band(float y, float y0, float h, float soft){
    return smoothstep(y0 - soft, y0 + soft, y) * (1.0 - smoothstep(y0 + h - soft, y0 + h + soft, y));
}

void main(){
    vec2 q = (qt_TexCoord0 - 0.5) * 4.0;      // unidades de R, y hacia abajo
    float d = length(q);
    vec4 acc = vec4(0.0);
    vec2 hp = vec2(-0.28, -0.40);             // punto de luz (como el SVG: cx .36 cy .3)
    float aa = 1.5 * fwidth(d);

    bool gem = kind > 0.5 && kind < 1.5;
    bool cla = kind < 0.5;

    // ---- anillo de Gemini, mitad trasera ----
    float ringBack = 0.0, ringFront = 0.0;
    if (gem) {
        float ca = cos(radians(18.0)), sa = sin(radians(18.0));
        vec2 qr = vec2(q.x*ca - q.y*sa, q.x*sa + q.y*ca);
        float e = length(vec2(qr.x/1.58, qr.y/0.30));
        vec2 g = vec2(qr.x/(1.58*1.58), qr.y/(0.30*0.30)) / max(e, 1e-4);
        float dist = abs(e - 1.0) / max(length(g), 1e-4);
        float stroke = 1.0 - smoothstep(0.035 - aa, 0.035 + aa, dist);
        ringBack  = stroke * 0.45 * step(qr.y, 0.0) * step(1.0, d);
        ringFront = stroke * 0.75 * step(0.0, qr.y);
        over(acc, vec3(0.725, 0.776, 1.0), ringBack);
    }

    // ---- cuerpo del planeta ----
    float body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
    if (body > 0.0) {
        float s0 = length(q - hp) / 1.7;
        vec3 col;
        if (cla) {
            col = ramp4(s0, vec3(0.933,0.733,0.541), vec3(0.722,0.416,0.235), vec3(0.369,0.176,0.110), vec3(0.133,0.063,0.039));
            // continentes oscuros
            float cont = smoothstep(0.52, 0.66, fbm(q*1.7 + 2.0));
            col = mix(col, vec3(0.29,0.141,0.078), cont * 0.5);
            // bandas de bruma
            col = mix(col, vec3(0.949,0.812,0.643), exp(-pow((q.y+0.08)/0.10, 2.0)) * 0.18);
            col = mix(col, vec3(0.949,0.812,0.643), exp(-pow((q.y-0.40)/0.08, 2.0)) * 0.12);
            // casquete polar
            float cap = exp(-(pow(q.x/0.46, 2.0) + pow((q.y+0.98)/0.18, 2.0)));
            col = mix(col, vec3(0.973,0.902,0.816), cap * 0.65);
        } else if (gem) {
            col = ramp4(s0*1.0, vec3(0.890,0.918,1.0), vec3(0.604,0.667,0.941), vec3(0.18,0.21,0.53), vec3(0.18,0.21,0.53));
            col = mix(vec3(0.890,0.918,1.0), vec3(0.604,0.667,0.941), smoothstep(0.0, 0.5, s0));
            col = mix(col, vec3(0.18,0.21,0.53), smoothstep(0.5, 1.0, s0));
            float y = q.y + (fbm(vec2(q.x*1.3, q.y*3.0)) - 0.5) * 0.06;
            float sf = 0.05;
            vec3 b = col; float a;
            a = band(y,-1.00,0.22,sf); b = mix(b, vec3(0.549,0.624,0.902), a*0.8);
            a = band(y,-0.78,0.14,sf); b = mix(b, vec3(0.890,0.914,0.988), a*0.8);
            a = band(y,-0.64,0.26,sf); b = mix(b, vec3(0.498,0.561,0.863), a*0.7);
            a = band(y,-0.38,0.12,sf); b = mix(b, vec3(0.804,0.733,0.941), a*0.8);
            a = band(y,-0.04,0.14,sf); b = mix(b, vec3(0.918,0.937,0.988), a*0.8);
            a = band(y, 0.10,0.24,sf); b = mix(b, vec3(0.541,0.498,0.839), a*0.7);
            a = band(y, 0.34,0.16,sf); b = mix(b, vec3(0.788,0.827,0.969), a*0.8);
            a = band(y, 0.50,0.50,sf); b = mix(b, vec3(0.373,0.435,0.769), a*0.7);
            col = b;
            // tormenta
            float st = 1.0 - smoothstep(0.7, 1.0, length(vec2((q.x+0.28)/0.24, (q.y-0.26)/0.11)));
            col = mix(col, vec3(0.941,0.961,1.0), st * 0.85);
        } else {
            vec3 t = tint.rgb;
            col = ramp4(s0, mix(t, vec3(1.0), 0.55), t, t*0.38, t*0.12);
            float y = q.y + (fbm(vec2(q.x*1.2, q.y*2.5)) - 0.5) * 0.10;
            col = mix(col, mix(t, vec3(1.0), 0.45), band(y, -0.30, 0.16, 0.06) * 0.35);
            col = mix(col, t * 0.45, band(y, 0.15, 0.22, 0.06) * 0.35);
            col = mix(col, vec3(1.0), smoothstep(0.55, 0.7, fbm(q*2.2 + 5.0)) * 0.15);
        }
        // sombreado (terminador)
        float sh = length(q - hp) / 1.8;
        float shadeA = smoothstep(0.4, 0.8, sh) * 0.55 + smoothstep(0.8, 1.0, sh) * 0.30;
        col = mix(col, vec3(0.0), shadeA);
        over(acc, col, body);
    }

    // ---- atmósfera (halo fino justo en el borde) ----
    {
        float r = d / 1.06;
        float a = smoothstep(0.88, 0.945, r) * (1.0 - smoothstep(0.945, 1.0, r)) * 0.5;
        vec3 ac = cla ? vec3(1.0, 0.773, 0.573) : (gem ? vec3(0.737, 0.839, 1.0) : mix(tint.rgb, vec3(1.0), 0.4));
        over(acc, ac, a);
    }

    // ---- anillo de Gemini, mitad delantera ----
    if (gem) over(acc, vec3(0.827, 0.863, 1.0), ringFront);

    fragColor = acc * qt_Opacity;
}
