#version 440
// composite5.frag — HDR + bloom → exposición → tonemap ACES (Narkowicz) → sRGB.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float exposure;
    float bloomAmt;
    vec2  resolution;
    vec2  bhCenter;
    float bhRadius;
    vec4  tint;
    vec2  boxOrigin;    // px de pantalla de la esquina de la caja
    float softAmt;      // 0..1: cuánto se difuminan los bordes contra el vacío (0 = como antes)
    vec2  edgeOpen;     // 1e4 en los ejes cuyo borde de caja coincide con el de pantalla (no desvanecer)
};
layout(binding = 1) uniform sampler2D scene;
layout(binding = 2) uniform sampler2D bloom;
layout(binding = 3) uniform sampler2D bloom2;
layout(binding = 4) uniform sampler2D soft;
vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), 0.0, 1.0); }
void main(){
    vec4 sc = texture(scene, qt_TexCoord0);
    // bordes contra el vacío: donde la cobertura difiere de su versión desenfocada hay una silueta; ahí se usa la
    // versión desenfocada (difuminado largo). En el interior (alfa 1 en ambas) y junto a la sombra no cambia nada.
    vec4 sf = texture(soft, qt_TexCoord0);
    // solo hacia fuera: el borde interior junto a la sombra (≈ bhRadius) y lo que cae dentro se queda nítido
    float dpx = length(boxOrigin + qt_TexCoord0 * resolution - bhCenter);
    float outer = smoothstep(1.08 * bhRadius, 1.3 * bhRadius, dpx);
    float ek = smoothstep(0.01, 0.35, abs(sc.a - sf.a)) * softAmt * outer;
    sc = mix(sc, sf, ek);
    // máscara del bloom: fuera solo de la sombra pura (cobertura total y oscuro)
    float bm = 1.0 - step(0.99, sc.a) * exp(-8.0 * dot(sc.rgb, vec3(0.2126, 0.7152, 0.0722)));
    // el resplandor se desvanece en los bordes de la caja que no son borde de pantalla
    vec2 px = qt_TexCoord0 * resolution;
    float ef = smoothstep(0.0, 60.0, px.x + edgeOpen.x) * smoothstep(0.0, 60.0, resolution.y - px.y + edgeOpen.y);
    vec3 bl = (0.22 * texture(bloom, qt_TexCoord0).rgb + 0.38 * texture(bloom2, qt_TexCoord0).rgb) * tint.rgb * ef;
    vec3 h = sc.rgb + bm * bloomAmt * bl;
    vec3 e = h * exposure;
    float L = dot(e, vec3(0.2126, 0.7152, 0.0722));
    vec3 t = e * (aces(vec3(L)).g / max(L, 1e-4));
    float mx = max(max(t.r,t.g),t.b);
    t = mix(t, vec3(mx), 0.5 * smoothstep(1.0, 2.0, mx));
    vec3 cc = pow(clamp(t, 0.0, 1.0), vec3(1.0/2.2));
    // premultiplicado sobre negro; alfa = cobertura o, en el resplandor, su brillo
    float a = clamp(max(sc.a, max(max(cc.r, cc.g), cc.b)), 0.0, 1.0);
    fragColor = vec4(cc, a);
}
