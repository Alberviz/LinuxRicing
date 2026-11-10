# Laura Holo — archivos en hologramas por voz y ratón

Fecha: 2026-11-09 · Rama: `feat/laura-holo` · Estado: diseño aprobado por Alberto

## Objetivo

Que Laura **enseñe** archivos en vez de solo leerlos en voz alta. «Lístame las descargas»
abre **un** panel holográfico con la lista numerada; «ábreme la 1 y la 2» abre un visor por
archivo en sitios distintos de la pantalla; «envía esa al móvil» lo manda por warp con la
animación del agujero negro. Todo se maneja por voz **y** con el ratón, y Laura sabe en todo
momento qué hay en pantalla.

No es un explorador de archivos: no renombra, no borra, no mueve, no navega carpetas.

## Aspecto (aprobado en el companion visual, `hud-ecosistema-v2.html`)

- **Solo aparece lo que se pide.** Listar = 1 panel. Abrir N = N visores. El modo
  «constelación» (muchos paneles a la vez) es la excepción, para peticiones amplias.
- **Velo de foco:** el escritorio se oscurece y desenfoca; brillo del color del tema que sube
  desde la píldora de Laura y una malla de puntos tenue (eco de las estrellas del sistema solar).
  Tapa lo de detrás a propósito: en ese momento Alberto está centrado en Laura.
- **Panel holograma:** cristal oscuro (`surfaceContainer` translúcido), borde fino `primary`,
  esquinas redondeadas de caelestia, líneas de escaneo y reflejo superior tenues, halo
  `primary`. Cabecera en mayúsculas con icono Material Symbols o el número del archivo en un
  círculo `primary`.
- **Colores 100 % Material You** (`Colours` del shell): cambian solos con el fondo. Nada de rojo
  fijo ni de la estética literal de la captura de referencia.
- **Nacimiento:** cada panel sale de la píldora con un rayo de luz `primary` y vuela a su hueco.
- **Colocación semi-aleatoria:** cada visor elige al azar entre huecos libres (sin pisar otros
  paneles, la píldora ni los bordes) y llega con un giro pequeño (±2°).
- **Hilo:** una línea de puntos une cada fila de la lista con su visor abierto. La lista se
  aparta a un lado (escala 0,92) y marca las filas abiertas.
- **Envío al móvil:** el visor se estira y se encoge hacia el agujero negro de warp (borde
  superior centrado); la fila queda marcada «→ móvil ✓».
- **Cierre:** los paneles se recogen en cascada hacia la píldora.

## Arquitectura

El **daemon es el dueño de la escena**: el LLM necesita saber qué es «la 2» o «esa» antes de
llamar a una tool, y solo el daemon lo tiene a mano. Quickshell solo pinta y reporta lo que hace
el ratón.

```
voz ─► laurad ─► tools/holo.py ─► laura/holo.py (Escena) ─► bus «holo» ─► Quickshell modules/holo/
                     │                     ▲                                   │
                     └── warp (listar/      └──── socket de control ◄── ratón ─┘
                          buscar/enviar)          holo-select|close|send
```

### 1. `assistant/laura/holo.py` — la escena (nuevo)

Clase `Escena` (thread-safe, una por daemon):

- `items: list[Item]`: los archivos numerados de la última lista
  (`n`, `ruta`, `nombre`, `tipo` ∈ `imagen|pdf|texto|video|audio|otro`, `tamano`, `mtime`).
- `paneles: dict[id, Panel]`: `lista` (como mucho una) y `visor` (uno por archivo abierto).
  `Panel = {id, kind, titulo, item_n?, payload}`.
- `seleccionado: int | None`: el último que se ha abierto o tocado con el ratón.
- `listar(titulo, items)`: sustituye la lista y renumera desde 1. Los visores abiertos de una
  lista anterior se cierran.
- `abrir(ns | ruta)`: crea un visor por archivo (una ruta suelta se añade como item nuevo).
  Si ya estaba abierto, lo trae al frente.
- `cerrar(ids | todo)`, `seleccionar(n)`, `marcar_enviado(n)`.
- `resolver(ref)`: `int` → item; `None` → el seleccionado (lo que significa «esa»).
- `contexto() -> str`: una línea para el system prompt, por ejemplo
  «En pantalla: lista Descargas (1 WhatsApp 21.04.jpg · 2 practica3_redes.pdf · …); abiertos 1, 2; seleccionado 2».
  Cadena vacía si no hay escena.
