"""Notas de Obsidian con el resultado de cada trabajo: <vault>/Laura/AAAA-MM-DD HHMM <título>.md."""
from __future__ import annotations

import json
import os
import re
from datetime import datetime
from pathlib import Path

from .config import CFG


def vault_dir() -> Path:
    v = CFG.get("background", {}).get("vault", "~/LinuxRicing/vault")
    return Path(os.path.expanduser(v)) / "Laura"


def _titulo_corto(t: str, n: int = 50) -> str:
    t = re.sub(r'[\\/:*?"<>|\n\r\t#^\[\]]+', " ", t).strip()
    t = re.sub(r"\s+", " ", t)
    if len(t) > n:
        t = t[:n].rsplit(" ", 1)[0] or t[:n]
    return t.strip(" .") or "trabajo"


def write_note(meta: dict, cuerpo: str) -> str:
    """Escribe la nota del trabajo y devuelve su ruta absoluta."""
    d = vault_dir()
    d.mkdir(parents=True, exist_ok=True)
    creado = datetime.fromtimestamp(meta["inicio"])
    base = f"{creado:%Y-%m-%d %H%M} {_titulo_corto(meta['titulo'])}"
    path = d / f"{base}.md"
    n = 2
    while path.exists():
        path = d / f"{base} ({n}).md"
        n += 1
    fm = ["---",
          "tipo: laura-resultado",
          f"agente: {meta['destino']}",
          f"estado: {meta['estado']}",
          f"peticion: {json.dumps(meta.get('peticion') or meta['titulo'], ensure_ascii=False)}",
          f"creado: {creado.isoformat(timespec='seconds')}",
          f"job: {meta['id']}",
          "tags:", "  - laura", "---", ""]
    partes = [f"# {meta['titulo']}", ""]
    if meta.get("resumen"):
        partes += ["## Resumen", "", meta["resumen"], ""]
    partes += ["## Resultado", "", cuerpo.strip() or "(sin salida)", ""]
    if meta.get("fuentes"):
        partes += ["## Fuentes", ""] + [f"- [{f['titulo']}]({f['url']})" for f in meta["fuentes"]] + [""]
    path.write_text("\n".join(fm + partes))
    return str(path)
