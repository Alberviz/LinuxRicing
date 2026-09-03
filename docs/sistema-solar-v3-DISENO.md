# Sistema Solar v3 — guía de diseño e implementación

> **Para el agente que implemente esto.** Alberto no va a estar durante la
> implementación. Toma las decisiones que hagan falta y anótalas (sección
> «Decisiones» de este documento + `vault/`). No tengas miedo de romper cosas:
> estás en la rama `feat/sistema-solar-v3`, aislada. Nunca toques `main`.
>
> **Objetivo de esta tanda: dejar EL DISEÑO hecho.** La interacción (hover, clic,
> congelar) y los comportamientos reactivos (que Laura cambie al estar activa,
> etc.) son de una tanda posterior. Ahora: la imagen, a pantalla completa, con
> calidad y detalle reales.

---

## 1. Estado y contexto

- **Rama:** `feat/sistema-solar-v3`, sacada de `refactor/background-modularize`
  (que trae el `Background.qml` modularizado + el fix de CPU del
  `FrameAnimation` de `DesktopCircularMedia`). Worktree en
  `.worktrees/sistema-solar-v3`. Ni esta rama ni su base están en `main`.
- **Archivos ya presentes** (traídos de la v1.5, se van a reescribir/ajustar):
  - `configs/quickshell/caelestia/modules/background/solarsystem/SolarSystem.qml` — la vista (Canvas)
  - `configs/quickshell/caelestia/modules/background/solarsystem/Sim.js` — motor de posiciones puro
  - `configs/quickshell/caelestia/modules/background/solarsystem/SolarSystemLayer.qml` — la capa layershell
  - `configs/quickshell/caelestia/services/SolarSystemModel.qml` — el modelo + adaptadores (batería, agentes, tareas, LED)
- **Plan histórico por versiones:** `docs/sistema-solar-binario.md` (contexto,
  principios, adaptadores). Este documento es la spec concreta de la v3.
- **Maqueta visual (norte):** `docs/sistema-solar-v3-mockup/` en el repo —
  `variantes.html` (interactivo; ábrelo con un navegador o pásale `?p=D`) y
  `variante-{A,B,C,D}.png` (capturas). **La D es la referencia de composición**;
  la calidad de render hay que **superarla**, no igualarla. (También hay un
  artifact `0951108d`, pero una sesión nueva no puede leerlo — usa los archivos
  del repo.)
- **Maqueta de reserva (visión B):** guardada en
  `vault/Rice LinuxRicing/01 - Linux/Widgets/Sistema Solar — visión B (reserva).md`.
  No se implementa ahora; se conserva por si más adelante se quiere el centro
  despejado con Laura como segundo sol de peso.

### Principios que no se tocan (de `docs/sistema-solar-binario.md`)

1. **Glanceable.** En reposo cada cuerpo ya dice su estado por color, brillo y tamaño.
2. **Calmo por defecto.** Movimiento lento. La atención se gana con brillo, no con velocidad.
3. **Cero telemetría inventada.** Cuerpo sin señal real → se omite o es decorativo y documentado. Nunca un % de batería falso.
4. **Color del wallpaper.** Cada cuerpo referencia un rol de `Colours.palette.m3*`. Nunca un hex fijo. Cambiar de fondo re-colorea todo (aunque el fondo esté oculto ahora, ver Decisión D-1).

---

## 2. La decisión de diseño (variante D)

El escritorio queda **vacío salvo el reloj**, a pantalla completa, sobre **fondo
negro** (wallpaper apagado por ahora). Dos anclas visuales en el mismo cielo:

### 2.1 El agujero negro «música» — esquina superior derecha

- **Masivo y saliéndose de cuadro.** Centro alrededor de `(x ≈ 1.02·W, y ≈ -0.04·H)`
  → se ve ~65-70 %. Horizonte de sucesos con radio `R ≈ 0.22·H` (≈ 240 px en 1080p).
