#version 440
// portal.frag — portal de borde de pantalla de Warp (v2.19.1, A6).
// Fuente de verdad: Olimpo (app/src/warp/shaders.ts: AE1_NEGRO, BINARIO y DISCO_FINO; fusion.ts da los tiempos).
// Dos modos en un mismo programa (uniform `mode`):
//   0  AE1 «Gargantúa en el cielo»: disco trazado con geodésicas (56 pasos) sobre el cielo doblado por el agujero,
//      con aro que cae al tragar. `reposo` (0 encendido, 1 reposo) apaga el disco al 13 % y el halo.
//   1  BINARIO «a los dos»: dos agujeros que se funden en uno (lente mutua, mareas, puente de gas, onda gravitatoria).
//      Centros en px del quad (ctr1, ctr2); fase, uno, onda y oval los da la fusión (Portals.qml).
// Se mantiene el arco del borde de pantalla que rodea el agujero (el tramo recto lo pone QML) y el tinte del tema.
// Todo procedural: sin partículas en CPU. Recompilar:
//   /usr/lib/qt6/bin/qsb --qt6 -b -o portal.frag.qsb portal.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  size;      // px del quad
    vec2  outward;   // normal del borde hacia fuera de la pantalla
    vec4  tint;      // rgb: mezcla suave con el tema (a = fuerza 0..1; > 0,5 = aviso en rojo)
    float rad;       // radio de la sombra en px
    float upx;       // px por «px de mockup» (ancho/1280)
    float en;        // energía 0..1
    float vis;       // visibilidad 0..1
    float armed;     // 0/1
    float pulse;     // 1 -> 0 tras la absorción
    float spin;      // fase acumulada del disco
    float pull;      // fase acumulada de la succión
    float time;      // segundos (cielo, titileo, flujo del gas)
    float reposo;    // 0 encendido, 1 reposo
    float mode;      // 0 AE1, 1 BINARIO
    vec2  ctr1;      // BINARIO: centro del primer agujero (px del quad)
    vec2  ctr2;      // BINARIO: centro del segundo
    float fase;      // BINARIO: giro de la espiral (curva el puente de gas)
    float uno;       // BINARIO: 0 dos agujeros, 1 fundidos
    float onda;      // BINARIO: onda gravitatoria 1 -> 0
    float oval;      // BINARIO: temblor del óvalo al asentarse
    vec2  quadPos;   // LENTE: esquina del quad en px de pantalla (para pasar a UV de la captura)
    vec2  scrSize;   // LENTE: tamaño lógico de la pantalla en px
    float lente;     // LENTE: 0 sin captura (cielo sintético) .. 1 con captura de pantalla (se funde al soltar)
    float fuerza;    // LENTE: 0 móvil/tablet, 1 PC grande (más desvío, disco más opaco y brillante)
    vec4  vecino;    // LENTE: el otro agujero del borde (xy: su centro desde el mío en px, z: su radio en px o 0, w: su vis)
};
layout(binding = 1) uniform sampler2D bg;   // captura congelada de la pantalla (al empezar el arrastre)

#define R rad
#define U upx
#define T time

