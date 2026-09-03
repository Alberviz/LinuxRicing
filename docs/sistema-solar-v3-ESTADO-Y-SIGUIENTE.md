# Sistema Solar v3 — estado y siguientes pasos (traspaso a sesión limpia)

> **Fecha:** 2026-09-03. Escrito para la sesión que continúe tras el reinicio del
> equipo. La spec de diseño sigue siendo `docs/sistema-solar-v3-DISENO.md`
> (composición variante D, capas del render §4, rendimiento §6, decisiones §8).
> Este documento es SÓLO el estado actual + qué falta.

---

## 1. Dónde está el código

- **Rama:** `feat/sistema-solar-v3`. Worktree en `.worktrees/sistema-solar-v3`.
  **NO está mergeada** a `main` ni a su base `refactor/background-modularize`.
- **Último commit:** `954c08e`. Arco de la rama:

  | commit | qué |
  |---|---|
  | `2cf4519` | base v3 (archivos traídos de la v1.5) |
  | `f1fb643` | porte a QML de la variante D en Canvas 2D |
  | `e066f21` | fix imports + Canvas robusto |
  | `3402d27` | docs — diseño hecho, verificación bloqueada (monitor) |
  | `c4f2ecc` | perf: 3 Canvas (estático/agujero/binario) |
  | `86fdae4` | docs — verificada en escritorio real tras reenchufe |
  | `d0b5d44` | movimiento siempre activo y más lento |
  | `b81e5b5` | **modo Laura activa** + reducir la vista para el fondo-GPU |
  | `e055cfd` | **`SolarField` — todo el fondo en un shader GLSL (GPU)** |
  | `954c08e` | integración: `SolarField` dentro de `SolarSystem` + reloj desacoplado |

- **El despliegue (`~/.config/quickshell/caelestia/`) == repo** en el momento de
  escribir esto (`diff -rq` sin salida).

### Archivos de la v3

```
configs/quickshell/caelestia/
├── shell.qml                                    → instancia SolarSystemLayer {}
├── services/SolarSystemModel.qml                → modelo: config v3 + adaptadores
│                                                   (música/cava, agentes, batería,
│                                                   tareas, LED). flag showWallpaper.
└── modules/background/
    ├── Background.qml                           → wallpaper OFF tras flag (D-1);
    │                                               DesktopCircularMedia / Peripherals /
    │                                               Deck / LedStrip COMENTADOS (D-6);
    │                                               solo el reloj, en WlrLayer.Bottom (D-8)
    └── solarsystem/
        ├── SolarSystemLayer.qml                 → la ventana de fondo:
        │                                           WlrLayer.Background, negro opaco,
        │                                           click-through. Importa el singleton
        │                                           Laura y pasa lauraActive/lauraAmplitude.
        │                                           Ata la paleta a Colours.palette.
        ├── SolarSystem.qml                      → LA VISTA. Instancia SolarField (fondo
        │                                           shader) + una capa fina en Canvas
        │                                           (cinturón + trazas de órbita +
        │                                           satélites) + el MODO LAURA (D-12) +
        │                                           los tics.
        ├── SolarField.qml                       → ShaderEffect a pantalla completa.
        │                                           Interfaz: time, music, lauraFocus,
        │                                           lauraAmp, layout (objeto de Sim.js),
        │                                           colPrimary/colLaura/colError/colVoid/colInk.
        ├── Sim.js                               → MOTOR PURO de posiciones. Sin deps de Qt.
        │                                           computeLayout(state, geom) → { bh, bary,
        │                                           suns[], bodies[], belt, bhSpin, bhBounds,
        │                                           binBounds, bounds, music }.
        └── shaders/
            ├── solarfield.frag                  → GLSL #version 440, UBO `buf` de Qt.
            └── solarfield.frag.qsb              → compilado. Recompilar tras editar:
                                                   cd .../shaders && \
                                                   /usr/lib/qt6/bin/qsb --qt6 \
                                                     -o solarfield.frag.qsb solarfield.frag
                                                   (commitear .frag Y .qsb)
```

### Arquitectura de render (lo que decidió Alberto sobre la marcha)