- **El objeto más pesado del sistema** y el más dominante visualmente. **No se
  mueve** de su sitio: rota sobre sí mismo lentísimo (spin, para el beaming del
  disco), no traslada.
- **Disco de acreción en diagonal** cruzando la pantalla hacia abajo-izquierda
  (eje mayor del disco a ≈ -28°, casi de canto: `ry/rx ≈ 0.14`). Es la "raya"
  luminosa que da dinamismo a la composición.
- Detalle de render: sección 4.1. **No un halo simple.**

### 2.2 El binario «Laura ↔ Configuración» — lejos, centro-izquierda

Dos soles orbitando un baricentro común, **despacio**. Situados alrededor de
`(x ≈ 0.30·W, y ≈ 0.50·H)`. Dejar libres:
- la **franja inferior ~200 px** (overlay de voz de Laura, otra capa encima),
- la **esquina inferior izquierda** (el reloj de Caelestia).

- **Laura** — **primario** del binario. Algo más grande (`r ≈ 0.045·H`). Rol de
  color: `m3secondary` (o `m3tertiary` si contrasta mejor con el disco cálido —
  decidir con capturas, ver Decisión D-3). Detalle: fotosfera granulada,
  cromosfera en el limbo, prominencias/fulguraciones lentas, corona. Sección 4.2.
  - **Órbita a su alrededor: los AGENTES.** Un satélite por sesión de
    Claude/Antigravity (`Agents.runningAgents` + `completedAgents`).
    - 0 agentes → 0 satélites.
    - En curso → satélite brillante con anillo de actividad, órbita más rápida (dentro de lo lento).
    - Completado → satélite tenue, órbita más lenta y más abierta.
    - Cuantos más, más satélites (a distintos radios/planos).
- **Configuración** — **secundario**. Algo más pequeño (`r ≈ 0.035·H`). Rol
  `m3primary`. Mismo nivel de detalle de render que Laura pero **más calmo** (sin
  fulguraciones, prominencias mínimas). Sin señal propia (tamaño/brillo fijos);
  es ancla y futuro objetivo de clic.
  - **Órbita a su alrededor: los DISPOSITIVOS conectados.** Auriculares V9 Pro,
    ratón K7 Ultra, teclado Akko, vía `SolarSystemModel` (`mchose-battery --json`).
    - Solo aparece el que está **conectado**. Desconectado → no se dibuja.
    - Tamaño y brillo del planeta = **% de batería real**.
    - `< 20 %` → aro rojo pulsante (rol `m3error`).

### 2.3 El binario está ANCLADO en su sitio (Decisión D-2, revisada)

El baricentro del binario Laura-Config está **fijo en coordenadas de pantalla**
(centro-izquierda). **No deriva** alrededor del agujero. Los dos soles se orbitan
entre sí despacio, pero el baricentro no se traslada.

Motivo: el sistema es informativo y (más adelante) interactivo — se usa para leer
estado y clicar cuerpos. Si el binario entero vagara por la pantalla, cada blanco
de información estaría en un sitio distinto cada vez que miras. **Los blancos
tienen que estar donde el usuario los espera.** El "un solo sistema" lo dan la
composición, el campo de estrellas compartido y la paleta compartida, no una
órbita común.

Principio general que sale de aquí: **posiciones estables y predecibles**. Las
órbitas locales (soles entre sí, satélites alrededor de su sol) son lentas y
acotadas; nada recorre distancias grandes por la pantalla.

### 2.4 Cinturón de tareas (Decisión D-4: se incluye)

Cinturón circumbinario **alrededor del par Laura-Config** (no alrededor del
agujero). Partículas dispersas, muy tenue. Densidad = nº de tareas `pendiente` del
backlog (`SolarSystemModel` ya lo cuenta). Prioridad visual baja: es textura, no
protagonista.

### 2.5 El reloj

El `DesktopClock` de Caelestia se queda **exactamente como está** (su propio
`Loader` en `Background.qml`, su config de posición). No se toca.

