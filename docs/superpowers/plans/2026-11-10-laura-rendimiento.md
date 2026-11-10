# Laura — rendimiento y escalado de tools: plan de implementación

> **Para quien ejecute:** cada tarea es independiente y se hace en serie (casi todas tocan
> `assistant/laura/llm.py` o `assistant/laura/daemon.py`). TDD: primero el test, verlo fallar,
> implementar, verlo pasar. Tests: `cd assistant && python3 -m pytest -q tests` (hoy 216 en verde;
> ninguno puede romperse).

**Spec:** [`docs/superpowers/specs/2026-11-10-laura-rendimiento-design.md`](../specs/2026-11-10-laura-rendimiento-design.md)

## Restricciones globales

- Python 3, mismo estilo que el resto de `assistant/laura/` (español en nombres, docstrings y logs; `from __future__ import annotations`; `log()` de `laura.config`).
- Sin dependencias nuevas en la Fase 1.
- Nada de llamadas reales a Ollama, micrófono ni red en los tests: `monkeypatch` de `llm._post` y similares.
- Mismo `num_ctx` en TODAS las peticiones a Ollama (cambiarlo recarga el modelo).
- No tocar `vault/` ni ficheros fuera de los listados en cada tarea.

## Ejecución: subagentes Gemini 3.8 Flash (decisión de Alberto)

Claude **no escribe el código** de las tareas: lo delega en subagentes Gemini 3.8 Flash a través
de `agy`, con la misma forma de llamada que `run_agy` en `assistant/laura/jobs.py`.

**Reparto de trabajo:**
- **Claude:**
  - Escribe el plan detallado en `docs/`.
  - Prepara un prompt autocontenido por tarea: la sección del plan, los ficheros y el criterio
    de los tests.
  - Revisa el diff de cada subagente y pasa los tests.
  - Commitea cada tarea.
  - Si una tarea sale mal, se la devuelve una vez al subagente con el error.
- **Las tareas van en serie, no en paralelo:** casi todas tocan `llm.py` o `daemon.py`.

**Tareas para Gemini Flash:** 1, 2, 3, 4, 5, 7 y 8. Están muy acotadas, tienen las firmas y
los tests definidos, y son cambios mecánicos.

**Se quedan sin hacer** (documentadas en el plan para una sesión posterior):
- **Tarea 6 (compactar esquemas):** depende del criterio de redacción y de repetir el examen
  en GPU parando el servicio `laura`. Exige juicio fino sobre qué reglas quitar sin que el
  4B empeore.
- **Tareas 9-10 (recuperador):** código de ML nuevo, descarga de un modelo de ~470 MB y una
  puerta de recall. Además viene apagado por defecto, así que no aporta nada hasta que alguien
  lo active con cuidado.

**Al acabar:** merge a `feat/laura-holo` y resumen a Alberto de qué hizo cada subagente, qué
pasó y qué falló.

## Entregables y forma de trabajo

1. **Documentación:**
   - Copiar este plan a `docs/superpowers/plans/2026-11-10-laura-rendimiento.md`, en el formato
     de la skill writing-plans: tareas TDD con código, cabecera y restricciones globales.
   - Commitear el spec y el plan juntos, solo esos dos ficheros (hay trabajo de otros agentes
     sin commitear en el árbol).
2. **Rama:** `feat/laura-rendimiento`, creada desde la rama activa (`feat/laura-holo`).
   - Se mergea de vuelta a esa rama al terminar, como dice el CLAUDE.md del repo.
   - Un commit por tarea.
3. **Tests:** `cd assistant && python3 -m pytest -q tests`. Hoy pasan 216 y no puede romperse
   ninguno.
4. **Tras cada cambio del daemon:** `systemctl --user restart laura` y comprobar el log con
   `journalctl --user -u laura -f`.

## Fase 1 — Velocidad