- **Caducidad:** pasados 10 min sin actividad, `contexto()` devuelve vacío y se emite `clear`.
- Cada mutación emite por el `EventBus`:
  `{"type":"holo","op":"open|close|select|sent|clear","panel":{…},"items":[…]}`.
  Al conectarse, un lector nuevo recibe un `{"type":"holo","op":"snapshot",…}` con la escena
  completa (igual que `state`).

`Session.refresh_system()` (`laura/llm.py`) añade `escena.contexto()` al bloque extra del
system, junto al de memoria.

### 2. Previsualización — `assistant/laura/holo_preview.py` (nuevo)

`preparar(item) -> payload`, que el daemon calcula antes de emitir el `open`:

| tipo | payload |
|---|---|
| imagen (png, jpg, jpeg, webp, gif, bmp) | `{src: ruta, w, h}` (tamaño con Pillow si está; si no, sin él) |
| pdf | `{paginas: N, pagina: 1, src: <png página 1>}` con `pdftoppm -r 110 -f p -l p -png` en `$XDG_RUNTIME_DIR/laura-holo/<hash>-p<n>.png`, generado bajo demanda (comando de control `holo-page <id> <n>`) |
| video / audio | `{src: ruta, poster: <png de ffmpegthumbnailer>, duracion}` (audio sin poster) |
| texto (md, txt, py, json, toml, sh, qml, js, ts, css, html, yaml, cfg, log…) | `{texto: primeras 200 líneas / 16 KiB, formato: "markdown"\|"mono", truncado: bool}` |
| otro | `{icono, mime}` → tarjeta con «Abrir con su programa» (`xdg-open`) |

- El tipo se decide por extensión y, si no basta, por el mime de `file --mime-type`.
- La caché de `$XDG_RUNTIME_DIR/laura-holo/` se vacía al arrancar el daemon y al pasar de 200 MB.
- Archivos de más de 2 GB, o de vídeo/PDF corruptos: payload `otro` con un aviso.

### 3. Tools — `assistant/laura/tools/holo.py` (nuevo)

- `mostrar_archivos(carpeta?: str, consulta?: str)`: usa `warp listar` (sin consulta) o
  `warp buscar` (con consulta), que ya devuelven `candidatos` con ruta. Hasta 12 items.
  Devuelve `{ok, decir, resumen}`, donde `decir` es una frase corta («Tienes ocho cosas recientes;
  la última es una captura de WhatsApp.»). Icono `folder_open`.
- `abrir(numeros?: list[int], ruta?: str)`: valida los números contra la escena. Si se abren
  más de 4 a la vez, el layout pasa a modo constelación. Icono `visibility`.
- `cerrar_holo(numeros?: list[int], todo?: bool)`. Icono `close`.
- **`warp`** (`tools/warp.py`) gana el parámetro opcional `numero: int`. Si se da (o si no hay
  ruta ni consulta y hay algo seleccionado en la escena, el caso de «envía esa»), resuelve la
  ruta por la escena, envía con `warp archivo` y llama a `escena.marcar_enviado(n)` (op `sent`).
- `config.toml` → `system_prompt`, una línea más en la guía: «Lista o enseña archivos =
  mostrar_archivos; abre/enséñame la N = abrir; "esa", "la 2" se refieren a lo que hay en
  pantalla; envía esa al móvil = warp con numero.»

### 4. Socket de control (ratón → daemon) — `laura/daemon.py:control`

Comandos nuevos (una línea, respuesta JSON):

- `holo-open <n>`: clic en una fila de la lista.
- `holo-select <n>`: clic en un visor (pasa a ser «esa»).
- `holo-close <id|all>`: Esc, clic derecho o botón de cerrar.
- `holo-send <n>`: visor arrastrado al borde superior (mismo camino que `warp numero`).
- `holo-page <id> <p>`: cambiar de página de PDF (rueda o «siguiente página»).
- `holo-ext <n>`: abrir con su programa.

### 5. Quickshell — `configs/quickshell/caelestia/modules/holo/` (nuevo)