### 2.6 Fondo

Negro puro (`#000000` o `#050505`). Campo de estrellas real (puntos estáticos),
con las cercanas al agujero **estiradas en arcos** por la lente (sección 4.1).

---

## 3. Movimiento — LENTO

Alberto fue explícito: *«tiene que ser un sistema lento, es interactivo y lo vamos
a usar para que nos dé información»*. Referencia de períodos (tiempo de pantalla):

| Elemento | Período orbital / de animación |
|----------|-------------------------------|
| Binario Laura ↔ Config (uno alrededor del otro, baricentro FIJO) | **~90-120 s** |
| Agentes alrededor de Laura (en curso) | **~40-60 s** |
| Agentes completados | **~120 s** |
| Dispositivos alrededor de Config | **~70-100 s** |
| Cinturón de tareas | **~600 s** |
| Rotación del disco de acreción / turbulencia | ciclo visible **~30-60 s** |
| Rotación del agujero (spin, beaming) | **~20-40 s** |
| Prominencias de los soles | **~15-25 s** por ciclo |

El tick de repintado: **2-4 fps en reposo** (`Timer`, no `FrameAnimation`). Solo
sube a ~30 fps si algún día se anima algo rápido (no ahora). Ver sección 6.

---

## 4. Especificación de render (CALIDAD)

Alberto: *«quiero calidad y detalle, no quiero el agujero negro hecho sencillo ni
los soles ni los astros»*. Canvas 2D (FBO). Todo color sale de
`Colours.palette.m3*` inyectada como propiedad; los "blancos calientes" se
derivan aclarando el rol (`Qt.lighter` / mezcla hacia blanco), no `#fff` a pelo.

### 4.1 Agujero negro — capas (de atrás a delante)

1. **Resplandor exterior.** Gradiente radial amplio (`R·0.8 → R·4.6`), del rol
   primario aclarado al transparente. Nunca `shadowBlur`.
2. **Borde lejano del disco, lente sobre el horizonte** (el "halo Gargantua"):
   arco de elipse **por encima** del horizonte, desplazado hacia arriba ~`0.55·ry`,
   sólo el sector superior (`π·1.06` a `π·1.94`). Varias bandas finas con gradiente
   de temperatura (blanco-caliente → ámbar). Recortar (`clip`) a la mitad superior
   para que no invada el disco frontal.
3. **Horizonte de sucesos.** Disco negro puro (rol de fondo llevado casi a negro,
   `Qt.darker(m3surface, 3)`). **Nunca `#04040a` fijo** (bug de la v1).
4. **Anillo de fotones.** Círculo fino brillante a `R·1.03` (rol aclarado casi a
   blanco), + un halo más suave a `R·1.08`. Más brillante en el lado que se
   acerca (Doppler): modular alpha con `cos(θ − beam)`.
5. **El disco de acreción.** ~50-60 bandas de elipse concéntricas de
   `R·1.32` a `R·3.7`, `ry = rx·0.14` (canto), con:
   - **Gradiente de temperatura** por radio: interior blanco-caliente → medio
     ámbar (`m3primary`) → exterior rojo profundo (`m3error` oscurecido).
   - **Doppler beaming**: recorrer cada elipse por arcos (~48 segmentos) y variar
     el alpha con `pow(0.5 + 0.5·cos(θ − beam), 2.4)` → un lado ~3× más brillante.
   - **Oclusión del lado de atrás**: donde `sin(θ) < 0` (detrás del horizonte),
     bajar alpha salvo cerca de los lados.
   - **Turbulencia**: `alpha *= 0.85 + 0.15·sin(θ·7 + f·30 + t·1.5)` (banding sutil que fluye).
6. **Labio interior caliente (ISCO).** Trazo grueso de elipse justo fuera del
   anillo de fotones, con gradiente lineal que lo hace más brillante en el lado beamed.
