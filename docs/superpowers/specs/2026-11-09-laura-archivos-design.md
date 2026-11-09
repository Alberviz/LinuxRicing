# Laura Archivos — gestión de archivos con confirmación y deshacer

Fecha: 2026-11-09 · Rama: `feat/laura-archivos` · Estado: diseño aprobado por Alberto (fase 1)

## Objetivo

Que Laura pueda **borrar, mover, renombrar y crear carpetas** por voz sobre la lista de
hologramas (Laura Holo), siempre con confirmación visible y con **deshacer**. Hoy Laura
solo puede listar y enseñar archivos; no tiene ninguna herramienta que los modifique.

## Descomposición en fases (una spec/plan por fase, misma rama)

| Fase | Contenido |
|---|---|
| **1. Núcleo seguro** (esta spec, detallada) | Motor, papelera, mover/renombrar/crear, deshacer, diario, confirmación voz+panel, panel `confirmar`, animaciones |
| 2. Orden inteligente | «Ordéname Descargas» (plan en árbol), renombrado en lote, clasificación por contenido con LLM |
| 3. Limpieza | Duplicados por hash, grandes/viejos, carpetas fantasma, reglas aprobadas una vez |
| 4. Extras | Comprimir/descomprimir, buscar por contenido, resumir un archivo, ficha, «papelera de Laura» |

Las fases 2–4 reutilizan el motor y el panel de confirmación de la fase 1 (un plan con más
operaciones, mismo flujo).

## Decisiones tomadas con Alberto

- **Confirmación:** por voz **o** clic en el panel, lo que llegue primero.
- **Alcance:** Descargas, Documentos, Escritorio, Imágenes, Vídeos, Música y `~/proyectos`.
  Nunca dotfiles, `~/.config`, el sistema ni el vault de Obsidian.
- **Seguridad:** solo papelera (nunca `rm`); el LLM nunca ejecuta, solo crea planes.

## Arquitectura

```
 voz → LLM → tool (borrar_archivos…) ──► archivos.planificar() ─► Plan pendiente
                                                                    │ effect="confirm:archivos"
 daemon.cycle() ◄───────────────────────────────────────────────────┘
   ├─ emite panel holo kind="confirmar"  ───────────► HoloConfirm.qml (botones, cuenta atrás)
   ├─ Laura pregunta por voz y escucha sí/no ─┐
   └─ clic: holo-confirm/holo-cancel <plan> ──┴─► primero que llegue resuelve el Plan
                                                    │ sí → archivos.ejecutar() → diario
                                                    └─ evento holo op="fx" (desintegrar / volar)
```

### 1. Motor — `assistant/laura/archivos.py` (sin LLM, sin QML)

**Plan** (dataclass): `id`, `accion` (`borrar|mover|renombrar|crear_carpeta`),
`ops: list[Op]` con `Op(origen, destino|None, tamano, es_dir)`, `total_bytes`, `creado`,
`estado` (`pendiente|ejecutado|cancelado|caducado`), `requiere_confirmacion: bool`.
TTL 60 s. Un único plan pendiente a la vez: uno nuevo cancela el anterior.

**Validador de rutas** `ruta_permitida(p)` (único punto de decisión):
- `os.path.realpath` primero (resuelve symlinks; un enlace que sale de las raíces se rechaza).
- Debe estar **estrictamente dentro** de una raíz permitida (las raíces mismas no se tocan).
  Las raíces salen de `xdg-user-dir` (Descargas, Documentos, Escritorio, Imágenes, Vídeos,
  Música) más `~/proyectos`; configurables en `[archivos] raices`.
- Rechaza cualquier componente oculto (empieza por `.`), `.git`, y cualquier ruta bajo un
  directorio llamado `vault` o bajo `~/Obsidian`.
- Rechaza si el destino de un mover queda fuera de las raíces.
- Máximo 50 operaciones por plan (`[archivos] max_ops`).

