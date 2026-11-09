# Warp — pasar archivos y texto entre el PC y el móvil

Fecha: 2026-11-09 · Repos: LinuxRicing (PC, shell, Laura) y Olimpo (Pi, PWA, Instinct) · Rama `feat/warp` en ambos.

## Qué es

**Warp** es el nombre del sistema que ya existía a trozos (portal de arriba al arrastrar, bandeja «Desde el PC»,
bandeja «Para el PC», llegadas por `llegadas.jsonl`) más tres cosas nuevas:

1. **Agujero blanco** para lo que *llega* al PC (inspiración Outer Wilds: lo que entra por el agujero negro sale por
   el blanco). Enviar = agujero negro arriba; recibir = agujero blanco arriba, en el mismo sitio.
2. **Texto** como ciudadano de primera: claves, notas, enlaces… sin pasar por `.txt`.
3. **Asistentes**: «Laura, manda X por warp» en el PC; «Instinct, manda X por warp» en el móvil.

## Decisiones tomadas con Alberto

| Tema | Decisión |
|---|---|
| Nombre | **Warp** |
| Texto que llega al PC | Se copia **solo** al portapapeles (`wl-copy`) y el agujero blanco suelta una tarjeta «Copiado» con un trozo. Sin modo secreto. |
| Texto del PC al móvil | **Atajo** `Super+Shift+K` (portapapeles; si está vacío, selección primaria — `Super+Shift+M` ya era silenciar) **y** arrastrar texto seleccionado al borde de arriba. |
| Móvil | Tarjeta «Llegó del PC» con el texto y botón **Copiar** (la web no puede escribir el portapapeles sin un toque). Compartir → Olimpo manda texto como texto. Botón **Enviar texto al PC** en Inicio (caja + Pegar + Enviar). |
| Asistentes | Texto dictado, portapapeles, captura, último archivo de una carpeta **y** búsqueda de archivos por descripción (pregunta si duda). |
| App nativa Android | Fuera de alcance; apuntada en `olimpo/docs/roadmap.md`. |

## Arquitectura: una sola puerta por máquina

```
           PC (LinuxRicing)                                      Pi (Olimpo)                 Móvil
 atajo ─┐                                                    ┌─ tele: bandeja «Desde el PC» ─→ PWA «Llegó del PC» [Copiar]
 arrastre ─┼─→ warp (CLI) ─→ olimpo enviar [--texto] ───────→│
 Laura ─┘        │  └→ salidas.jsonl ─→ Portals (agujero negro)│
                 │                                           │
 olimpo-puente ←─┼── órdenes warp.* (buscar/enviar/último) ←─┤←─ Horas /v1/warp/orden ←─ Instinct
     │           └── (ejecuta `warp … --json`)               │
     └─ recoge «Para el PC» (archivo | texto) ←──────────────┤←─ Horas /v1/paraelpc[/texto] ←─ PWA / Compartir / Instinct
          ├ archivo → ~/Descargas/Desde el móvil/
          ├ texto   → wl-copy
          └ llegadas.jsonl ─→ WhiteHole.qml (agujero blanco)
```

### PC: el CLI `warp` (`widgets/warp`, Python stdlib, se instala en `~/.local/bin`)

```
warp texto "…" | warp texto -        texto (argumento o stdin)
warp portapapeles                    wl-paste: texto → texto; imagen → archivo PNG temporal
warp seleccion                       wl-paste --primary (lo subrayado)
warp rapido                          portapapeles; si está vacío, selección (lo usa el atajo; la selección
                                     primaria guarda lo último subrayado aunque sea viejo: lo copiado manda)
warp captura                         grim del monitor enfocado → PNG
warp ultimo [carpeta]                archivo más reciente (por defecto Descargas)
warp buscar "<descripción>"          candidatos (no envía)
warp archivo <ruta>                  envía ese archivo
Opciones: --json (una línea JSON en stdout; contrato con Laura y el puente) · --remoto (restricciones de órdenes remotas)
```

