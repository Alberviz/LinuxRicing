"""Tools de tareas: el backlog de Alberto vía tasks-index."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

from . import tool


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


_TASKS_BIN = str(Path.home() / ".local/bin/tasks-index")


def _tasks(*args: str) -> dict:
    p = _run([_TASKS_BIN, *args])
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except (IndexError, ValueError):
        return {"ok": False, "error": (p.stderr or "tasks-index no respondió").strip()}


@tool("listar_tareas", "Lista las tareas pendientes de Alberto de todos sus repos. Úsala cuando pregunte qué tiene que hacer o qué tiene pendiente.",
      {"repo": {"type": "string", "description": "limitar a un repo (LinuxRicing, Universidad, Minecraft, OpenGym)"},
       "estado": {"type": "string", "description": "pendiente, en-curso o hecha"}})
def listar_tareas(repo: str = "", estado: str = "") -> dict:
    """Tareas abiertas. Sin filtros: las en curso y las de prioridad 1-2."""
    d = _tasks("scan", "--print")
    if "repos" not in d:
        return d
    out = []
    for r in d["repos"]:
        if repo and r["nombre"].lower() != repo.lower():
            continue
        for t in r["tareas"]:
            if estado and t["estado"] != estado:
                continue
            if not estado and not (t["estado"] == "en-curso" or t["prioridad"] <= 2):
                continue
            out.append({"repo": r["nombre"], "titulo": t["titulo"],
                        "estado": t["estado"], "prioridad": t["prioridad"]})
    return {"ok": True, "tareas": out[:15], "total": len(out)}


@tool("crear_tarea", "Apunta una tarea nueva en el backlog de un repo (por defecto LinuxRicing).",
      {"titulo": {"type": "string", "description": "título corto de la tarea"},
       "repo": {"type": "string", "description": "repo donde apuntarla"},
       "prioridad": {"type": "integer", "description": "1 urgente … 5 algún día"},
       "area": {"type": "string", "description": "área (escritorio, rgb, agentes, infra…)"}},
      required=["titulo"])
def crear_tarea(titulo: str, repo: str = "LinuxRicing", prioridad: int = 3, area: str = "general") -> dict:
    return _tasks("add", repo, titulo, "-p", str(prioridad), "-a", area)


@tool("cambiar_estado",
      "Cambia el estado de una tarea existente (pendiente, en-curso, hecha). Si la respuesta trae `candidatos`, pregunta a Alberto cuál de ellos quiere en vez de adivinar.",
      {"tarea": {"type": "string", "description": "título o parte del título de la tarea"},
       "estado": {"type": "string", "description": "pendiente, en-curso o hecha"},
       "repo": {"type": "string", "description": "repo de la tarea"}},
      required=["tarea", "estado"])
def cambiar_estado(tarea: str, estado: str, repo: str = "LinuxRicing") -> dict:
    """estado: pendiente | en-curso | hecha. Si el nombre es ambiguo devuelve candidatos."""
    return _tasks("set", repo, tarea, estado)
