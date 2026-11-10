# Laura — rendimiento, escalado de tools y ajuste fino (diseño)

Fecha: 2026-11-10 · Autor: Claude (Opus 5.5) con Alberto · Estado: propuesto
Plan de implementación: [`docs/superpowers/plans/2026-11-10-laura-rendimiento.md`](../plans/2026-11-10-laura-rendimiento.md)

## 0. Resumen

1. **El mayor coste de Laura hoy no es el modelo, es que la caché de prompt de Ollama casi
   nunca se aprovecha.** El system prompt lleva la hora con minutos (y la memoria y el contexto
   del holo) y, en la plantilla de Qwen3, el system va **antes** que las 56 tools. Cualquier
   cambio en él obliga a reprocesar ~7.700 tokens: **~3 s por petición** que se pueden quitar.
2. Para tener **muchas más tools** sin más VRAM hay que dejar de mandarlas todas: un núcleo fijo
   + las pocas relevantes elegidas por un recuperador de embeddings en CPU (0 VRAM).
3. El **ajuste fino** (LoRA) es la palanca de calidad y de contexto a medio plazo: enseñar
   *comportamiento* (cuándo llamar a qué, con qué argumentos, cómo hablar), no *hechos*.

## 1. Mediciones (2026-11-10, RTX 4050 6 GB, Ollama 0.33.2, `qwen3:4b-instruct`)

Entorno Ollama: `OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_KV_CACHE_TYPE=q8_0`, `OLLAMA_KEEP_ALIVE=20m`.
Prompt real (system de `config.toml` + `tools.activas()`): **7.682 tokens**.

| Caso | Prefill (procesar el prompt) | Generación | Total |
|---|---|---|---|
| Modelo frío (carga + prefill) | 3,42 s | 23 tok en 0,51 s | 11,40 s |
| Mismo prefijo que la petición anterior | **0,05 s** | 22 tok en 0,51 s | **0,66 s** |
| Solo cambia el minuto en el system | **2,98 s** | 22 tok en 0,51 s | **3,82 s** |

- Generación: ~45 tok/s. No es el cuello de botella (las respuestas son de 20-80 tokens).
- Prefill sin caché: ~2.600 tok/s. Cada 1.000 tokens que se reprocesan cuestan ~0,4 s.
- Cambiar `num_ctx` entre peticiones **recarga el modelo** (≈6 s). Todas las llamadas al mismo
  modelo deben usar el mismo `num_ctx`.

Tamaño del esquema de tools (caracteres JSON, 56 tools, ~23,9 k caracteres ≈ 7,2 k tokens).
Las más caras: `spotify` 2.197, `warp` 1.657, `cola_dj` 881, `listar_tareas` 756, `tele` 672,
`escalar_a_claude` 619, `escalar_a_gemini` 615. El system prompt: 3.152 caracteres, y gran parte
repite reglas «frase = tool» que ya están en las descripciones.

Examen (`eval/`), mejor histórico del modelo actual: herramientas 84-95 %, argumentos 98-100 %,
0/18 falsos positivos, ttft medio ~0,5 s (el examen siempre manda el mismo prefijo, por eso su
ttft es optimista respecto al uso real).

## 2. Diagnóstico

### 2.1 Por qué se rompe la caché

Ollama (con `NUM_PARALLEL=1`) guarda la caché KV de **la última petición** y reutiliza el
prefijo común con la siguiente. La plantilla de Qwen3 con tools renderiza:

```
<|im_start|>system
{system prompt}            ← aquí van la hora, la memoria y el holo (cambian)
# Tools ... <tools>{56 esquemas}</tools> ...<|im_end|>
<|im_start|>user ...
```

`Session.refresh_system()` (`assistant/laura/llm.py`) reescribe `messages[0]` en cada turno con
`fecha_hora_texto()` (resolución de minutos), `memory.prompt_block(user_text)` (cambia según la
frase si hay >20 hechos) y `escena().contexto()` (cambia con lo que hay en pantalla). En cuanto
difiere un carácter, todo lo que va detrás (las tools) se reprocesa.

### 2.2 Las llamadas auxiliares machacan la caché

`summarize_for_voice`, `answer_from_sources` (`llm.py`) y `resumen_correo._llm` (vigía) usan el
mismo modelo con prompts distintos y sin tools. Con una sola ranura, la siguiente frase de Alberto
tras una de ellas paga el prefill completo.

### 2.3 El modelo frío

`KEEP_ALIVE=20m`: tras 20 min sin uso el primer «Laura despierta» paga ~11 s. Hoy no se
aprovecha el tiempo en que Alberto está hablando (2-4 s) para cargar el modelo.

## 3. Diseño — Fase 1: velocidad (sin cambiar de modelo)

### 3.1 Prefijo estable (lo más importante)