- Envía con `olimpo enviar <ruta>` y el nuevo `olimpo enviar --texto -` (stdin). Nada de red propia.
- Por cada envío añade a `$XDG_RUNTIME_DIR/warp/salidas.jsonl` líneas `{"fase":"enviando|ok|error","tipo":"texto|archivo",
  "nombre","fragmento","origen":"atajo|laura|instinct|arrastre","mensaje","ts"}` → el portal de arriba se abre, se traga
  una mini tarjeta y muestra el resultado, venga de donde venga. Los arrastres de archivos siguen con su flujo propio de
  progreso en `Portals.qml`.
- **Búsqueda:** `plocate -i` (o `fd` si no hay) sobre `$HOME`, ignorando directorios ocultos, `node_modules`, `.git`,
  cachés. La consulta se normaliza (sin tildes, minúsculas); palabras de tipo se traducen a extensiones (pdf, foto/imagen,
  vídeo, documento/word, presentación, hoja/excel, audio, zip). Puntuación: todas las palabras en la ruta (nombre pesa más
  que carpeta), bonus por recencia y por `Documentos`, `Descargas`, `Universidad`, `Escritorio`. Devuelve hasta 5 con
  `{ruta, nombre, tamano, modificado, puntos}` y `"claro": true` si el primero gana con holgura (≥1,5× al segundo).
- **Restricciones `--remoto`** (órdenes que vienen del móvil): solo `buscar`, `ultimo` y `archivo`; la ruta debe estar
  bajo `$HOME`, sin componentes ocultos, sin patrones sensibles (`.ssh`, `.gnupg`, `*.key`, `*.pem`, `*.token`, `.env*`,
  `id_*`, `*.kdbx`). `portapapeles`, `seleccion` y `captura` nunca se ejecutan en remoto.

### PC: agujero blanco (`modules/whitehole/WhiteHole.qml`)

- Se recupera `whitehole.frag` de `a259eec` (núcleo incandescente, disco fino frío con Doppler, chorro hacia la pantalla con
  pulsos, onda de destello) y vuelve a ser el render de las llegadas. El agujero negro queda solo para enviar.
- Si durante una llegada el portal de arriba está abierto por un arrastre, la llegada espera a que se cierre (no se pintan
  dos agujeros en el mismo sitio).
- `llegadas.jsonl` admite `"tipo":"texto"` (`{"tipo":"texto","texto","caracteres","copiado","ts"}`). Vive en
  `$XDG_RUNTIME_DIR` (tmpfs, solo el usuario): nunca toca el disco. El puente lo vacía al arrancar y cuando pasa de
  256 KiB (`tail -F` soporta el truncado). Las líneas sin `tipo` son archivos (compatibilidad).
- Tarjeta de texto: icono de portapapeles, «Copiado», fragmento (3 líneas máx.). Clic: vuelve a copiarlo (`wl-copy`)
  y se va. X / 60 s: se va.
- El puente ya ha hecho `wl-copy` antes de escribir la línea, así que funciona aunque el shell esté reiniciándose.

### PC: portal de arriba (`modules/portals/Portals.qml`)

- Nuevo `Process` con `tail -n 0 -F salidas.jsonl`: `enviando` abre el agujero negro con la mini tarjeta (texto o
  nombre); `ok`/`error` la tragan o la rebotan con el mensaje; se retrae como ya hace.
- Drop de texto plano (sin `file://`) en la banda de arriba → `warp texto -` con origen `arrastre`.

### PC: atajo y Laura

- `Super+Shift+K` → `warp rapido` (en la config de Hyprland de este repo).
- Tool de Laura `assistant/laura/tools/warp.py`: acciones `texto`, `portapapeles`, `captura`, `ultimo`, `buscar`, `archivo`.
  Instrucción en la descripción: con `buscar`, si `claro` → enviar el primero; si no → leer los candidatos y preguntar.

### Pi: Olimpo

