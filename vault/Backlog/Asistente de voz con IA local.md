---
fileClass: Backlog
tipo: tarea
estado: en-curso
area: agentes
origen: Alberto
esfuerzo: L
creado: 2026-09-01
flujo: "[[Asistente de voz con IA local]]"
tags:
  - backlog
---

# Asistente de voz con IA local

Un **asistente de IA local**, integrado con el ecosistema del escritorio (Quickshell /
Caelestia, paleta matugen, sistema de notificaciones de agentes). Se activa con un
**atajo de teclado**, escucha y responde **por voz** (STT + TTS locales), muestra una
**animación reactiva minimalista** (círculo futurista que late con la voz) y puede
**ejecutar acciones en el ordenador**, no solo conversar.

> [!info] Estado — **v1 en curso** (rama `feat/aurora-voice-assistant`)
> Fase 0 hecha. Fases 1-3 formalizadas en `assistant/` (daemon `aurorad.py` +
> `tools.py` + `config.toml` + `aurora-toggle` + `aurora.service`). Bucle completo:
> atajo → VAD → Whisper (CPU) → Qwen3-4B con tool-calling → acciones → Kokoro
> `ef_dora` + efecto "jarvis". **Servicio systemd `--user` instalado y activo**
> (autoarranca en login). **Pendiente:** Alberto ata el atajo de Hyprland y prueba
> con el micro. Siguiente: fase 4 (más acciones + n8n + memoria).
>
> ⚠️ **RAM: el daemon ocupa ~3 GB** cargado (torch + Whisper + Kokoro + silero) — en
> una máquina de 15 GB es mucho para tenerlo siempre. **Optimización recomendada
> (fase 7, adelantar):** carga perezosa de modelos + descarga tras inactividad → el
> daemon en reposo baja a ~150 MB y recarga en ~10-15 s al primer uso. Alternativa
> más agresiva: pasar Kokoro y silero a ONNX y quitar torch del todo (~-1,5 GB).
>
> El plan (§4) reparte el trabajo: **Alberto** hace instalaciones y configuración,
> **un agente** hace toda la programación. Esta nota es la fuente única del estudio.

---

## 1. Restricción de hardware

GPU **RTX 2060 6 GB** (Turing: Tensor Cores, FP16/INT8 acelerados, ~336 GB/s de ancho de
banda). El límite sigue siendo **6 GB de VRAM**, pero el cómputo da de sobra: un 7B en Q4
va a ~30-40 tok/s y faster-whisper en `float16` vuela. Todo lo que se pueda, local.
Presupuesto de VRAM si STT y LLM conviven cargados a la vez:

| Componente | Opción elegida                   | VRAM aprox.                               |
| ---------- | -------------------------------- | ----------------------------------------- |
| STT        | faster-whisper `small` int8      | 0,5 – 1 GB (nominal)                      |
| LLM        | Qwen3-4B-Instruct Q4_K_M, ctx 4k | 3,2 GB (medido con `ollama ps`)            |
| TTS        | Kokoro-82M (corre en CPU)        | ~0 GB                                     |
| **Total**  |                                  | **~4 – 4,5 GB** → deja 1,5 GB de margen ✅ |

> [!bug] Probado en real (2026-09-01): Whisper en GPU **no es fiable** aquí
> Con el LLM cargado quedan libres solo **~1,9 GiB** (medido, no ~1,5 GB teórico). El
> presupuesto "nominal" de Whisper (0,5-1 GB) no cuenta el *overhead* de un **segundo
> contexto CUDA** (proceso Python aparte del de Ollama), que ronda 300-600 MB extra. En
> la prueba de extremo a extremo (`/tmp/talk.py`) Whisper-GPU aguantó 4 turnos y reventó
> con `CUDA out of memory` en el 5º. **Decisión: Whisper corre en CPU**, no en GPU, en
> esta máquina — la latencia extra es asumible para frases cortas y es fiable.

Con un LLM de 7-8B en Q4 (~5 – 5,5 GB) **no caben LLM + Whisper a la vez en VRAM**: habría
que descargar Whisper entre turnos (añade latencia) o correr Whisper en CPU. Por eso el
primario es un 4B; el 7-8B queda como "modo calidad" opcional. En la RTX 2060 correr
Whisper en CPU es asumible y la velocidad del 7B ya no es problema, así que un
**Qwen2.5-Coder-7B / Qwen3-8B siempre cargado** es más viable que en una 1060.

---

## 2. Componentes: decisión, motivo y plan B

### 2.1 LLM local

