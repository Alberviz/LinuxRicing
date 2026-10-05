# Agujero negro Gargantua — estado y pendientes

Rama: `feat/gargantua-lut` (sin mergear a `main`). Última actualización: 2026-10-05.

## Dónde estamos

- **En vivo desde `8dc21de`:** el agujero negro del escritorio es la versión **B10-B**. Sustituye al `blackHole()` analítico de la «variante D».
- **Archivos en vivo:**
  - `configs/quickshell/caelestia/modules/background/solarsystem/SolarField.qml`
  - `configs/quickshell/caelestia/modules/background/solarsystem/shaders/bhnoise`
  - `configs/quickshell/caelestia/modules/background/solarsystem/shaders/bhgeo`
  - `configs/quickshell/caelestia/modules/background/solarsystem/shaders/bhshade`
  - `configs/quickshell/caelestia/modules/background/solarsystem/shaders/bhbloom`
  - `configs/quickshell/caelestia/modules/background/solarsystem/shaders/bhcomp`
  - `configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag`
  - más los `.qsb` de cada shader, copiados a `~/.config/quickshell/caelestia/`
- **Cómo funciona:**
  - Raymarch de Schwarzschild **por píxel** contra UN solo disco. La bóveda, la franja y el creciente salen del mismo rayo, así que es una sola pieza.
  - Ese raymarch se cachea **una vez** en una caja de ~1370x650 px. Solo se recalcula si cambian el centro, el radio o la caja.
  - En cada frame corre un pase barato de sombreado (vetas, motas y Doppler), luego el bloom y por último el composite.
- **Parámetros aprobados por Alberto:**
  - Elevación de la cámara: 6°.
  - Giro en pantalla: -0.30 rad.
  - Deflexión debilitada lejos del agujero (`weakR`, ×1/(1+(r/3)³)). Es artística: deja plana la cara de atrás lejana y la bóveda nace cerca del agujero.
  - Sombra de ~290 px en la esquina superior derecha.
  - Piel B9: rampa de 5 roles del tema (onPrimaryContainer → primaryContainer → primary → tertiary), vetas finas, motas de absorción y bloom lavanda.
  - Anillo de fotones separado del disco por un hueco.
- **Criterio de Alberto:** «no hiperrealista, lo que queda bien». La física decide la FORMA y el ojo decide la LUZ. El color sale SIEMPRE de los roles del tema. Nunca se añaden capas o bandas sueltas delante de la sombra, porque rompen la unidad.
- **Referencias:**
  - `ref-gemini-vision.jpg`: la visión que a Alberto le encanta.
  - `../../reference_interstellar.png`
  - `comparativa-todas.png`
  - `B10-vs-gemini.png`

## Hecho el 2026-10-05 (sesión Claude Sonnet 5.5) — SIN verificar en vivo (pantalla apagada)

- **Música (commit `12267fe`):** `bhshade.frag` recibe `musicActive/Progress/Bass/Treble`, `beatAge`, `beatSeed`.
  - El progreso enciende en sentido horario desde las 12 la bóveda (tramo 1) y el anillo de fotones como un solo trazo; lo no recorrido queda al 25 % (`DIM_OFF`) y la cabeza brilla un poco.
  - Con `musicActive = 0` (silencio, sin canción) todo igual que lo aprobado. En pausa se queda donde está.
  - Graves → disco interior; golpe → punto caliente kepleriano que se apaga; agudos → grano. Falta la onda gravitacional al cambiar de canción.
- **Aliasing (commit `6ab1dfb`):** cada octava de ruido se funde con su media según la huella del píxel (`aaw`); menos motas en la punta de la cola.
- **Overlay viejo:** `musicVariant` por defecto 0, que ahora es `BhReadout.qml` (tiempo, título y artista dentro de la sombra, por encima de la franja). Los arcos grises no se han podido confirmar como suyos: si siguen, mirar el Canvas fino de `SolarSystem.qml`.
- **Arnés de pruebas sin pantalla:** `qml6` con `QT_QPA_PLATFORM=wayland` y `QT_FORCE_STDERR_LOGGING=1` renderiza a PNG aunque el monitor esté apagado (con `offscreen` sale en blanco; `grim` se cuelga con DPMS apagado). Se vio un artefacto de bloom abajo a la derecha que parece del arnés, no confirmado en vivo.
- **CPU de `qs` medida:** 42 % de un núcleo en reposo sin música.

## Pendiente, en orden

1. **Verificar en vivo con música:** progreso, tenue 25 % (¿más o menos?), cabeza del trazo, punto caliente y que el bloom no se desboque con graves fuertes.
2. **Arcos grises** abajo a la derecha: confirmar si han desaparecido con la variante 0.
3. **Anillo de fotones:** Alberto quiere mejorarlo (poco hueco con el creciente, astilla blanca a la izquierda de la sombra). Preguntarle qué cambiaría.
4. **Bóveda cortada** por el borde superior. Valorar bajar un poco el centro; preguntar.
5. **Onda gravitacional** al cambiar de canción (no hecha).
6. **Rendimiento:** con música el reloj de `bhShade` sube a ~25 Hz (lo que cambian las propiedades de música); medir en la Intel UHD 770 y gatear si pesa.
7. **Merge** de `feat/gargantua-lut` a `main` cuando Alberto lo dé por bueno.
8. **Fuera de este proyecto:** `qs` gasta ~30-40 % de CPU con cualquier agujero. Va en la tarea «Arreglar rendimiento y uso de la tarjeta gráfica».

## Historia rápida (por qué está hecho así)

- **A/A3:** LUT de lente precalculada con dos órdenes (dos imágenes compuestas). Alberto veía siempre «dos piezas».
- **B:** raymarch real por píxel. Primera vez que sale una sola pieza: forma aprobada.
- **B2–B5:** rendimiento con caché geométrica, polvo y luz. En B5 se añadió una bruma o banda que rompía la unidad, y Alberto la rechazó.
- **B6/B7:** vuelta a la unidad de B y retoques.
- **B8/B9:** piel copiada de la visión de Gemini y luz artística.
- **B10:** la cara de atrás lejana queda plana y la bóveda nace cerca del agujero. La variante artística (B) es la aprobada.
- Cada versión se regenera con `./runBN.sh` en esta carpeta (necesita `qml6`; abre una ventana breve).