- **El fondo entero (agujero negro + los dos soles + campo de estrellas + lente)
  lo pinta el shader `solarfield.frag` en la GPU** (decisión D-13). Motivo: Canvas
  2D no llegaba a la calidad de la spec §4 sin pasarse de CPU, y como el modo
  Laura congela/oscurece todo el sistema, la GPU queda libre para la inferencia
  de Laura justo cuando hace falta — así que no hay conflicto GPU.
- **La capa fina en Canvas** (`SolarSystem.qml` → `dynCanvas`) dibuja SOLO lo que
  es dato vivo y de pocos elementos: cinturón de tareas, trazas de órbita,
  satélites (agentes/dispositivos). Repinta a ~2 fps.
- **El tiempo del shader (`_t`)** avanza en un `Timer` ligero a ~20 fps (solo un
  `+=` a una propiedad; el shader se refresca por el binding del uniform). Las
  posiciones de Sim.js y la capa fina van a ~2 fps (los cuerpos orbitan en
  períodos de 200-360 s — ver §3 abajo).
- **`simTime`** (`_t` menos el rato acumulado en modo Laura) es la ÚNICA fuente
  de tiempo del sistema: se congela mientras Laura habla y reanuda sin salto.

### Modo Laura activa (D-12)

`SolarSystemLayer` importa `qs.modules.assistant` (singleton `Laura`) y pasa
`lauraActive: Laura.active` + `lauraAmplitude: Laura.amplitude`. Con Laura activa:
- el tiempo del sistema se **congela** (`simTime` latcheado);
- la capa fina en Canvas se **oscurece** al 18 % (`_dimK`);
- el shader recibe `lauraFocus` (0→1 con Behavior de 380 ms) y debe **oscurecer
  el fondo y hacer que Laura brille latiendo con `lauraAmp`**.

La propiedad se llama **`lauraFocus`**, no `focus` (colisiona con el `focus`
final de `QQuickItem`). El uniform en el shader es `focusAmt`.

---

## 2. Qué funciona

- Carga limpia (`INFO: Configuration Loaded`, sin warnings QML nuevos), 1 instancia.
- **Renderiza en el escritorio real** — captura `docs/sistema-solar-v3-mockup/real-shader-fondo.png`.
- Composición correcta: agujero en la esquina superior derecha saliéndose de
  cuadro, disco en diagonal, binario Laura↔Config centro-izquierda anclado, reloj
  arriba-izquierda, campo de estrellas.
- Los dos soles se ven bien (Laura oro grande, Config peach pequeño; con un
  satélite si hay agente/dispositivo).
- El modo Laura está cableado y carga sin crash (probado forzando `lauraActive:true`).
- Colores 100 % de `Colours.palette.m3*`. Cero hex fijos.

---

## 3. Qué falta / qué está mal (EN ORDEN DE PRIORIDAD)

### 3.0 Regresión de CPU del Repeater de satélites ✅ RESUELTO (2026-09-03, commit `74a988a`)

Tras el Frente A (satélites como `Repeater` de `ShaderEffectSource`) el shell
subió de ~48 % a ~57 % de un núcleo **con 100 cuerpos de prueba**. Causa: cada
`ShaderEffectSource` iba con `live: true` (defecto) → repintaba su render-target
CADA frame aunque la textura de origen es fija (100 FBO/frame); y cada delegado
tenía 2 bindings por frame con `Math.sin(root._t*…)` + string `rgba()` (aro de
alerta, anillo de actividad) que corrían 60×/s por cuerpo aunque invisibles.
Arreglo: `live: false` + `scheduleUpdate()` puntual; aro y anillo detrás de
`Loader { active }`; los pulsos a propiedades de root a ~20 fps y sólo si hay
cuerpo que los use. **Medido: 100 cuerpos 57 %→12 %; reposo real (0 agentes)
7.6 %; con 4 agentes 9.7 %. Ya no sube al añadir cuerpos.**

### 3.0b Disposición seleccionable — 3 variantes (2026-09-03, commit `f5ba2cc`)