**Planificar** (`planificar_borrar / _mover / _renombrar / _crear_carpeta`): valida, calcula
tamaños, detecta colisiones de destino y devuelve el `Plan` **sin tocar el disco**. Errores
como `{"ok": False, "error": "…"}` con mensaje apto para decir en voz alta.

**Confirmación requerida** (`requiere_confirmacion`): `borrar` siempre; `mover`/`renombrar`
con más de 5 operaciones. `crear_carpeta` y mover/renombrar de 1–5 operaciones se ejecutan
directamente (tienen deshacer).

**Ejecutar** (`ejecutar(plan)`):
- `borrar` → papelera freedesktop **propia** (`files/` + `info/*.trashinfo`), no `gio trash`.
- `mover`/`renombrar` → `shutil.move`; **nunca sobrescribe**: si el destino existe se usa
  `nombre (2).ext`, `(3)`…; el destino real queda en el diario.
- `crear_carpeta` → `mkdir` (sin `parents` fuera de raíces).
- Cada operación completada se anota en el diario; un fallo a medias no revierte lo ya
  hecho: se informa y se puede deshacer.

**Diario** `~/.local/state/laura/archivos.jsonl` (append-only, una línea por operación):
`{accion_id, ts, accion, origen, destino, trash_path?}`. La papelera propia conoce la ruta exacta
de lo borrado (`trash_files`, `trash_info`) y escribe el `.trashinfo` estándar, así que los
gestores de archivos también la ven.

**Deshacer** (`deshacer()`): revierte la **última acción completa** (todas sus operaciones):
mover/renombrar → devolver a `origen` (si ya existe algo en `origen`, se conserva con sufijo);
borrar → restaurar desde la papelera a su ruta original; crear_carpeta → `rmdir` solo si
sigue vacía. Marca la acción como deshecha para no repetirla. Funciona tras reiniciar.

### 2. Herramientas — `assistant/laura/tools/archivos.py`

`borrar_archivos(numeros)`, `mover_archivos(numeros, destino)`,
`renombrar_archivo(numero, nombre)`, `crear_carpeta(nombre, en?)`,
`deshacer_archivos()`.
- `numeros` resuelven contra la lista holográfica (`escena().resolver`; sin números, el
  seleccionado). `destino` acepta nombre de carpeta (Descargas, «Universidad»…) o ruta.
- Las tools **solo planifican**. Si `requiere_confirmacion`, devuelven `effect="confirm:archivos"`
  con el plan (el mecanismo ya existente para `escalate:*`); si no, ejecutan y devuelven
  «decir» («Hecho. Dime “deshaz” si te arrepientes»).
- Las descripciones de las tools llevan los ejemplos de routing (el system prompt no se toca:
  el contexto va al límite). Evaluación con frases en `assistant/eval/frases.toml`.

### 3. Confirmación en el ciclo — `daemon.cycle()` / `escalation.py`

Igual que `_confirm_and_run_escalation`: tras `converse()`, si hay un plan pendiente:
1. Emite el panel `confirmar` (evento holo `op="confirm"`).
2. Laura dice el resumen («Voy a borrar tres archivos, cuarenta y ocho megas. ¿Confirmas?»).
3. Escucha un sí/no (`_is_affirmative`) **a la vez** que espera `holo-confirm`/`holo-cancel`
   del panel (un `threading.Event` compartido por plan, como `jobs.answered_event`).
4. Sí → `ejecutar` + evento `fx` + «Hecho»; no / cancelar / silencio+TTL → `cancelado|caducado`
   y el panel se apaga. Sin respuesta de voz el plan sigue 60 s visible (solo clic).
Nada se ejecuta sin un `confirmar` explícito de ese `plan.id`.

### 4. Hologramas (QML)

- `HoloState.qml`: panel `kind: "confirmar"` con payload `{plan, accion, titulo, items[], mas,
  total_bytes, destino, segundos}`; acciones `confirmar(id)` / `cancelar(id)` →
  `Laura.ctrl("holo-confirm <id>")` / `holo-cancel`; manejo del evento `op: "fx"`.
