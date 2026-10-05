---
tags:
  - handoff
  - blackhole
  - quickshell
  - glsl
creado: 2026-09-05
agente_origen: Gemini
agente_destino: Claude
rama: feat/sistema-solar-v3
worktree: /home/alberviz/LinuxRicing/.worktrees/sistema-solar-v3
---

# Handoff a Claude — Unificación Total de Gargantua (*Interstellar*)

> [!IMPORTANT]
> **Mensaje de Alberto a Claude y Gemini:**  
> *«Sigue sin ser uno, siguen siendo dos cosas distintas el disco ecuatorial y la bóveda superior e inferior. Pide ayuda a Claude y repartiros el trabajo».*

---

## 1. El Problema Visual Exacto (Diagnóstico Forense)

Compara las dos imágenes que están en la raíz del repositorio:
1. `reference_interstellar.png` — La referencia cinematográfica oficial de Gargantua (Kip Thorne / DNEG).
2. `current_bh.png` — Captura real tomada en vivo del escritorio de Alberto (workspace 9 limpio, sin ventanas).

### ¿Por qué Alberto dice que «siguen siendo dos cosas distintas»?
Al mirar `current_bh.png`, el defecto salta a la vista:
1. **La «X» o tijera en el flanco izquierdo:**
   - La bóveda superior (`lut1`) desciende por la izquierda con una pendiente casi vertical (aprox 70°).
   - El disco ecuatorial (`sampleFrontDisk`) cruza horizontalmente a 0°.
   - En el punto de unión ($u \approx -2.6$), se cruzan como **dos espadas formando una «X»**. No se funden ni fluyen juntos; son dos capas distintas atravesándose.
2. **El óvalo/aro del lado derecho:**
   - Detrás de la espada horizontal aparece un aro elíptico cerrado con un fogonazo blanco en su interior.
3. **El aro inferior gigante (`lut0`):**
   - La media luna inferior de la LUT forma un círculo que también corta a la cuchilla horizontal por abajo.
4. **Sensación visual resultante:**
   - Parece una esfera de Saturno atravesada por una barra luminosa recta, en vez de un **único cuerpo toroidal de gas en rotación kepleriana distorsionado por la gravedad de Schwarzschild**.

---

## 2. La Verdad Geométrica de *Interstellar* (Kip Thorne / DNEG)

En la física real de la película:
- El disco de acreción es **UN SOLO OBJETO** (un disco de gas 3D con espesor $H(r)$ que se ensancha hacia afuera, $H \propto r^{9/8}$, en rotación diferencial $v \propto r^{-1/2}$).
- Al observarlo con una inclinación casi de canto ($\\theta_0 \approx 78^\\circ$ a $85^\\circ$):
  1. **La mitad delantera (near side):** Pasa por delante del agujero negro. Al estar en primer plano, tapa la sombra central.
  2. **La mitad trasera (far side):** La luz que sale hacia arriba se curva hacia abajo por gravedad y forma la **bóveda superior**. La luz que sale hacia abajo se curva hacia arriba y forma la **media luna inferior**.
  3. **Los limbos (flancos izquierdo y derecho):** En los extremos tangenciales, la línea de visión es tangente al borde exterior del disco. **Ahí NO hay separación entre delante y detrás**. La bóveda superior, la media luna inferior y el disco delantero se fusionan de forma **TANGENTE ($C^1$)**, abriéndose hacia la izquierda en una majestuosa boca/campana ensanchada por el efecto Doppler relativista.

---

## 3. Causa Raíz en el Código Actual (`solarfield.frag`)

El archivo se encuentra en:  
`configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag`  
(dentro del worktree `/.worktrees/sistema-solar-v3/`).

