---
tags:
  - debate
  - shaders
  - fisica
  - agujero-negro
  - coordinacion
creado: 2026-09-05
autores:
  - Gemini
  - Claude
---

# 🌌 Debate y Diagnóstico Técnico: Conseguir el Agujero Negro de Interstellar (Gargantua)

> **Para Claude y Gemini (Sesiones concurrentes):**  
> Este documento recoge el diagnóstico forense, la física real y el debate técnico entre agentes tras el feedback explícito de Alberto: *"sigue sin parecerse en nada, habla con claude y debatir de que hacer para conseguir llegar al de interstellar"*.

---

## 1. Diagnóstico Forense: ¿Por qué NO se parece a la foto de referencia?

Al comparar pixel a pixel la captura de referencia (`ref_bh_crop.png`) con lo que hemos renderizado en pantalla (`bh_live_v3.png`), los fallos fundamentales son **estructurales y geométricos**, no de pequeños retoques:

| Aspecto | Foto de Referencia (*Interstellar*) | Lo que hay en nuestro Shader actual |
| :--- | :--- | :--- |
| **Bóveda Superior (Lensed Arch)** | Domina la imagen: es un arco majestuoso, altísimo y masivo ($\sim 2.5 \times$ el radio de la sombra). | Está recortada casi al 80% contra el borde superior de la pantalla por el encuadre en la esquina (`fy: 0.08`). |
| **Bóveda Inferior (Lower Arch)** | Es una **fina y elegante media luna** comprimida debajo de la sombra. Apenas ocupa un $\sim 15\%$ del tamaño visual. | Es una **cuenca gigantesca y masiva** (`lut0`) que ocupa casi la mitad de la pantalla hacia abajo, deformando la silueta. |
| **Disco Ecuatorial Frontal** | Es una **losa volumétrica gruesa, densa y brillante** que cruza horizontal/diagonalmente. Tiene un núcleo blanco incandescente y bordes gaseosos con polvo. | Se percibe como una franja fina o un "chorro" artificial que cruza en medio de dos aros enormes. |
| **Inclinación (Tilt)** | Inclinado hacia arriba a la derecha ($\approx +20^\circ$). El gas se acerca por la izquierda (blanco) y se aleja por la derecha. | Estaba configurado con `bhTilt = -0.35` ($\approx -20^\circ$), es decir, **inclinado en la dirección opuesta**. |
| **Unión en el Flanco Izquierdo** | La bóveda superior y el disco frontal convergen en una **cúspide continua** que se proyecta hacia abajo a la izquierda. | Aparecen artefactos de solape entre las texturas LUT y la franja paramétrica. |
| **Encuadre / Posición** | Visto como un "Hero Shot" donde el agujero es el protagonista y su anatomía es visible. | Encastrado en la esquina superior derecha (`0.90, 0.08`), perdiendo 3 de los 4 cuadrantes del agujero. |

---

## 2. El Fallo de Física: La trampa de la hoja 2D en la LUT de Schwarzschild

Claude implementó `gen_lut_final.py` integrando numéricamente (RK4) las geodésicas de Schwarzschild:
$$ \left(\frac{du}{d\phi}\right)^2 = \frac{1}{b^2} - u^2(1 - u) $$

La matemática relativista de los fotones nulos es impecable, pero el modelo físico asumió una **hoja infinitesimalmente delgada en $z = 0$**.

### ¿Qué ocurre en una hoja 2D plana?
1. Los rayos que apuntan a la sombra ($b < b_{crit} \approx 2.6$) caen al horizonte de sucesos. Como la hoja solo existe en $z=0$, los rayos caen sin intersectar ningún disco frontal.
2. Por eso la textura `lens_lut_order0.png` (`lut0`) **tiene un hueco vacío absoluto dentro de la sombra**.
3. Además, los rayos con $y > 0$ impactan el plano $z=0$ a radios muy lejanos debido a la perspectiva ($\theta_0 \approx 78^\circ$), lo que convierte a `lut0` en una **cuenca gigante que se extiende hacia abajo**, en lugar de una banda ecuatorial estrecha.

### ¿Cómo es Gargantua en *Interstellar* (Kip Thorne / DNEG)?
1. El disco de acreción **NO es una hoja 2D**: es un toroide gaseoso con **espesor vertical real** $H(r) \approx 0.15 r - 0.25 r$.
2. Cuando el observador mira desde una inclinación de $\approx 78^\circ$, la luz que cruza por delante de la sombra proviene del **gas en primer plano** (entre el observador y la singularidad). Los rayos atraviesan el gas **antes** de alcanzar el campo gravitatorio fuerte del agujero negro.
3. El disco frontal, por tanto, **bloquea la sombra por delante** como un cuerpo volumétrico tridimensional, ocultando el horizonte detrás de él.

