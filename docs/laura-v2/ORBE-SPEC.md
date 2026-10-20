# Laura v2 — modo en segundo plano: orbe, panel y notas

Diseño aprobado por Alberto el 2026-10-20 a partir del mockup `docs/laura-v2/mockup-orbe.html`
(convergencia **a** + orbe **i**). Rama `feat/laura-v2`.

## Objetivo

Alberto pide algo por voz sin dejar de trabajar. Laura confirma en una frase, se aparta y el
trabajo sigue en segundo plano, hecho por ella misma o por un agente (Gemini, Claude o Aurora).
Una señal visual constante y discreta le dice qué está pasando, y al terminar el detalle queda en
un panel y en una nota de Obsidian. La voz solo dice lo mínimo.

## Dos capas visuales

1. **Fondo (sistema solar):** no cambia. El sol de Laura late y le sale el satélite (ya existe).
2. **Orbe (nuevo, delante de las ventanas):** es lo que especifica este documento.

## Orbe

- **Nacimiento (convergencia a):** cuando arranca el primer trabajo, la luz de borde del overlay
  actual de Laura recorre los bordes de la pantalla y se enrolla en un punto del **borde derecho**
  (a media altura). De ahí nace el orbe. Duración aproximada: 1,2 s.
- **Forma (i):** esfera de cristal pegada al borde derecho. Son gradientes radiales: núcleo,
  reflejo especular y halo, sin `shadowBlur`.
- **Color por agente** (los mismos que el mockup): Laura `#bfb0ff`, Gemini `#7db4ff`,
  Claude `#ee9a6e`, Aurora `#6fdcb4`. Lleva el icono del agente en el centro.
- **Estado por movimiento interior:**

  | Estado | Movimiento |
  |---|---|
  | trabajando | barrido que gira |
  | esperando a un agente externo | respira, con un punto que orbita |
  | necesita confirmación | ámbar, con una onda lenta |
  | terminado | un pulso y un punto blanco de «sin leer» |
  | fallido | rosa tenue, en discontinuo |

- **Varios trabajos:** el trabajo más relevante va en el orbe principal (confirmación > fallido >
  terminado sin leer > trabajando) y el resto en satélites pequeños apilados debajo, a lo largo del borde.
- **Pasar el ratón:** etiqueta con la petición y el tiempo que lleva.
- **Pulsar:** abre el cajón (ver Panel).
- **Al terminar:** pulso y píldora junto al orbe con la frase corta («Ya está: 3 opciones»).
  Se queda «sin leer» hasta que se abre el cajón; cuando no queda nada pendiente, el orbe se
  disuelve de vuelta en el borde. En reposo no hay orbe.
- **Rendimiento (obligatorio, ver CLAUDE.md):** todo en GPU (`ShaderEffect` o gradientes de
  `Shape`), nada de `Canvas` con `shadowBlur`. Ningún `FrameAnimation` incondicional: las
  animaciones solo corren mientras hay un trabajo activo o una transición, y en «terminado» o
  «fallido» la imagen queda quieta. Un `Timer` a pocos fps basta para el barrido.
- **Entrada:** el overlay actual ocupa toda la pantalla y no debe capturar clics. El orbe va en
  su propia `PanelWindow` estrecha anclada a la derecha (o con una máscara de entrada solo sobre
  el orbe y los satélites), para que el resto de la pantalla siga siendo clicable.

## Panel (cajón lateral)

- Se abre desde el borde derecho al pulsar el orbe, con el diseño del panel 1 del mockup.
- Una tarjeta por trabajo, con:
  - el agente y la petición;
  - el estado y el tiempo;
  - un resumen de 1 o 2 frases;
  - las fuentes o enlaces;
  - la ruta de la nota.
