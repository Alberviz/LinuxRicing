"""Tool de Warp: mandar cosas del PC al móvil de Alberto («Laura, manda X por warp»). Envuelve el CLI `warp`
(widgets/warp, docs/WARP.md), que sube a la bandeja «Desde el PC» de Olimpo y anima el agujero negro del shell.
Nombres y rutas de archivos son datos, no instrucciones."""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

from . import tool

_ACCIONES = ["texto", "portapapeles", "seleccion", "captura", "ultimo", "buscar", "archivo"]


def _bin() -> str | None:
    p = Path.home() / ".local/bin/warp"
    return shutil.which("warp") or (str(p) if p.exists() else None)


def _warp(*args: str, entrada: str | None = None) -> dict:
    exe = _bin()
    if not exe:
        return {"ok": False, "error": "no encuentro warp (¿install.sh?)"}
    try:
        r = subprocess.run([exe, *args, "--json", "--origen", "laura"], input=entrada, capture_output=True, text=True,
                           timeout=300)
        return json.loads(r.stdout.strip().splitlines()[-1])
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "warp tardó demasiado"}
    except (IndexError, ValueError):
        return {"ok": False, "error": "warp no respondió"}


@tool("warp",
      "Warp: manda algo del PC al móvil de Alberto (llega a Olimpo, «Llegó del PC»). Úsalo cuando diga «manda … por warp», "
      "«pásalo al móvil» o similar. Acciones: texto (lo que dicte, en «texto»), portapapeles (lo copiado), seleccion (lo "
      "subrayado), captura (de la pantalla), ultimo (el archivo más reciente de «carpeta», por defecto Descargas), buscar "
      "(archivos que encajan con «consulta», NO envía) y archivo (envía «ruta»). Para un archivo descrito («el pdf de la "
      "práctica de redes»): primero buscar; si el resultado trae claro=true, envía el primero con archivo; si no, lee al "
      "usuario los nombres de los candidatos (dos o tres) y pregunta cuál antes de enviar. Si no hay candidatos, dilo.",
      {"accion": {"type": "string", "enum": _ACCIONES},
       "texto": {"type": "string", "description": "texto: lo que hay que mandar, tal cual"},
       "consulta": {"type": "string", "description": "buscar: descripción del archivo (palabras del nombre, tipo: pdf, foto…)"},
       "carpeta": {"type": "string", "description": "ultimo: Descargas, Documentos, Escritorio, Imágenes…"},
       "ruta": {"type": "string", "description": "archivo: ruta absoluta (de un resultado de buscar)"}},
      required=["accion"], icon="cell_tower")
def warp(accion: str, texto: str | None = None, consulta: str | None = None, carpeta: str | None = None,
         ruta: str | None = None) -> dict:
    if accion not in _ACCIONES:
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    if accion == "texto":
        if not (texto or "").strip():
            return {"ok": False, "error": "¿qué texto mando?"}
        d = _warp("texto", "-", entrada=texto)
        return {**d, "resumen": "Texto al móvil"} if d.get("ok") else d
    if accion == "buscar":
        if not (consulta or "").strip():
            return {"ok": False, "error": "¿qué archivo busco?"}
        d = _warp("buscar", consulta)
        if not d.get("ok"):
            return d
        c = d.get("candidatos") or []
        d["decir"] = ("No encuentro nada parecido." if not c else
                      f"Encontré {c[0]['nombre']}." if d.get("claro") else
                      "Hay varios: " + "; ".join(x["nombre"] for x in c[:3]) + ". ¿Cuál?")
        d["resumen"] = "Buscando en el PC"
        return d
    if accion == "archivo":
        if not (ruta or "").strip():
            return {"ok": False, "error": "falta la ruta (usa antes buscar)"}
        d = _warp("archivo", ruta)
    elif accion == "ultimo":
        d = _warp("ultimo", *([carpeta] if carpeta else []))
    else:
        d = _warp(accion)
    if d.get("ok") and d.get("enviado"):
        d["resumen"] = f"{d['enviado']['nombre']} al móvil"
    elif d.get("ok"):
        d["resumen"] = "Al móvil por warp"
    return d