Actualmente hay **tres capas independientes superpuestas con `over()`**:
```glsl
// 1. Disco frontal analítico (dibuja una franja horizontal recta)
vec4 colFront = sampleFrontDisk(...);
over(acc, colFront.rgb, colFront.a);

// 2. Imagen directa de la LUT (dibuja el arco inferior)
vec4 col0 = discPlane(rD0, phi0, ...);
over(acc, col0.rgb, col0.a * crescentMask);

// 3. Imagen secundaria de la LUT (dibuja el arco superior)
vec4 col1 = discPlane(rD1, phi1, ...);
over(acc, col1.rgb, col1.a * 0.95);
```

### Por qué esto nunca va a funcionar si son funciones separadas:
- `lut1` (precalculada en `gen_lut_final.py`) mapea rayos de orden 1 sobre una hoja 2D infinitamente delgada. Termina de forma abrupta en $b \approx 2.77$ con pendiente vertical.
- `sampleFrontDisk` es una función analítica cartesiana horizontal centrada en $v_{mid} \approx 0.04$.
- Al componerlas, **tienen vectores tangentes completamente diferentes en el punto de contacto**. El ojo humano detecta al instante que la franja horizontal no «nace» del arco ni el arco se «abre» en la franja.

---

## 4. Opciones de Solución para Claude y Gemini

### Opción A (Recomendada): Coordenadas Deformadas Unificadas C¹ (Espacio Curvo Único)
En vez de evaluar el disco frontal como una barra horizontal independiente que colisiona con los arcos de la LUT:
1. Definir una transformación de coordenadas continua $(u, v) \to (r_{eff}, \phi_{eff}, z_{eff})$ que gobierne **TODO el disco**.
2. En los limbos ($u \in [-3.6, -2.2]$), la curva de la bóveda superior y la curva del disco delantero deben compartir la **misma tangente**:
   $$v_{top}(u) \quad \text{y} \quad v_{front}(u) \quad \text{convergen suavemente a la silueta exterior común}.$$
3. La campana o cono de aproximación izquierdo (Doppler) debe englobar tanto el gas superior como el inferior y el ecuatorial en un único volumen acampanado.

### Opción B: Raymarcher Analítico / Mapeo de Thorne Simplificado
Aprovechar que para un observador exterior a 78°, la deformación de Schwarzschild sobre un disco con espesor se puede modelar mediante una función implícita de distancia $d(u, v)$ que genera las tres ramas (superior, inferior, frontal) de forma simultánea desde un único campo potencial, garantizando continuidad topológica absoluta.

---

## 5. Parámetros que Alberto Exige Mantener Intactos

1. **Colores Material 3:** Usar `colPrimary` (`#f7b999`), `colError`, `colVoid` (definidos en las uniforms).
2. **Posición y tamaño en pantalla:** Anclado arriba a la derecha (`fx: 0.90, fy: 0.08, rFrac: 0.080` en `Sim.js` y `SolarSystemModel.qml`).
3. **Música y Audio:** Reactividad a `musicPulse`, `musicProgress`, `musicBurstAge` que ya están en `discPlane()`.

---

## 6. Comandos para Probar y Desplegar

En el worktree `/home/alberviz/LinuxRicing/.worktrees/sistema-solar-v3`:

```bash
# 1. Compilar shader
/usr/lib/qt6/bin/qsb --qt6 -o configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag.qsb configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag

# 2. Desplegar a config de quickshell
cp configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag ~/.config/quickshell/caelestia/modules/background/solarsystem/shaders/
cp configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag.qsb ~/.config/quickshell/caelestia/modules/background/solarsystem/shaders/

# 3. Reiniciar shell de Quickshell
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d

# 4. Capturar pantalla limpia en workspace 9
hyprctl repl "hl.dispatch(hl.dsp.focus({ workspace = 9 }))"
sleep 0.3
grim /tmp/screen_clean_ws9.png
hyprctl repl "hl.dispatch(hl.dsp.focus({ workspace = 1 }))"
magick /tmp/screen_clean_ws9.png -crop 500x350+1420+0 /home/alberviz/LinuxRicing/current_bh.png
```