float sm(float a, float b, float x){ float t = clamp((x - a) / (b - a), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){
    vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p){ float a = 0.5, s = 0.0; for (int i = 0; i < 4; i++){ s += a * vn(p); p *= 2.03; a *= 0.5; } return s; }
// Tramado contra las bandas (v2.16)
float trama(){ return (h21(gl_FragCoord.xy) - 0.5) / 160.0; }
// Bordes del quad que se apagan sin cortes. En el binario el quad llega hasta el borde superior de la pantalla
// (donde está el agujero): ahí no se apaga.
float bordes(vec2 f){
    vec2 m = size * 0.5 - abs(f - size * 0.5);
    return sm(0.0, 36.0 * U, mode > 0.5 ? min(m.x, size.y - f.y) : min(m.x, m.y));
}
// Tinte del tema (error en rojo, música en verde, toque suave del primario)
vec3 tinte(vec3 c){
    float k = tint.a > 0.5 ? 0.85 : tint.a * 0.6;
    return mix(c, tint.rgb * (0.25 + 1.1 * dot(c, vec3(0.34))) * 1.4, k);
}

// ---------------------------------------------------------------------------------------------------------------
// AE1 (Olimpo, shaders.ts)
// ---------------------------------------------------------------------------------------------------------------
// Cielo doblado: estrellas curvadas por el agujero (sg 1 converge) y en espiral (giro) cerca del horizonte.
vec3 cielo(vec2 p, float b, float sg, float giro){
    float rp = length(p); if (rp > R * 9.0 || rp < 1.0) return vec3(0.0);
    vec2 L = p - sg * p * b * b / (rp * rp);
    float an = giro * R * R / (rp * rp + R * R); float c = cos(an), s = sin(an); L = vec2(L.x * c - L.y * s, L.x * s + L.y * c);
    vec2 g = L / (16.0 * U); vec2 i = floor(g), f = fract(g) - 0.5; float h = h21(i); if (h < 0.72) return vec3(0.0);
    vec2 o = (vec2(h21(i + 3.1), h21(i + 7.7)) - 0.5) * 0.6; float d = length(f - o); float tw = 0.7 + 0.3 * sin(T * 1.7 + h * 60.0);
    float mag = 1.0 + 1.6 * sm(2.4, 1.1, rp / R);
    return mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.88, 0.74), h21(i + 1.3)) * smoothstep((0.07 + 0.1 * h21(i + 5.5)) * mag, 0.0, d) * tw * (h - 0.72) * 2.2 * mag * sm(9.0, 4.0, rp / R) * sm(1.08, 1.5, rp / R);
}
// Aro que cae hacia el horizonte al tragar (pulse 1 -> 0): nace fuera y se cierra sobre el disco negro.
float aroDentro(float r){ float k = sqrt(pulse); float rr = 1.04 + 4.0 * k; float w = 0.06 + 0.12 * k; return 2.8 * sm(0.0, 0.04, pulse) * sm(1.0, 0.55, pulse) * exp(-pow((r - rr) / w, 2.0)); }

const float TILT = -0.29670597;
const float RIN = 3.0;
const float ROUT = 10.5;
vec3 paleta(float t){ return mix(vec3(1.0, 0.92, 0.78), vec3(1.0, 0.45, 0.14), sm(0.0, 0.65, t)) * mix(1.0, 0.5, t); }
float gas(vec3 x, float rc, float dir, float flujo){
    float w = pow(rc / RIN, -1.5); float a = atan(x.z, x.x) - dir * spin * 2.2 * w; vec2 e = vec2(cos(a), sin(a));
    float g = vn(e * 4.0 + vec2(rc * 1.9 + flujo, 0.0)) * 0.6 + vn(e * 11.0 + vec2(0.0, rc * 4.3 + flujo * 2.0)) * 0.4;
    return 0.3 + 1.4 * smoothstep(0.3, 0.78, g);
}
// Disco trazado con geodésicas de verdad; cámara a 0,17 sobre el plano del disco. xyz = luz, w = capturado por el horizonte.
vec4 trazar(vec2 s, float dir, float flujo, float brillo, out float tr){
    float c = cos(TILT), sn = sin(TILT); vec2 q = vec2(s.x * c + s.y * sn, -s.x * sn + s.y * c) * 2.598;
    vec3 f = normalize(vec3(0.0, -0.170, 1.0)), up = normalize(cross(f, vec3(1.0, 0.0, 0.0)));
    vec3 pos = vec3(q.x, 0.0, 0.0) - up * q.y - f * 14.0; vec3 vel = f; vec3 hv = cross(pos, vel); float h2 = dot(hv, hv);
    vec3 col = vec3(0.0); tr = 1.0; float cap = 0.0;
    for (int i = 0; i < 56; i++){
        float rr = length(pos); if (rr < 1.03){ cap = 1.0; break; }
        float dt = clamp(0.13 * rr, 0.04, 1.5); vel += -1.5 * h2 * pos / pow(rr, 5.0) * dt; vec3 np = pos + vel * dt;
        if (pos.y * np.y < 0.0){
            vec3 x = mix(pos, np, pos.y / (pos.y - np.y)); float rc = length(x.xz);
            if (rc > RIN && rc < ROUT){
                float rn = (rc - RIN) / (ROUT - RIN); float edge = sm(RIN, RIN + 0.7, rc) * (1.0 - sm(ROUT - 4.0, ROUT, rc));
                vec3 tg = normalize(vec3(-x.z, 0.0, x.x)) * dir; float be = sqrt(0.5 / rc); float D = sqrt(1.0 - be * be) / (1.0 - be * dot(tg, -normalize(vel)));
                float I = pow(RIN / rc, 1.5) * pow(D, 3.0) * gas(x, rc, dir, flujo) * edge;
                I += pulse * 1.4 * exp(-pow((rc - RIN - 0.6) / 0.8, 2.0)) * pow(D, 3.0);
                col += tr * paleta(clamp(rn * 1.15 - (D - 1.0) * 0.6, 0.0, 1.0)) * I * brillo; tr *= 1.0 - (0.8 + 0.17 * fuerza) * edge * clamp(I * (1.2 + 0.8 * fuerza), 0.0, 1.0);
            }
        }
        pos = np; if (rr > 18.0 && dot(pos, vel) > 0.0) break;
    }
    return vec4(col, cap);
}