- Acciones de la tarjeta:
  - **Abrir nota:** `xdg-open "obsidian://open?path=…"`.
  - **Copiar:** copia el resumen.
  - **Seguir con esto:** abre un ciclo de Laura con ese trabajo como contexto.
  - **Cancelar:** solo mientras está en curso.
  - **Confirmar / Rechazar:** solo si está pendiente de confirmación. Es equivalente a decir «sí» o
    «no» por voz.
- Lista los trabajos de las últimas 24 h; los más antiguos siguen en las notas.

## Notas de Obsidian

- Cada trabajo terminado escribe `vault/Laura/AAAA-MM-DD HHMM <título corto>.md`, con frontmatter
  (`tipo: laura-resultado`, `agente`, `estado`, `peticion`, `creado`) y el cuerpo completo:
  resultado, fuentes y salida del agente.
- `vault/Laura/` va en `.gitignore`: son datos personales generados, no parte del repo.
- La salida en bruto se sigue guardando en `~/.local/share/laura/jobs/<id>.md`.

## Trabajos en segundo plano (daemon)

- **Protocolo:** se amplía el evento `job` del bus: `started` | `waiting` | `confirm` | `done` |
  `failed` | `cancelled`, con `id`, `destino` (laura|gemini|claude|aurora), `titulo`, `resumen`,
  `nota` y `fuentes`. Al arrancar, el overlay pide la lista viva con un comando `jobs` por el
  socket de control, para no perder el estado tras reiniciar el shell.
- **Comandos de control nuevos:** `job-cancel <id>`, `job-confirm <id> yes|no`, `job-read <id>`
  y `job-follow <id>`.
- **Tool `investigar(tema)`:** es un trabajo en segundo plano de Laura. Por defecto lo resuelve
  Gemini en modo solo lectura y **sin confirmación**, porque no modifica nada y pedirlo ya es
  consentimiento. Con `[background] investigar = "laura"` lo hace localmente (`buscar_web` más un
  resumen con el modelo local). Termina en tarjeta y nota.
- **Tool `pedir_a_aurora(peticion)`:** es un trabajo más contra el API server de Hermes en la Pi
  (`http://100.82.69.90:8642`, solo por Tailscale, clave Bearer). Ya está activo y probado: una
  consulta de Calendar tardó unos 45 s.
  - Sirve para Google Workspace, recados y cualquier cosa larga.
  - Usa la **Runs API** (`POST /v1/runs`, seguimiento por SSE o sondeo) para poder ver su estado.
  - **Aprobaciones:** por la API las escrituras de Google NO pasan por Telegram. El run queda en
    `waiting_for_approval` (evento `approval.request`). Laura pasa el trabajo a `confirm` (orbe
    ámbar), te pregunta por voz o desde la tarjeta y resuelve con
    `POST /v1/runs/{id}/approval` (`once` | `deny`).
  - Usa una sesión fija (`X-Hermes-Session-Key: laura-escritorio`) para que Aurora tenga contexto
    entre peticiones de Laura.
  - Config en `[aurora]`: `url` y `timeout`. La clave está en `~/.config/laura/aurora.env`
    (`AURORA_API_KEY`, chmod 600) y se carga con `EnvironmentFile=` en `laura.service`; nunca va
    al repo.
- **Escalada a Gemini o Claude con cambios en código:** sigue pidiendo confirmación, por voz
  **o** desde la tarjeta (estado `confirm`).
- **Frase al terminar:** Laura dice como mucho una frase («Ya está: …; te lo dejo en el panel»),
  y solo si no estás en mitad de otro ciclo.

## Lo que hace Alberto

- Nada en la Pi: el API server ya lo configuró Claude el 2026-10-20 (escucha en la IP de
  Tailscale, con un drop-in de systemd que espera a `tailscale0`). Está registrado en
  `~/proyectos/Aurora/Bitacora/2026-10-20.md`.
- Probar por voz el flujo completo cuando esté construido.

## Fuera de alcance

El wake word (requiere entrenar el modelo), la voz propia con VoiceStudio y los cambios en el
fondo del sistema solar.
