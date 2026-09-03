# Prompt para la sesión limpia — Sistema Solar v3

Copia todo lo que hay debajo de la línea en la primera petición de la sesión nueva.

---

Vas a implementar el **rediseño v3 del sistema solar del escritorio** de LinuxRicing:
el escritorio pasa a estar vacío salvo el reloj, a pantalla completa, con un
agujero negro masivo en una esquina y un sistema binario de dos soles. Alberto
**no va a estar** durante la implementación: toma tú las decisiones que hagan
falta y anótalas. Estás en una rama aislada, no puedes romper nada de `main`.

## Lo primero que tienes que hacer

1. Lee **`docs/sistema-solar-v3-DISENO.md`** entero. Es la spec. Este prompt solo
   la resume.
2. Lee `docs/sistema-solar-binario.md` (contexto y principios del proyecto).
3. Mira la maqueta de referencia en el repo: `docs/sistema-solar-v3-mockup/` —
   `variante-D.png` (captura) y `variantes.html` (interactivo, ábrelo con
   `chromium --headless ... "file://.../variantes.html?p=D"` y captura, o en un
   navegador). Es el norte de composición; la calidad de render hay que
   **superarla**.
4. Mira `vault/Rice LinuxRicing/01 - Linux/Widgets/Sistema Solar — visión B (reserva).md`
   (contexto de una alternativa descartada por ahora; no la implementes).

## Dónde trabajas

- **Rama:** `feat/sistema-solar-v3`, worktree en `.worktrees/sistema-solar-v3`.
  Sacada de `refactor/background-modularize`. Ni esa rama ni su base están en
  `main`. **Nunca toques `main`.**
- Archivos base ya en la rama (de la v1.5, se reescriben/ajustan):
  `configs/quickshell/caelestia/modules/background/solarsystem/{SolarSystem.qml,Sim.js,SolarSystemLayer.qml}`
  y `configs/quickshell/caelestia/services/SolarSystemModel.qml` (adaptadores de
  batería/agentes/tareas ya hechos).

## Qué hay que dejar hecho (SOLO el diseño)

- Escritorio a pantalla completa: **solo el reloj de Caelestia + el sistema solar,
  sobre fondo negro**. Wallpaper apagado (flag restaurable). Fuera los widgets
  (periféricos, deck de tareas/clima/hardware/foco, tira LED, visualizador
  circular) — comentar sus `Loader` en `Background.qml`, no borrar los `.qml`.
- **Agujero negro «música»** en la esquina superior derecha, saliéndose ~30 % de
  cuadro, masivo, con disco de acreción en diagonal cruzando la pantalla. Capas
  completas (horizonte, anillo de fotones con Doppler, disco multi-banda con
  gradiente de temperatura + turbulencia + beaming, lente gravitacional sobre el
  horizonte, estrellas lensadas en arcos, jet tenue). **No un halo simple.**
- **Binario «Laura ↔ Configuración»** centro-izquierda, **anclado** (no deriva).
  Dos soles detallados (fotosfera granulada, cromosfera, corona, prominencias
  lentas en Laura). Laura = primario (mayor). Config = secundario (menor, calmo).
- **Agentes** reales (`Agents.qml`) orbitando Laura: 0 si no hay; en curso =
  brillante con anillo; completado = tenue. **Dispositivos** conectados
  (`mchose-battery`) orbitando Config: solo si conectado; tamaño/brillo = batería;
  rojo pulsante si < 20 %.
- **Cinturón de tareas** circumbinario alrededor del par, muy tenue, densidad =
  tareas `pendiente` del backlog.
- Colores 100 % de `Colours.palette.m3*`. **Cero hex fijos.**

**Fuera de alcance:** interacción (hover/clic/congelar), reactividad (Laura se
aviva al hablarle…), zonas LED como cuerpos, clima/foco. Diseña la vista para
poder añadir la entrada después sin reestructurar (expón bounding-box e ids).

## Restricciones que NO puedes saltarte

- **Movimiento LENTO.** Períodos orbitales de 1-2 minutos, no segundos. Tabla en
  la spec §3. Es un sistema que se usa para leer información; posiciones estables
  y predecibles.
- **Rendimiento (spec §6, y `CLAUDE.md`):**
  - Nunca dos instancias del shell. Antes de cada arranque:
    `caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d`.
    Verifica después con `pgrep -af "qs -c caelestia"` que hay **una sola**.
  - Restart completo siempre, **nunca** confiar en el hot-reload (fuga animaciones zombis).
  - **Prohibido `FrameAnimation { running: true }`.** Tick por `Timer` gateado a
    actividad real; en reposo el `Timer` para del todo. `interval` de reposo
    250-500 ms (2-4 fps).
  - Nada de `shadowBlur` a ritmo de animación (gradiente radial para resplandores).
  - Cachea las capas estáticas (resplandor del agujero, campo de estrellas,
    granulación base de los soles) a un canvas offscreen; cada frame solo redibuja
    disco, prominencias y posiciones.
  - Dimensiona el `Canvas` a la caja del contenido, no a 1920×1080.
  - Presupuesto: shell en reposo ≤ ~5-7 % de un núcleo. Mídelo.
  - Si Canvas 2D no llega a la calidad sin pasarse de CPU: para, anótalo, y monta
    el disco del agujero como `ShaderEffect` GLSL en GPU.

## Flujo de trabajo

1. Itera los visuales en un **harness HTML** (Canvas 2D ≈ misma API que QML
   Canvas), capturas con `chromium --headless ... --screenshot`. Lee el PNG,
   ajusta, repite hasta que la imagen esté.
2. Porta a QML (`SolarSystem.qml` + `Sim.js`).
3. Despliega a `~/.config/quickshell/caelestia/`, verifica gemelos con `diff -q`,
   restart limpio, confirma `INFO: Configuration Loaded` sin errores.
4. Captura el escritorio real: workspace vacío de Hyprland + `grim` + volver
   (comando en la spec §9). Mide CPU.
5. **Commit pronto y a menudo** (otro agente puede barrerte el working tree).
   Mensajes en español, termina con
   `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` y la línea
   `Claude-Session: <url de tu sesión>`.
6. **No pares hasta que el diseño esté hecho** (criterio en la spec §11).
7. Al terminar: bitácora en `vault/🎯 Hoy.md` (una línea arriba de «Bitácora de
   sesiones»), actualiza la tabla de versiones de `docs/sistema-solar-binario.md`,
   marca `docs/sistema-solar-v3-DISENO.md` §11 y deja un resumen con capturas.
8. Toda decisión nueva → tabla §8 de la spec + una línea en
   `vault/Rice LinuxRicing/01 - Linux/Widgets/Sistema Solar — decisiones v3.md`.

## Skills

Empieza por `superpowers:using-superpowers`. Para el trabajo de render, el diseño
ya está cerrado en la spec — no necesitas `brainstorming`; ve a implementar
siguiendo `docs/sistema-solar-v3-DISENO.md`. Usa `test-driven-development` /
`verification-before-completion` según proceda, pero recuerda que Alberto prueba
en vivo y no quiere tests automáticos (memoria del proyecto).

Cuando tengas el diseño hecho y capturado, para y deja el resumen para Alberto.
