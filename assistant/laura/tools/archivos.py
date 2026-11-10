"""Tools de Laura para gestionar archivos. Solo PLANIFICAN: confirmar y ejecutar lo hace el
daemon (ver `confirmar_archivos.py`); el LLM nunca borra ni mueve nada por su cuenta."""
from __future__ import annotations

import re
from pathlib import Path

from .. import archivos, holo
from . import tool

# Las tools de archivos solo se ofrecen al LLM si la frase habla de ello (ahorra ~650 tokens).
_PIDE = re.compile(r"\b(borra\w*|elimina\w*|mueve\w*|mover|renombra\w*|carpeta\w*|deshaz|deshacer|"
                   r"recupera\w*|papelera|nombre|p[aá]sa(?:la|lo|las|los|r)\b)", re.I)


def _hace_falta(texto: str) -> bool:
    return bool(_PIDE.search(texto))


_NUMS = {"type": "array", "items": {"type": "integer"}, "description": "números de la lista en pantalla"}


def _rutas(numeros: list[int] | None) -> list[str]:
    esc = holo.escena()
    out: list[str] = []
    for n in numeros or []:
        it = esc.resolver(n)
        if it is None:
            raise archivos.Rechazo(f"No veo la número {n}.")
        out.append(it.ruta)
    if not out:
        it = esc.resolver(None)
        if it is None:
            raise archivos.Rechazo("¿Cuál? No veo ninguno seleccionado.")
        out.append(it.ruta)
    return out


def _resultado(plan: archivos.Plan) -> dict:
    esc = holo.escena()
    if plan.requiere_confirmacion:
        archivos.registrar(plan)
        esc.mostrar_confirmacion(plan)
        return {"ok": True, "confirmar": True, "plan": plan.id, "decir": plan.pregunta(),
                "resumen": plan.titulo()}
    res = archivos.ejecutar(plan)
    esc.tras_plan(plan)
    if not res.get("ok"):
        return {"ok": False, "error": res["error"]}
    return {"ok": True, "decir": res["decir"], "resumen": plan.titulo()}


@tool("borrar_archivos",
      "Borra (papelera, con confirmación del sistema): «borra la 2», «elimina esas». Sin números, el seleccionado.",
      {"numeros": _NUMS}, icon="delete", effect="confirm:archivos", cuando=_hace_falta)
def borrar_archivos(numeros: list[int] | None = None) -> dict:
    try:
        return _resultado(archivos.planificar_borrar(_rutas(numeros), holo.escena().carpeta))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("mover_archivos",
      "Mueve a otra carpeta: «mueve la 3 a Universidad».",
      {"destino": {"type": "string", "description": "carpeta: Documentos, Universidad…"}, "numeros": _NUMS},
      required=["destino"], icon="drive_file_move", effect="confirm:archivos", cuando=_hace_falta)
def mover_archivos(destino: str, numeros: list[int] | None = None) -> dict:
    try:
        carpeta = archivos.resolver_destino(destino, holo.escena().carpeta)
        return _resultado(archivos.planificar_mover(_rutas(numeros), carpeta))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("renombrar_archivo",
      "Renombra un archivo: «renombra la 1 a factura.pdf».",
      {"nombre": {"type": "string", "description": "nombre nuevo, con extensión"},
       "numero": {"type": "integer", "description": "número de la lista"}},
      required=["nombre"], icon="edit", effect="confirm:archivos", cuando=_hace_falta)
def renombrar_archivo(nombre: str, numero: int | None = None) -> dict:
    try:
        origen = _rutas([numero] if numero else None)[0]
        return _resultado(archivos.planificar_renombrar(origen, nombre))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("crear_carpeta",
      "Crea una carpeta: «crea una carpeta Facturas».",
      {"nombre": {"type": "string", "description": "nombre"},
       "en": {"type": "string", "description": "dónde (por defecto, la carpeta que se ve)"}},
      required=["nombre"], icon="create_new_folder", cuando=_hace_falta)
def crear_carpeta(nombre: str, en: str | None = None) -> dict:
    try:
        esc = holo.escena()
        if en:
            base = archivos.resolver_destino(en, esc.carpeta)
        elif esc.carpeta:
            base = Path(esc.carpeta)
        else:
            raise archivos.Rechazo("¿Dónde la creo?")
        return _resultado(archivos.planificar_crear_carpeta(nombre, base))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("deshacer_archivos",
      "Deshace lo último hecho con archivos: «deshaz», «recupéralo».",
      {}, icon="undo", cuando=_hace_falta)
def deshacer_archivos() -> dict:
    res = archivos.deshacer()
    if not res.get("ok"):
        return {"ok": False, "error": res["error"]}
    holo.escena().refrescar(res.get("carpeta"))
    return {"ok": True, "decir": res["decir"], "resumen": "Deshecho"}
