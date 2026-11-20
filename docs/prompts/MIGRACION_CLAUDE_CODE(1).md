# Guía de migración de Claude Code — para el propio Claude

Esta guía la escribió Claude en el dispositivo antiguo de Alberto para que, al arrancar
en el dispositivo nuevo, pueda replicar la instalación y configuración existentes.
Cópiala al nuevo equipo (USB, cloud, git, etc.) y pégala o léela como primer mensaje
en la nueva sesión de Claude Code.

## 1. Instalar Claude Code CLI

Instalado como app nativa (`installMethod: "native"`), versión `2.1.241` en el
dispositivo de origen. En el nuevo equipo:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

(o el instalador nativo correspondiente al SO). Verificar con `claude --version`.

## 2. CLAUDE.md global (preferencias del usuario)

Archivo: `~/.claude/CLAUDE.md`

```markdown
# Preferencias generales del usuario

- Empieza siempre tus respuestas dirigiéndote a mí por mi nombre, Alberto.
```

Crear este archivo tal cual en el nuevo equipo.

## 3. Marketplaces y plugins

En `~/.claude/settings.json` hay dos marketplaces registrados:

```json
"extraKnownMarketplaces": {
  "claude-plugins-official": { "source": { "source": "github", "repo": "anthropics/claude-plugins-official" } },
  "superpowers-marketplace": { "source": { "source": "github", "repo": "obra/superpowers-marketplace" } }
}
```

Y un plugin habilitado:

```json
"enabledPlugins": { "superpowers@superpowers-marketplace": true }
```

Pasos en el nuevo equipo:
1. Añadir el marketplace `superpowers-marketplace` (repo `obra/superpowers-marketplace`).
2. Instalar y habilitar el plugin `superpowers` (versión usada: `6.3.0`).
3. `claude-plugins-official` es el marketplace oficial; puede que ya venga por defecto — verificarlo.

El plugin `superpowers` trae consigo estas skills (no requieren instalación aparte):
`brainstorming`, `dispatching-parallel-agents`, `executing-plans`,
`finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`,
`subagent-driven-development`, `systematic-debugging`, `test-driven-development`,
`using-git-worktrees`, `using-superpowers`, `verification-before-completion`,
`writing-plans`, `writing-skills`.

## 4. Skills instaladas manualmente (fuera del plugin)

En `~/.claude/skills/` hay dos skills instaladas a mano, cada una con su
`SKILL.md` y carpetas de soporte (`references/`, `scripts/`, `assets/`, etc.):

- **`claude-council`** — consejo estructurado de asesores LLM para decisiones de peso.
  Origen: **https://github.com/TorpedoD/claude-council** (clonado con
  `git clone --depth 1 https://github.com/TorpedoD/claude-council.git` el 18/08/2026).
- **`agent-reach`** — investigación/scraping multi-plataforma (redes sociales, foros, etc.).
  Origen: **https://github.com/Panniantong/Agent-Reach** (indicado en el propio
  frontmatter de `SKILL.md` como `metadata.homepage`).

Estas no vienen de un marketplace de plugins; hay que clonar/descargar cada repo y
copiar su contenido a `~/.claude/skills/claude-council/` y
`~/.claude/skills/agent-reach/` respectivamente en el nuevo equipo.

## 5. Configuración general (`~/.claude/settings.json`)

- `"model": "sonnet"` — modelo por defecto.
- Bloque `autoMode` con contexto de entorno específico del proyecto
  `stel-pos` (repo Bitbucket `stelorder/stel-pos`), incluyendo una política dura:
  **nunca hacer `git push` a ese repo sin petición explícita** (`soft_deny` sobre
  `Bash(git push:*)`). Si Alberto sigue trabajando en ese proyecto desde el nuevo
  equipo, replica este bloque `autoMode` (o dejar que se regenere solo, ya que
  Auto Mode lo compone dinámicamente a partir del contexto del repo).
- No hay `settings.local.json` con overrides.
- No hay `keybindings.json` personalizado (usa los atajos por defecto).

## 6. Servidores MCP

Configurados en `~/.claude.json` → `mcpServers`:

```json
{
  "codegraph": { "type": "stdio", "command": "codegraph", "args": ["serve", "--mcp"] },
  "codebase-memory-mcp": { "command": "/home/alberto-vizcaino/.local/bin/codebase-memory-mcp" }
}
```