### Tarea 1: medir (`_post` único + `eval/prefill.py`)
- En `assistant/laura/llm.py`:
  - `_post(body, etiqueta, timeout=None) -> dict`: hace el POST a Ollama y escribe en el log
    `ollama[etiqueta]: prefill N tok en X s` (campos `prompt_eval_count` y
    `prompt_eval_duration`).
  - `texto_prefill(etiqueta, r)`: función pura que construye esa línea, para poder testearla.
  - `ollama_chat` usa `_post`. `_stream_round` llama a `log_prefill` con el chunk final
    (`done`).
- Nuevo `assistant/eval/prefill.py`:
  - Reproduce la medición con `llm._ollama_body` real y `num_predict=1`.
  - Tres casos: frío, mismo minuto y minuto cambiado.
  - Sirve como línea base: antes del arreglo, el tercer caso debe dar unos 3 s.
- Test: `tests/test_llm_prefill.py` (formato de `texto_prefill`, y `None` si faltan los campos).

### Tarea 2: prefijo estable (el arreglo principal)
- En `llm.py`:
  - `contexto_turno(user_text) -> str`: hora, `memory.prompt_block`, `escena().contexto()`.
    Es la lógica que hoy está en `refresh_system`.
  - `envolver(texto, contexto) -> str`: devuelve
    `"<contexto>\n…\n</contexto>\n\n" + texto`, o el texto tal cual si no hay contexto.
  - `Session.refresh_system()` solo guarda `self.turn_ctx`. Ya **no** toca `messages[0]`.
  - `_mensajes(session)`: copia los mensajes y envuelve únicamente el **último** mensaje
    `user`. `_ollama_body` usa `_mensajes`.
  - El historial guarda el texto limpio.
- En `eval/run.py`: envolver la frase con un contexto fijo
  (`envolver(texto, "Ahora mismo es lunes 10 de noviembre de 2026, 18:30.")`), para que el
  examen mida el formato de producción.
- Tests en `tests/test_llm_prefijo.py`:
  - System y tools idénticos aunque cambie la hora.
  - El contexto aparece solo en el último mensaje de usuario.
  - El historial queda limpio.
  - Los turnos anteriores no llevan `<contexto>`.
  - Se usan `monkeypatch` de `laura.tools.sistema.fecha_hora_texto` y de
    `llm.memory.prompt_block`.
- Verificación: `eval/prefill.py`; el caso «cambia el minuto» debe bajar de ~3 s a < 0,3 s.

### Tarea 3: llamadas auxiliares con el mismo prefijo
- `chat_lateral(instrucciones, etiqueta, fmt=None, temperature=None, num_predict=None,
  timeout=None) -> str` en `llm.py`:
  - Manda el **mismo** system base y `tools_mod.activas("")`.
  - La tarea va en el mensaje de usuario, precedida de «[Tarea interna…: no uses herramientas]».
  - Si la respuesta trae `tool_calls` o viene vacía, repite la petición **sin tools** (el
    comportamiento actual) como respaldo.
- Migrar a `chat_lateral`:
  - `summarize_for_voice`.
  - `answer_from_sources`: se le dice que es una nota escrita, así que aquí sí puede usar
    viñetas.
  - `resumen_correo._llm` con `fmt="json"`, importando en local para evitar el import circular.
- Tests: `tests/test_llm_lateral.py`, con un `_post` falso que guarda los cuerpos. Comprueban
  que el system y las tools coinciden con `Session`, el respaldo sin tools y el `format=json`.

### Tarea 4: precalentar mientras Alberto habla
- `precalentar(ahora=None) -> bool` en `llm.py`:
  - Construye el cuerpo real con `num_predict=1`.
  - No repite si ya precalentó en los últimos 30 s (`_ultimo_calentado`).
  - Nunca lanza excepciones.
- `_keep_alive(body)`: si `[llm] keep_alive` tiene valor en `config.toml`, lo pasa en
  `_ollama_body` y en `chat_lateral`. Vacío = el valor de Ollama.
- `assistant/laura/daemon.py`: lanzar `precalentar` en un hilo en `main()` (tras
  `tts_warmup()`) y en `fire()`, justo antes de arrancar el worker, en paralelo con la escucha.
- Test: el límite de 30 s y que el prefijo sea idéntico al de `Session`.

