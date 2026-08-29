---
tags: [tarea-agente, gemini, python, agentes, notificaciones]
para: Gemini
de: Claude
creado: 2026-08-29
estado: completado
modelo-sugerido: Gemini 2.5 Flash (el plan trae el código completo; es transcripción + pytest)
---

# Gemini · `agent-notify` — CLI de notificación de agentes

> **Eres el agente `agent-notify-cli`.** Este documento es tu única fuente de instrucciones.
> Léelo entero antes de tocar nada. No tienes contexto previo de esta sesión.

## 0. Contexto en una frase

Estamos rehaciendo el sistema de avisos "un agente de IA ha terminado en un terminal":
al terminar, sale un toast rico y el **pip del workspace** de ese terminal se enciende en
la barra de Caelestia. Tú construyes **solo la pieza Python** que dispara el aviso:
`rgb/agent-notify`. El resto (QML) lo hace Claude en paralelo.

## 1. Lee primero (en este orden)

1. `/home/alberviz/LinuxRicing/CLAUDE.md` — flujo de ramas, coordinación multi-agente.
2. `docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md` — el diseño. Secciones **§Arquitectura** y **§Componentes → 1. `rgb/agent-notify`**.
3. `docs/superpowers/plans/2026-08-29-agent-notifications-workspace-pip.md` — **Task 1 entera** (tu alcance exacto: trae el test completo y el refactor paso a paso). También lee **"Contrato de datos → Payload IPC"**. Ignora Tasks 2-8.
4. El estado actual de `rgb/agent-notify` (ya existe, funciona; le añades `--task`, extraes `build_parser()`/`build_agent_data()`, y `test` inyecta en el workspace activo real).
5. `rgb/tests/conftest.py` y `rgb/tests/test_telemetry.py` — patrón de la casa para cargar un script sin extensión `.py` con `SourceFileLoader` y para monkeypatch de `subprocess`.

## 2. Rama y aislamiento

```
cd /home/alberviz/LinuxRicing
git worktree add .worktrees/gemini-agent-notify -b feat/agent-notify-cli feat/agent-notifications
cd .worktrees/gemini-agent-notify
```

- Trabaja **solo** en `rgb/agent-notify` y `rgb/tests/test_agent_notify.py`. Nada más.
- **NO toques** `configs/`, `widgets/`, `docs/`, `vault/`, `README.md` (lo edita Alberto), ni ningún otro `rgb/*`.
- **Nunca `git add -A` / `git add .`** — añade siempre las rutas explícitas.
- Commits: mensajes terminan con `Co-Authored-By: Gemini <noreply@google.com>`.
- Textos que ve el usuario: español (el toast). Sin tildes en el cuerpo si te preocupa la codificación de `notify-send`, pero el código y comentarios en español está bien.

## 3. Alcance exacto

Ejecuta **Task 1** del plan tal cual: pasos 1-6 (test que falla → refactor → test que pasa → commit). Puntos clave:

- `build_agent_data(name, status, task, duration, address, ws, terminal) -> dict` con las 9 claves del contrato (`id, name, task, status, dir, ws, address, duration, terminal`). `task` cae a `status` si viene `None`.
- `build_parser() -> argparse.ArgumentParser` con **todo** el argparse actual + `--task`/`-t` en el parser raíz y en el subparser `notify`. El subparser `run` también acepta `-t`.
- `test` inyecta en el **workspace activo real** (no fuerces `-w`).
- `send_desktop_notification` usa `task` en el cuerpo cuando difiere de `status`.
- `run_wrapped_command` acepta y propaga `task`; sigue propagando el código de salida del comando envuelto.

El plan trae el código literal de cada función y el test completo — es transcripción. Si algo del plan no cuadra con el `agent-notify` real, **decide tú** lo razonable y anótalo en el informe (no bloquees).

## 4. Verificación

```
cd /home/alberviz/LinuxRicing/.worktrees/gemini-agent-notify/rgb/tests
python -m pytest test_agent_notify.py -v
```

Esperado: **6 passed**.

Y una prueba manual si tienes el shell delante:
```
python /home/alberviz/LinuxRicing/.worktrees/gemini-agent-notify/rgb/agent-notify test
```
Esperado: toast arriba a la derecha con "Antigravity" y el cuerpo con la tarea de prueba. (El pip aún no reacciona — eso es trabajo de Claude.)

## 5. Cuando termines

- Deja la rama `feat/agent-notify-cli` lista. **NO la mergees** — lo hace Claude tras revisar.
- Escribe el informe en `vault/Rice LinuxRicing/00 - Arquitectura/Tareas de Agentes/Gemini · agent-notify — INFORME.md`:
  - Archivos tocados + hashes de commit.
  - Salida de `pytest -v`.
  - Cualquier desviación del plan y por qué.
- Avisa a Alberto. Él le dirá a Claude que revise e integre.
