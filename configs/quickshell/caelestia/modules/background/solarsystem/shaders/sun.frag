#version 440

// sun.frag — decoración de los dos soles (diseño D «Paleta viva»), en GPU.
// Se pinta ENCIMA del disco del shader de fondo. Item de 4.8·R de lado; `q` en
// unidades de R. Colores = roles del tema en vivo.
//   kind 0  Laura         (tertiary):  rayos, corona que late, puntos, ondas de escucha
//   kind 1  Configuración (primary):   estrella de 4 puntas, facetas hexagonales, aro dentado
// `pulse` 0..1 lo anima SolarSystem.qml despacio (≈6 s); `wave` 0..1 es la fase de las ondas.
//
// Compilar: /usr/lib/qt6/bin/qsb --qt6 --glsl "100 es,120,150" --hlsl 50 --msl 12 -o sun.frag.qsb sun.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float kind;
    float pulse;
    float wave;
    float listening;   // 0..1 — ondas de escucha más marcadas cuando Laura escucha
    vec4  cMain;       // tertiary (Laura) / primary (Config)
    vec4  cContainer;  // tertiaryContainer / primaryContainer
    vec4  cOnSurface;
};

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

void over(inout vec4 acc, vec3 c, float a){
    a = clamp(a, 0.0, 1.0);
    acc.rgb = c * a + acc.rgb * (1.0 - a);
    acc.a   = a + acc.a * (1.0 - a);
}
float ring(float d, float r, float hw, float aa){ return 1.0 - smoothstep(hw - aa, hw + aa, abs(d - r)); }
// rayo: elipse fina de semieje largo L y ancho w, girada `deg`
float ray(vec2 q, float deg, float L, float w){
    float a = radians(deg), c = cos(a), s = sin(a);
    vec2 p = vec2(q.x*c + q.y*s, -q.x*s + q.y*c);
    float e = length(vec2(p.x / L, p.y / w));
    return (1.0 - smoothstep(0.2, 1.0, e)) * 0.7;
}
float hexOutline(vec2 p, float R, float hw, float aa){
    // hexágono con vértices arriba/abajo (como el polígono del SVG)
    p = abs(p);
    float d = max(p.x * 0.8660254 + p.y * 0.5, p.y) - R * 0.8660254 * 1.0;
    return 1.0 - smoothstep(hw - aa, hw + aa, abs(d));
}

void main(){
    vec2 q = (qt_TexCoord0 - 0.5) * 4.8;
    float d = length(q);
    float aa = 1.5 * fwidth(d);
    float ang = mod(atan(q.x, -q.y) + TAU, TAU) / TAU;
    vec4 acc = vec4(0.0);
    float pu = 0.75 + 0.25 * pulse;

    if (kind < 0.5) {
        // ---- Laura ----
        float rays = ray(q, 20.0, 1.75, 0.08) + ray(q, -40.0, 1.5, 0.06) + ray(q, 78.0, 1.65, 0.05) + ray(q, 130.0, 1.4, 0.06);
        over(acc, cMain.rgb, clamp(rays, 0.0, 1.0) * 0.55 * smoothstep(0.95, 1.1, d));
        float s = 1.0 + 0.06 * pulse;
        over(acc, cMain.rgb, ring(d, 1.30 * s, 0.015, aa) * 0.40 * pu);
        over(acc, cMain.rgb, ring(d, 1.52 * s, 0.015, aa) * 0.22 * pu);
        // anillo de puntos
        float dots = step(0.55, fract(ang * 88.0)) ;
        over(acc, cContainer.rgb, ring(d, 1.24, 0.035, aa) * (1.0 - step(0.16, fract(ang * 88.0))) * 0.55);
        // ondas de escucha: tres anillos que se expanden y se desvanecen
        for (int i = 0; i < 3; i++) {
            float ph = fract(wave + float(i) / 3.0);
            float r = 1.1 + 0.9 * ph;
            over(acc, cMain.rgb, ring(d, r, 0.012, aa) * (1.0 - ph) * (0.10 + 0.30 * listening));
        }
    } else {
        // ---- Configuración ----
        float star = ray(q, 0.0, 2.15, 0.06) + ray(q, 90.0, 2.15, 0.06);
        float diag = ray(q, 45.0, 1.4, 0.04) + ray(q, -45.0, 1.4, 0.04);
        over(acc, cMain.rgb, clamp(star, 0.0, 1.0) * 0.8 * smoothstep(0.95, 1.1, d));
        over(acc, cContainer.rgb, clamp(diag, 0.0, 1.0) * 0.8 * smoothstep(0.95, 1.1, d));
        // aro dentado (dientes de 14 / huecos de 8 sobre ~35 dientes)
        float tooth = step(fract(ang * 35.0), 0.64);
        over(acc, cMain.rgb, ring(d, 1.22, 0.035, aa) * tooth * 0.40);
        over(acc, cMain.rgb, ring(d, 1.08, 0.008, aa) * 0.30);
        // facetas hexagonales sobre el disco
        float disc = 1.0 - smoothstep(0.98, 1.0, d);
        float hx = hexOutline(q, 0.7 / 0.866, 0.012, aa) + hexOutline(q, 0.38 / 0.866, 0.012, aa);
        over(acc, cOnSurface.rgb, clamp(hx, 0.0, 1.0) * 0.35 * disc);
    }
    fragColor = acc * qt_Opacity;
}