### Tarea 5: atajos sin LLM (`assistant/laura/rapido.py`)
- Ya prototipado contra `eval/frases.toml`: **captura 10 de 169 frases con 0 errores**.
- API:
  - `normalizar(texto)`: minúsculas, sin tildes, sin puntuación y sin muletillas al principio o
    al final.
  - `resolver(texto) -> Atajo | None`, con `Atajo(tool, args)`.
  - `decir(atajo, resultado) -> str`: «Son las X» para la hora; vacío (solo overlay) para los
    controles de música, volumen y similares; «No he podido: …» si falla.
- Reglas, con `fullmatch` sobre la frase completa:

  | Orden | Tool |
  |---|---|
  | pausa / reanudar / siguiente / anterior / parar la música | `control_musica` |
  | subir o bajar volumen («un poco», «un 20», «veinte por ciento») | `volumen` |
  | silenciar | `silenciar` |
  | subir o bajar brillo | `brillo` |
  | qué hora es | `hora_fecha` |
  | bloquear | `bloquear_pantalla` |
  | captura | `captura_pantalla` |

  Ampliar con lo que no captó el prototipo y no es ambiguo: «pon pausa a la música»,
  «bájalo un 15» y «bloquea el ordenador que me voy».
- `daemon.py` `cycle()`: después de `responder_pendiente_archivos` y de `auto_case`, si
  `[rapido] enabled` (nuevo en `config.toml`, `true` por defecto) y `resolver(text)` da algo:
  - Ejecuta `tools_mod.run_tool`.
  - Emite `result` / `reply`.
  - Añade el turno `user` + `assistant` al historial de la sesión.
  - Habla solo si `decir` devuelve texto.
- Tests en `tests/test_rapido.py`:
  - Positivos y negativos: frases compuestas («pausa y abre google»), «baja el volumen al 20»,
    «qué hora es en Tokio».
  - Todas las tools de las reglas existen en `REGISTRY`.
  - **Coherencia con el examen:** toda frase de `eval/frases.toml` que el atajo capture debe
    dar la misma tool y los mismos argumentos que espera el examen.
  - Al menos 10 capturas.

### Tarea 6: compactar esquemas y system prompt
- Línea base: `eval/run.py --model qwen3:4b-instruct` (herramientas %, falsos positivos) y
  `eval/prefill.py` (tokens).
- Reglas:
  - Cada regla «frase → tool» vive solo en la descripción de su tool, y se borra del system
    prompt de `assistant/config.toml`.
  - Descripciones telegráficas.
  - Nada que repita un `enum`.
- Por dónde empezar: `spotify` (2.197 caracteres), `warp`, `cola_dj`, `listar_tareas`,
  `tele` y las dos escaladas.
- Objetivo: ≤ 5.500 tokens.
- Puerta: el examen no baja más de 2 puntos en herramientas y sigue con 0/18 falsos positivos.
  Si no la pasa, revertir la tool que la rompa.
- Ajustar `test_tools_activas.py` si algo cambia de nombre (no debería cambiar nada).

### Tarea 7: historial ligero
- `_compactar_turno(messages, desde)` en `llm.py`:
  - Al terminar un turno, deja los mensajes `tool` de ese turno solo con las claves `ok`,
    `resumen`, `decir`, `error`, `candidatos` y `pregunta`.
  - Se llama en los `return` de `converse`, pero no en las escaladas (ahí el resultado completo
    puede hacer falta).
- Tests: qué claves se conservan, y que los mensajes de turnos anteriores y el JSON siguen
  siendo válidos.

### Tarea 8: registro de interacciones (semilla del ajuste fino)
- `assistant/laura/registro.py`, función `apuntar(**campos)`:
  - Escribe una línea JSONL en `DATA_DIR/interacciones.jsonl` (`assistant/laura/config.py`):
    fecha, texto, vía (`rapido` | `llm`), tools con argumentos, respuesta y segundos.
  - Nunca falla.
