#version 440
// whitehole.frag — agujero BLANCO clavado en el borde superior (lo que llega del móvil sale por aquí; Outer Wilds).
// Esfera de luz pequeña con borde suave (no un disco plano), halo frío, rayos que giran despacio, anillo de lente fino
// y, en cada expulsión (pulse 1 -> 0), un frente de chispas en cono hacia la pantalla + onda de choque + destello.
// Todo aditivo y con tone-mapping (nunca satura en una placa blanca). Sin chorro permanente ni línea de borde.
// Procedural; sin partículas en CPU. Recompilar: /usr/lib/qt6/bin/qsb --qt6 -o whitehole.frag.qsb whitehole.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  size;
    vec4  tint;     // color del tema (rgb; a = fuerza del tinte)
    float rad;      // radio del núcleo en px
    float upx;      // px por «px de mockup»
    float en;       // energía 0..1 (sube en cada expulsión)
    float vis;      // presencia 0..1 (abrirse / cerrarse)
    float phase;    // 0..1 cíclico (giro de rayos y brillo)
    float pulse;    // 1 -> 0: expulsión en curso
};
#define R rad
#define U upx

float sm(float a, float b, float x){ float t = clamp((x - a) / (b - a), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){
    vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void main(){
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    vec2 s = p / max(R, 1.0);
    float r = length(s);
    float ang = atan(s.x, s.y);                 // 0 = hacia abajo (dentro de la pantalla)
    float t = phase * 6.2831853;
    float out_ = max(r - 1.0, 0.0);
    vec3 cold = vec3(0.62, 0.78, 1.0);
    cold = mix(cold, cold * (0.55 + tint.rgb * 0.9), tint.a);
    vec3 col = vec3(0.0);

    // halo: cercano intenso + lejano tenue
    col += cold * 0.50 * exp(-out_ * 1.8) * vis;
    col += cold * 0.14 * exp(-out_ * 0.5) * vis;

    // rayos: rendijas radiales que giran muy despacio (dos capas en sentidos opuestos)
    float ra = vn(vec2(ang * 6.0 + t * 0.25, 1.7));
    float rb = vn(vec2(ang * 15.0 - t * 0.4, 9.3));
    float rays = pow(ra * rb, 1.4);
    col += cold * rays * 1.6 * exp(-out_ * 0.75) * sm(0.95, 1.3, r) * vis * (0.45 + 0.55 * en);

    // anillo de lente: fino, con brillo que recorre el contorno
    float rq = (r - 1.32) * R / (1.0 * U + 0.9); float ring = exp(-rq * rq);
    col += vec3(0.86, 0.93, 1.0) * ring * (0.30 + 0.20 * sin(ang * 3.0 + t * 2.0)) * vis;

    // núcleo: esfera con borde suave; el centro blanco, el limbo azulado; centelleo muy leve
    float body = 1.0 - sm(0.84, 1.02, r);
    float limb = sm(0.25, 1.0, r);
    float hot = 0.30 + 0.95 * exp(-r * r * 1.8) + 0.35 * sm(0.55, 0.95, r);   // centro ardiente, limbo con brillo
    vec3 coreCol = mix(vec3(1.0), cold * 1.1 + 0.1, limb * 0.7);
    col += coreCol * body * hot * (0.9 + 0.8 * en) * vis;
    col += body * 0.18 * vn(s * 3.5 + vec2(t * 0.6, -t * 0.9)) * vis;

    // expulsión: frente de chispas en cono hacia abajo + onda de choque + destello central
    if (pulse > 0.0){
        float k = 1.0 - pulse;                           // avance 0 -> 1
        float front = 1.1 + k * 8.0;
        float ca = ang / 0.6; float cone = exp(-ca * ca);
        float sparks = pow(vn(vec2(ang * 38.0, r * 0.7 - k * 12.0)), 3.0);
        float band = sm(front - 3.5, front, r) * (1.0 - sm(front, front + 0.35, r));
        col += vec3(0.92, 0.96, 1.0) * cone * band * sparks * 3.0 * pulse;
        float sq = (r - (1.15 + k * 5.5)) * R / (1.5 * U + 4.0 * pulse + 0.5); float sw = exp(-sq * sq);
        col += vec3(0.85, 0.93, 1.0) * sw * pulse * 0.75;
        col += vec3(1.0) * pulse * pulse * exp(-r * r * 0.3) * 0.9;
    }

    // ventana: se apaga antes del borde del quad (nada de cortes rectos)
    col *= 1.0 - sm(5.0, 7.6, r);
    col = 1.0 - exp(-col * 1.25);                       // tone-map: brillo sin placa saturada
    fragColor = vec4(col, 0.0) * qt_Opacity;
}
