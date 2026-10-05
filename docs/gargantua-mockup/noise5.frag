#version 440
// noise5.frag — textura de ruido PERIÓDICA (se hornea una vez, live:false, wrap Repeat).
// 4 canales = 4 ruidos de valor independientes, periodo 16 celdas en u y en v.
// El pase por frame la muestrea en (φ/2π·m, r·F): periódica en φ (sin costura) y barata
// (un fetch filtrado por octava en vez de 8 hashes).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
};
const float P = 16.0;
float hash(vec2 i, float s){
    i = mod(i, P);
    vec3 p3 = fract(vec3(i.xyx + s * 17.31) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p, float s){
    vec2 i = floor(p), f = fract(p);
    vec2 u = f*f*f*(f*(f*6.0 - 15.0) + 10.0);
    return mix(mix(hash(i, s), hash(i + vec2(1,0), s), u.x),
               mix(hash(i + vec2(0,1), s), hash(i + vec2(1,1), s), u.x), u.y);
}
void main(){
    vec2 p = qt_TexCoord0 * P;
    fragColor = vec4(vnoise(p, 1.0), vnoise(p, 2.0), vnoise(p, 3.0), vnoise(p, 4.0));
}