`Sim.js` → `D.layoutVariant` (1|2|3). 1 conservadora (activa por defecto), 2
aprovecha el hueco (baricentro abajo-izquierda), 3 diagonal completa. Períodos
escalados con la separación (velocidad angular px/s constante). Trazas de órbita
con estela de cometa. **Capturas de las 3 PENDIENTES**: `grim` cuelga por el
gotcha #1 (eDP-2 en x=-3840); tras reiniciar/re-enchufar el monitor, ejecutar
`scratchpad/capturar-variantes.sh` (o el equivalente de §4.7) para generar
`composicion-v{1,2,3}.png` y que Alberto elija.

### 3.1 «Se ve petado» / va lento — RENDIMIENTO ✅ RESUELTO (2026-09-03, commit `ba7a4fa`)

**Medido en limpio tras el reinicio: 15.1 % → 4.7 % de un núcleo** (objetivo del
diseño §6.8: ≤ ~5 %). El sistema solar ya no añade nada medible sobre la base
del shell. Qué se hizo:
- `sun()`: corte temprano `if (rn > 3.4) return`. Los soles miden ~40-50 px; sin
  el return, el bucle de prominencias + los `pow` de corona corrían para CADA
  píxel de la pantalla, dos veces. **El mayor ahorro.**
- `blackHole()`: corte temprano `if (dS > 4.6) return` tras el resplandor
  exterior — salta fbm + anillo + labio + jet en la mayoría de la pantalla.
- `starfield()`: la rama de lente (2 `atan`/estrella) sólo si el píxel está a
  < 2.1R del agujero. Celda 46 → 54 px.
- `fbm` 4 → 3 octavas. Tic del shader 20 → 10 fps. Ticker de posiciones 2 → 1 fps.
- Se probó bajar la resolución del shader con `layer.textureSize` (0.62x): **no
  compensó** (el RTT+blit costaba más que lo ahorrado con el shader ya recortado).
  Revertido.

<details><summary>Cifras históricas (máquina cargada, antes del fix)</summary>

- línea base del shell: ~8-12 %
- con el sistema solar: ~15-19 %  → añadía ~5-8 % de un núcleo.
</details>

El `ShaderEffect` a pantalla completa (1920×1080) refrescándose a ~20 fps cuesta
más de lo esperado en esta máquina **multi-GPU** — probablemente el hilo de
render se bloquea esperando a la GPU (misma familia de problema que tumbaba a
`grim`). Con el shader OCULTO (`visible: false`) el resto (tics + capa fina)
ya costaba ~12-18 %.

**Qué probar (después del reinicio, con la máquina tranquila):**
1. **Medir en condiciones.** Cerrar spotify/otros agentes. Medir línea base (capa
   comentada en `shell.qml`) vs con capa, con el comando de §6.
2. Bajar el tic de `_t` a ~12-15 fps (`interval` de 65-80 ms en el `Timer` `id: clock`
   de `SolarSystem.qml`). El shader se ve más entrecortado pero la turbulencia
   es lenta, puede aguantar.
3. **Recortar el fragment shader** (`solarfield.frag`): menos octavas de fbm,
   menos capas por píxel, quitar el jet / estrellas lensadas si pesan.
4. Ver si `Sim.computeLayout` (Sim.js) es caro — bajar el `ticker` de 500 ms a
   1000 ms; las posiciones se mueven imperceptiblemente.
5. Si sigue igual → el `ShaderEffect` fullscreen no vale en esta GPU. Alternativa:
   dimensionar el shader SOLO a la caja del agujero (`bhBounds`) y los soles a
   Canvas otra vez (pero con caché offscreen para que no cuesten).
6. Comprobar `QSG_RENDER_LOOP` — el shell fuerza `threaded`. Probar `basic`.

### 3.2 El agujero negro del shader perdió detalle ✅ MEJORADO (2026-09-03, commit `4b23c35`)

Antes: un «chorro» salmón plano. Ahora el `solarfield.frag` (parte del agujero):
- **Bandeado concéntrico** del disco: dos frecuencias de aros (`rD·23` + `rD·61`)
  rotas por el fbm. Es lo que lo hace leer como disco de acreción y no mancha.
- **Gradiente de temperatura real**: labio interno blanco-caliente → ámbar
  (`m3primary`) → rojo profundo (`m3error` oscurecido), con las alfas del tramo
  medio/exterior subidas para que el rojo se vea.
