#version 440
// bhcomp.frag — compone la capa del agujero (media resolución) sobre el campo de estrellas a
// resolución completa. out = E + T·estrellas (HDR lineal).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  resolution;
    vec4  colInk;
};
layout(binding = 1) uniform sampler2D bhTex;
vec3 lit(vec3 c, float k){ return mix(c, vec3(1.0), k); }
vec3 toLin(vec3 c){ return pow(c, vec3(2.2)); }
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
vec2  hash22(vec2 p){ float n = sin(dot(p, vec2(41.0, 289.0))); return fract(vec2(262144.0, 32768.0)*n); }
void starfield(inout vec3 acc, vec2 frag, vec3 ink){
    vec3 sc = lit(ink, 0.45);
    float cell = 54.0;
    vec2 id = floor(frag / cell);
    for (int oy=-1; oy<=1; oy++)
    for (int ox=-1; ox<=1; ox++){
        vec2 cid = id + vec2(ox, oy);
        vec2 rnd = hash22(cid);
        if (rnd.x > 0.40) continue;
        vec2 spos = (cid + hash22(cid+3.7)) * cell;
        float b = fract(rnd.y * 91.7);
        float pr = distance(frag, spos);
        float s  = b < 0.7 ? 0.9 : 1.7;
        acc += sc * smoothstep(s, 0.0, pr) * (0.14 + b*0.55);
    }
}

void main(){
    vec2 frag = qt_TexCoord0 * resolution;
    vec3 stars = vec3(0.0);
    starfield(stars, frag, colInk.rgb);
    vec4 L = texture(bhTex, qt_TexCoord0);
    fragColor = vec4(L.rgb + L.a * toLin(min(stars, vec3(1.0))), 1.0);
}