7. **Arco frontal del disco interior** re-dibujado **sobre** el borde inferior del
   horizonte (para que el disco pase por delante abajo y por detrás arriba).
8. **Jet relativista** (opcional, muy tenue): haz perpendicular al plano del
   disco, gradiente que se desvanece, alpha ≤ 0.15.
9. **Estrellas lensadas**: las del campo de estrellas a `0.7·R < d < 3·R` del
   centro se dibujan como **arcos** cortos centrados en el agujero, no como puntos.

Con música sonando (`SolarSystemModel.music`, 0..1): subir la amplitud de la
turbulencia y el brillo del labio ISCO proporcionalmente. Sin música: disco
tranquilo, rotación lenta.

### 4.2 Soles (Laura, Configuración) — capas

1. **Corona.** Gradiente radial `r·0.3 → r·3.6` del rol al transparente. Latido
   muy leve (`1 + 0.04·sin`).
2. **Fotosfera.** Disco con gradiente radial descentrado (luz arriba-izquierda):
   blanco-caliente en el núcleo → rol → rol oscurecido en el limbo.
3. **Granulación.** Textura sutil: ~40-60 celdas Voronoi/ruido de bajo contraste
   sobre la fotosfera, regeneradas lentamente (cada pocos segundos) o cacheadas y
   rotadas. No debe "hervir" rápido.
4. **Cromosfera / limbo.** Aro fino más brillante en el borde, con ligera
   irregularidad.
5. **Prominencias / fulguraciones** (solo Laura; Config casi sin): 2-3 arcos
   finos que salen del limbo y vuelven, apareciendo y desvaneciéndose en
   ~15-25 s. Rol aclarado.
6. Laura primario = mayor y con prominencias; Config secundario = menor, liso, calmo.

### 4.3 Planetas / satélites (agentes, dispositivos) — capas

1. **Lado iluminado.** Gradiente radial descentrado: el punto de luz mira **hacia
   su ancla** (Laura o Config), no siempre arriba-izquierda. Terminador suave.
2. **Atmósfera / limbo.** Aro fino translúcido del color del cuerpo, más visible
   en el lado iluminado (dispersión).
3. **Textura** muy sutil (bandas o moteado de bajo contraste) para que no sea un
   círculo plano.
4. **Anillo de actividad** (agente en curso): elipse fina inclinada + halo suave
   que late despacio.
5. **Aro de alerta** (batería < 20 %): círculo rojo (`m3error`) pulsante alrededor.
6. **Estela** (opcional, tenue): un rastro corto detrás del planeta en su órbita.

### 4.4 Órbitas

Trazas de elipse **muy tenues** (alpha ≈ 0.04-0.07). En reposo casi no se ven; se
harán más visibles con el hover en la tanda de interacción (no ahora).

---

## 5. Vaciar el escritorio — cambios en `Background.qml`

En `configs/quickshell/caelestia/modules/background/Background.qml`:

- **Wallpaper:** el `Loader` de `Wallpaper {}` → `active: false` (o gateado por
  `SolarSystemModel.showWallpaper`, por defecto `false`). El `win.color` de la
  ventana del fondo → negro. **No borrar `Wallpaper.qml`.**
- **Quitar del árbol** (comentar los `Loader`, no borrar los `.qml`):
  `DesktopPeripherals`, `DesktopWidgetDeck` (deck: tareas/clima/hardware/foco),
  `DesktopLedStrip`, `DesktopCircularMedia`.
- **Mantener:** el `Loader` del `DesktopClock` tal cual (posición, estados).
- **Añadir:** `SolarSystemLayer {}` — o instanciar la vista dentro del propio
  `Background` si encaja mejor con el layout de capas. Decidir y anotar.
- Los archivos `Desktop*` / `Deck*` / `DeviceItem` / `TaskRow` se quedan en disco
  para poder reactivarlos o reaprovechar patrones en la tanda de interacción.

`install.sh` ya despliega toda la carpeta `modules/background/`, así que la
carpeta `solarsystem/` viaja sola.