- Se llama desde `cycle()` en la ruta del atajo y tras `converse`. Para tener las tools con sus
  argumentos, `converse` las devuelve en `acciones` mediante un campo `tool` y `args` extra
  (los consumidores actuales solo leen `icon` y `text`).
- Test con `LAURA_DATA` en `tmp_path`.

## Fase 2 — Recuperador de tools (activable, por defecto apagado)

### Tarea 9: ejemplos por tool
- Ampliar el decorador `tool()` (`assistant/laura/tools/__init__.py`) con dos parámetros
  nuevos:
  - `siempre: bool = False`: marca el núcleo, unas 12 tools de uso diario más las
    escaladas, `pedir_a_aurora`, `ejecutar_comando` y `buscar_web`.
  - `ejemplos: list[str] | None = None`.
- Nuevo `assistant/laura/tools/ejemplos.json`, versionado, con 3-8 frases por tool.
  - Se genera con una opción nueva `--solo-ejemplos` de `finetune/gen_dataset.py`, que
    reutiliza sus plantillas `T(tool, phrases)` sin ruido de Whisper.
  - A mano para las tools que no tengan plantilla (archivos, holo, warp, tele, dj…).
- Test: toda tool del registro tiene ≥ 3 ejemplos y ninguno coincide con una frase de
  `eval/frases.toml` (el examen no puede filtrarse al índice).

### Tarea 10: `assistant/laura/recuperador.py` y su integración
- Modelo: `intfloat/multilingual-e5-small` con `transformers` en CPU (ya está en el venv).
  - Mean pooling y los prefijos `query:` / `passage:`.
  - Índice cacheado en `DATA_DIR/tools_index.npz`, invalidado por hash de esquemas + ejemplos.
  - Carga perezosa, la primera vez que se usa.
- `top_k(texto, k) -> list[str]`: la puntuación de cada tool es la similitud máxima entre la
  frase y sus ejemplos.
- `activas()`:
  - Con `[tools] modo = "recuperar"`: núcleo (en orden estable) + `top_k` al final + las
    contextuales `cuando=`.
  - Con `"todas"` (por defecto): exactamente lo de hoy.
  - Si el recuperador falla, cae a `"todas"`.
- `eval/recall_tools.py`: recall@k sobre `eval/frases.toml`, es decir, si la tool esperada está
  dentro de núcleo + recuperadas.
- Puerta para activarlo: recall ≥ 98 % con k=6, y el examen completo en modo `"recuperar"` sin
  empeorar.
- Tests:
  - `top_k` con un embebedor falso inyectable, para no descargar el modelo en los tests.
  - El orden del núcleo es estable.
  - `"todas"` no cambia nada.

## Fuera de este plan

Quedan documentados en el spec (§4.3, §5.1 y §6):
- Ajuste fino v2: plan propio cuando acaben las Fases 1-2.
- Fusionar tools afines en una con `accion`.
- Intercambio de modelos para visión.
- KV en q4.
- Ideas del brainstorming: se apuntan en el backlog solo si Alberto lo pide, como `estado: idea`.

## Verificación de punta a punta

1. `cd assistant && python3 -m pytest -q tests`: todo en verde, más los tests nuevos.
2. `systemctl --user stop laura && .venv/bin/python eval/prefill.py`: caso «cambia el minuto»
   < 0,3 s (hoy 2,98 s).
3. `.venv/bin/python eval/run.py --model qwen3:4b-instruct`: herramientas ≥ línea base − 2
   puntos y 0/18 falsos positivos. El resultado se guarda en `eval/results/`.
4. Daemon real: `systemctl --user restart laura`.
   - Decir «Laura despierta, sube el volumen»: el log debe mostrar `rápido: volumen` sin
     prefill.
   - Esperar más de 1 minuto y preguntar algo: `ollama[chat]: prefill … en 0,1x s`.
   - Tras un aviso del vigía, la siguiente frase sigue con prefill bajo.
5. Comprobar que `~/.local/share/laura/interacciones.jsonl` recibe una línea por turno.
6. Fase 2: `eval/recall_tools.py` ≥ 98 % antes de poner `modo = "recuperar"`.
7. Al cerrar la sesión de trabajo, añadir la línea en la bitácora de `vault/🎯 Hoy.md`.

