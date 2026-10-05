#version 440
// composite.frag — HDR + bloom → exposición → tonemap ACES (Narkowicz) → sRGB.
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
};
layout(binding = 1) uniform sampler2D scene;
layout(binding = 2) uniform sampler2D bloom;
vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), 0.0, 1.0); }
void main(){
    // el bloom no entra en la sombra: negro puro y opaco
    float sh = smoothstep(bhRadius - 1.5, bhRadius + 1.5, distance(qt_TexCoord0 * resolution, bhCenter));
    vec3 h = texture(scene, qt_TexCoord0).rgb + sh * bloomAmt * texture(bloom, qt_TexCoord0).rgb;
    vec3 c = pow(aces(h * exposure), vec3(1.0/2.2));
    fragColor = vec4(c, 1.0);
}
