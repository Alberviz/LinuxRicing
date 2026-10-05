# Sistema unificado de tareas — diseño

Fecha: 2026-10-05 · Rama: `feat/sistema-tareas` · Tarea: `vault/Backlog/Sistema unificado de tareas.md`

## Objetivo

Al abrir el ordenador, Alberto ve de inmediato sus tareas, agrupadas desde todos sus repos.
Cada repo conserva sus tareas como notas de Obsidian; un sitio central las agrupa.
Se ven en un widget abajo a la derecha y en el cometa de tareas del sistema solar, y Laura
puede listarlas, crearlas y cambiarles el estado.

## Decisiones (acordadas con Alberto)

- **Fuente de verdad:** notas de Obsidian en el `Backlog/` de cada repo. Un indexador las agrupa.
- **Vista:** widget abajo a la derecha + clic en el cometa de tareas; el widget tiene un botón
  para abrir Obsidian.
- **Interacción:** ver, marcar hecha/en curso y abrir la nota. Crear y editar el detalle se hace
  en Obsidian o por voz con Laura.
- **Enfoque:** indexador Python + JSON central (descartados: QML leyendo notas directamente;
  plugin de Obsidian).

## 1. Formato de nota y registro de repos

Formato = el actual de `vault/Backlog/` (no cambia nada existente). Frontmatter:

```yaml
tipo: tarea
estado: pendiente | en-curso | hecha | idea
prioridad: 1-5          # 1 urgente … 5 algún día
area: ...
esfuerzo: S|M|L
creado: 2026-10-05
```

El título es el nombre del archivo. Registro único: `~/.config/caelestia/task-repos.json`.

```json
[
  {"nombre": "LinuxRicing", "backlog": "~/LinuxRicing/vault/Backlog", "vault": "vault"},
  {"nombre": "Universidad", "backlog": "~/Documentos/Universidad/Backlog", "vault": "Universidad"},
  {"nombre": "Minecraft",   "backlog": "~/minecraft-server/vault/Backlog", "vault": "vault"},
  {"nombre": "OpenGym",     "backlog": "~/proyectos/opengym-fork/Backlog", "vault": "opengym-fork"}
]
```

- `vault` = nombre del vault en Obsidian, para `obsidian://open?vault=…&file=…`.
- Un `Backlog/` inexistente se ignora sin error. `add` lo crea si hace falta.
- Las tareas ya apuntadas para OpenGym/Universidad se quedan en el Backlog de LinuxRicing;
  migrarlas es mover la nota.

## 2. Indexador `widgets/tasks-index`

Python, solo biblioteca estándar. `install.sh` lo despliega en `~/.local/bin`.

| Comando | Efecto |
|---|---|
| `tasks-index scan` | Recorre los repos registrados, parsea el frontmatter y escribe `~/.cache/tasks.json` |
| `tasks-index set <repo> <nota> <estado>` | Cambia **solo la línea `estado:`** de la nota y reescanea |
| `tasks-index add <repo> "título" -p N -a area` | Crea la nota con el frontmatter estándar y reescanea |

Esquema de `tasks.json`:

```json
{"generado": "2026-10-05T10:00:00", "avisos": [],
 "repos": [{"nombre": "LinuxRicing", "vault": "vault", "hechas": 15, "ideas": 5,
   "tareas": [{"id": "LinuxRicing/Rediseño del agujero negro",
     "titulo": "Rediseño del agujero negro", "estado": "en-curso",
     "prioridad": 2, "area": "escritorio", "esfuerzo": "L",
     "ruta": "/home/…/Backlog/Rediseño del agujero negro.md",
     "uri": "obsidian://open?vault=vault&file=Backlog/Rediseño%20del%20agujero%20negro"}]}]}
```

- `hecha` e `idea` no van en `tareas`, solo cuentan por repo (`hechas`, `ideas`).
- Orden: `en-curso` primero, luego `pendiente` por prioridad.
- `prioridad: alta` (valor heredado) se normaliza a 1; vacío = 5.
- Escritura atómica (temporal + rename). Una nota con frontmatter roto se salta y se anota
  en `avisos`. `set` relee la nota justo antes de escribir.
- Sin demonio: lo invoca Quickshell por `Timer`.

## 3. Widget y cometa (Quickshell)

- **`services/Tasks.qml`** (singleton): `Timer` de 30 s + tras cada `set` ejecuta
  `tasks-index scan`, lee `tasks.json`; expone `repos`, `tareas`, `pendientes`,
  `abrir(tarea)`, `marcarHecha(tarea)`. Sustituye al adaptador `taskCount` de
  `SolarSystemModel.qml` (que solo leía LinuxRicing y solo `pendiente`); el cometa pasa a
  contar las tareas de todos los repos, incluidas `en-curso`.
- **`TasksWidget.qml`** (nuevo, ventana propia anclada abajo-derecha): cabecera con recuento
  y botón «Abrir en Obsidian»; lista agrupada por repo, `en-curso` arriba y luego por
  prioridad; casilla (= `set … hecha`), clic en el título abre la nota; ~8 filas y «+N más».
- **Clic en el cometa** (hoy solo hover): panel con la lista completa, chips de filtro por repo
  y prioridad, mismas acciones. `clickMask` acotado a cometa + panel para conservar el
  click-through del resto.
- **Reglas de CLAUDE.md:** sin animaciones permanentes; repintado solo al cambiar el JSON;
  respeta modo ahorro / fondo negro; sync a `~/.config/quickshell/caelestia/` y **restart
  completo** del shell tras cambios de UI.
- **Diseño visual:** maqueta HTML con 2-3 variantes del widget y revisión de Alberto antes de
  escribir el QML.

## 4. Laura

Tres tools en `assistant/tools.py` que llaman a `tasks-index`, sin lógica propia:

| Tool | Efecto |
|---|---|
| `listar_tareas(repo?, estado?)` | Lee `tasks.json` (por defecto `en-curso` y prioridad 1-2) |
| `crear_tarea(titulo, repo, prioridad?, area?)` | `tasks-index add` |
| `cambiar_estado(tarea, estado)` | `tasks-index set` |

- Coincidencia aproximada de nombre: una candidata clara → la cambia; varias → pregunta cuál.
- Repo por defecto: LinuxRicing.
- Solo pueden cambiar `estado` y crear notas nuevas: nada de borrar ni reescribir contenido.
- Respuesta hablada corta. Si Laura está apagada por el ahorro de batería, widget y cometa
  siguen funcionando.

## Fuera de alcance (YAGNI)

Editar el contenido de las notas, borrar tareas, sincronización con Google Tasks, recordatorios
con fecha. Google Tasks sería, si se quiere, un exportador futuro que lee el mismo JSON.

## Orden de construcción y verificación

1. `tasks-index` — verificación manual en terminal sobre el vault real.
2. `Tasks.qml` + cometa leyendo del JSON.
3. Maqueta del widget → `TasksWidget.qml` + panel del cometa.
4. Tools de Laura.

Sin tests automáticos (Alberto prueba a mano). Se mergea `feat/sistema-tareas` a `main` al terminar.