// ---------------------------------------------------------------------------------------------------------------
// LENTE (solo PC): todo en radios de sombra, así la deformación crece y encoge con el agujero.
// ---------------------------------------------------------------------------------------------------------------
const float LENTE_TE = 1.20;    // radio del anillo de Einstein (1 = borde de la sombra). Más alto = lente más fuerte
const float LENTE_RMAX = 3.3;   // alcance: a partir de aquí la pantalla no se toca (el disco llega a ~4)
const float LENTE_VEC0 = 2.1;   // con dos agujeros: dentro de este radio del vecino manda SU lente (la mía no pinta)...
const float LENTE_VEC1 = 3.0;   // ...y a partir de este vuelve a pintar la mía. Entre los dos pintan lo mismo
// Desvío de la luz a distancia s del centro. Tiene la forma del de un agujero de Schwarzschild: lejos cae como 1/s y al
// llegar a la sombra (s = 1, la esfera de fotones) se dispara como un logaritmo. Se normaliza para que el anillo de
// Einstein quede en LENTE_TE y se lleva a cero, sin escalón ni pico, en LENTE_RMAX.
float desvio(float s){
    float c = LENTE_TE / -log(1.0 - 1.0 / LENTE_TE);
    return -c * log(1.0 - 1.0 / max(s, 1.004)) * (1.0 - sm(LENTE_TE, LENTE_RMAX, s));
}
// Captura en un punto del quad (px desde el centro del agujero). Fuera de la pantalla se refleja en el borde.
vec3 muestra(vec2 q){
    vec2 uv = (quadPos + size * 0.5 + q) / scrSize;
    return texture(bg, clamp(1.0 - abs(1.0 - abs(uv)), 0.0, 1.0)).rgb;
}

