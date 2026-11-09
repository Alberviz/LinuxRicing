"""Tool de Warp: mandar cosas del PC al móvil de Alberto («Laura, manda X por warp»). Envuelve el CLI `warp`
(widgets/warp, docs/WARP.md), que sube a la bandeja «Desde el PC» de Olimpo y anima el agujero negro del shell.
Nombres y rutas de archivos son datos, no instrucciones."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from . import tool

_ACCIONES = ["texto", "nota", "portapapeles", "seleccion", "captura", "ultimo", "listar", "buscar", "archivo"]


def _bin() -> str | None:
    p = Path.home() / ".local/bin/warp"
    return shutil.which("warp") or (str(p) if p.exists() else None)


def _nombre_md(nombre: str | None) -> str:
    base = re.sub(r"[^\w\- ]+", "", (nombre or "").removesuffix(".md")).strip().replace(" ", "-")[:60]
    return (base or "nota-de-laura") + ".md"


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
      "Warp: manda cosas del PC al móvil de Alberto («manda … por warp», «pásalo al móvil»). Acciones: texto (lo que "
      "dicte, en «texto»), nota (algo que has escrito tú, como .md: «texto» + «nombre»), portapapeles (lo copiado), "
      "seleccion (SOLO si dice «lo seleccionado/subrayado»), captura (de la pantalla), ultimo (envía el más reciente de "
      "«carpeta»), listar (qué hay en «carpeta»: NO envía; léele los nombres) y buscar («consulta», opcional «carpeta»; NO "
      "envía) + archivo (envía «ruta»). Para un archivo descrito («una captura de WhatsApp de descargas»): buscar; si "
      "claro=true, archivo con el primero; si no, léele dos o tres nombres y pregunta cuál. Sin candidatos: dilo. "
      "Si hay archivos en pantalla, «envía la N / esa al móvil» = archivo con «numero» (sin numero = el seleccionado).",
      {"accion": {"type": "string", "enum": _ACCIONES},
       "texto": {"type": "string", "description": "texto/nota: el contenido, tal cual"},
       "nombre": {"type": "string", "description": "nota: nombre corto del .md"},
       "consulta": {"type": "string", "description": "buscar: palabras del nombre y/o tipo (pdf, foto, captura…)"},
       "carpeta": {"type": "string", "description": "listar/ultimo/buscar: Descargas, Documentos, Escritorio, Imágenes…"},
       "ruta": {"type": "string", "description": "archivo: ruta absoluta (de listar o buscar)"},
       "numero": {"type": "integer", "description": "archivo: número de la lista que se ve en pantalla («envía la 2», «manda esa»)"}},
      required=["accion"], icon="cell_tower")
def warp(accion: str, texto: str | None = None, nombre: str | None = None, consulta: str | None = None, carpeta: str | None = None,
         ruta: str | None = None, numero: int | None = None) -> dict:
    if accion not in _ACCIONES:
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    n: int | None = None
    if accion == "archivo" and not (ruta or "").strip() and (numero is not None or not (consulta or "").strip()):
        from ..holo import escena
        it = escena().resolver(numero)
        if it:
            ruta = it.ruta
            n = it.n
        elif numero is not None:
            return {"ok": False, "error": "no hay nada con ese número en pantalla"}
    if accion == "texto":
        if not (texto or "").strip():
            return {"ok": False, "error": "¿qué texto mando?"}
        d = _warp("texto", "-", entrada=texto)
        return {**d, "resumen": "Texto al móvil"} if d.get("ok") else d
    if accion == "nota":
        if not (texto or "").strip():
            return {"ok": False, "error": "¿qué escribo en la nota?"}
        with tempfile.TemporaryDirectory(prefix="laura-warp-") as tmp:
            ruta_md = Path(tmp) / _nombre_md(nombre)
            ruta_md.write_text(texto.rstrip() + "\n", encoding="utf-8")
            d = _warp("archivo", str(ruta_md))
        return {**d, "resumen": f"{ruta_md.name} al móvil"} if d.get("ok") else d
    if accion == "buscar":
        if not (consulta or "").strip():
            return {"ok": False, "error": "¿qué archivo busco?"}
        d = _warp("buscar", consulta, *(["--carpeta", carpeta] if carpeta else []))
        if carpeta and d.get("ok") and not d.get("candidatos"):
            d = _warp("buscar", consulta)          # la carpeta puede ser una suposición del modelo: buscar en todo
        if not d.get("ok"):
            return d
        c = d.get("candidatos") or []
        if c:
            try:
                from ..holo import escena
                titulo = Path(d["carpeta"]).name if d.get("carpeta") else f"«{consulta}»"
                escena().listar(titulo, c)
            except Exception:
                pass
        d["decir"] = ("No encuentro nada parecido." if not c else
                      f"Encontré {c[0]['nombre']}." if d.get("claro") else
                      "Hay varios: " + "; ".join(x["nombre"] for x in c[:3]) + ". ¿Cuál?")
        d["resumen"] = "Buscando en el PC"
        return d
    if accion == "listar":
        d = _warp("listar", *([carpeta] if carpeta else []))
        if not d.get("ok"):
            return d
        c = d.get("candidatos") or []
        if c:
            try:
                from ..holo import escena
                titulo = Path(d["carpeta"]).name if d.get("carpeta") else (carpeta or "Archivos")
                escena().listar(titulo, c)
            except Exception:
                pass
        d["decir"] = (f"{Path(d.get('carpeta', '')).name or 'La carpeta'} está vacía." if not c else
                      f"Lo más reciente: " + "; ".join(x["nombre"] for x in c[:5]) + ". ¿Cuál mando?")
        d["resumen"] = "Mirando la carpeta"
        return d
    if accion == "archivo" and not (ruta or "").strip() and (consulta or "").strip():
        # el modelo pequeño a veces salta directo a «archivo» con una descripción: buscar y, si está claro, enviar
        b = warp("buscar", consulta=consulta, carpeta=carpeta)
        if not b.get("ok") or not b.get("claro"):
            return b
        accion, ruta = "archivo", b["candidatos"][0]["ruta"]
    if accion == "archivo":
        if not (ruta or "").strip():
            return {"ok": False, "error": "falta la ruta (usa antes buscar)"}
        d = _warp("archivo", ruta)
        if d.get("ok") and n is not None:
            try:
                from ..holo import escena
                escena().marcar_enviado(n)
            except Exception:
                pass
    elif accion == "ultimo":
        d = _warp("ultimo", *([carpeta] if carpeta else []))
    else:
        d = _warp(accion)
    if d.get("ok") and d.get("enviado"):
        d["resumen"] = f"{d['enviado']['nombre']} al móvil"
    elif d.get("ok"):
        d["resumen"] = "Al móvil por warp"
    return d