- `modules/assistant/Laura.qml` (el singleton que ya existe y lee el bus): enruta los eventos
  `type == "holo"` a un singleton nuevo `modules/holo/HoloState.qml` (modelo de paneles + items),
  que manda los comandos de ratón por el socket de control igual que hace hoy el cajón.
- `HoloOverlay.qml` (entrada, registrada en `shell.qml` junto a `Assistant {}`): un `Variants` por
  pantalla que solo se activa en la pantalla enfocada.
- `HoloLayer.qml`: `PanelWindow` en la capa `Overlay`, con anclaje a todo y exclusión `Ignore`.
  `keyboardFocus: OnDemand` mientras haya paneles (para Esc). Se pinta el velo (dos gradientes y
  la malla de puntos con un `ShaderEffect`, o una imagen en tile). Solo visible con escena.
- `HoloPanel.qml`: el chasis del holograma (cristal, borde, escaneo con un `ShaderEffect`
  barato o una imagen en tile, reflejo, cabecera y botón de cerrar), la animación de nacimiento
  desde la píldora (rayo + vuelo con `ParallelAnimation`), el arrastre (`DragHandler`) y el
  giro aleatorio.
  Animaciones con `running:` condicionado, sin `FrameAnimation` permanente ni `shadowBlur`.
- Contenidos: `HoloList.qml` (filas numeradas, miniatura por tipo, filas abiertas marcadas),
  `HoloImage.qml` (zoom con la rueda, pan arrastrando), `HoloPdf.qml` (página y
  rueda → `holo-page`), `HoloMedia.qml` (QtMultimedia `MediaPlayer` + `VideoOutput`; pausa al
  cerrar), `HoloText.qml` (`TextEdit` de solo lectura, `MarkdownText` o mono).
- `HoloLinks.qml`: un `Shape` con las curvas de puntos fila → visor.
- **Colocación** (`HoloPlacer.js`): rejilla virtual de 12×8 celdas; se marcan como ocupadas
  la píldora, los paneles y un margen de borde, y se escoge al azar una de las mejores posiciones
  libres para el tamaño pedido. La lista va a la izquierda o al centro; en modo constelación
  se llena todo.
- **Envío:** el visor vuela hacia `(centro, top)` y se desvanece; el agujero negro lo abre solo
  `Portals.qml` porque `warp archivo` ya escribe en `$XDG_RUNTIME_DIR/warp/salidas.jsonl`.
- IPC de depuración: `qs -c caelestia ipc call holo demo` (escena falsa con 8 items, 2 visores).

## Errores

- Archivo desaparecido al abrirlo: el visor muestra «Ya no existe» y la tool devuelve
  `ok: false` para que Laura lo diga.
- Número fuera de rango: la tool devuelve un error con las opciones válidas («Solo hay 8»).
- Sin overlay conectado: las tools funcionan igual (escena y voz); al conectarse llega el
  `snapshot`.
- `pdftoppm` o `ffmpegthumbnailer` ausentes: payload `otro` y abrir con su programa.
- Daemon reiniciado: escena vacía y el overlay recibe `clear` en el `snapshot` inicial.

## Pruebas

- `assistant/tests/test_holo.py`: numeración, `resolver(None)` = seleccionado, sustitución de
  la lista que cierra visores, caducidad, `contexto()` y eventos emitidos (bus falso).
- `assistant/tests/test_holo_preview.py`: tipo por extensión, truncado de texto, PDF con
  `pdftoppm` simulado.
- `assistant/tests/test_tools_holo.py`: `mostrar_archivos` / `abrir` / `warp numero` con
  `warp` simulado.
- `eval/frases.toml`: «lístame las descargas», «busca el pdf de redes», «ábreme la 1 y la 2»,
  «enséñame la captura», «envía esa al móvil», «cierra eso». El modelo de 4B debe elegir bien
  la tool y no bajar la nota global.
- UI: `ipc call holo demo` y prueba real con restart del shell (`INFO: Configuration Loaded`),
  revisando la CPU en reposo (0 % con la escena cerrada).

## Fuera de alcance (fase 2)

- Modo constelación con paneles generados por Laura (resumen de un PDF, fecha de entrega).
  En la fase 1 la constelación es solo «muchos visores a la vez».
- Renombrar, borrar o mover archivos; navegar carpetas desde el panel.
- Enviar al móvil desde Olimpo con el holograma abierto en el PC.
