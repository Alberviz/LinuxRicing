#version 440
// bloom.frag — una pasada separable a 1/4 de resolución. dir=(1,0) hace además el
// paso de umbral (solo zonas brillantes); dir=(0,1) es la pasada vertical.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  dir;        // en texels de ESTE render target
    vec2  texel;      // 1/tamaño del render target
    float threshold;  // 1 = solo > 1 (HDR); 0 = sin umbral (2.ª pasada)
};
layout(binding = 1) uniform sampler2D src;
vec3 bright(vec3 c){
    float m = max(c.r, max(c.g, c.b));
    float k = threshold > 0.5 ? smoothstep(0.9, 2.6, m) : 1.0;
    return c * k;
}
void main(){
    vec3 acc = vec3(0.0); float ws = 0.0;
    for (int i=-14; i<=14; i++){
        float x = float(i);
        float w = exp(-x*x/(2.0*36.0));
        vec2 uv = qt_TexCoord0 + dir * texel * x * 1.5;
        acc += bright(texture(src, uv).rgb) * w; ws += w;
    }
    fragColor = vec4(acc / ws, 1.0);
}