---

## 3. Debate Técnico: ¿Qué debemos hacer para que sea IDÉNTICO a la foto?

Proponemos a Claude y Gemini las siguientes decisiones clave:

### Punto 1: Las Proporciones de las Bóvedas (Arco Superior vs Inferior)
- En la referencia de *Interstellar*, el arco superior es el protagonista absoluto y el inferior es una línea secundaria fina.
- **Causa en el shader:** La inclinación de cámara $\theta_0$ y la escala radial de `lut0` y `lut1`. Si `lut0` se dibuja como un disco plano de orden 0 completo, la mitad inferior se ve demasiado ancha.
- **Solución propuesta:**
  - El tramo inferior de la imagen directa debe comprimirse verticalmente o reemplazarse por la geodésica del orden secundario que pasa justo por debajo del anillo de fotones.
  - El disco ecuatorial frontal debe ser el que dicte la geometría visual de la mitad inferior, eliminando la cuenca sobredimensionada de `lut0`.

### Punto 2: El Espesor y Textura del Disco Ecuatorial
- Alberto rechazó el disco frontal cuando parecía un "chorro" desconectado sin homogeneidad.
- **Para que sea homogéneo y volumétrico:**
  - **Espesor:** Debe tener un $H$ generoso en pantalla ($\approx 0.5 R$ en el centro, expandiéndose a $\approx 0.8 R$ en el limbo izquierdo).
  - **Estructura Interna:**
    1. **Spine Core:** Un filamento central incandescente hiperblanco (`vec3(1.0)`), continuo de izquierda a derecha.
    2. **Manto de Gas Volumétrico:** Densidad gaussiana $\exp(-2.5 \eta^2)$ con turbulencia laminar horizontal que comparta las frecuencias de `sampleDisk()`.
    3. **Bandas de Polvo (Dust Lanes):** Filamentos de absorción oscuros que viajan estrictamente paralelos al flujo del gas.
    4. **Oclusión:** En el núcleo ($|\eta| < 0.7$), la opacidad debe ser $\ge 0.98$ para que la sombra no "se transparente" de forma fantasmal por el medio.

### Punto 3: La Inclinación y el Flujo Doppler
- **Tilt:** Cambiar `bhTilt` de negativo a positivo ($\approx +0.35$ rad, $\approx +20^\circ$) para que el disco suba hacia la derecha exactamente como en la foto de referencia.
- **Doppler:**
  - Flanco izquierdo: gas acercándose a $\approx 0.55c \implies$ blanco puro sobreexpuesto, ensanchamiento y máxima energía.
  - Flanco derecho: gas alejándose $\implies$ transición hacia ámbar cálido, cobre y ceniza cósmica.

### Punto 4: Encuadre y Tamaño en el Escritorio
- Si Alberto quiere que se vea como en la foto, **no puede estar metido al 90% fuera de pantalla en la esquina**:
  - Si el centro está en `fy: 0.08`, la bóveda superior desaparece por el techo del monitor.
  - **Propuesta:** Bajar el centro ligeramente hacia el interior (por ejemplo `fx: 0.86, fy: 0.18` o `0.20`) y darle un radio $R$ adecuado para que la bóveda superior completa, el disco ecuatorial y el anillo de fotones entren dentro del encuadre visible, sin tapar el sistema binario Laura/Prisma.

---

## 4. Plan de Acción Coordinado para la Siguiente Iteración

1. **Alineación de Parámetros:**
   - Invertir el signo de `bhTilt` ($+0.35$).
   - Ajustar el ancla del agujero negro en `SolarSystemModel.qml` y `Sim.js` a una posición donde la bóveda superior sea plenamente visible.
2. **Refactor de Composición en `solarfield.frag`:**
   - La bóveda superior (`lut1`) genera el arco superior.
   - La sombra rellena el horizonte con el anillo de fotones fino.
   - El disco frontal 3D cruza con espesor real, espina incandescente y oclusión opaca.
   - El arco inferior se restringe a una fina silueta estilizada bajo la sombra, eliminando la cuenca ancha residual.
3. **Verificación Visual:**
   - Captura con `grim` comparada lado a lado con `ref_bh_crop.png`.
   - Confirmación de que las líneas de corriente son 100% paralelas y que no existe ningún salto ni "chorro" aislado.
