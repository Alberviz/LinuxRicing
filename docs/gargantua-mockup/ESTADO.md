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

## Pendiente, en orden

1. **Aliasing en vivo**, lo más visible: las vetas de la cola y del creciente inferior hacen un patrón de peine/moiré, y la cola acaba en una lluvia de puntos negros. Hace falta un filtro de la frecuencia del ruido según la derivada (`fwidth` de r,φ), menos motas en la punta de la cola y quizá algo más de bloom.
2. **Quitar los arcos grises viejos** abajo a la derecha del agujero. Vienen de `MusicHole.qml`, que sigue con la geometría antigua: retirarlos o adaptarlos.
3. **Anillo de fotones:** Alberto quiere mejorarlo. Ahora tiene poco hueco respecto al creciente y asoma una astilla blanca junto a la franja, a la izquierda de la sombra. Hay que preguntarle qué cambiaría (grosor, brillo, hueco).
4. **Bóveda cortada** por el borde superior de la pantalla. Valorar bajar un poco el centro sin romper la composición; preguntar a Alberto.
5. **Sincronización con la música**, todavía no hecha (`musicProgress`/`musicLines` no están conectados). Plan acordado:
   - graves → brillo y temperatura del disco interior;
   - golpe de ritmo → punto caliente que orbita (kepleriano) y se apaga;
   - agudos → brillo fino del grano;
   - progreso de la canción → el anillo de fotones se enciende en sentido horario;
   - cambio de canción → onda gravitacional;
   - silencio → disco en reposo.
   Todo sutil, sin destellos y con ganancia automática.
6. **Rendimiento:** medir en frío el pase por frame en la Intel UHD 770; en el mockup eran ~6 ms. No hay `intel_gpu_top` instalado: si Alberto lo instala, se puede medir.
7. **Merge** de `feat/gargantua-lut` a `main` cuando Alberto lo dé por bueno.
8. **Fuera de este proyecto:** `qs` gasta ~30% de CPU con cualquier agujero, el viejo o el nuevo, y no baja al reiniciar. Viene de otra parte del shell. Va en la tarea del backlog «Arreglar rendimiento y uso de la tarjeta gráfica». El widget de rendimiento tiene su propia tarea para que muestre también la GPU Intel.

## Historia rápida (por qué está hecho así)

- **A/A3:** LUT de lente precalculada con dos órdenes (dos imágenes compuestas). Alberto veía siempre «dos piezas».
- **B:** raymarch real por píxel. Primera vez que sale una sola pieza: forma aprobada.
- **B2–B5:** rendimiento con caché geométrica, polvo y luz. En B5 se añadió una bruma o banda que rompía la unidad, y Alberto la rechazó.
- **B6/B7:** vuelta a la unidad de B y retoques.
- **B8/B9:** piel copiada de la visión de Gemini y luz artística.
- **B10:** la cara de atrás lejana queda plana y la bóveda nace cerca del agujero. La variante artística (B) es la aprobada.
- Cada versión se regenera con `./runBN.sh` en esta carpeta (necesita `qml6`; abre una ventana breve).
