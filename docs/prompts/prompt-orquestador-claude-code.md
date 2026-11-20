# PROMPT PARA CLAUDE CODE — SESIÓN DE ORQUESTACIÓN AUTÓNOMA

## 0. ROL Y CONTEXTO

Actúas como **orquestador principal** de una sesión de trabajo autónoma sobre mi ecosistema Linux personal (widgets, LEDs, notificaciones, workspaces, Caelestia Shell como barra vertical fija en el lateral izquierdo, y el asistente de IA local llamado **Laura**).

**No voy a estar delante durante toda la sesión.** Cuando yo vuelva, espero encontrar todas las tareas de abajo resueltas o en el estado explícito que se indica en cada una. Tú tomas **todas** las decisiones técnicas y de alcance por tu cuenta. Solo debes dejar algo bloqueado y pendiente de mí si es **hipercrítico** y objetivamente imposible de decidir sin mi intervención (por ejemplo: una credencial que no tienes, una decisión irreversible que destruye trabajo previo, o un coste real que no puedes asumir sin permiso). En ese caso, no te bloquees: sigue con el resto de tareas y déjame ese punto claramente señalado en el informe final.

Antes de tocar nada:
1. Inspecciona el repositorio y el estado actual del ecosistema. **No inventes rutas, nombres de ficheros ni APIs**: verifícalos.
2. Consulta el **vault de Obsidian** donde documento decisiones y tareas del proyecto, para no repetir trabajo ya hecho por otros agentes.
3. Al terminar, **documenta en el vault de Obsidian** lo que se ha hecho, lo que ha quedado a medias y las decisiones tomadas.

---

## 1. MODELO DE EJECUCIÓN: SUBAGENTES

Puedes y debes **paralelizar** el trabajo generando subagentes:

- **Subagentes de Gemini** (vía Antigravity) para el trabajo que se pueda delegar fuera.
- **Subagentes propios de Sonnet** para el trabajo que quieras mantener dentro de Claude Code.

Reparte las tareas entre ellos como te parezca más eficiente. Si dos tareas tocan las mismas zonas del código y pueden pisarse, **usa ramas git separadas** (una rama por tarea o por bloque de tareas) y haz el merge tú al final, resolviendo conflictos. Si son independientes, puedes trabajar en la misma rama. Tú decides la estrategia de ramas; solo asegúrate de que al final el árbol quede limpio, sin conflictos sin resolver y con commits descriptivos.

---

## 2. REGLAS DE OPERACIÓN (IMPORTANTES)

- **Tienes libertad total** para hacer lo que haga falta hasta que las tareas estén terminadas.
- **Optimiza tokens de forma agresiva.** No hagas lecturas masivas innecesarias, no repitas contexto, no re-explores lo ya explorado.
- **Corta los bucles.** Si detectas que un subagente está en un bucle, repitiendo intentos fallidos o sin converger hacia una solución, **córtalo inmediatamente**. No insistas quemando tokens. Anota en qué punto quedó, qué se intentó y qué falló, y déjalo para mañana. Es preferible una tarea parada y bien documentada que una tarea que se ha comido el presupuesto.
- Prioriza que quede **funcionando y probado** sobre que quede perfecto.

---

## 3. TIMING Y GESTIÓN DE LA CUOTA DE GEMINI

A Gemini le quedan **30 minutos** para recuperar sus tokens.

- Ejecuta un **`sleep` de 30 minutos** para esperar esa recuperación.
- **Aprovecha ese tiempo**: durante la espera, o antes de lanzarla, haz todo el trabajo que **no** dependa de Gemini (análisis del repo, lectura del vault, planificación, implementación con tus propios subagentes de Sonnet, preparación de los prompts que luego lanzarás a Gemini). El objetivo es que el reloj de espera y el trabajo corran en paralelo, no que la sesión se quede parada 30 minutos sin hacer nada.
- Ajusta el ritmo para que **todo el bloque de trabajo quepa en ese orden de magnitud (~30 minutos de ejecución efectiva)**. Si algo no cabe, prioriza según el orden de importancia que indico en la sección 5 y deja el resto documentado.