void ae1(){
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    float g = 1.0 + 0.05 * sin(3.14159 * pulse); vec2 s = p / (R * g); float r = length(s);
    if (r > 9.0){ fragColor = vec4(0.0); return; }
    float tr = 1.0; vec4 d = vec4(0.0);
    // v2.19.1: el interruptor `armed` suma un poco de brillo al disco (como en el borde antes de AE1)
    float brillo = vis * mix((0.42 + 0.62 * en + 0.1 * armed) * (1.0 + 0.7 * fuerza), 0.13, reposo);
    if (r < 4.6) d = trazar(s, 1.0, T * 0.45 * (1.0 + en), brillo, tr);
    vec3 rgb = d.rgb;
    vec3 aire = vec3(1.0, 0.62, 0.32) * vis * mix(0.5 + en, 0.25, reposo) * (0.05 * exp(-max(r - 1.0, 0.0) * 0.8) + 0.02 * exp(-max(r - 1.0, 0.0) * 0.28) * sm(9.0, 5.0, r));
    vec3 fondo = cielo(p, 1.9 * R, 1.0, 1.2 * en + 5.0 * pulse + T * 0.15) * vis;
    // Lente gravitatoria sobre la captura de la pantalla (ver desvio()): cada píxel a distancia r del centro enseña lo que
    // hay en beta = r - desvío(r), en la misma dirección. Fuera del anillo de Einstein la imagen se aprieta hacia el
    // agujero y se estira en arco; dentro (entre el anillo y la sombra) sale la imagen secundaria, del revés y muy fina.
    float a = 0.0; vec3 cap = vec3(0.0);
    if (lente > 0.001){
        float Rg = R * g; float kv = min(vis, 1.0);
        float dl = desvio(r) * kv;
        float b0 = r - dl;
        // Huella radial: px de la captura que caben en un px de pantalla (crece hacia la sombra); se promedia para no serrar.
        float b1 = r + 1.0 / Rg - desvio(r + 1.0 / Rg) * kv;
        float huella = clamp(abs(b1 - b0) * Rg, 1.0, 14.0) - 1.0;
        vec2 dir = s / max(r, 0.001);
        // Dos agujeros en el mismo borde: los desvíos se suman (cada quad pinta la misma imagen donde se pisan) y cerca
        // del vecino no pinto yo, para no taparle el disco ni la sombra: ninguno se come al otro.
        vec2 dv = vec2(0.0); float libre = 1.0;
        if (vecino.z > 1.0){
            vec2 pv = p - vecino.xy; float rv = length(pv) / vecino.z;
            dv = pv / max(length(pv), 0.001) * desvio(rv) * vecino.z * min(vecino.w, 1.0);
            libre = sm(LENTE_VEC0, LENTE_VEC1, rv);
        }
        for (int i = 0; i < 5; i++) cap += muestra(dir * (b0 * Rg + (float(i) - 2.0) * 0.25 * huella) - dv);
        cap *= 0.2 * sm(1.0, 1.12, r);   // la imagen secundaria se apaga al llegar a la sombra
        // La captura solo tapa la pantalla donde el desvío se ve (más de ~3 px); por debajo de medio píxel ya no pinta:
        // así no hay costura ni imagen doble donde acaba la lente.
        a = lente * libre * sm(0.5, 3.0, length(dir * dl * Rg + dv)) * bordes(qt_TexCoord0 * size);
        fondo *= 1.0 - a;
    }
    rgb += (1.0 - d.a) * tr * (aire + fondo);
    rgb += (1.0 - d.a) * vec3(1.0, 0.8, 0.55) * aroDentro(r) * vis * 1.4;
    rgb = tinte(1.0 - exp(-rgb * 1.3));
    // Lo que deja pasar el agujero: nada la sombra y, en el PC (`fuerza`), solo lo que no tapa el disco. La captura no pasa
    // por el tono (se conserva tal cual) y va premultiplicada: color = captura · alfa, sin oscurecer ni duplicar.
    float paso = (1.0 - d.a * vis) * mix(1.0, tr, fuerza);
    rgb += paso * a * cap;
    // Arco del borde de pantalla curvado alrededor del agujero (solo el arco; el tramo recto lo pone QML)
    float Rr = R * (1.45 + 0.25 * en) * vis;
    if (dot(p, outward) <= 0.0 && Rr > 1.0){
        float dd = abs(length(p) - Rr); vec3 rc = vec3(1.0, 0.871, 0.725); float amp = vis * (0.35 + 0.65 * en);
        rgb += rc * amp * 0.06 * (1.0 - smoothstep(2.5 * U, 2.5 * U + 2.0, dd));
        rgb += rc * amp * 0.45 * (1.0 - smoothstep(0.7 * U, 0.7 * U + 1.2, dd));
    }
    float alfa = clamp(1.0 - paso * (1.0 - a), 0.0, 1.0);
    fragColor = vec4(max(rgb * bordes(qt_TexCoord0 * size) + trama(), 0.0), alfa) * qt_Opacity;
}