- `HoloConfirm.qml` (contenido del panel): hasta 6 afectados + «y N más», resumen y tamaño,
  botones Confirmar / Cancelar, barra de cuenta atrás de **un solo tramo** (sin bucle).
  Borrar en rojo (`m3error`), mover con la carpeta destino.
- `HoloPanel.qml` / `HoloList.qml`: `fx` **desintegrar** (filas/visores afectados se estiran,
  se encogen hacia una papelera que aparece un instante en la esquina inferior derecha; sin
  partículas, `Canvas` ni `shadowBlur`). Al mover, la fila se desliza y se apaga y los visores
  afectados vuelven a la píldora. Todo one-shot; coste cero en reposo.
- Tras ejecutar, la escena **vuelve a listar** la carpeta (números nuevos; Laura lo avisa).
- Tras tocar QML: sincronizar a `~/.config/quickshell/caelestia/` y reinicio completo del shell.

### 5. Errores

| Caso | Comportamiento |
|---|---|
| Ruta fuera de raíces / oculta / vault | «No puedo tocar eso.» (no se crea plan) |
| Origen desaparecido al ejecutar | Se omite y se avisa |
| Colisión de destino | Sufijo « (2)» y se dice |
| Fallo a medias | Se anota lo hecho, se informa, `deshaz` lo revierte |
| >50 operaciones | «Son demasiados de golpe; hazlo en tandas» |
| Plan caducado | «Se me pasó el tiempo; vuelve a pedírmelo» |

### 6. Tests

- `assistant/tests/test_archivos.py`: validador (symlink que escapa, ocultos, vault, raíz misma,
  destino fuera), planificar sin efectos, colisiones, ejecutar→deshacer (mover, borrar con
  `XDG_DATA_HOME` temporal como papelera, crear carpeta), TTL, tope de 50, un plan a la vez,
  diario tras «reinicio» (relectura).
- `assistant/tests/test_tools_archivos.py`: tools con escena simulada (números → rutas).
- `assistant/tests/test_confirmacion.py`: resolución voz/clic con eventos simulados; que
  ningún camino ejecute sin `confirmar`.
- Visual: IPC `holo demo-confirm` (plan de ejemplo) + capturas; revisión de log sin
  `ReferenceError`/`TypeError`.

## Fuera de alcance (fase 1)

Borrado definitivo, acciones fuera de las raíces, reglas automáticas, clasificación por
contenido, duplicados, compresión y búsqueda por contenido (fases 2–4).

## Siguiente spec separada: correo y calendario con hologramas

Pedido por Alberto durante este diseño; **no** forma parte de esta spec. Se brainstormea
aparte tras la fase 1 (listas holográficas de correos y agenda, Laura lee lo importante,
herramientas completas de correo, delegación en segundo plano; modelos por defecto Gemini
3.8 Flash medium / Claude Haiku 5.5 medium).

## Desviaciones respecto al diseño original (decididas al implementar)

- **Papelera propia** en vez de `gio trash` (ruta exacta de lo borrado, testeable sin `gio`).
- **Tools contextuales** (`tools.activas()`): solo se ofrecen al LLM si la frase las pide, y
  sin parámetro `rutas`. Medido con Ollama: el prompt (sistema + 51 tools) ya ocupaba 7.502
  de 8.192 tokens; con las 5 tools nuevas pasaba a 8.149. `num_ctx` sube a **10240**
  (8.152 tokens con «borra la 2»; +156 MiB de VRAM, 4.097 de 6.141 MiB).
- **Animaciones sin partículas**: el panel se encoge hacia la papelera de la esquina.
- **Bug previo corregido de paso** en `HoloLayer.qml`: la ventana arranca en 500×500 hasta que
  el compositor la configura; los paneles colocados en ese instante (se colocan una sola vez)
  quedaban con una caja absurda. `sync()` ahora espera a que mida lo que la pantalla.