---

## 6. Rendimiento — REQUISITOS DUROS

Alberto lo ha pedido dos veces. El `CLAUDE.md` tiene las reglas; aquí van
concretas para la v3:

1. **Nunca dos instancias del shell.** Antes de cada arranque:
   ```bash
   caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true
   sleep 1
   caelestia shell -d
   ```
   Después, **verificar**: `pgrep -cf "qs -c caelestia"` debe dar **1** proceso
   `qs` real (ojo, `pgrep` también matchea el propio comando; comprobar con
   `pgrep -af`). Si hay dos, matar y reintentar.
2. **Restart completo, nunca hot-reload.** El hot-reload de Quickshell fuga las
   animaciones de la generación anterior (`FrameAnimation`/`Canvas` zombis a
   60 fps). Cada cambio de archivo → `caelestia shell -k` + arranque limpio.
   Nunca editar y seguir mirando el reload.
3. **Gatear el `running:` de toda animación.** Prohibido
   `FrameAnimation { running: true }`. El tick de la vista es un **`Timer`** con
   `interval` regulable, gateado a `visible && !paused && hayAlgoQueAnimar`. En
   reposo (sin música, sin agentes en curso) el `Timer` **para del todo** y solo
   se repinta una vez al cambiar los datos.
4. **`interval` de reposo: 250-500 ms (2-4 fps).** Solo bajar a 33 ms si de
   verdad se anima algo rápido (no en esta tanda).
5. **Nada de `shadowBlur` a ritmo de animación** — es un gaussian por-píxel en el
   hilo GUI. Resplandores = gradiente radial. Algo más pesado = `ShaderEffect` / `Shape` en GPU.
6. **Cachear las capas estáticas.** El resplandor exterior del agujero, el campo
   de estrellas (con arcos de lente), la granulación base de los soles: renderizar
   **una vez** a un `Canvas` / imagen offscreen y solo regenerar al cambiar tamaño
   o paleta. Cada frame solo redibuja: disco (arcos), prominencias, posiciones de
   cuerpos, anillos de actividad.
7. **Dimensionar el `Canvas` a la caja del contenido, no a toda la pantalla.** La
   capa layershell ocupa la pantalla (para posicionar), pero el `Canvas` interior
   se ajusta al bounding-box del sistema (agujero incluido) + margen. Pintar
   1920×1080 de FBO cada tick cuando el contenido está en una caja menor es tirar
   fill.
8. **Presupuesto:** shell en reposo ≤ ~5 % de un núcleo (medido: sin el sistema
   solar está a ~5 % tras el fix de `DesktopCircularMedia`). La capa del sistema
   solar debe añadir **poco** en reposo. Medir con:
   ```bash
   pid=$(pgrep -f "qs -c caelestia" | head -1); top -b -n 3 -d 3 -p $pid | grep " $pid "
   ```
9. **Si Canvas 2D no llega al listón de calidad sin pasarse de CPU:** parar,
   anotarlo en «Decisiones», y montar el disco del agujero (y quizá los soles)
   como `ShaderEffect` GLSL en GPU. Es la vía correcta para lensing y turbulencia
   de verdad; el plan ya la contempla para v5. No forzar 2D hasta que humee.
10. **Pausa con GameMode.** `SolarSystemLayer` ya ata `paused: GameMode.enabled`.
    Mantener. Añadir pausa cuando haya una ventana a pantalla completa encima si
    es barato de detectar (`Hypr.activeToplevel`), si no, anotarlo como pendiente.

---

## 7. Datos / adaptadores (`SolarSystemModel.qml`)

Ya existen de la v1.5. Reconfigurar las **anclas**:

| Señal | Fuente (ya implementada) | Ancla en v3 |
|-------|--------------------------|-------------|
| `music` (0..1) | `Audio.cava` + `Players` | agujero negro (turbulencia/brillo del disco) |
| `musicPlaying` | `Players.list.some(isPlaying)` | gatea el ritmo del disco |
| agentes `runningAgents`/`completedAgents` | `Agents.qml` | **satélites de Laura** |
| `batt:<headset\|mouse\|keyboard>` + `battLow:*` | `rgb/mchose-battery --json` (30 s) | **planetas de Configuración**, solo si conectado |
| `tasks` (0..1) | `grep estado: pendiente` en `vault/Backlog` | cinturón circumbinario |
| `led:<magichome\|akko\|base>` | `RgbConfig.devices` | **por ahora fuera** — las zonas LED vuelven en una tanda posterior (Alberto: «más adelante veremos más cosas»). Dejar el adaptador, no dibujar los cuerpos. |

`anyActivity` (gate del `Timer`) = `musicPlaying || hayAgentesEnCurso`. Nota: con
un agente en curso el sistema anima despacio (2-4 fps), no rápido.

El agujero, Laura y Config son **anclas** en la config del modelo; agentes y
dispositivos son **cuerpos dinámicos** (`_deviceBodies()` ya lo hace para los
periféricos; hacer lo análogo para agentes → ancla `laura`).

Config de disposición sigue siendo un JSON editable en
`~/.config/caelestia/solarsystem.json` (mismo formato); actualizar el
`defaultConfig` de `SolarSystemModel.qml`.

---

## 8. Decisiones tomadas (por el agente, sin Alberto)

| # | Decisión | Motivo |
|---|----------|--------|
| **D-1** | Wallpaper **apagado** por ahora (fondo negro), tras flag `showWallpaper: false`. Restaurable. | Alberto lo pidió como referencia de trabajo. El plan decía mantenerlo; se revisará al terminar el diseño. La paleta sigue saliendo de `Colours.palette` para cuando vuelva. |
| **D-2** | El binario Laura-Config está **anclado** (baricentro fijo en pantalla). No deriva alrededor del agujero. | Alberto lo señaló: es un sistema para *usar*; los blancos de información y de clic tienen que estar donde el usuario los espera. Principio: posiciones estables y predecibles. |
| **D-3** | Laura = **primario** del binario (mayor, con prominencias). Config = secundario (menor, calmo). Color de Laura a decidir con capturas entre `m3secondary` y `m3tertiary`. | Laura es el personaje principal (voz, agentes). |
| **D-4** | El **cinturón de tareas se incluye** ya, circumbinario alrededor del par, muy tenue. | Es dato real y estaba en todas las versiones; es barato. |
| **D-5** | Las **zonas LED NO se dibujan** en esta tanda (adaptador se queda). | Alberto: «más adelante veremos más cosas». Reduce ruido visual mientras se cierra la composición. |
| **D-6** | Componentes `Desktop*`/`Deck*` se **comentan, no se borran**. | Reversible; patrones reutilizables para la tanda de interacción. |
| **D-7** | Interacción (hover/clic/congelar) y reactividad (Laura activa, etc.) **fuera de alcance**. Diseñar la vista para que la entrada se pueda añadir luego sin reestructurar (exponer bounding-box, ids de cuerpo). | Alberto: «de momento deja el diseño hecho». |
| **D-8** | `SolarSystemLayer` se instancia como capa propia en `shell.qml` (no dentro de `Background`), y es **EL fondo**: `WlrLayer.Background`, opaco negro. `Background.qml` (sólo el reloj) baja a `WlrLayer.Bottom` transparente por encima. | La opción de la spec §5. Capa separada = menos acoplamiento; el reloj flota limpio sobre el sistema solar; el negro puro queda garantizado por la ventana, no por el compositor. |
| **D-9** | Laura = `Colours.palette.m3tertiaryFixedDim` (oro apagado), no `m3tertiary`. Config = `m3primary`. | En el scheme *tonalspot* cálido actual, `m3tertiary` es casi blanco: no contrasta ni con el disco cálido ni con el núcleo blanco-caliente del agujero. `m3tertiaryFixedDim` da un oro que sí diferencia a Laura y colorea sus agentes frente a los dispositivos (peach) de Config. Cierra la duda abierta en D-3. |
| **D-10** | El baricentro del binario cae en `y ≈ 0.47·h` (no `0.50`) y la órbita mutua tiene el eje mayor casi horizontal (`ecc 0.45`, `tilt -0.15`) para acotar el vaivén vertical. | Con `0.50·h` y órbita poco excéntrica, en su punto más bajo el binario invadía la franja inferior de ~200 px del overlay de Laura. |
| **D-11** | La vista se parte en **3 Canvas** (estático / agujero negro / binario), cada uno a su caja (`bhBounds`, `binBounds`) y su ritmo: estático 1 vez; agujero 1 de cada 3 tics; binario cada tic. `fastRate` (música) = ~7 fps, no ~30. | Con el agujero repintándose entero cada tic (era lo más caro: relleno de anillo elíptico + gradiente + bandas + beaming + clips), el shell costaba ~22 % CPU con un agente en curso. Partido → +~4 % sobre la línea base. El visualizador en tiempo real es de una tanda posterior (§3, §6.4). |