// ---------------------------------------------------------------------------------------------------------------
// BINARIO «a los dos» (Olimpo, shaders.ts: DISCO_FINO + BINARIO)
// ---------------------------------------------------------------------------------------------------------------
vec3 pal2(float t, float frio){
    vec3 a = mix(vec3(1.0, 0.93, 0.8), vec3(1.0, 0.42, 0.12), sm(0.0, 0.8, t)) * mix(1.0, 0.55, t);
    vec3 b = mix(vec3(1.0), vec3(0.42, 0.6, 1.0), pow(t, 0.8)); return mix(a, b, frio);
}
float gas2(float ang, float rho, float fl){ return 0.35 + 1.3 * smoothstep(0.3, 0.8, vn(vec2(ang * 3.0, rho * 2.6 + fl)) * 0.6 + vn(vec2(ang * 9.0, rho * 6.0 + fl * 2.0)) * 0.4); }
// Disco fino analítico: banda delantera aplastada, imagen trasera en arco y anillo de fotones.
vec4 discoFino(vec2 s, float dir, float fl, float br, float frio, out vec3 atras){
    float c = cos(-0.2), sn = sin(-0.2); vec2 q = vec2(s.x * c + s.y * sn, -s.x * sn + s.y * c);
    float rho = length(vec2(q.x, q.y / 0.21)); float ang = atan(q.y / 0.21, q.x);
    float band = sm(1.4, 1.75, rho) * (1.0 - sm(2.8, 4.3, rho));
    float dop = 1.0 + 0.6 * dir * (-q.x) / max(rho, 0.001);
    float I = band * pow(1.6 / rho, 1.3) * dop * dop * gas2(ang - dir * (spin * 1.6) / rho, rho, fl);
    float delante = sm(-0.02, 0.06, q.y) + (1.0 - sm(-0.02, 0.06, q.y)) * sm(1.05, 1.25, length(q));
    vec3 front = pal2(sm(1.4, 4.0, rho) - (dop - 1.0) * 0.4, frio) * I * br * delante;
    float fa = clamp(I * 1.6, 0.0, 1.0) * band * delante;
    float r = length(q); float an = atan(q.x, -q.y);
    float arco = sm(1.08, 1.2, r) * (1.0 - sm(1.35, 1.85, r));
    float arriba = sm(-0.35, 0.5, -q.y / max(r, 0.001));
    float abajo = sm(0.2, 0.9, q.y / max(r, 0.001)) * 0.35 * (1.0 - sm(1.12, 1.3, r));
    float dop2 = 1.0 + 0.5 * dir * (-q.x) / max(r, 0.001);
    float I2 = arco * (arriba + abajo) * pow(1.25 / r, 2.2) * dop2 * dop2 * (0.55 + 0.45 * gas2(an * 1.2 - dir * spin * 1.2, r * 1.2, fl * 0.5));
    atras = pal2(sm(1.08, 2.1, r), frio) * I2 * br;
    atras += mix(vec3(1.0, 0.9, 0.74), vec3(0.9, 0.95, 1.0), frio) * exp(-pow((r - 1.035) * R / (1.3 * U), 2.0)) * (0.55 + 0.45 * dop2) * br * 1.1;
    return vec4(front, fa);
}
vec2 desv(vec2 p, vec2 c, float b){ vec2 d = p - c; return d * b * b / max(dot(d, d), 1.0); }
float smin(float a, float b, float k){ float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }

void binario(){
    vec2 f = qt_TexCoord0 * size;
    vec2 c1 = ctr1, c2 = ctr2; float b = R * 1.75; float k2 = 1.0 - uno;
    vec2 dv = c2 - c1; float dd = length(dv) / R; vec2 eje = dd > 0.01 ? dv / length(dv) : vec2(1.0, 0.0);
    float cerca = sm(0.3, 1.5, dd);
    // lente: la del vecino solo mientras son dos
    vec2 L = f - desv(f, c1, b) - desv(f, c2, b) * k2;
    // onda gravitatoria: solo el cielo, desde fuera del horizonte
    { vec2 cm = (c1 + c2) * 0.5; float dm = length(f - cm); float rw = (1.0 - onda) * 14.0 * R + 2.5 * R;
      L += (f - cm) / max(dm, 1.0) * sin((dm - rw) / R * 3.0) * onda * 7.0 * U * exp(-pow((dm - rw) / (2.2 * R), 2.0)) * sm(2.0 * R, 3.0 * R, dm); }
    vec2 s1 = (f - c1 - desv(f, c2, b * 0.85) * k2 * cerca) / R, s2 = (f - c2 - desv(f, c1, b * 0.85) * k2 * cerca) / R;
    // óvalo amortiguado al asentarse
    s1 = vec2(s1.x / (1.0 + oval), s1.y * (1.0 + oval));
    float marea = 0.22 * sm(7.0, 2.5, dd) * k2 * cerca;
    vec2 m1 = s1 - eje * dot(s1, eje) * marea, m2 = s2 - eje * dot(s2, eje) * marea;
    float br = vis * (0.55 + 0.7 * en + 0.6 * pulse);
    vec3 a1, a2; vec4 d1 = discoFino(m1, 1.0, T * 0.5, br, 0.0, a1); vec4 d2 = discoFino(m2, 1.0, T * 0.5 + 3.7, br, 0.0, a2);
    float dl = length(f - c2) - length(f - c1); float w1 = 0.22 + 0.78 * sm(-R * 0.6, R * 0.6, dl), w2 = 0.22 + 0.78 * sm(R * 0.6, -R * 0.6, dl);
    w1 = mix(w1, 1.0, uno); w2 *= k2; a1 *= w1; a2 *= w2; d1 *= w1; d2 *= w2;
    // sombra: un cacahuete que se redondea (mínimo suave de las dos)
    float r1 = length(vec2((f - c1).x / (1.0 + oval), (f - c1).y * (1.0 + oval))), r2 = length(f - c2);
    float kk = R * 0.9 * sm(3.2, 1.2, dd) * k2; float ds = k2 > 0.001 ? smin(r1, r2, max(kk, 0.001)) : r1;
    float px = 1.0 / R; float sombra = (1.0 - smoothstep(1.0 - px, 1.0 + px, ds / R)) * vis;
    float o1 = 1.0 - smoothstep(1.0 - px, 1.0 + px, r1 / R), o2 = (1.0 - smoothstep(1.0 - px, 1.0 + px, r2 / R)) * k2;
    vec3 cie = vec3(0.0);
    { vec2 g = L / (16.0 * U); vec2 i = floor(g), fr = fract(g) - 0.5; float h = h21(i);
      if (h > 0.72){
          vec2 o = (vec2(h21(i + 3.1), h21(i + 7.7)) - 0.5) * 0.6; float kq = length(fr - o);
          float mag = 1.0 + 1.4 * (sm(2.4, 1.1, length(f - c1) / R) + sm(2.4, 1.1, length(f - c2) / R) * k2);
          cie = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.88, 0.74), h21(i + 1.3)) * smoothstep(0.07 + 0.1 * h21(i + 5.5), 0.0, kq) * (h - 0.72) * 2.2 * mag;
      }
      // en el shell no hay lienzo de cielo: las estrellas solo existen alrededor de los agujeros (como en AE1)
      cie *= sm(1.15, 1.5, ds / R) * sm(9.0, 4.0, min(length(f - c1), length(f - c2)) / R); }
    // puente de materia: aparece al acercarse y se va al fundirse
    vec2 med = (c1 + c2) * 0.5; vec2 nor = vec2(-eje.y, eje.x); vec2 ctrl = med + nor * length(c2 - c1) * 0.28 * sin(fase);
    float best = 1e9, bt = 0.0;
    for (int i = 0; i <= 24; i++){ float t = float(i) / 24.0; vec2 q = mix(mix(c1, ctrl, t), mix(ctrl, c2, t), t); float kq = length(f - q); if (kq < best){ best = kq; bt = t; } }
    float ancho = R * (0.12 + 0.2 * sin(3.14159 * bt));
    float hilo = exp(-pow(best / ancho, 2.0)) * sm(0.0, 0.18, bt) * sm(1.0, 0.82, bt) * sm(6.5, 3.0, dd) * sm(0.9, 1.8, dd) * k2;
    float grumo = 0.45 + 0.9 * fbm(vec2(bt * 9.0 - T * 1.6, best / R * 2.0));
    vec3 puente = vec3(1.0, 0.66, 0.36) * hilo * grumo * vis * (0.9 + 0.8 * en + 1.5 * pulse);
    vec3 rgb = (cie * vis + a1 + a2 + puente + vec3(1.0, 0.62, 0.32) * vis * 0.05 * (exp(-max(r1 / R - 1.0, 0.0) * 0.6) + exp(-max(r2 / R - 1.0, 0.0) * 0.6) * k2)) * (1.0 - max(d1.a, d2.a)) * (1.0 - sombra);
    rgb += d1.rgb * (1.0 - o2) + d2.rgb * (1.0 - o1);
    float rr = 1.04 + 1.6 * sqrt(pulse); float ww = 0.04 + 0.06 * sqrt(pulse);
    rgb += vec3(1.0, 0.8, 0.55) * 1.4 * sm(0.0, 0.04, pulse) * sm(1.0, 0.55, pulse) * exp(-pow((r1 / R - rr) / ww, 2.0)) * vis * (1.0 - sombra);
    rgb += vec3(0.9, 0.95, 1.0) * onda * onda * 0.07 * exp(-pow((length(f - med) - ((1.0 - onda) * 14.0 * R + 2.5 * R)) / (0.5 * R), 2.0));
    rgb = tinte(1.0 - exp(-rgb * 1.35));
    fragColor = vec4(max(rgb * bordes(f) + trama(), 0.0), sombra) * qt_Opacity;
}

void main(){
    if (mode > 0.5) binario(); else ae1();
}