Además, `claude.ai Canva` (`https://mcp.canva.com/mcp`) estaba añadido pero **sin
autenticar** (estado "Needs authentication") — no hace falta migrar nada, solo
volver a añadirlo y autenticar si se quiere usar.

### 6.1 codegraph (v1.5.0)

Indexa el codebase en un grafo SQLite de símbolos/relaciones para exploración rápida.
En el equipo de origen está instalado como binario nativo en
`~/.codegraph/versions/v1.5.0/`, con symlink `codegraph` en `~/.local/bin/`.
No viene de pip ni npm. En el nuevo equipo:

```bash
curl -fsSL https://codegraph.dev/install.sh | bash   # (verificar URL oficial actual)
```

o el método de instalación que use el instalador propio de codegraph (revisar
la documentación del proyecto si el comando anterior no aplica). Tras instalarlo,
registrar el servidor MCP:

```bash
claude mcp add codegraph -- codegraph serve --mcp
```

Luego, en cada repo donde se quiera usar, correr `codegraph init` (es opcional,
por proyecto — no se instala globalmente el índice).

### 6.2 codebase-memory-mcp

Binario standalone (~271 MB) en `/home/alberto-vizcaino/.local/bin/codebase-memory-mcp`.
No se encontró rastro de instalación vía pip/npm/apt en este equipo, así que su
origen exacto no se pudo determinar automáticamente. Opciones para el nuevo equipo:
1. Copiar directamente el binario `~/.local/bin/codebase-memory-mcp` al nuevo equipo
   (mismo path, o ajustar el `command` en `mcpServers` si cambia la ruta).
2. Si Alberto recuerda de dónde lo descargó/compiló originalmente, reinstalarlo desde ahí.

Registrar después con:

```bash
claude mcp add codebase-memory-mcp -- /home/alberto-vizcaino/.local/bin/codebase-memory-mcp
```

## 7. Memoria persistente (auto memory)

Claude Code guarda lecciones aprendidas por proyecto en
`~/.claude/projects/<slug-del-path>/memory/*.md`. En el equipo de origen hay
memorias guardadas para el proyecto `stel-pos`:

- `~/.claude/projects/-home-alberto-vizcaino-workspacePOS-stel-pos/memory/no-duplicar-en-front-datos-que-devuelve-el-backend.md`
- `~/.claude/projects/-home-alberto-vizcaino-workspacePOS-stel-pos/memory/use-codegraph-before-manual-search.md`

(No hay memorias globales guardadas aún para `~/` en sí, ni para el proyecto
`stel-front-assistant`.)

Si Alberto sigue trabajando en los mismos repos en el nuevo equipo, copia la
carpeta `memory/` correspondiente al mismo slug de proyecto (el slug se deriva
del path absoluto del repo — si el path cambia, el slug también cambiará y
habrá que renombrar la carpeta destino en consecuencia).

## 8. Repos de trabajo con su propio CLAUDE.md

Estos viven dentro de los propios repos (no en `~/.claude`), así que se
migran solos al clonar los repos de nuevo — no requieren acción aparte, solo
confirmarlos:

- `~/workspacePOS/stel-pos/CLAUDE.md`
- `~/workspacePOS/stel-order-catalog/CLAUDE.md`
- `~/workspaceAssistant/stel_front_assistant/claude.md`

## 9. Resumen de pasos en el nuevo dispositivo

1. Instalar Claude Code CLI (nativo).
2. Crear `~/.claude/CLAUDE.md` con la preferencia de nombre (Alberto).
3. Añadir marketplace `superpowers-marketplace` e instalar/habilitar el plugin `superpowers`.
4. Copiar manualmente `~/.claude/skills/claude-council/` y `~/.claude/skills/agent-reach/`.
5. Fijar `"model": "sonnet"` en `~/.claude/settings.json`.
6. Instalar `codegraph` y `codebase-memory-mcp`, registrarlos con `claude mcp add`.
7. (Opcional) volver a añadir y autenticar el MCP de Canva si se usa.
8. Copiar las carpetas `memory/` de los proyectos que se sigan usando, ajustando el slug si el path cambia.
9. Clonar de nuevo los repos de trabajo (traen su propio CLAUDE.md).