Si tomas más decisiones, **añádelas a esta tabla** y a la nota del vault.

---

## 9. Flujo de trabajo del agente

1. **Iterar los visuales rápido en un harness HTML** (Canvas 2D ≈ igual API que
   QML Canvas). Capturas con:
   ```bash
   chromium --headless --no-sandbox --disable-gpu --hide-scrollbars \
     --window-size=1280,760 --virtual-time-budget=2500 \
     --screenshot=/tmp/shot.png "file:///ruta/harness.html"
   ```
   Leer el PNG. Ajustar. Repetir hasta que la imagen esté.
2. **Portar a QML** (`SolarSystem.qml` + `Sim.js`). El `2d` context de QML Canvas
   es casi idéntico; `Sim.js` es JS puro y se reusa.
3. **Desplegar y verificar en el shell real:**
   - Sincronizar a `~/.config/quickshell/caelestia/` (verificar gemelos con `diff -q`).
   - Restart limpio (sección 6.1). Confirmar `INFO: Configuration Loaded` sin errores.
   - Captura del escritorio real: crear un **workspace vacío** de Hyprland, cambiar
     a él, `grim`, volver:
     ```bash
     ws=$(hyprctl activeworkspace -j | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
     hyprctl dispatch workspace empty; sleep 0.6
     grim /tmp/desktop.png
     hyprctl dispatch workspace $ws
     ```
   - Medir CPU (sección 6.8).
4. **Commit pronto y a menudo** (otro agente puede hacer `git add -A` y barrer tu
   working tree). Mensajes en español, `Co-Authored-By` + `Claude-Session`.
5. **No parar hasta que el diseño esté** (instrucción de Alberto). "Está" =
   sección 11.
6. Al terminar: bitácora en `vault/🎯 Hoy.md`, actualizar la tabla de versiones de
   `docs/sistema-solar-binario.md`, y dejar un resumen de estado.

---

## 10. Fuera de alcance (para tandas posteriores)

- Interacción: región de input, `HoverHandler`, panel de detalle, clic→acción,
  congelar al acercarse. (Plan en `docs/sistema-solar-binario.md` §v2.)
- Reactividad: Laura se aviva/acelera al hablarle o al abrir un terminal; modo
  conjunción; cometa de build.
- Zonas LED como cuerpos (D-5).
- Clima, foco/pomodoro, hardware como cuerpos.
- Sub-lunas = subagentes; eclipses/conjunciones por git.
- Decidir si el wallpaper vuelve (D-1).

---

## 11. Criterio de «hecho»

Estado 2026-09-03 (sesión de implementación): **diseño hecho, portado a QML y
verificado en el escritorio real** (Alberto reenchufó el equipo y se recuperó el
compositor — ver §13). Marcas:

