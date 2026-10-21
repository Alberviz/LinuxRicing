# Laura v2 — asistente completo: Workspace, decisión de a quién encargar y vigía proactivo

Objetivo de Alberto (2026-10-21): usar a Laura para pedirle cosas como leer las tareas o mirar el
correo, que ella decida si lo hace sola, con Gemini o con Claude, y que **se levante sola** para
avisarle de correos, eventos o tareas, **diferenciando mucho** cuándo la levanta él y cuándo se
levanta sola.

## 1. Workspace (correo, calendario, Drive…) a través de Aurora

- No se carga el MCP de Workspace en Laura: son 73 herramientas, que un modelo de 4B no puede
  manejar (en la Pi, Gemini tardaba más de 400 s con todas cargadas).
- Laura gana **herramientas con nombre propio** que por dentro son trabajos contra Aurora (Runs
  API), con prompts fijos y bien redactados:
  - `correo(consulta="")`: «mírame los correos», «¿tengo algo de X?». Resume los no leídos
    importantes, o busca.
  - `agenda(cuando="hoy|mañana|semana|próximo")`: eventos.
  - `redactar_correo(para, asunto, idea)`: crea un **borrador**; enviarlo siempre requiere
    confirmación (estado `confirm`).
  - `pedir_a_aurora(peticion)` se mantiene para todo lo demás (Drive, Docs, recados).
- La respuesta corta se lee en voz y el detalle va a la tarjeta y a la nota, como cualquier
  trabajo.

## 2. Decidir a quién le toca

Reglas en el system prompt, con ejemplos, validadas con el examen:

| Nivel | Quién | Ejemplos |
|---|---|---|
| Instantáneo | Laura sola, con sus tools | música, volumen, avisos, tareas, hora, tiempo, luces, buscar_web rápida |
| Google o lento | Aurora (en segundo plano) | correo, agenda, Drive, recados |
| Investigar | `investigar` (Gemini, solo lectura, segundo plano) | «infórmate de…», comparativas |
| Cambio mediano | `escalar_a_gemini` (confirmación) | un script, un widget, un ajuste de config |
| Hipercomplejo | `escalar_a_claude` (confirmación) | features de varios ficheros, rediseños, depurar algo difícil |

## 3. Vigía: Laura se levanta sola

- Nuevo módulo `laura/vigia.py`: un hilo del daemon que cada `[vigia] cada_min` (por defecto 20)
  comprueba:
  - **Correo y agenda:** UNA petición a Aurora en su propia sesión (`laura-vigia`, para no
    mezclarla con la sesión de Alberto), pidiendo **JSON estricto** solo con lo NUEVO desde la
    última revisión:
    - correos importantes: persona real, universidad o trabajo, plazos, pagos, viajes; nada de
      spam ni newsletters;
    - eventos que empiezan en los próximos `aviso_evento_min` (por defecto 30).
  - **Local, sin LLM:** tareas en curso estancadas más de N días (resumen como mucho una vez al
    día) y trabajos fallidos sin leer.
  - **Deduplicación** por id (correo o evento) en `~/.local/share/laura/vigia.json`: nunca se
    avisa dos veces de lo mismo.
- **Cuándo NO corre:** con batería (ahorro), entre `silencio_desde` y `silencio_hasta` (por
  defecto 23:30–08:00), con No molestar activo, o con `[vigia] enabled = false`.
- **Prioridad de cada aviso:** `baja` (solo tarjeta), `normal` (orbe y píldora, sin voz) o `alta`
  (además una frase hablada). Laura **no habla** si hay una ventana en pantalla completa (juego o
  vídeo) o si Alberto está en una conversación con ella; en ese caso se queda en el orbe.

## 4. Diferenciar «la levanto yo» y «se levanta sola»

| | La levanta Alberto | Se levanta sola (vigía) |
|---|---|---|
| Entrada visual | Overlay de borde completo y, al delegar, convergencia «a» | **Sin overlay ni convergencia.** El orbe aparece con un fundido suave en su sitio (arriba a la derecha) |
| Orbe | Color del agente y movimiento de estado | **Glifo de campana**, color Laura y un **halo de doble anillo** que late 3 veces y se queda quieto |
| Voz | Respuesta normal | Solo con prioridad alta: un **sonido corto** («ding») y una frase que empieza por «Alberto, …» |
| Cajón | Tarjetas normales | Tarjeta con la etiqueta **«Por su cuenta»** y acciones «Abrir en Gmail» o «Ver evento» si hay URL, y «Descartar» |
| Protocolo | `origen: "alberto"` | `origen: "laura"`, `tipo: "aviso"`, `prioridad` |

Campos nuevos del evento `job` (compatibles hacia atrás; si faltan, `origen = "alberto"`):
`origen` (`alberto` | `laura`), `tipo` (`trabajo` | `aviso`) y `prioridad` (`baja` | `normal` |
`alta`). Los avisos llegan directamente como `done`, con `resumen`, `fuentes` (URL de Gmail o
Calendar si la hay) y `nota`.

Comando de control nuevo: `vigia-now`, que fuerza una revisión (para depurar y para «Laura,
¿hay algo nuevo?»). Tool nueva: `novedades()`, que hace lo mismo a petición de Alberto.

## Nota

La tarea programada «Vigilante silencioso» de Aurora ya avisa por Telegram. Para no recibir el
mismo aviso dos veces, el vigía de Laura solo avisa en el escritorio. Alberto decide si pausa el
de Telegram (con `/autonomo_off` lo pausa).