- **Bandejas** (`tele/almacen.py`): `tipo` admite `'texto'`; columna nueva `texto TEXT` (migración con `ALTER TABLE`, como
  `entregado`). Límite `texto_max` = 32 KiB. `bytes` = longitud UTF-8 del texto (cuenta para la cuota). `_publico` incluye
  `texto` para el tipo texto. `pendientes()` incluye textos; `pendiente()` acepta texto sin fichero.
- **Rutas nuevas:**
  - `POST /bandeja/texto` (núcleo PC, token `envio`) `{texto}` → bandeja «Desde el PC», aviso de Iris «Desde el PC: texto».
  - `POST /v1/paraelpc/texto` (núcleo interno y Horas, `bandeja:escribir`) `{texto}` → «Para el PC».
  - `POST /v1/warp/orden` (Horas, permiso nuevo `warp:pedir`) `{accion: buscar|ultimo|archivo, consulta?, carpeta?, ruta?}`
    → cola de órdenes del puente; espera el resultado (como la tele) y devuelve `{ok, datos}`.
- **Puente PC** (`pc/olimpo-puente/puente.py`): texto pendiente → `wl-copy` (stdin) → línea `tipo:texto` en
  `llegadas.jsonl` → `entregado`. Orden `warp` → `warp <accion> --json --remoto …` → resultado con `datos` (máx. 8 KiB).
  `ResultadoIn` gana `datos: dict | None`.
- **CLI** `olimpo enviar --texto -`: lee stdin y llama a `/bandeja/texto`.
- **Permisos:** `warp:pedir` para `olimpo-app`, `instinct` y `laura`.
- **PWA:** tarjeta «Llegó del PC» de tipo texto con el texto y **Copiar** (`navigator.clipboard.writeText`); un brillo
  blanco radial al entrar (guiño al agujero blanco). Compartir solo texto/enlace → `POST /paraelpc/texto` en lugar de
  `Compartido.txt`. Botón **Enviar texto al PC** en Inicio → hoja con `<textarea>`, **Pegar** (`clipboard.readText`) y
  **Enviar**.
- **Instinct:** se añade a `docs/instinct.md` cómo mandar texto (`POST /v1/paraelpc/texto`), archivos (`POST /v1/paraelpc`)
  y pedir al PC (`POST /v1/warp/orden`), con la regla de preguntar si `claro` es falso.

## Errores

- Pi caída: `warp` sale con `{"ok":false,"error":"La Pi no responde…"}` y el portal rebota la tarjeta con ese mensaje.
- Texto vacío / demasiado largo: 422 `texto_no_valido` / 413 `texto_demasiado_largo`.
- `wl-copy` falla en el puente: se registra igualmente la llegada con `"copiado": false` y la tarjeta dice «No se pudo
  copiar» con clic = reintentar; el texto no se pierde (queda en memoria de la tarjeta).
- Orden remota rechazada por restricciones: `{ok:false, error:"Esa ruta no se puede enviar desde el móvil"}`.
- Búsqueda sin resultados: `{ok:true, datos:{candidatos:[]}}`; el asistente lo dice.

## Pruebas

- Olimpo (pytest): bandeja con texto (alta, cuota, migración, `_publico`, pendientes), rutas `/bandeja/texto`,
  `/v1/paraelpc/texto`, `/v1/warp/orden` (permiso, ida y vuelta con `datos`), puente (texto → wl-copy simulado + línea en
  llegadas; orden warp → subprocess simulado), CLI `--texto`.
- Olimpo (vitest): modelo de la tarjeta de texto y del compartir sin archivos.
- LinuxRicing: pruebas de `warp` (búsqueda y puntuación sobre un árbol temporal, restricciones remotas, salidas.jsonl).
- Manual: `qs ipc call whitehole demo` (archivo) y `demoTexto`; atajo real; envío y recepción de texto reales con la Pi.

## Fuera de alcance

Portapapeles automático en el móvil, widget de Android (→ app nativa en el roadmap de Olimpo); historial de envíos;
cifrado extremo a extremo propio (va por el tailnet y tokens como el resto de Olimpo).