- [x] Escritorio a pantalla completa: solo reloj + sistema solar sobre fondo negro. Sin widgets. *(código: `Background.qml` wallpaper apagado tras flag `showWallpaper`, `Desktop*` loaders comentados, `SolarSystemLayer` opaco negro en `WlrLayer.Background`.)*
- [x] Agujero negro en la esquina superior derecha, masivo, con **todas** las capas de la sección 4.1. No parece un halo. *(harness `v3-harness-activo.png`; disco relleno con gradiente de temperatura + bandeado + beaming + halo lensado + jet + estrellas en arcos.)*
- [x] Binario Laura-Config, dos soles detallados (sección 4.2), orbitándose despacio. Centro-izquierda, anclado (D-2/D-10).
- [x] Agentes reales orbitando Laura (0 si no hay). Dispositivos reales conectados orbitando Config. *(adaptadores en `SolarSystemModel.qml`; agente en curso = anillo + órbita más cerrada; dispositivo = tamaño/brillo por batería, aro rojo < 20 %.)*
- [x] Cinturón de tareas circumbinario, tenue, densidad = backlog.
- [x] Todo se mueve **lento** (sección 3). *(períodos de la tabla §3 en `Sim.js`.)*
- [x] Colores 100 % de `Colours.palette.m3*`. Cero hex fijos. *(paleta inyectada como propiedad; `_a/_lit/_dk/_mix` derivan de los roles; `#000000` del fondo negro es el único literal y es negro puro, no un rol de color.)*
- [x] Rendimiento. Una sola instancia (`pgrep -xc qs` = 1). Sin `FrameAnimation` incondicionales (tic por `Timer` gateado a `anyActivity`). **Tres** Canvas: estático (fondo/estrellas/resplandor, se pinta 1 vez), agujero negro (repinta 1 de cada 3 tics), binario; cada uno dimensionado a SU caja, no a 1920×1080. `onValuesChanged/onConfigChanged` coalescidos (Timer 350 ms). Coste medido **sobre la línea base del shell**: reposo **+~0.4 %**, agente en curso (~2 fps) **+~4 %**, música (~7 fps) **+~5 %**. *(La línea base del shell en el momento de medir estaba en ~8 % por otros agentes corriendo en la máquina; con el equipo tranquilo la base es ~2.5 %.)*
- [x] `INFO: Configuration Loaded` sin errores ni warnings nuevos de QML.
- [x] **Capturas del resultado real** — `docs/sistema-solar-v3-mockup/real-escritorio.png` (más las del harness).
- [x] Decisiones nuevas anotadas (sección 8: D-8, D-9, D-10 + vault).
- [x] Bitácora + tabla de versiones actualizadas.

---

## 13. Nota: el bloqueo de verificación (resuelto)

Durante casi toda la sesión NO se pudo comprobar el dibujo en el escritorio real.
El compositor había perdido la asociación monitor↔GPU tras enchufar/quitar un
monitor externo (eDP-2 en `x=-3840`, `gsr`: «failed to find the gpu ... no
/dev/dri/cardX»): `grim` colgaba **y** el `onPaint` de *cualquier* `Canvas` del
shell no disparaba (comprobado también con `DesktopCircularMedia`; un `qs -p`
aislado sí pintaba → el código quedó descartado como causa).

**Alberto reenchufó el equipo y se recuperó.** Con eso: `grim` funciona, el
sistema solar renderiza (idéntico al harness) y se pudo perfilar la CPU — de ahí
salió el refactor a 3 Canvas (ver §11, punto de rendimiento).

Si en el futuro se ve el mismo síntoma (capturas cuelgan / Canvas no pinta con el
shell «normal» funcionando), la causa es el estado de monitores del compositor,
no el código: reenchufar el externo o resetear los monitores de Hyprland.

---

## 12. Prompt para la sesión limpia

Ver `docs/sistema-solar-v3-PROMPT.md`.