- **Elegido: Qwen3-4B-Instruct (Q4_K_M) vía Ollama.**
  - Mejor tool-calling del tramo sub-7B a principios de 2026; modo *thinking* opcional
    para tareas que necesitan razonar. Cabe holgado junto a Whisper. Multilingüe sólido
    en español. Ollama da API de *tools*, cambio de modelo en caliente y arranque por
    systemd.
- **Alternativa fuerte: NousResearch Hermes (3B ó 8B).** Familia *fine-tuned* de Llama
  3.1 especializada en *function calling* y salida estructurada (formato `<tool_call>`),
  muy "dirigible" y poco censurada — buena si se quiere una personalidad marcada para el
  asistente. Hermes-3B cabe cómodo; Hermes-8B compite con Llama-3.1-8B en VRAM (malabares
  con Whisper). Se queda como plan B por debajo de Qwen3-4B solo porque este último
  puntúa mejor en *tool use* en el tramo pequeño; si en pruebas reales Hermes obedece
  mejor las herramientas, se promociona.
- **Modo calidad (local, opcional): Qwen2.5-Coder-7B ó Qwen3-8B Q4**, descargando Whisper
  entre turnos. Para respuestas más largas / programación (ver §5).
- **Descartados:**
  - *Llama 3 / 3.1 8B Q4* como primario: ~5,5 GB, no convive con Whisper; sin ventaja
    clara sobre Qwen3 en tool use.
  - *Gemma 2 9B*: no cabe en Q4 con contexto útil.
  - *Phi-4-mini*: correcto, pero por detrás de Qwen3-4B en *function calling*.
  - Modelos < 3B (Llama 3.2 3B, Qwen 1.5B): rápidos pero flojos siguiendo herramientas.
- **Plan B online:** API de Claude (Haiku para barato/rápido, Sonnet para difícil) ó
  GPT-4o-mini. Se activa con un *toggle* "modo potente" en config o por detección de
  intención (tarea larga, contexto grande, código). Claves en `config.toml`.

### 2.2 STT (voz → texto)

- **Elegido: faster-whisper (CTranslate2), modelo `small`, `int8`, en `device="cpu"`**
  (probado: en GPU revienta por OOM tras varios turnos junto al LLM — ver §1), idioma
  `es`. Segmentación con **Silero VAD** (detecta cuándo empiezas y acabas de hablar).
  Subir a `medium` solo si la precisión en español no basta (ojo: aún más lento en CPU).
- **Alternativas:** *whisper.cpp* (buena, un poco más lenta en GPU NVIDIA que CT2);
  *distil-whisper* (rápido, peor en español que en inglés); *Vosk* (ligerísimo, precisión
  muy inferior — descartado).
- **Sin wake word:** la activación es por atajo de teclado, así que no hace falta
  openWakeWord. Se puede añadir después.
- **Plan B online:** Whisper vía API de Groq (muy rápido y barato) u OpenAI; Deepgram
  para *streaming* real.

### 2.3 TTS (texto → voz)

> [!success] Voz decidida (2026-09-01)
> **Kokoro-82M, voz `ef_dora` (femenina), con la cadena de efectos "JARVIS", corriendo
> en CPU.** Alberto no quería una voz hiperrealista sino sintética/robótica tipo JARVIS
> o la IA de Subnautica; con `ef_dora` + efecto queda bien. Acento neutro con deje
> latino (Kokoro no tiene voces `es_ES`) — aceptado, el efecto lo disimula.
>
> ```
> Motor:  Kokoro-82M, lang_code="e", voice="ef_dora"
> Efecto: ffmpeg -af "highpass=f=200,lowpass=f=3800,chorus=0.5:0.9:50:0.4:0.25:2,
>                      aecho=0.85:0.75:35:0.2,volume=2"   (cadena "jarvis")
> ```
>
> **Cambiar de voz más adelante es trivial:** en el daemon (fase 3), la voz de Kokoro y
> la cadena de efectos son **dos valores de `config.toml`** (`voz` y `efecto`), no código
> — cambiarlos no toca el daemon. Kokoro trae ~54 voces (`em_alex`, `em_santa`, inglesas,
> etc., incluso mezclables entre sí) y las cadenas de efecto de este documento (`jarvis`,
> `subnautica`, `robot`, `dry`) quedan ya escritas en `/tmp/tts_lab.py` para reusar. Piper
> y eSpeak NG se quedan documentados arriba como alternativas si el acento castellano
> real importase más que el timbre.

