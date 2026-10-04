---
tags: [rice, ui, sistema-solar, decisiones]
estado: en-curso
actualizado: 2026-09-03
---

# 🪐 Sistema Solar v3 — registro de decisiones

Decisiones de diseño de la v3 (escritorio a pantalla completa). Alberto no está
durante la implementación; los agentes deciden y anotan aquí. Espejo de la tabla
§8 de `docs/sistema-solar-v3-DISENO.md` — **si cambias una, cámbiala en los dos
sitios.**

## Cerradas con Alberto

- **Variante D.** Agujero negro «música» masivo y detallado en la **esquina
  superior derecha**, saliéndose ~30 % de cuadro, disco de acreción en diagonal
  cruzando la pantalla. Descartadas A (centro), B (guardada como reserva), C
  (disco de fondo).
- **Binario Laura ↔ Configuración**, lejos del agujero (centro-izquierda). Dos
  soles: **Laura primario**, **Configuración secundario**.
- **Agentes** orbitan Laura (0 si no hay; más = más satélites; en curso más
  vivos). **Dispositivos conectados** orbitan Configuración (desconectado → no
  aparece).
- **Escritorio vacío salvo el reloj.** Wallpaper fuera → fondo negro (referencia
  de trabajo).
- **Movimiento lento.** Es un sistema informativo e (a futuro) interactivo.
- **Prioridad: el diseño.** Interacción y reactividad (Laura activa, etc.), después.
- **El binario NO deriva alrededor del agujero.** Alberto: seguir la física
  estaría bien pero no tiene sentido para la utilidad — los blancos de
  información/clic tienen que estar donde el usuario los espera. Baricentro del
  binario **fijo en pantalla**. Principio: posiciones estables y predecibles.
- **El cinturón de tareas se incluye ya** (circumbinario, tenue, densidad = backlog).

## Tomadas por el agente (revisar si algo chirría)

- **D-1** · Wallpaper apagado tras flag `showWallpaper: false`, restaurable. La
  paleta sigue saliendo de `Colours.palette` para cuando vuelva. *(El plan
  original decía mantener el wallpaper; se revisa al terminar el diseño.)*
- **D-3 → cerrada por D-9** · (Era: color de Laura a decidir entre `m3secondary`
  y `m3tertiary`.)
- **D-5** · Las **zonas LED** (MagicHome, tira Akko, anillo base K7) **no se
  dibujan** en esta tanda; el adaptador se queda. Vuelven «más adelante».
- **D-6** · Componentes `Desktop*`/`Deck*` se **comentan, no se borran**
  (reversibles; patrones reutilizables para la interacción).
- **D-7** · Interacción y reactividad fuera de alcance; la vista se diseña para
  poder añadir entrada luego sin reestructurar. Laura no lleva `dimSignal`.
- **D-8** · `SolarSystemLayer` se instancia como capa propia en `shell.qml` y es
  **EL fondo**: `WlrLayer.Background`, opaco negro. `Background.qml` (sólo el
  reloj) baja a `WlrLayer.Bottom` transparente por encima.
- **D-9** · **Laura = `m3tertiaryFixedDim`** (oro apagado), Config = `m3primary`.
  En el scheme *tonalspot* cálido, `m3tertiary` es casi blanco y no contrasta con
  el disco ni con el núcleo blanco-caliente del agujero. El oro además distingue
  a los agentes de Laura de los dispositivos (peach) de Config. Cierra D-3.
- **D-10** · Baricentro del binario en `y ≈ 0.47·h` (no `0.50`) y órbita mutua de
  eje mayor casi horizontal (`ecc 0.45`, `tilt -0.15`), para que en su punto más
  bajo el binario no invada la franja inferior de ~200 px del overlay de Laura.
- **D-11** · La vista se parte en **3 Canvas** (estático / agujero negro /
  binario), cada uno dimensionado a SU caja y con su propio ritmo: el estático se
  pinta 1 vez; el del agujero, 1 de cada 3 tics (giro de período ~30 s); el del
  binario, cada tic. `fastRate` (música) baja de ~30 fps a ~7 fps — el
  visualizador en tiempo real es de una tanda posterior (spec §3/§6.4). Motivo:
  con el agujero repintándose entero cada tic el shell costaba ~22 % CPU con un
  agente en curso; partido baja a +~4 % sobre la línea base.