- `messages[0]` = **solo** el system base de `config.toml`, idéntico siempre.
- Las tools en orden fijo (las contextuales `cuando=` ya van al final del registro).
- Lo dinámico (hora, memoria, holo) se calcula por turno y se inyecta **en el último mensaje del
  usuario al construir el cuerpo de la petición**, dentro de un bloque `<contexto>…</contexto>`.
  El historial guarda el texto limpio, así que los turnos anteriores no acumulan contextos viejos.
- Coste residual por turno: reprocesar desde el primer mensaje que cambió (el historial, unos
  cientos de tokens → ~0,1-0,2 s) en vez de 7.700.

### 3.2 Medir siempre

Todas las peticiones a Ollama pasan por un `_post()` único que registra en el log
`prefill N tok · X s` (campos `prompt_eval_count`/`prompt_eval_duration` de la respuesta). Así se
ve en `journalctl --user -u laura` cuándo falla la caché. Script reproducible `eval/prefill.py`.

### 3.3 Llamadas auxiliares con el mismo prefijo

Nuevo `chat_lateral(instrucciones, …)`: manda **el mismo system y las mismas tools** que la
conversación y pone la tarea en el mensaje de usuario («tarea interna, responde solo con texto»).
Reutiliza la caché y no la destruye. Si el modelo devuelve una `tool_call` o nada, se repite sin
tools (comportamiento actual) como respaldo.

Alternativa descartada: `OLLAMA_NUM_PARALLEL=2` (una segunda ranura) cuesta ~0,75 GB de VRAM con
`num_ctx=10240`.

### 3.4 Precalentar mientras Alberto habla

`precalentar()`: petición con el prefijo real y `num_predict: 1`. Se lanza en segundo plano:
al arrancar el daemon y **en `fire()`** (atajo o palabra de activación), en paralelo con la
escucha. Para cuando acaba la transcripción, el modelo está cargado y el prefijo en caché.
Con limitador (máx. una vez cada 30 s). Opcional: `[llm] keep_alive` en `config.toml` se pasa en
cada petición (p. ej. `"60m"`).

### 3.5 Atajos sin LLM (fast-path)

`laura/rapido.py`: patrones anclados (frase completa, tras quitar muletillas) para las órdenes
más frecuentes y sin ambigüedad: pausa/reanudar, siguiente, anterior, parar música, subir/bajar
volumen (con o sin número), silenciar, subir/bajar brillo, qué hora es, bloquear pantalla,
captura. Ejecuta la tool directamente (~0 ms de LLM) y añade el turno al historial para que el
contexto siga siendo coherente. Cualquier frase compuesta («pausa y abre Google») o con matices
(«baja el volumen **al** 20») cae al LLM. Un test cruza los patrones con `eval/frases.toml`:
toda frase del examen que el atajo capture debe dar la misma tool y argumentos que espera el
examen.

### 3.6 Esquemas y system prompt más cortos

Objetivo: de ~7.700 a **≤ 5.500 tokens** sin bajar el examen. Reglas:

1. Cada regla de enrutado «frase → tool» vive en **un solo sitio**: la descripción de la tool. Se
   borra del system prompt.
2. Descripciones en estilo telegráfico; nada de repetir lo que ya dice un `enum`.
3. `description` de parámetros solo cuando el nombre no basta.
4. Puerta: el examen no baja más de 2 puntos en herramientas y sigue con 0 falsos positivos.

### 3.7 Historial más ligero

Al cerrar un turno, los mensajes `tool` de ese turno se reducen a las claves útiles para turnos
posteriores (`ok`, `resumen`, `decir`, `error`, `candidatos`, `pregunta`). Dentro del turno el
modelo ve el resultado completo.

### 3.8 Registro de interacciones (semilla del ajuste fino)

`laura/registro.py` añade una línea JSONL por turno a `~/.local/share/laura/interacciones.jsonl`
(local, fuera del repo): fecha, texto transcrito, tools llamadas con argumentos, respuesta,
vía (`rapido`/`llm`), latencias. Es el material para el dataset real del ajuste fino (§5) y
para encontrar frases que fallan. Nunca sale del ordenador.

## 4. Diseño — Fase 2: muchas más tools sin más VRAM

### 4.1 Qué cuesta VRAM

La VRAM la pone la ventana de contexto (`num_ctx`), no el número de tools. Con KV en q8, Qwen3-4B
gasta ~74 KB por token (36 capas × 8 cabezas KV × 128 × K+V × 1 B):

| `num_ctx` | caché KV aprox. |
|---|---|
| 4.096 | 0,30 GB |
| 6.144 | 0,45 GB |
| 10.240 (hoy) | 0,75 GB |

Con todas las tools en el prompt, cada tool nueva empuja `num_ctx` hacia arriba. Con
recuperación, `num_ctx` se queda fijo aunque haya 200 tools.