- **Elegido para empezar: Piper (rhasspy/piper), voz `es_ES` / `es_MX`.** Primer audio en
  ~40 ms, corre en CPU (no gasta VRAM), factor tiempo-real ~0,03 → latencia mínima, que
  es lo que hace que un asistente se sienta vivo. La voz base va **post-procesada** para
  el efecto robótico (ver nota de arriba). El repo se archivó en oct-2025 pero el modelo
  y el binario (`piper-tts`) siguen funcionando.
- **Mejora de calidad: Kokoro-82M (v1.0+).** 82M parámetros, calidad claramente superior
  a Piper, muy rápido (< 0,3 s por frase), con **voces en español** (europeo y
  latino). Se ofrece como *toggle* "voz bonita" una vez el bucle básico funcione.
  *Verificar en pruebas la naturalidad real de las voces `es`.*
- **Descartado como base: XTTS-v2 (Coqui).** Clonación de voz excelente desde ~6 s de
  muestra, 17 idiomas, pero ~600 ms al primer audio + más VRAM → se suma a STT y LLM y
  rompe la sensación de conversación. Solo si algún día se quiere *clonar una voz
  concreta*.
  - *Nota:* Alberto preguntó si se podría clonar una voz real y conocida (p.ej. la de su
    novia) en vez de una sintética. Técnicamente sí — XTTS-v2 clona desde clips reales,
    cuantos más minutos de audio limpio mejor calidad (los ~6 s mínimos dan resultados
    mediocres). Sigue chocando con el mismo problema de VRAM/latencia de arriba, y
    requiere el consentimiento de la persona cuya voz se clona — es su voz saliendo del
    ordenador de Alberto, no un efecto cualquiera. Aparcado, no descartado del todo.
- **Plan B online:** ElevenLabs Flash ó OpenAI TTS (voz premium, latencia baja).

**Kokoro probado (2026-09-01): a Alberto le convence** — voz `ef_dora` (femenina) +
cadena de efectos JARVIS/Subnautica. Acento: **neutro con deje latino, no castellano**
(Kokoro no tiene voces `es_ES`; para castellano real solo Piper). Kokoro corre en
**CPU** (no en GPU: compite por los ~1,5-2 GiB libres que dejan LLM+Whisper).

#### Rendimiento e impacto real por opción (RTX 2060, con Qwen3-4B + Whisper cargados)

| Opción | Dónde corre | VRAM extra | Latencia por frase | Impacto real |
|---|---|---|---|---|
| Piper | CPU | 0 | ~40-80 ms | Nulo — ni se nota. |
| eSpeak NG | CPU | 0 | <10 ms | Nulo. |
| **Kokoro (CPU)** | CPU | 0 | ~0,2-0,5 s | Pequeño; se diluye con *streaming* por frases (fase 3). |
| Kokoro (GPU) | GPU | ~0,5-1 GiB | ~0,05-0,1 s | Más rápido pero **no cabe** con LLM+Whisper ya cargados en 6 GB — descartado. |
| XTTS-v2 | GPU | ~2 GiB | ~0,5-0,8 s | No cabe en 6 GB junto a LLM+Whisper — solo viable descargando algo entre turnos. |
| **Online (ElevenLabs/OpenAI/Azure)** | Nube | 0 | ~0,15-0,4 s (red incluida) | Cero coste de VRAM/CPU; mejora clara de naturalidad y da **castellano real** + voces de IA ya diseñadas. Coste: ver abajo. Requiere internet y el texto de cada respuesta sale de casa. |

**Conclusión de rendimiento:** en local, Piper/eSpeak son gratis en todo sentido;
Kokoro en CPU añade una latencia pequeña y asumible. Lo online no mejora el
rendimiento del PC (ya es irrelevante) — mejora **naturalidad y acento**, a cambio de
depender de internet y (según volumen) de pagar.

#### ¿Las voces online son de pago?

| Servicio | Gratis | Pago | Nota |
|---|---|---|---|
| **Azure TTS** | 500.000 caracteres/mes gratis (voces neuronales) | ~$16 / millón de caracteres tras eso | Mejor relación calidad/precio y **tiene castellano** `es-ES` de verdad. |
| **Google Cloud TTS** | ~1.000.000 caract./mes gratis (estándar) | Similar a Azure tras el límite | También `es-ES`. |
| **OpenAI TTS** | Sin capa gratis | ~$15 / millón de caracteres | Muy sencillo de integrar, sin acento castellano específico. |
| **ElevenLabs** | ~10.000 créditos/mes (~10 min de audio) | Desde $5/mes (Starter, ~30 min) | La mejor calidad y las voces de IA/robóticas "de diseñador" ya hechas — pero el nivel gratis se agota rápido con uso diario. |

