"""Herramientas de Laura para enseñar y abrir archivos en paneles holográficos."""
from __future__ import annotations

import re
from pathlib import Path

from . import tool
from . import warp
from .. import holo


def _num_palabra(n: int) -> str:
    """Convierte números del 1 al 12 en su forma léxica en español."""
    palabras = {
        1: "una",
        2: "dos",
        3: "tres",
        4: "cuatro",
        5: "cinco",
        6: "seis",
        7: "siete",
        8: "ocho",
        9: "nueve",
        10: "diez",
        11: "once",
        12: "doce",
    }
    return palabras.get(n, str(n))


def _nombre_corto(nombre: str) -> str:
    """Quita la extensión y recorta a 40 caracteres."""
    stem = Path(nombre).stem
    if len(stem) > 40:
        return stem[:39] + "…"
    return stem


@tool(
    "mostrar_archivos",
    "Enseña en pantalla (hologramas) los archivos de una carpeta o los que coinciden con una búsqueda: «lístame/enséñame las descargas», «qué hay en Documentos», «busca el pdf de redes». Abre un panel con la lista numerada. Para ENVIAR al móvil usa warp.",
    {
        "carpeta": {
            "type": "string",
            "description": "Descargas, Documentos, Escritorio, Imágenes…",
        },
        "consulta": {
            "type": "string",
            "description": "palabras del nombre y/o tipo (pdf, foto, captura…)",
        },
    },
    icon="folder_open",
)
def mostrar_archivos(carpeta: str | None = None, consulta: str | None = None) -> dict:
    if consulta:
        d = warp._warp("buscar", consulta, *(["--carpeta", carpeta] if carpeta else []))
        if carpeta and d.get("ok") and not d.get("candidatos"):
            d = warp._warp("buscar", consulta)
    else:
        d = warp._warp("listar", *([carpeta] if carpeta else []))

    if not d.get("ok"):
        return d

    candidatos = d.get("candidatos") or []
    titulo = Path(d["carpeta"]).name if d.get("carpeta") else (f"«{consulta}»" if consulta else (carpeta or "Archivos"))

    items = holo.escena().listar(titulo, candidatos)
    n = len(items)

    if n == 0:
        decir = "No hay nada."
    elif n == 1:
        decir = f"Tienes una cosa; la más reciente es {_nombre_corto(items[0].nombre)}."
    elif any(it.tipo == "carpeta" for it in items):
        nc = sum(it.tipo == "carpeta" for it in items)
        decir = f"Tienes {_num_palabra(n)} cosas, {_num_palabra(nc)} de ellas carpetas."
    else:
        decir = f"Tienes {_num_palabra(n)} cosas; la más reciente es {_nombre_corto(items[0].nombre)}."

    return {
        "ok": True,
        "decir": decir,
        "resumen": f"{titulo} en pantalla",
        "n": n,
    }


@tool(
    "abrir",
    "Abre en pantalla uno o varios archivos de la lista que se ve («ábreme la 1 y la 2», «enséñame esa captura», «abre el pdf»): «numeros» de la lista; o «ruta» si viene de otra herramienta.",
    {
        "numeros": {
            "type": "array",
            "items": {"type": "integer"},
            "description": "números de la lista que se ve en pantalla",
        },
        "ruta": {
            "type": "string",
            "description": "ruta absoluta del archivo a abrir",
        },
    },
    icon="visibility",
)
def abrir(numeros: list[int] | None = None, ruta: str | None = None) -> dict:
    res = holo.escena().abrir(numeros=numeros, ruta=ruta)
    if not res.get("ok"):
        return res

    if res.get("carpeta"):
        n = res.get("n", 0)
        decir = "Está vacía." if n == 0 else f"En {res['carpeta']} tienes {_num_palabra(n)} cosas."
        return {"ok": True, "decir": decir, "resumen": f"Dentro de {res['carpeta']}", "n": n}

    abiertos = res.get("abiertos", [])
    nombres = [it.nombre for it in abiertos]
    decir = "Ahí lo tienes." if len(abiertos) == 1 else "Ahí los tienes."
    resumen = "Abriendo " + ", ".join(nombres)
    return {
        "ok": True,
        "decir": decir,
        "resumen": resumen,
        "abiertos": nombres,   # nombres, no Item: el resultado va en JSON al LLM
    }


@tool(
    "cerrar_holo",
    "Cierra hologramas: «cierra eso / cierra todo» (todo=true) o «cierra la 2» (numeros).",
    {
        "numeros": {
            "type": "array",
            "items": {"type": "integer"},
            "description": "números de los visores a cerrar",
        },
        "todo": {
            "type": "boolean",
            "description": "true para cerrar todos los hologramas",
        },
    },
    icon="close",
)
def cerrar_holo(numeros: list[int] | None = None, todo: bool = False) -> dict:
    n = holo.escena().cerrar(numeros, todo or not numeros)
    return {
        "ok": True,
        "decir": "Hecho.",
        "resumen": "Hologramas cerrados",
        "n": n,
    }


@tool(
    "mostrar_nota",
    "Pone en pantalla un texto que TÚ escribes (holograma): un resumen, una lista, una receta, pasos, una explicación larga… "
    "Úsala cuando Alberto diga «ponlo en pantalla», «enséñamelo escrito», «hazme una lista de…» o cuando la respuesta sea "
    "demasiado larga para decirla. Markdown corto (títulos ##, listas -, **negrita**).",
    {"titulo": {"type": "string", "description": "título corto"},
     "texto": {"type": "string", "description": "contenido en markdown"}},
    required=["titulo", "texto"],
    icon="sticky_note_2",
    cuando=lambda t: bool(re.search(r"pantalla|escrit|lista|res[uú]m|pasos|receta|nota|apunt|expl[ií]ca", t, re.I)),
)
def mostrar_nota(titulo: str, texto: str) -> dict:
    import hashlib
    pid = "nota-" + hashlib.md5(titulo.encode()).hexdigest()[:6]
    holo.escena().mostrar_datos(pid, titulo[:60], {"tipo": "texto", "formato": "markdown", "texto": texto[:16000],
                                                   "truncado": len(texto) > 16000}, "sticky_note_2")
    return {"ok": True, "resumen": "Nota en pantalla", "nota": "Ya está en pantalla: di solo una frase corta."}