---

## 4. TAREAS

### T1 — Conectar Laura (agente IA local) con Gemini / Antigravity  *(fallback inteligente)*

Objetivo: que **cualquier cosa que Laura no pueda resolver por sí misma, se la pida a Antigravity (Gemini) y recoja la respuesta de ahí**, devolviéndomela integrada como si fuera suya.

La clave está en la **política de escalado**, que tiene dos modos distintos:

**Modo A — Automático, sin preguntarme (casos preprogramados):**
- Para acciones rutinarias y predefinidas, como **búsquedas en internet**, Laura **no me pregunta nada**: escala directamente.
- Estas peticiones las atiende un **agente ligero de Gemini: el modelo más ligero disponible y con el nivel de *effort* / *reasoning* más bajo que exista**. Nada de modelos caros para esto.
- Define en la configuración una lista de este tipo de casos preprogramados (búsqueda web, consultas factuales rápidas, etc.), fácilmente ampliable por mí después.

**Modo B — Con confirmación previa (tareas complejas):**
- Para tareas complejas o que impliquen modificar el ecosistema —por ejemplo: *"haz que el reloj marque la hora en formato 12 horas"*— Laura **me pregunta primero**, con algo del estilo: *"¿Quieres que mande a Gemini a hacer eso?"*.
- Si respondo que sí, **se abre una sesión de Gemini** y **es Laura quien le redacta el prompt** a Gemini (Laura traduce mi petición en lenguaje natural a un prompt bien formado para la sesión de Gemini).
- Laura recoge el resultado, lo integra y me lo comunica.

Implementa el mecanismo completo: detección de "no puedo resolverlo", enrutado según modo A o B, construcción automática del prompt, apertura/gestión de la sesión de Gemini, recogida de la respuesta y devolución al usuario. Deja la clasificación A/B configurable y documentada.

---

### T2 — Wakeword para Laura  *(NO implementar: dejar preparada + guía)*

Cuando yo vuelva quiero encontrar:

1. Una **tarea creada y visible en estado "pendiente" o "en curso"** (en el sistema de tareas del proyecto / vault de Obsidian) titulada claramente como la **wakeword para Laura**.
2. Una **guía paso a paso, detallada y escrita para mí**, para poder implementarla **mañana** cuando vuelva. Que sea explícita: qué opciones existen, cuál recomiendas y por qué, qué instalar, qué comandos ejecutar, qué ficheros tocar y con qué contenido, cómo integrarla con el arranque de Laura, cómo probarla y cómo depurarla si no responde. Que yo pueda seguirla sin tener que pensar ni investigar por mi cuenta.

Ten en cuenta mi hardware al recomendar: **GPU con 6 GB de VRAM (~GTX/RTX 1060)**, y mi preferencia por **modelos locales**, recurriendo a modelos online solo si el hardware local no da.

---

### T3 — Nueva versión del background con información al pasar el ratón  *(alcance: lo decides tú)*

Quiero **empezar a preparar** la nueva versión del background, en la que **al pasar el ratón por encima obtengo información**.

**Tú decides hasta dónde llegamos**: ¿la implementamos entera, o simplemente la planeamos y dejamos el terreno preparado (arquitectura, estructura de ficheros, puntos de enganche, prototipo mínimo)? Decide según el tiempo y los tokens disponibles y según lo que veas al inspeccionar el código. **Justifica la decisión** en el informe final.

---

### T4 — Indicador de notificaciones en workspaces ≥ 6  *(asignar a otro agente)*

Problema: si tengo un agente trabajando en un workspace ≥ 6 y yo estoy, por ejemplo, en el workspace 2, **no veo que haya pasado nada allí**.