- **D-12** · **Modo Laura activa** (revoca la exclusión de D-7 para este caso).
  Al activarse Laura, el sistema **se congela**, todo **se oscurece** a ~18 % y el
  sol de Laura **brilla latiendo con la voz** (`Laura.amplitude`). Transición de
  380 ms. `SolarSystemLayer` importa el singleton `Laura` y pasa
  `lauraActive`/`lauraAmplitude`; `SolarSystem` deriva `lauraFocus` (no `focus` —
  colisiona con el `focus` final de `QQuickItem`) y `_dimK`. Alberto: «cuando
  llamen a Laura, todo se para y se oscurece y Laura brilla con fuerza».
- **D-13** · **El fondo entero pasa a un shader GLSL en GPU** (`SolarField`).
  `SolarSystem.qml` queda: Sim.js a ~2 fps (posiciones) + capa fina en Canvas
  (cinturón, órbitas, satélites) + modo Laura. El shader (agujero + 2 soles +
  estrellas + lente) recibe `_t`, `music`, `lauraFocus`, `lauraAmplitude`,
  `layout` y la paleta. Motivo: Canvas 2D no llega a §4.1 sin pasarse de CPU
  (§6.9); y como el modo Laura congela/oscurece todo, la GPU queda libre para la
  inferencia de Laura justo cuando hace falta.

## Estado de implementación (2026-09-03) — EN CURSO, traspaso a sesión limpia

**Traspaso completo: `docs/sistema-solar-v3-ESTADO-Y-SIGUIENTE.md`.**

1. **Canvas 2D** (variante D, agujero + soles + estrellas + capa fina): hecho,
   portado a QML, **verificado en el escritorio real** tras el reenchufe del
   monitor (`real-escritorio.png`). Coste ~+4 % con un agente. Commits hasta `86fdae4`.
2. **Movimiento**: Alberto lo veía «a tirones» y «recorre demasiado espacio». Se
   pasó a animar SIEMPRE (no gateado a actividad) y ~2-3× más lento (`d0b5d44`).
3. **Modo Laura activa** (D-12): cableado (`b81e5b5`). Congela + oscurece + Laura
   brilla latiendo con la voz. Sin probar en vivo.
4. **Fondo entero a shader GPU** (D-13, `SolarField` + `solarfield.frag`):
   integrado (`e055cfd` + `954c08e`). **Renderiza** (`real-shader-fondo.png`),
   composición correcta, soles bien.

**D-14 · Rendimiento del shader — RESUELTO (2026-09-03).** 15,1 % → **4,7 % de un
núcleo** en limpio (objetivo ≤5 %). El `ShaderEffect` a pantalla completa clavaba
~10 % de más porque cada píxel corría el bucle de prominencias de los dos soles +
el fbm de turbulencia del disco, contribuyeran o no. Fix: cortes tempranos por
distancia (`sun()` > 3,4r; `blackHole()` > 4,6R; `starfield()` lente sólo cerca
del agujero); fbm 4→3 octavas; tic del shader 20→10 fps; posiciones 2→1 fps.
Bajar la resolución del shader (`layer.textureSize`) se probó y **no compensó**.

**D-15 · El agujero negro recupera detalle (2026-09-03).** El shader lo pintaba
plano. Añadido: bandeado concéntrico de dos frecuencias, gradiente de temperatura
real (blanco-caliente → ámbar → rojo profundo, con las alfas medias/exteriores
subidas), anillo de fotones casi blanco en el lado Doppler, halo lensado más
marcado. El horizonte negro se ve poco porque la composición D lo saca de cuadro
(centro en `(1.02W, -0.04H)`); verlo como disco elíptico negro pediría acercar el
centro → decisión de composición pendiente de Alberto.

**Fuera de esta tanda** (van después): zonas LED como cuerpos (D-5), interacción
(hover/clic/congelar), visualizador de música en tiempo real, modo Laura probado
en vivo. La vista ya expone `contentBounds` para la región de input.

Fuera de esta tanda (van después): zonas LED como cuerpos (D-5), interacción
(hover/clic/congelar), visualizador de música en tiempo real. La vista ya expone
`contentBounds` para la región de input.

## Historial

- **2026-09-03** — Brainstorming de composición (Claude). 4 posibilidades
  (maqueta en el repo `docs/sistema-solar-v3-mockup/`; también
  [artifact `0951108d`](https://claude.ai/code/artifact/0951108d-14ed-46df-8a48-9264b32df0ab)).
  Alberto elige D. Se guarda B como reserva. Se prepara la rama
  `feat/sistema-solar-v3` y el traspaso (`docs/sistema-solar-v3-DISENO.md` +
  `-PROMPT.md`). Revisada D-2: el binario no deriva.