## Anexo A — prototipo de `rapido.py` (Tarea 5)

Probado contra `eval/frases.toml`: captura 10 de 169 frases, todas con la tool y los argumentos
esperados. Punto de partida; añadir `decir()` y ampliar reglas sin romper la coherencia.

```python
from __future__ import annotations
import re
import unicodedata
from dataclasses import dataclass, field
from typing import Callable

_NUMEROS = {"cinco": 5, "diez": 10, "quince": 15, "veinte": 20, "veinticinco": 25,
            "treinta": 30, "cuarenta": 40, "cincuenta": 50}
_PRE = re.compile(r"^(?:(?:oye|eh|venga|vale|bueno|a ver|mira|laura)\s+)+")
_POST = re.compile(r"(?:\s+(?:por favor|porfa|anda|ya|laura|gracias))+$")


def normalizar(texto: str) -> str:
    t = unicodedata.normalize("NFD", texto.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    t = re.sub(r"[^a-z0-9%\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    t = _PRE.sub("", t)
    t = _POST.sub("", t)
    return t.strip()


@dataclass(frozen=True)
class Atajo:
    tool: str
    args: dict = field(default_factory=dict)


_N = (r"(?:\s+(?:un poco|un poquito|(?:(?:en\s+)?un\s+)?(?P<n>\d{1,3}|" + "|".join(_NUMEROS)
      + r")(?:\s*%|\s+por\s*ciento)?))?")


def _num(m: re.Match, defecto: int = 10) -> int:
    v = m.group("n")
    if not v:
        return defecto
    return int(v) if v.isdigit() else _NUMEROS[v]


_REGLAS: list[tuple[str, Callable[[re.Match], Atajo]]] = [
    (r"(?:pon(?:me)?\s+)?pausa|pausa(?:la)?\s+(?:la\s+)?(?:musica|cancion)|pon (?:la )?musica en pausa"
     r"|reanuda(?:\s+la\s+(?:musica|cancion))?|dale al play",
     lambda m: Atajo("control_musica", {"accion": "reproducir_pausar"})),
    (r"(?:pasa a la |pon la )?siguiente(?: cancion)?|salta(?:te)?(?: esta| la)? cancion",
     lambda m: Atajo("control_musica", {"accion": "siguiente"})),
    (r"(?:pon la |vuelve a la )?cancion anterior|(?:pon la |vuelve a la )anterior",
     lambda m: Atajo("control_musica", {"accion": "anterior"})),
    (r"(?:para|quita|apaga) la musica",
     lambda m: Atajo("control_musica", {"accion": "parar"})),
    (r"sube(?:me)?(?: el)? volumen" + _N, lambda m: Atajo("volumen", {"porcentaje": _num(m)})),
    (r"baja(?:me)?(?: el)? volumen" + _N, lambda m: Atajo("volumen", {"porcentaje": -_num(m)})),
    (r"silencia(?:lo)?(?: el (?:audio|sonido))?|mutea(?:lo)?|quita el sonido",
     lambda m: Atajo("silenciar")),
    (r"sube(?:me)?(?: el)? brillo" + _N, lambda m: Atajo("brillo", {"cambio": _num(m)})),
    (r"baja(?:me)?(?: el)? brillo" + _N, lambda m: Atajo("brillo", {"cambio": -_num(m)})),
    (r"que hora es", lambda m: Atajo("hora_fecha")),
    (r"bloquea(?: la pantalla| el (?:ordenador|pc)| la sesion)?", lambda m: Atajo("bloquear_pantalla")),
    (r"(?:haz(?:me)?|saca(?:me)?) una captura(?: de pantalla)?", lambda m: Atajo("captura_pantalla")),
]
_COMPILADAS = [(re.compile(p), f) for p, f in _REGLAS]


def resolver(texto: str) -> Atajo | None:
    t = normalizar(texto)
    for patron, hacer in _COMPILADAS:
        m = patron.fullmatch(t)
        if m:
            return hacer(m)
    return None
```