Solución que quiero: **si hay notificaciones en workspaces ≥ 6**, que se me avise visualmente. Por ejemplo, que **la parte de abajo de la cápsula general de workspaces parpadee**. Esa es la idea base; si encuentras una variante mejor que encaje con la estética actual de la barra (Caelestia Shell, barra vertical izquierda), puedes proponerla e implementarla, pero **el comportamiento mínimo requerido es ese: aviso visible en la cápsula de workspaces cuando hay actividad/notificaciones en workspaces ≥ 6**.

Asigna esta tarea a **un agente distinto** del que lleve las demás.

---

### T5 — Planeta de configuración → abre el panel de LEDs  *(esta SÍ debe quedar implementada)*

Quiero que **al hacer clic en el planeta de configuración se abra el panel de configuración de LEDs** que estuvimos desarrollando durante tanto tiempo. Esto **sí** quiero que quede **implementado y funcionando**, no solo planificado.

Además: **piensa un nombre original para ese planeta**, o bien quítale el nombre por completo (déjalo sin etiqueta), lo que estéticamente quede mejor. Propón el nombre elegido y aplícalo; explícame en el informe por qué elegiste eso.

---

### T6 — Reactivar y ayudar a la sesión de Gemini del agujero negro  *(última tarea, y se cierra el tema)*

Ahora mismo hay una **sesión de Gemini activa** que se va a quedar sin tokens. Tu última tarea es **volver a activarla y ayudarla**.

- Está intentando hacer un **agujero negro como el de *Interstellar***. **Adjunto la imagen de referencia** (el fotograma de *Interstellar* con Gargantua): ese es exactamente el resultado que buscamos. Úsala como referencia visual y pásasela / descríbesela a la sesión de Gemini.
- El problema concreto: **el disco del ecuador le sale mal**. Ese es el punto a atacar.
- A ti **te suele salir bien** cuando te lo pido. Así que **juntad vuestros puntos fuertes**: aporta tú lo que sabes que funciona (geometría del disco ecuatorial, el arco superior e inferior por lente gravitacional, el halo, el gradiente de color, el brillo asimétrico por *Doppler beaming*) y deja que Gemini aporte lo suyo, para que quede **tal cual el de *Interstellar***.
- **Aviso de expectativas y de presupuesto:** llevamos **más de 5 horas** con esto y lo veo casi imposible. Así que **no te obsesiones ni te fundas los tokens**: simplemente **reactiva esa sesión, dale la mejor ayuda posible en un intento acotado, y ahí se cierra el tema**. No abras un ciclo largo de iteración. Un intento bueno, documentado, y cerramos.

---

## 5. PRIORIDAD SI NO DA TIEMPO A TODO

1. **T5** (planeta → panel de LEDs): obligatoria, debe quedar implementada.
2. **T2** (tarea pendiente + guía de la wakeword): obligatoria, debe existir la guía.
3. **T1** (Laura ↔ Gemini con los dos modos de escalado).
4. **T4** (indicador de workspaces ≥ 6).
5. **T3** (background con hover), con el alcance que tú decidas — puede quedarse en solo planificación.
6. **T6** (agujero negro), con el alcance acotado descrito.

---

## 6. ENTREGABLE FINAL

Cuando termines, déjame en el vault de Obsidian (y como resumen final de la sesión) un informe con:

- **Estado de cada tarea**: completada / parcial / parada, y por qué.
- **Decisiones tomadas** y su justificación (especialmente el alcance de T3 y el nombre del planeta en T5).
- **Ramas creadas**, commits relevantes y estado del merge.
- **Agentes cortados por bucle**, si los hubo: en qué punto quedaron, qué se intentó, qué falló y cuál es el siguiente paso sugerido.
- **Cualquier punto hipercrítico** que requiera mi intervención, destacado arriba del todo y explicado en una línea.
- **Cómo probar** lo que has implementado, para que yo lo verifique en 5 minutos al volver.