Para un asistente de uso diario (decenas de respuestas cortas al día), el volumen de
texto suele caber en los niveles gratis de **Azure o Google**; **ElevenLabs** es la
mejor opción de timbre pero previsiblemente de pago si se usa a diario.
**Recomendación si se activa el *fallback* de voz:** Azure o Google como
*default* (gratis, castellano real), ElevenLabs como *opcional* de lujo.

### 2.4 Orquestación y ejecución de acciones

- **Elegido: daemon propio en Python (`assistantd`) usando el *tool calling* nativo de
  Ollama.** Un registro de herramientas = funciones Python en lista blanca que envuelven
  comandos del sistema (`playerctl`, `brightnessctl`, `hyprctl`, `notify-send`, lanzar
  apps, portapapeles con `wl-clipboard`, captura con `grim`, búsqueda de archivos,
  gestión de ventanas). **Puerta de confirmación** para acciones destructivas o ambiguas
  ("¿borro estos 3 archivos?"). Control total sobre el bucle de voz y la latencia.
- **Exponer las herramientas como servidor MCP (fase posterior):** así las reutilizan
  otros agentes (Claude Code, el agente del gestor de arranque) y el asistente se vuelve
  un cliente MCP más.
- **Descartados como núcleo:**
  - *Open Interpreter*: deja al LLM ejecutar **código arbitrario** (Python/shell) en la
    máquina real → demasiado riesgo para los dotfiles y el sistema; además pesa. Útil
    como inspiración y quizá como herramienta acotada y sandboxed más adelante.
  - *Goose* (Agentic AI Foundation): buen cliente MCP y agente de escritorio, pero da
    menos control sobre el pipeline de voz y la máquina de estados visual. Alternativa
    válida si no queremos mantener daemon propio.
  - *Hermes Agent* (Nous Research): agente "auto-mejorable" con bucle de creación de
    *skills* y 6 backends de ejecución. Interesante para la parte de "aprender tareas
    nuevas", pero es un marco grande y opinado; se evalúa en fase 6 como capa opcional,
    no como base.
  - *LangChain / LlamaIndex*: sobra peso para lo que necesitamos.

### 2.5 Animación reactiva

