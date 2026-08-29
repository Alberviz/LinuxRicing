# Paletas de sonido — notificaciones de agentes

Cada subcarpeta es una **paleta**: tres ficheros `start.ogg`, `complete.ogg`,
`error.ogg` que `services/Agents.qml` reproduce cuando un agente inicia una tarea,
la completa, o termina con error/cancelado.

| Paleta | Carácter | Fuente |
| --- | --- | --- |
| `system` | Neutra, la del escritorio | tema **freedesktop** (`/usr/share/sounds/freedesktop`) |
| `kenney-soft` | Suave, *pluck* + campana discreta | **Kenney Interface Sounds** (CC0) |
| `kenney-glass` | Cristalino, tipo *glassmorphism* | **Kenney Interface Sounds** (CC0) |
| `kenney-arcade` | Marcado, retro-UI | **Kenney Interface Sounds** (CC0) |

Los sonidos de Kenney son **CC0** (dominio público, sin atribución obligatoria); ver
`KENNEY-LICENSE.txt`. Fuente: <https://kenney.nl/assets/interface-sounds>.

## Uso

```bash
agent-notify sound-set                 # lista las paletas disponibles
agent-notify sound-preview kenney-soft  # escúchala (start → complete → error)
agent-notify sound-set kenney-soft      # actívala
agent-notify sound on|off               # interruptor global
```

`sound-set` escribe `soundStart` / `soundComplete` / `soundError` en
`~/.config/caelestia/agents-config.json` (recarga en caliente). También se puede
apuntar cada clave a un `.ogg`/`.wav` propio sin usar paletas.

`install.sh` copia estas carpetas a `~/.config/caelestia/sounds/`. Sin instalar, los
subcomandos `sound-*` funcionan directamente sobre esta carpeta del repo.

## Añadir una paleta

Crea `rgb/sounds/<nombre>/` con `start.ogg`, `complete.ogg` y `error.ogg` (cortos,
< 400 ms, mezcla suave). Aparecerá automáticamente en `sound-set`.