### 4.2 Recuperador de tools

- **Núcleo fijo** (`siempre=True` en el decorador, ~12 tools de uso diario y las de
  enrutado/escalada) en orden estable → prefijo cacheable.
- **Recuperadas**: las `k` (6 por defecto) más parecidas a la frase, añadidas **al final**. Solo ese
  tramo final (~1-2 k tokens) se reprocesa: ~0,4-0,8 s. Por eso no es más rápido que la Fase 1
  con todas las tools en caché; lo que gana es **escala** (y VRAM si se baja `num_ctx`).
- Índice: embeddings de **frases de ejemplo por tool** (no solo de la descripción; es la técnica
  que mejor funciona en la literatura, «Tool2Vec»). Las frases salen de las plantillas de
  `finetune/gen_dataset.py` + ejemplos escritos a mano para las tools que no tengan.
  `eval/frases.toml` **no** entra en el índice: se usa para medir el recuperador.
- Modelo: `intfloat/multilingual-e5-small` (118 M parámetros, 384 dims) en **CPU** con
  `transformers` (ya en el venv). ~10-20 ms por frase en los 16 hilos. Índice cacheado en
  `~/.local/share/laura/tools_index.npz`, invalidado por hash de esquemas + ejemplos.
- Puntuación de una tool = máxima similitud entre la frase y sus ejemplos.
- Activable: `[tools] modo = "todas" | "recuperar"`. Por defecto `"todas"` hasta que el examen
  diga que `"recuperar"` no empeora. Puerta: **recall@k ≥ 98 %** sobre `eval/frases.toml` (la
  tool esperada está entre el núcleo + las k recuperadas).
- Las tools con `cuando=` (archivos) siguen igual.

### 4.3 Otros recursos para escalar (no en este plan)

- **Fusionar tools afines en una con `accion` enum** (como ya hace `spotify`):
  `luces`+`teclado_color`+`brillo` → `iluminacion`; `volumen`+`silenciar`+`control_musica` →
  `audio`; `wifi`+`bluetooth`+`bateria` → `estado_sistema`. Un enum cuesta pocos tokens. Romper
  esto exige rehacer frases del examen y del dataset, así que va con el ajuste fino v2.
- **Tools que delegan**: lo pesado (Workspace, Drive, investigación) cuesta una línea de esquema
  y se ejecuta fuera (Aurora en la Pi, Gemini, Claude, servidores MCP). 0 VRAM local.
- **Intercambio de modelos bajo demanda**: descargar el LLM, cargar un VLM pequeño (~2 B) para
  «¿qué es esto en pantalla?», y volver. ~4 s; aceptable para algo ocasional.
- **KV en `q4_0`**: otra mitad de VRAM de contexto; pasar el examen antes.
- **Modelo mayor**: con recuperación y `num_ctx` 4-6 k podría caber un 7-8 B en Q4. Ojo: el
  examen dio peor a `qwen2.5:7b` (54 %); probar familias recientes antes de decidir.

## 5. Ajuste fino: qué es y qué esperar

**Sí: ajuste fino = cambiar los pesos.** Con LoRA no se reescriben los 4.000 M de pesos: se
entrenan unas matrices pequeñas (decenas de MB) que se suman a las capas, y luego se fusionan en
un GGUF nuevo (`laura-qwen3:4b`). Entrenar un modelo **desde cero** no es viable (billones de
tokens y miles de GPUs); ajustar uno existente sí, y en la 4050 cabe con QLoRA
(`finetune/soup.yaml`).

**La intuición de Alberto es correcta en lo esencial**, con matices:

| Lo que se gana de verdad | Lo que NO conviene meterle en los pesos |
|---|---|
| Elegir la tool correcta en frases coloquiales y con errores de Whisper | Hechos que cambian: tareas, archivos, correos, estado de proyectos. Se quedan viejos y el modelo los «recordaría» mal con total seguridad (alucinación). Eso va por tools y memoria. |
| Argumentos bien puestos, dobles acciones, escalar en vez de «no puedo» | Conocimiento general nuevo: el LoRA aprende *forma* mucho mejor que *datos*. |
| **Prompt mucho más corto**: si ha aprendido las tools, las descripciones pueden ser de una línea y el system prompt de tres. Menos tokens = menos prefill y menos VRAM. | |
| Tono y longitud de respuesta de Laura | |

Sobre «fallaría más con Harry Potter»: con LoRA de rango bajo (r=16) y mezclando algo de charla
general en el dataset (ya lo hace `gen_dataset.py`: ~320 negativos sin tool), la pérdida de
cultura general es pequeña. El riesgo real no es ese, sino **sobreajustar**: que vea una tool en
todo. Se controla con el grupo `trampa` del examen (hoy 0/18 falsos positivos).

