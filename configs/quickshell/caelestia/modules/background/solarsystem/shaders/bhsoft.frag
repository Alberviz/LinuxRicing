#version 440
// bhsoft.frag — desenfoque gaussiano separable de la escena COMPLETA (rgb premultiplicado y alfa), a media resolución.
// Lo usa bhcomp solo en los bordes donde la cobertura cambia de golpe (silueta contra el vacío) para darles el
// difuminado largo de la bóveda superior; el interior y el borde junto a la sombra no se tocan.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  dir;        // (1,0) horizontal, (0,1) vertical
    vec2  texel;      // 1/tamaño del render target
    float sigma;      // en texels de ESTE render target
};
layout(binding = 1) uniform sampler2D src;
void main(){
    vec4 acc = vec4(0.0); float ws = 0.0;
    for (int i = -10; i <= 10; i++){
        float x = float(i);
        float w = exp(-x * x / (2.0 * sigma * sigma));
        acc += texture(src, qt_TexCoord0 + dir * texel * x) * w; ws += w;
    }
    fragColor = acc / ws;
}
