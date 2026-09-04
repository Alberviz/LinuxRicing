# Diseño: Agujero Negro Estilo Gargantua (Relatividad General en GPU)

Fecha: 2026-09-05  
Estado: Aprobado por Alberto  
Ubicación: `configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag`

## 1. Contexto y Objetivos

Actualmente el agujero negro de `solarfield.frag` utiliza una aproximación 2D plana donde el horizonte de sucesos se dibuja encima de todo el disco, impidiendo ver el disco ecuatorial cruzando por delante de la sombra y careciendo del arco lensado inferior. Esto resulta en una apariencia de "anillos de Saturno" finos en lugar del característico aspecto de Gargantua (*Interstellar* / modelo relativista de Kip Thorne).

El objetivo es actualizar la función `blackHole()` en `solarfield.frag` para recrear fielmente la física visual de Gargantua manteniendo un coste de GPU mínimo (~0% sobrecarga, 144 Hz estables) y la integración armónica con la paleta de Material You (M3).

## 2. Geometría y Capas Ópticas

La proyección se divide analíticamente en capas ordenadas de atrás hacia adelante:

1. **Campo estelar y resplandor de fondo:**
   - Estrellas de fondo deflectadas por la gravedad cerca del horizonte.
   - Resplandor exterior difuso y suave.

2. **Sector Trasero Lensado (Dual Arch):**
   - **Arco Superior:** Rayos de luz que viajan desde la parte posterior del disco y se curvan por encima del horizonte hacia la cámara.
   - **Arco Inferior:** Rayos de luz que viajan desde la parte posterior y se curvan por debajo del horizonte hacia la cámara.
   - Ambos arcos se unen en los laterales con el disco exterior.

3. **Sombra Central (Horizonte de Sucesos y Esfera de Fotones):**
   - Disco opaco central que cubre el sector trasero y el fondo.
   - Anillo de fotones ultra-delgado e hiperbrillante en el borde exacto de la sombra ($r \approx 1.035 R$).

4. **Sector Delantero del Disco Ecuatorial:**
   - Tramo del disco de acreción ubicado entre la singularidad y la cámara.
   - Se dibuja **por encima** de la sombra del agujero negro, cortándola horizontalmente en su mitad inferior con perspectiva casi de canto.

## 3. Textura de Plasma y Gradiente Térmico

- **Sustitución de aros sinusoidales:** Se retiran las fórmulas periódicas rígidas (`sin(rD * 28.0)`) para evitar el efecto de microsurcos. Se implementa una densidad continua de plasma gaseoso con turbulencia laminar fluida mediante `fbm` continuo en coordenadas angulares/radiales.
- **Gradiente de temperatura incandescente (Física + M3):**
  - **Borde interior / ISCO:** Emisión blanco puro sobreexpuesto (`vec3(1.0)`) con halo difuso de incandescencia.
  - **Cuerpo del disco:** Transición cálida hacia oro y ámbar modulados con `colPrimary` (`m3primary`).
  - **Borde exterior:** Desvanecimiento suave hacia rojo profundo (`colError` oscurecido) y gas cósmico que se disuelve en el negro espacial.
- **Beaming Relativista:** Asimetría marcada de brillo y color en el lado que rota hacia el observador (`pow(approach, 3.2)`), emulando la velocidad relativista (~0.5c) de la materia en caída libre.

## 4. Reactividad Musical y Compatibilidad

- **Reactividad:** Destellos en el anillo de fotones y labio ISCO con `musicPulse`, desplazamiento espectral térmico con `musicBass` / `musicTreble`, y ondas de acreción espiralantes con `musicBurstAge`.
- **`MusicHole`:** El horizonte central mantiene espacio despejado en su cuadrante superior para los metadatos de audio de Quickshell.

## 5. Verificación y Despliegue

1. Compilar shader: `/usr/lib/qt6/bin/qsb --qt6 -o solarfield.frag.qsb solarfield.frag`.
2. Sincronizar archivos con `~/.config/quickshell/caelestia/`.
3. Reiniciar Quickshell limpiamente comprobando `INFO: Configuration Loaded`.
4. Captura real de pantalla con `grim` para verificación visual.