«Triple de eficiente» en tareas del ordenador es razonable en **fiabilidad** (de ~90 % hacia
97-99 % en el examen) y en **coste de contexto** (de ~7,7 k tokens a 2-3 k). No será el triple
de rápido generando: la velocidad de generación la pone el tamaño del modelo, no el ajuste.

### 5.1 Ajuste fino v2 (plan aparte, tras las Fases 1-2)

El material de `finetune/` está desfasado (se generó con 42 tools; hoy hay 56). La v2:

1. Regenerar con las tools y descripciones **compactadas** (§3.6) y con el `<contexto>` en el
   mensaje de usuario (§3.1), para entrenar exactamente el formato que se usa en producción.
2. **Entrenar con listas de tools variables** (núcleo + recuperadas + distractores, en orden
   variable): así el modelo aprende a usar *las tools que le den*, y una tool nueva funciona sin
   reentrenar. Es lo que permite combinar ajuste fino y recuperador.
3. Añadir **frases reales** de `interacciones.jsonl` (§3.8), corregidas a mano cuando la tool fue
   la equivocada (bucle de datos: cuanto más se usa, mejor dataset).
4. Generar variantes con un modelo grande (Claude/Gemini) a partir de las reales («destilación»).
5. Adoptar solo si supera el criterio de `finetune/README.md` también en las 22 frases held-out.

Opcional después: un **router diminuto** (Qwen3-0.6B/1.7B ajustado) que decide la tool en
~50 ms y deja el 4B solo para conversar y para lo ambiguo.

## 6. Brainstorming — cosas que añadirle

Ya existen y no se repiten: `novedades`, `leer_pantalla`, `ventanas_abiertas`, holo de archivos,
warp, tele, Spotify, DJ, vigía, escaladas.

**Contexto y memoria**
- *«¿Qué hice ayer por la tarde?»*: registro de la ventana activa y su título por intervalos
  (Hyprland IPC) en SQLite; Laura lo resume.
- **Memoria de conversaciones**: resumen corto de cada sesión con embeddings (el mismo modelo del
  recuperador) → «¿qué te dije del viaje?».
- **Reconocer la voz de Alberto** (huella de voz en CPU) para que otra persona no pueda dar
  órdenes; encaja con la palabra de activación.

**Rutinas y escritorio**
- **Macros enseñadas por voz**: «Laura, aprende: *modo estudio* es abrir X, luces en blanco y no
  molestar». Se guardan como secuencia de tool_calls y se ejecutan por el fast-path, sin LLM.
- **Hyprland**: «pon esto a la izquierda», «manda Spotify al workspace 4», guardar y restaurar
  distribuciones de ventanas.
- **Escenas** (cine, juego, dormir) que combinan luces, tele, notificaciones y teclado (backlog:
  «Escenas de 1 clic», «Modo Cine»).
- **Pomodoro por voz** con la tira LED y el teclado como indicador de progreso.
- Al entrar en **modo juego**, descargar el LLM de la VRAM y volver a cargarlo al salir.

**Ecosistema de Alberto**
- **Gym-hub**: «¿qué me toca hoy?» (la API actual es de solo lectura; apuntar series por voz
  necesitaría acceso de escritura).
- **Universidad**: próximas entregas desde el repo `Universidad` + calendario.
- **Git y agentes**: «¿qué hay sin commitear?», «resúmeme lo que hizo Claude hoy» (git log),
  «¿en qué está Gemini?».
- **Baterías de periféricos** (`mchose-battery`) con aviso por voz al bajar del umbral.

**Pequeñas y útiles**
- **Calculadora y conversor de unidades exacto** (Python seguro): un 4B se equivoca en cuentas.
- **Briefing matinal** con el primer «Laura despierta» del día: tiempo, agenda, tareas y correo
  importante (el vigía ya tiene casi todo).
- **Dictado largo a una nota de Obsidian** («apunta en el diario…»).

## 7. Fuera de alcance

Cambiar de motor de inferencia (llama.cpp server, vLLM), STT en streaming, voz nueva, y el
ajuste fino v2 en sí (plan propio cuando acaben las Fases 1-2).

## 8. Referencias

- [Semantic Tool Discovery for LLMs (arXiv 2603.20313)](https://arxiv.org/html/2603.20313v1) — top-3 ≈ 97 % de acierto y −99 % de tokens de tools.
- [Tool RAG — Red Hat](https://next.redhat.com/2025/11/26/tool-rag-the-next-breakthrough-in-scalable-ai-agents/) — RAG-MCP y Tool2Vec (embeddings de frases de uso).
- [ScaleMCP (arXiv 2505.06416)](https://arxiv.org/html/2505.06416v1) — el agente pide tools durante la conversación.
- `assistant/finetune/README.md`, `assistant/eval/README.md` — dataset, criterio de adopción y examen.