- **Anillo de fotones** fino, alpha .95, casi blanco puro en el lado que se
  acerca (Doppler). Dibuja la silueta del horizonte (que aquí cae casi entero
  fuera de cuadro por la composición D — centro en `(1.02W, -0.04H)`).
- Halo lensado «Gargantua» más marcado, labio ISCO más intenso.

Captura de referencia: `docs/sistema-solar-v3-mockup/` (regenerar) o
`scratchpad/bh-v3.png` de la sesión.

**Si se quiere seguir puliendo** (menor prioridad): el horizonte negro se ve
poco porque la composición lo saca de cuadro; se podría acercar el centro a
`~(0.96W, 0.02H)` para que se vea el disco negro elíptico como en la variante D.
Es cambio de composición → decisión de Alberto. Pasada original de referencia:
`git show d0b5d44:.../SolarSystem.qml` (`_drawBlackHole`).

**Qué hacer si hace falta otra pasada:** al `solarfield.frag` SOLO en la parte del agujero.
Referencia de calidad: la versión Canvas (git `d0b5d44:configs/quickshell/caelestia/modules/background/solarsystem/SolarSystem.qml`,
función `_drawBlackHole`) y el harness. Capas de la spec §4.1: resplandor
exterior, halo lensado SOBRE el horizonte, horizonte negro puro, anillo de
fotones + Doppler, disco con gradiente de temperatura + beaming ~3× +
turbulencia + oclusión del sector de atrás, labio ISCO, arco frontal por delante
del horizonte, jet tenue. El `harness-blackhole.html` del fork tiene el cuerpo
GLSL para iterar — PERO el WebGL headless de chromium NO renderiza en esta
máquina (mismo fallo GPU); hay que iterar con `qs -p` + `grim`.

### 3.3 Modo Laura no probado en vivo (medio)

Solo se ha probado forzando `lauraActive: true` en el .qml. Falta activarlo de
verdad (hablarle a Laura) y ver: congelación + oscurecido + Laura latiendo con la
voz. El bus de eventos `$XDG_RUNTIME_DIR/laura-events.sock` es solo
servidor→cliente (no se puede inyectar); mirar `assistant/events.py`.

### 3.4 Fluidez del movimiento (medio)

Alberto ya se quejó de que el movimiento «va a tirones» y «recorre demasiado
espacio en poco tiempo». Con el shader el FONDO debería ir fluido; verificar. La
capa fina (satélites) va a 2 fps — si se nota, subir a ~10 fps o interpolar.
Períodos actuales en `Sim.js` (constante `D`): binario 220 s, agentes en curso
200 s, completados 360 s, dispositivos 260 s, cinturón 1400 s, giro del disco
150 s. Alberto quiere ~1°/frame — si algo se ve rápido, alargar su período.

### 3.5 Pendiente antiguo (baja / tandas posteriores)

- Zonas LED como cuerpos (D-5) — adaptador está, no se dibuja.
- Interacción: hover/clic/congelar-al-acercarse. La vista ya expone
  `contentBounds` para la región de input.
- Visualizador de música en tiempo real.
- Decidir si el wallpaper vuelve (D-1).

---

## 4. Gotchas de esta máquina (IMPORTANTE, ahorra horas)

1. **`grim` y el `Canvas`/`ShaderEffect` del shell MUEREN si el compositor pierde
   la asociación monitor↔GPU.** Pasa tras enchufar/quitar un monitor externo
   (eDP-2 se queda en `x=-3840`). Síntoma: `grim` cuelga, `onPaint` de Canvas no
   dispara, `qs -p` aislado sí pinta. **Arreglo: reiniciar el equipo o
   re-enchufar el monitor externo.** (Por eso Alberto reinicia ahora.)

2. **Quickshell cachea una compilación FALLIDA.** Tras un error de QML, sigue
   sirviendo el error viejo aunque arregles el código. Arreglo:
   ```bash
   caelestia shell -k 2>/dev/null
   pkill -9 -f quickshell; pkill -9 -x qs; pkill -9 -f "caelestia shell"
   sleep 2.5
   rm -rf ~/.cache/quickshell/qmlcache
   caelestia shell -d
   ```
   (Un `caelestia shell -k` a secas NO basta.)