> [!success] Diseño decidido (2026-09-01) — mockups en canvas
> `assistant/design/aurora-overlay.html` (canvas de Claude Design). **Dos modos, dos
> disparadores:**
> - **Modo centro — orbe líquido.** Círculo grande en el centro de la pantalla al
>   activar Aurora. Esfera con brillo y degradado (rosa primario + lavanda) que ondula
>   y respira. Estados: reposo (orbe pequeño, respira lento) · escuchando (crece y
>   ondula con la voz) · pensando (halo que gira) · hablando (anillos que emanan) +
>   bocadillo de respuesta breve. Se hará con `ShaderEffect` GLSL.
> - **Modo barra — "punto con cordón".** La barra de Caelestia es **vertical, a la
>   izquierda**. En reposo, Aurora es un **punto** anclado a la barra. Al activarla,
>   el punto **se despega en un cordón fino** (que nunca se corta — de ahí la "fusión
>   sin ventana") y se convierte en una **gota que se deforma con la voz**.
>   *Pensando:* la gota se calma y un aro gira a su alrededor. *Resultado:* la gota se
>   "deshace" hacia abajo en un **tallo con una pastilla por acción** colgando (icono +
>   texto corto); al terminar todo se recoge en el punto. Color = accent dinámico del
>   theming. Para invocación rápida y ligera, sin la experiencia a pantalla completa.
>   *(Descartadas: "lóbulo" —la barra se hincha— y "halo + brote".)*

- **Implementación: overlay QML en Quickshell**, módulo nuevo `modules/assistant/`.
  Modo centro = ventana `WlrLayershell` sin marco, transparente, centrada, *click-through*
  salvo al interactuar; el orbe es un `ShaderEffect` con *fragment shader* GLSL
  controlado por *uniforms*: `amplitude` (RMS del audio), `state` (idle / listening /
  thinking / speaking) y `accent` (paleta matugen). Modo barra = entrada en la barra +
  popout propio (aprovechar `BarPopouts.Wrapper`). La amplitud y el estado llegan por
  el socket de eventos del daemon (que hay que añadir en la fase 1).
- **Integración de tema:** reutilizar los *singletons* `Appearance` / `Colours` de
  Caelestia. El know-how de visualización de audio ya existe en el ecosistema
  ([[Pulsación rítmica CAVA en la tira LED]]).
- **Fallback simple (sin shader):** `Shape` / `Canvas` con `RadialGradient` animado y
  `SequentialAnimation` por estado. Menos vistoso, cero riesgo de shaders.
- **Descartado:** overlay web (Electron/navegador) o GTK layer-shell propio — Quickshell
  ya está montado y tematizado; añadir otro stack visual es deuda.

### 2.6 Integraciones externas (calendario, tareas…) y memoria

> [!question] Preguntas de Alberto (2026-09-01): ¿memoria local? ¿conectar a Internet
> para calendario/tareas? ¿sirve n8n para esto?

- **Sí a ambas, y van por caminos distintos:**
  - **Acciones del propio ordenador** (subir volumen, brillo, cambiar de ventana,
    captura…) → siguen siendo **tools de Python directas** en el daemon (§2.4): rápidas,
    sin red, sin nada que mantener.
  - **Integraciones con servicios externos** (Google Calendar, Google Tasks y similares)
    → **elegido: n8n como capa de integración**, no reimplementar cada API a mano.
    n8n se auto-aloja (Docker, ligero), tiene nodos ya hechos para Calendar/Tasks/Todoist/
    Notion/email con su propio OAuth, y expone **webhooks**. La *tool* del asistente para
    "apúntame una cita" es entonces solo *"haz un POST a este webhook con estos
    campos"* — nada de escribir un cliente OAuth por servicio. Ventaja extra: los
    workflows de n8n se editan en su **editor visual**, así que Alberto puede crear o
    tocar una integración nueva él mismo sin que sea "programar" en el sentido estricto
    (encaja con el reparto de trabajo de §4). Contras: un servicio más corriendo (RAM
    modesta) y un salto de red de más (insignificante en `localhost`).
  - **Alternativa descartada como base:** llamar a las APIs de Google directamente desde
    el daemon Python. Funciona, pero cada integración nueva = escribir y mantener su
    propio cliente OAuth — n8n ya lo resuelve una vez por servicio con su UI.
- **Memoria local:** dos capas distintas, ninguna necesita agrandar el contexto del LLM:
  - **Historial de la conversación en curso** — ya existe (lista de mensajes en RAM,
    como en `/tmp/talk.py`), se pierde al reiniciar el daemon salvo que se persista.
  - **Hechos que Alberto pide recordar** ("acuérdate de que no como pescado") → una
    tabla **SQLite** sencilla (hecho + fecha), sin vector DB — a esta escala (asistente
    personal) sobra la complejidad de un almacén vectorial; basta con inyectar los
    hechos relevantes al *prompt* cuando hagan falta (coincidencia de palabras clave es
    suficiente). Tool nueva: `recordar(hecho)` / `qué recuerdas de X`.
- **Internet, en general:** el daemon no necesita "estar conectado" de forma
  permanente — solo hace una petición HTTP puntual cuando una *tool* concreta la
  necesita (webhook de n8n, o el *fallback* online de §2.1/§2.3). El LLM y el STT/TTS
  siguen 100% locales.

### 2.7 Activación por voz ("Aurora", en vez de solo el atajo)

> [!question] Pregunta de Alberto: ¿se puede activar diciendo "Aurora" en vez de tener
> que pulsar el atajo, sin que el micro esté escuchando (y transcribiendo) todo el rato?

Sí, existe la pieza exacta para esto: **openWakeWord**. Es un modelo diminuto
especializado en **solo detectar una palabra**, nada de transcribir — corre en CPU con
un consumo mínimo (no es Whisper escuchando de fondo, que sí sería caro y invasivo). El
micro está siempre "abierto" para ese modelo tan ligero, pero el pipeline pesado
(Whisper + LLM + Kokoro) solo arranca cuando detecta la palabra.

- **La pega:** los modelos ya entrenados de openWakeWord son para otras palabras ("hey
  jarvis", "alexa"…). Para "Aurora" hace falta **entrenar uno propio**, con un proceso
  ya documentado por el proyecto: generar cientos de muestras *sintéticas* de la palabra
  con un TTS (`piper-sample-generator`) en vez de grabarse a sí mismo repitiendo
  "Aurora" cientos de veces, y entrenar un modelo pequeño con eso. Es un trabajo real
  pero acotado y ya resuelto por otros — no investigación desde cero.
- **Recomendación de orden:** el atajo de teclado (ya funciona, cero falsos positivos,
  cero preocupación de privacidad) se queda como **disparador de la v1**. El wake word
  "Aurora" es un añadido de **fase posterior** (encaja con la fase 5 de abajo), no
  bloquea nada de lo demás — el daemon simplemente gana un segundo disparador además
  del atajo.

---

## 3. Arquitectura general

```
[Atajo Hyprland]
      │  bind → script → mensaje IPC (socat / D-Bus)
      ▼
┌─────────────────────────  assistantd (Python, systemd --user)  ─────────────────────────┐
│                                                                                         │
│  Audio in (PipeWire/sounddevice) → Silero VAD → faster-whisper ──► texto                │
│                                                                     │                   │
│                                          Gestor de conversación ◄───┘                   │
│                                                     │                                   │
│                                     Ollama (Qwen3-4B + esquema de tools)                │
│                                          │                    │                         │
│                              respuesta texto          llamada(s) a tool                 │
│                                          │                    │                         │
│                                          │        Ejecutor (lista blanca + confirmación)│
│                                          ▼                                              │
│                              Piper / Kokoro → audio out (PipeWire, agacha otros audios) │
│                                                                                         │
│  Bus de eventos → socket  $XDG_RUNTIME_DIR/assistantd.sock  (JSON por líneas)           │
│     {state, amplitude, transcript, response}                                            │
└───────────────────────────────────────────┬─────────────────────────────────────────────┘
                                            ▼
                         Quickshell  modules/assistant/  (suscrito al socket)
                         → shader del círculo reactivo + captions opcionales
                         → usa paleta matugen (Colours singleton)
```

- **Config:** `~/.config/assistantd/config.toml` — modelos, claves de fallback online,
  lista blanca de acciones, idioma, voz.
- **IPC:** un socket Unix con JSON por líneas (simple, sin dependencias). D-Bus como
  alternativa si otros agentes necesitan hablar con él.
- **Identidad visual del agente:** color de acento y avatar propios, igual que el
  [[Agente IA para el gestor de arranque dual-boot]], para distinguirlo del resto.

> [!note] Referencia "Bolt / CDNs"
> Alberto mencionó "Bolt" y "CDNs" como parte del setup conocido. Interpretado aquí como
> el stack visual del ecosistema = **Quickshell + Caelestia + matugen**. Confirmar con
> Alberto si "Bolt" es un componente concreto que deba integrarse.

---

## 4. Plan de implementación por fases (no implementar aún)

> [!important] Reparto de trabajo (para minimizar tokens de agente)
> - **Alberto hace:** instalar paquetes y herramientas (Ollama, modelos, librerías
>   Python, dependencias del sistema), descargar voces/modelos, editar archivos de
>   configuración (atajo de Hyprland, `config.toml`, habilitar el servicio systemd) y
>   **todas las pruebas**.
> - **Agente hace:** todo lo que sea programar — el daemon Python, el ejecutor de
>   acciones, el módulo QML y el shader, el IPC, el *streaming* y el *barge-in*.
>
> Cada fase de abajo marca sus pasos con **[A]** (Alberto) o **[Ag]** (agente).

**Fase 0 · Preparación del entorno — [A] · ✅ HECHA (2026-09-01)**

Arch tiene el Python del sistema *externally-managed* (PEP 668): las librerías del
asistente van en un **venv dedicado**, nunca con `pip` global ni `--break-system-packages`.

Estado verificado:

| Pieza | Estado |
|---|---|
| Ollama | ✅ v0.33.2 (script oficial, `/usr/local/bin`), servicio activo. **No** instalar `ollama-cuda` de pacman. |
| Modelo LLM | ✅ `qwen3:4b-instruct` (2,5 GB). `ollama ps` → **100% GPU**, ctx 4096, ~3,2 GB. Inferencia OK. |
| GPU | ✅ RTX 2060, CUDA compute 7.5. Con el 4B cargado se usan ~4,2/6 GiB → queda sitio para Whisper `small`. |
| venv `~/LinuxRicing/assistant/.venv` | ⚠️ **rehacer con Python 3.12** — ver abajo. |
| Piper | ✅ instalado como **`piper-tts`** (AUR `piper-tts-bin`), no como `piper`. Voz `es_ES-davefx-medium` descargada; `es_ES-sharvard-medium` es 2 locutores (0 = M, 1 = F). Piper convence poco → probando Kokoro. |
| Utilidades sistema | ✅ `playerctl`, `brightnessctl`, `grim`, `wl-copy`, `nvidia-smi`, `espeak-ng`, `uv`. |

> [!warning] El Python del sistema es 3.14 — rompe el TTS
> CachyOS ya trae **Python 3.14** como `/usr/bin/python`. `faster-whisper` y `torch`
> funcionan, pero **Kokoro** (vía `misaki[en]` → `spacy`/`thinc`/`blis`) no tiene wheels
> para 3.14 y falla al compilar. Solución: fijar el venv a **Python 3.12** con `uv`
> (descarga un CPython 3.12 *standalone* solo, no toca el sistema):
> ```fish
> cd ~/LinuxRicing/assistant
> rm -rf .venv
> uv venv --python 3.12
> uv pip install faster-whisper silero-vad sounddevice soundfile kokoro nvidia-cudnn-cu12 nvidia-cublas-cu12
> ```
> A partir de aquí, instalar SIEMPRE en este venv con `uv pip install …`.

Prueba de voz (tras rehacer el venv):

```fish
# Piper
echo "Hola Alberto, prueba de voz." | piper-tts -m ~/.local/share/piper/voices/es_ES-davefx-medium.onnx -f /tmp/p.wav && paplay /tmp/p.wav
# Kokoro (script en /tmp/kok.py; voces es: ef_dora mujer, em_alex hombre)
~/LinuxRicing/assistant/.venv/bin/python /tmp/kok.py && paplay /tmp/kok.wav
```

> [!success] Reordenado (2026-09-01): utilidad antes que estética
> Alberto preguntó qué priorizar. **Acciones/integraciones van antes que el overlay
> visual**: el overlay es cosmético y no bloquea nada; el calendario/tareas es la
> utilidad real del día a día. El *wake word* es fase aparte, después de que el resto
> funcione. `/tmp/talk.py` ya demuestra en vivo cimientos + STT + bucle de voz — falta
> formalizarlo en el daemon real.

1. **Cimientos.** *(prototipado en `/tmp/talk.py`, falta formalizar)*
   - **[Ag]** Esqueleto del daemon, socket de eventos, captura/reproducción PipeWire,
     script del atajo → IPC de *toggle*, plantilla de la unidad systemd `--user` y del
     `config.toml`.
   - **[A]** Copiar la unidad systemd, `systemctl --user enable --now`, añadir el `bind`
     en la config de Hyprland.
   - *Verificable (A):* pulsar el atajo graba un wav y el evento `listening` llega al socket.
2. **STT.** *(hecho en el prototipo: `small`, CPU — ver §1/§2.2)*
   - **[Ag]** Integrar Silero VAD + faster-whisper (CPU), transcripción al socket.
   - **[A]** Ya probado: `small` en CPU va fiable; solo revisar si compensa `medium`.
3. **Bucle de voz completo.** *(prototipado en `/tmp/talk.py`, funciona de extremo a
   extremo con Qwen3-4B + Kokoro `ef_dora` + efecto "jarvis")*
   - **[Ag]** Formalizar en el daemon: *streaming* por frases (bajar de ~6 s a ~1-2 s),
     *barge-in*, historial persistente.
   - **[A]** Seguir probando latencia y ajustando el *prompt* de sistema en `config.toml`.
4. **Acciones y memoria** *(antes era la fase 5 — ahora va primero por prioridad de
   utilidad, ver §2.6)*.
   - **[Ag]** Esquema de *tools*, ejecutor con lista blanca, puerta de confirmación,
     acciones locales (media, brillo, ventanas/workspaces, lanzar apps, portapapeles,
     captura, búsqueda de archivos, notificaciones), tabla SQLite de "hechos" a recordar,
     *tool* que llama a webhooks de n8n para lo externo (calendario, tareas).
   - **[A]** Instalar y montar n8n (Docker), crear en su editor visual los workflows de
     Google Calendar / Google Tasks con su webhook; revisar la lista blanca de acciones
     en `config.toml`.
5. **Activación por voz ("Aurora").** *(nueva fase — ver §2.7)*
   - **[Ag]** Integrar openWakeWord como segundo disparador (además del atajo), entrenar
     el modelo custom con `piper-sample-generator`.
   - **[A]** Grabar/validar el modelo entrenado, ajustar sensibilidad para evitar falsos
     positivos.
6. **Overlay visual.** *(antes era la fase 4)*
   - **[Ag]** Módulo Quickshell `modules/assistant/`, máquina de estados, shader del
     círculo reactivo a `amplitude`, integración con la paleta matugen, captions.
   - **[A]** Reiniciar el shell y verificar en vivo (ver `CLAUDE.md`); dar *feedback*
     visual (a Alberto le va lo visual: pedir mockup/preview si hay dudas de diseño).
7. **Fallback online + pulido.**
   - **[A]** Meter las claves de API en `config.toml` si se activa el *fallback*.
   - **[Ag]** *Toggle* "modo potente", detección de intención para escalar, delegación a
     un agente de código (Claude Code / `aider`) como *tool*, identidad visual del
     agente (acento + avatar), sonidos (encaja con
     [[Sistema de sonido completo del ecosistema]]), carga perezosa de modelos, métricas.
   - **[A]** Elegir acento/avatar y paleta de sonidos.

---

## 5. ¿Sirve para tareas simples de programación?

Sí, con matices — y "tomarse el tiempo que haga falta" **no** arregla lo principal:

- **El cuello de botella es la capacidad del modelo, no el tiempo.** Un 4B en una GTX
  1060 hace bien: scripts cortos, *boilerplate*, explicar código, editar una función,
  arreglos de bugs pequeños. Para nada llega al nivel de Claude/GPT en tareas de varios
  archivos o lógica delicada. Darle más tiempo solo ayuda si añades un **bucle agéntico**
  (modo *thinking* de Qwen3, o iterar: escribir → ejecutar tests → corregir).
- **Velocidad (RTX 2060):** ~35-45 tok/s con un 4B, ~30-40 tok/s con un 7B en Q4 cabiendo
  entero en VRAM. Un script de ~150 líneas sale en < 1 min. La velocidad no es el
  problema; la calidad del modelo pequeño sí.
- **Opción local mejor para código:** cargar **Qwen2.5-Coder-7B** como "modo código"
  (~4,7 GB en Q4; en la RTX 2060 cabe con Whisper en CPU, o descargando Whisper).
- **La mejor arquitectura para esto:** que el asistente **delegue**. Comando de voz →
  lanza un agente de código de verdad en una terminal (Claude Code, `aider`) como si
  fuera otra *tool*. El asistente local se queda de capa de voz + control del sistema +
  preguntas rápidas; el trabajo de programación serio va a un modelo grande (local 7B o
  API). Esto es lo que hay que diseñar en la fase 6 (fallback / delegación).

---

## 6. Resumen de decisiones clave

| Componente | Elegido | Plan B / online |
|---|---|---|
| LLM | Qwen3-4B-Instruct Q4 (Ollama) | Hermes 3B/8B local · API Claude/GPT-4o-mini |
| STT | faster-whisper `small` + Silero VAD | Groq/OpenAI Whisper API |
| TTS | Piper (`es_ES`) → luego Kokoro-82M | ElevenLabs Flash / OpenAI TTS |
| Orquestación | Daemon Python + tools de Ollama + MCP | Goose / Hermes Agent |
| Animación | Overlay Quickshell + shader GLSL | `Shape`/`Canvas` sin shader |
| Activación | Atajo Hyprland → IPC | (wake word openWakeWord a futuro) |

**Relacionado:** [[Agente IA para el gestor de arranque dual-boot]] ·
[[Sistema de sonido completo del ecosistema]] ·
[[Pulsación rítmica CAVA en la tira LED]] ·
[[Terminar el sistema de notificaciones de agentes]] · [[Roadmap Maestro de Innovaciones]]

### Fuentes de la investigación

- [Best Local TTS Models 2026 (localaimaster)](https://localaimaster.com/blog/best-local-tts-models)
- [Kokoro vs Piper vs XTTS v2 (Contra Collective)](https://contracollective.com/blog/kokoro-vs-piper-vs-xtts-local-text-to-speech-m5-max-2026)
- [Local AI Voice Assistant Stack 2026 (dev.to)](https://dev.to/kunal_d6a8fea2309e1571ee7/local-ai-voice-assistant-stack-2026-whisper-piper-ollama-wired-together-572l)
- [On-device tool calling 2026: Qwen3 / Gemma4 / Phi-4 (Ertas AI)](https://www.ertas.ai/blog/on-device-tool-calling-2026-qwen3-gemma4-phi4)
- [Best Local LLM 6GB VRAM 2026 (PromptQuorum)](https://www.promptquorum.com/prompt-bites/best-local-llm-6gb-vram)
- [Qwen Function Calling docs](https://qwen.readthedocs.io/en/latest/framework/function_call.html)
- [Top 10 Open Source AI Agents You Can Run Locally 2026 (fast.io)](https://fast.io/resources/top-10-open-source-ai-agents/)
- [Open Interpreter](https://pypi.org/project/open-interpreter/)
