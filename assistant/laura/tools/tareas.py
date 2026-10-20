"""Tools de tareas: el backlog de Alberto (varios proyectos) vía tasks-index."""
from __future__ import annotations

import json
import re
import subprocess
import unicodedata
from pathlib import Path

from . import tool

_TASKS_BIN = str(Path.home() / ".local/bin/tasks-index")
_ESTADO_SINON = {"pendiente": "pendiente", "por hacer": "pendiente", "en-curso": "en-curso",
                 "en curso": "en-curso", "hecha": "hecha", "hecho": "hecha", "terminada": "hecha",
                 "completada": "hecha", "terminado": "hecha"}


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def _tasks(*args: str) -> dict:
    p = _run([_TASKS_BIN, *args])
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except (IndexError, ValueError):
        return {"ok": False, "error": (p.stderr or "tasks-index no respondió").strip()}


def _n(s: str) -> str:
    """Minúsculas y sin tildes, para comparar nombres."""
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def _scan() -> list[dict] | None:
    d = _tasks("scan", "--print")
    return d.get("repos") if "repos" in d else None


def _match_repo(repos: list[dict], nombre: str) -> dict | None:
    """Proyecto por coincidencia aproximada sin tildes (exacta > prefijo > contiene)."""
    q = _n(nombre).strip()
    if not q:
        return None
    for test in (lambda r: r == q, lambda r: r.startswith(q) or q.startswith(r), lambda r: q in r):
        hits = [r for r in repos if test(_n(r["nombre"]))]
        if len(hits) == 1:
            return hits[0]
    return None


def _lista(titulos: list[str]) -> str:
    return titulos[0] if len(titulos) == 1 else ", ".join(titulos[:-1]) + " y " + titulos[-1]


def _item(r: dict, t: dict) -> dict:
    return {"proyecto": r["nombre"], "titulo": t["titulo"], "estado": t["estado"],
            "prioridad": t["prioridad"]}


@tool("listar_tareas",
      "Lee las tareas pendientes de Alberto («mis tareas», «qué tengo pendiente»). Sin proyecto da un resumen; con proyecto, las de ese proyecto. Lee el campo «decir» tal cual, sin añadir ni cambiar nada. Para cambiar su estado usa cambiar_estado.",
      {"repo": {"type": "string", "description": "proyecto (LinuxRicing, Krakount, Universidad…); vacío = resumen"},
       "estado": {"type": "string", "description": "pendiente o en-curso (opcional)"}})
def listar_tareas(repo: str = "", estado: str = "") -> dict:
    repos = _scan()
    if repos is None:
        return {"ok": False, "error": "no pude leer las tareas"}
    estado = _ESTADO_SINON.get(_n(estado), "") if estado else ""
    if repo:
        r = _match_repo(repos, repo)
        if r is None:
            return {"ok": False, "error": f"no conozco el proyecto «{repo}»",
                    "proyectos": [x["nombre"] for x in repos if x["tareas"]]}
        ts = [t for t in r["tareas"] if not estado or t["estado"] == estado]
        return {"ok": True, "proyecto": r["nombre"], "tareas": [_item(r, t) for t in ts[:8]],
                "total": len(ts), "resumen": f"Tareas de {r['nombre']}",
                "decir": (f"En {r['nombre']} tienes {len(ts)} por hacer. Las más urgentes: "
                          f"{_lista([t['titulo'] for t in ts[:5]])}." if ts
                          else f"En {r['nombre']} no tienes nada pendiente."),
                "nota": "Di el campo «decir» tal cual, sin añadir nada."}
    todas = [(r, t) for r in repos for t in r["tareas"]]
    gen = sorted((p for p in todas if p[1]["estado"] == "en-curso" or p[1]["prioridad"] <= 2),
                 key=lambda p: (p[1]["estado"] != "en-curso", p[1]["prioridad"], p[1]["titulo"]))
    en_marcha = [(r, t) for r, t in todas if t["estado"] == "en-curso"]
    por_proy = {r["nombre"]: len(r["tareas"]) for r in repos if r["tareas"]}
    cola = ", ".join(f"{n} {c}" for n, c in sorted(por_proy.items(), key=lambda kv: -kv[1]))
    if en_marcha:
        ini = f"Tienes {len(en_marcha)} en marcha: {_lista([t['titulo'] for _, t in en_marcha[:3]])}."
    elif gen:
        ini = f"Lo más urgente: {_lista([t['titulo'] for _, t in gen[:3]])}."
    else:
        ini = "No tienes nada en marcha."
    return {"ok": True, "principales": [_item(r, t) for r, t in gen[:5]],
            "pendientes_por_proyecto": por_proy, "resumen": "Resumen de tareas",
            "decir": f"{ini} Pendientes por proyecto: {cola}. ¿Quieres las de algún proyecto?",
            "nota": "Di el campo «decir» tal cual, sin añadir nada."}


@tool("crear_tarea", "Apunta una tarea nueva en el backlog de un proyecto («apunta la tarea…»).",
      {"titulo": {"type": "string", "description": "título corto de la tarea"},
       "repo": {"type": "string", "description": "proyecto (por defecto LinuxRicing)"},
       "prioridad": {"type": "integer", "description": "1 urgente … 5 algún día"},
       "area": {"type": "string", "description": "área (escritorio, rgb, agentes, infra…)"}},
      required=["titulo"])
def crear_tarea(titulo: str, repo: str = "LinuxRicing", prioridad: int = 3, area: str = "general") -> dict:
    repos = _scan() or []
    r = _match_repo(repos, repo) if repos else None
    return _tasks("add", r["nombre"] if r else repo, titulo, "-p", str(prioridad), "-a", area)


@tool("cambiar_estado",
      "Cambia el estado de una tarea: «marca X como hecha», «pon en curso lo del cometa». El proyecto es opcional (si no se da, busca en todos). Si trae candidatos, pregunta a Alberto cuál.",
      {"tarea": {"type": "string", "description": "título o parte del título de la tarea"},
       "estado": {"type": "string", "description": "pendiente, en-curso o hecha"},
       "repo": {"type": "string", "description": "proyecto (opcional)"}},
      required=["tarea", "estado"])
def cambiar_estado(tarea: str, estado: str, repo: str = "") -> dict:
    canon = _ESTADO_SINON.get(_n(estado))
    if canon is None:
        return {"ok": False, "error": f"estado no válido: {estado} (usa pendiente, en-curso o hecha)"}
    repos = _scan()
    if repos is None:
        return {"ok": False, "error": "no pude leer las tareas"}
    if repo:
        r = _match_repo(repos, repo)
        if r is None:
            return {"ok": False, "error": f"no conozco el proyecto «{repo}»"}
        repos = [r]
    palabras = [w for w in re.findall(r"\w+", _n(tarea)) if len(w) > 1]
    cands = [(r, t) for r in repos for t in r["tareas"]
             if palabras and all(w in _n(t["titulo"]) for w in palabras)]
    if not cands:
        return {"ok": False, "error": f"no encuentro ninguna tarea abierta como «{tarea}»"}
    if len(cands) > 1:
        return {"ok": False, "error": "hay varias tareas posibles; pregunta a Alberto cuál",
                "candidatos": [{"proyecto": r["nombre"], "titulo": t["titulo"]} for r, t in cands[:6]]}
    r, t = cands[0]
    res = _tasks("set", r["nombre"], t["titulo"], canon)
    if res.get("ok"):
        res["resumen"] = f"{t['titulo']}: {canon}"
        res["proyecto"] = r["nombre"]
    return res