3. **Hyprland usa una API Lua para `dispatch`.** `hyprctl dispatch workspace 8`
   FALLA. Para cambiar de workspace (p. ej. para capturar el escritorio vacío):
   ```bash
   hyprctl dispatch 'hl.dsp.focus({ workspace = 8 })'
   ```
   `hyprctl keyword monitor` también está deshabilitado por ese parser.

4. **`qsb`** está en `/usr/lib/qt6/bin/qsb` (paquete `qt6-shadertools`, ya
   instalado). Compilar: `qsb --qt6 -o X.frag.qsb X.frag`.

5. **`focus`** es propiedad `final` de `QQuickItem` → no se puede sombrear. Por
   eso la propiedad del modo Laura es `lauraFocus`.

6. **Medir CPU del shell** (inmune al ruido de muestreo):
   ```bash
   pid=$(pgrep -x qs | head -1); hz=$(getconf CLK_TCK)
   a=$(awk '{print $14+$15}' /proc/$pid/stat); sleep 15
   b=$(awk '{print $14+$15}' /proc/$pid/stat)
   python3 -c "print(round(($b-$a)/$hz/15*100,1), '% de un núcleo')"
   ```
   La línea base varía MUCHO según qué más corra en la máquina.

7. **Capturar el escritorio real limpio:**
   ```bash
   cur=$(hyprctl activeworkspace -j | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
   hyprctl dispatch 'hl.dsp.focus({ workspace = 8 })'; sleep 1
   grim -o eDP-2 /tmp/desktop.png
   hyprctl dispatch "hl.dsp.focus({ workspace = $cur })"
   ```

8. **Coordinación:** Gemini toca `vault/`; hay a veces otro agente de Claude en el
   repo. `git fetch` a menudo, commitear pronto (`git add -A` del otro puede
   barrer tu working tree). Reparto: Claude = `rgb/`, `configs/quickshell/`,
   `docs/`, etc.

9. **Arrancar el shell desde un agente: `qs -c caelestia -n -d` TIENE QUE IR
   SOLO en su propia llamada de shell**, con la salida al terminal (no a un
   fichero, no por una tubería), seguido sólo de `sleep 6; pgrep -xc qs`. Si se
   encadena tras `cd`/`cp`/`pkill` en el mismo comando, o se redirige/pipea su
   salida, el daemon arranca, carga la config («Configuration Loaded») y **muere
   al instante** (el grupo de procesos se limpia al volver el comando en
   primer plano). Patrón que funciona, en DOS llamadas:
   ```
   # llamada 1: limpiar
   pkill -9 -x qs; pkill -9 -f quickshell; sleep 2.5; rm -rf ~/.cache/quickshell/qmlcache
   # llamada 2, ella sola:
   qs -c caelestia -n -d 2>&1; sleep 6; pgrep -xc qs
   ```
   `caelestia shell -d` hace exactamente ese `qs ... -d` por dentro (ver
   `/usr/lib/python3.14/site-packages/caelestia/subcommands/shell.py`).

---

## 5. Ciclo de trabajo

1. Editar en el worktree `.worktrees/sistema-solar-v3` (rama `feat/sistema-solar-v3`).
2. `qmllint -I configs/quickshell/caelestia <archivo>` para pillar errores rápido.
3. Desplegar: `cp` de los archivos a `~/.config/quickshell/caelestia/` (verificar
   gemelos con `diff -rq`).
4. Restart limpio (gotcha #2).
5. Verificar `Configuration Loaded` sin warnings, 1 instancia (`pgrep -xc qs`).
6. Capturar (gotcha #7), medir CPU (gotcha #6).
7. Iterar los visuales del shader con `qs -p` + `grim` (el harness WebGL no
   funciona en esta máquina).
8. Commit pronto, mensajes en español, `Co-Authored-By` + `Claude-Session`.

## 6. Al terminar

- Bitácora: una línea arriba de la sección «📓 Bitácora de sesiones» de
  `vault/🎯 Hoy.md`.
- Tabla de versiones de `docs/sistema-solar-binario.md`.
- Decisiones nuevas → `docs/sistema-solar-v3-DISENO.md` §8 + `vault/Rice
  LinuxRicing/01 - Linux/Widgets/Sistema Solar — decisiones v3.md` (los dos).
- Marcar `docs/sistema-solar-v3-DISENO.md` §11.
