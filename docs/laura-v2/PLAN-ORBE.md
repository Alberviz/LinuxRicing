# Plan — orbe y modo en segundo plano

Implementa `docs/laura-v2/ORBE-SPEC.md` en `feat/laura-v2` (worktree `.worktrees/laura-v2`).
Hay dos agentes en paralelo, con ficheros disjuntos. El contrato entre ellos es el protocolo de
eventos de abajo. Alberto prueba a mano al final.

## Contrato: protocolo (lo fija este plan; ningún agente lo cambia por su cuenta)

**Bus de eventos** (`$XDG_RUNTIME_DIR/laura-events.sock`, una línea JSON por evento). Evento `job`:

```json
{"type":"job","value":"started|waiting|confirm|done|failed|cancelled",
 "id":"<str>","destino":"laura|gemini|claude|aurora","titulo":"<≤80>",
 "resumen":"<1-2 frases o vacío>","pregunta":"<solo en confirm>",
 "nota":"<ruta absoluta .md o vacío>","fuentes":[{"titulo":"…","url":"…"}],
 "inicio":<epoch>,"fin":<epoch|null>}
```

- **Significado de cada estado:**
  - `waiting`: esperando a un agente externo.
  - `confirm`: necesita un sí o un no.
  - `done` o `failed`: final. Lleva `resumen` y `nota`.
- **Socket de control** (`laura.sock`), una línea por comando y una línea JSON de respuesta:
  - `jobs` → `{"jobs":[<job de las últimas 24 h, mismo formato>]}`
  - `job-cancel <id>`
  - `job-confirm <id> yes|no`
  - `job-read <id>`: lo marca como leído y emite `job` con `"leido":true`.
  - `job-follow <id>`: abre un ciclo de Laura con el trabajo como contexto.

## Tarea A — backend (Python). Ficheros: `assistant/**`, `.gitignore`

1. Ampliar `laura/jobs.py` al protocolo: estados nuevos, `resumen`, `nota`, `fuentes`,
   `leido`, cancelación (matar el proceso o la petición) y confirmación pendiente (voz **o**
   `job-confirm`, lo que llegue antes).
2. Comandos de control nuevos en `laura/daemon.py`.
3. `laura/notes.py`: al terminar un trabajo, escribe `vault/Laura/AAAA-MM-DD HHMM <título>.md` con
   el frontmatter de la especificación. La ruta del vault va en config `[background] vault`, por
   defecto `~/LinuxRicing/vault`. Añadir `vault/Laura/` a `.gitignore`.
4. Tool `investigar(tema)`: trabajo en segundo plano. Destino según `[background] investigar`,
   `gemini` o `laura`.
   - Con `gemini`: `agy` en solo lectura y sin confirmación. El prompt prohíbe modificar
     archivos y pide un resultado en markdown con fuentes.
   - Con `laura`: `buscar_web` más un resumen local.
5. Tool `pedir_a_aurora(peticion)`, en un módulo nuevo `laura/aurora.py`. Usa la Runs API de
   Hermes (`POST /v1/runs` y su SSE o sondeo de estado), con la cabecera
   `X-Hermes-Session-Key: laura-escritorio` y la clave en la variable `AURORA_API_KEY`.
   - Al recibir `approval.request` o `waiting_for_approval`, el trabajo pasa a `confirm` con la
     pregunta, y el sí o el no van a `POST /v1/runs/{id}/approval` (`once` o `deny`).
   - Mientras el run está en curso, el estado es `waiting`.
   - Config `[aurora]`: `url = "http://100.82.69.90:8642"` y `timeout = 600`.
   - Mira la API real en `GET /v1/capabilities` y en la doc
     `website/docs/user-guide/features/api-server.md` del repo NousResearch/hermes-agent
     (`gh api`).
6. `laura.service`: `EnvironmentFile=-%h/.config/laura/aurora.env`.
7. Frase final hablada de como mucho una frase, y solo si no hay un ciclo en curso.
8. Actualizar el system prompt: cuándo usar `investigar`, `pedir_a_aurora` y las dos escaladas.
   Ampliar `assistant/eval/frases.toml` con 6 frases y pasar el examen sin bajar del 90 %.

**Verifica:**
- `--text "investiga qué es el protocolo A2A"` produce un trabajo que acaba en `done` con su nota.
- `--text "pregúntale a Aurora qué tengo mañana"` llega a `done`. La API real ya funciona: una
  consulta de Calendar tardó unos 45 s.
- Una petición de escritura a Aurora («créame un evento de prueba mañana a las 9 y bórralo
  después») pasa por `confirm` → `job-confirm … no` → `failed` o `cancelled`, **sin crear nada**.
- `socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/laura.sock <<< jobs` devuelve la lista.

## Tarea B — orbe y cajón (QML). Ficheros: `configs/quickshell/caelestia/modules/assistant/**`

1. `Laura.qml`: manejar el evento `job` (un modelo de lista por `id`); al conectar, pedir `jobs`
   por el socket de control; exponer funciones `cancel`, `confirm`, `read` y `follow`. Ruta de
   los sockets sobreescribible con las variables de entorno `LAURA_EVENTS_SOCK` y
   `LAURA_CTRL_SOCK`, para probar con un servidor simulado.
2. `LauraOrb.qml` (ventana nueva y estrecha anclada a la derecha, capa Overlay, sin foco de
   teclado, entrada solo sobre el orbe y los satélites):
   - convergencia **a**;
   - orbe **i**;
   - estados, prioridad y satélites;
   - etiqueta al pasar el ratón, píldora y «sin leer»;
   - se disuelve cuando no queda nada.

   Referencia visual exacta: `docs/laura-v2/mockup-orbe.html`. La convergencia puede salir de la
   luz de borde que ya pinta `LauraOverlay.qml`.
3. `LauraDrawer.qml` y `LauraJobCard.qml`: el cajón con las tarjetas y sus acciones, tal cual la
   especificación. «Abrir nota» usa `xdg-open "obsidian://open?path=<ruta urlencoded>"`.
4. Instanciar el orbe y el cajón desde el propio módulo `assistant/`, donde ya se instancia
   `LauraOverlay`. Si hay que tocar un fichero fuera de `modules/assistant/`, compáralo antes con
   la copia desplegada en `~/.config/quickshell/caelestia/`: el checkout principal está en otra
   rama y no hay que pisar sus cambios.
5. Reglas de CLAUDE.md, obligatorias: GPU (`ShaderEffect` o gradientes de `Shape`), sin
   `shadowBlur`, `running:` atado a que haya un trabajo activo o una transición, y restart completo
   del shell, nunca hot-reload.
6. `assistant/eval/` y el Python no son tuyos. Para probar sin el daemon, crea
   `assistant/dev/mock_events.py` (una excepción de fichero para B). Es un servidor simulado de
   los dos sockets que reproduce una escena: started → waiting → confirm → done, más un failed.

**Verifica:**
- Despliega y reinicia el shell, y comprueba que aparece `Configuration Loaded`.
- Con el servidor simulado, recorre la escena y haz capturas (`grim`) de la convergencia, el
  orbe en cada estado, los satélites y el cajón abierto.
- CPU del proceso `qs` en reposo menor o igual que antes, y sin `FrameAnimation` vivos sin
  trabajos.
- Al acabar, quita las variables de entorno y deja el shell con los sockets reales.

## Integración (orquestador)

Cuando las dos tareas estén terminadas:

1. Prueba conjunta con el daemon real del worktree.
2. Revisión del diff.
3. Prueba manual de Alberto.
4. Merge de `feat/laura-v2` a `main`.
