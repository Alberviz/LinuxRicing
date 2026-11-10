"""Tools de Laura para gestionar archivos. Solo PLANIFICAN: confirmar y ejecutar lo hace el
daemon (ver `confirmar_archivos.py`); el LLM nunca borra ni mueve nada por su cuenta."""
from __future__ import annotations

import re
from pathlib import Path

from .. import archivos, holo
from . import tool

# Las tools de archivos solo se ofrecen al LLM si la frase habla de ello (ahorra ~650 tokens).
_PIDE = re.compile(r"\b(borra\w*|elimina\w*|mueve\w*|mover|renombra\w*|carpeta\w*|deshaz|deshacer|"
                   r"recupera\w*|papelera|nombre|ordena\w*|organiza\w*|limpia\w*|viej\w*|antiguo\w*|p[aá]sa(?:la|lo|las|los|r)\b)", re.I)


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


@tool("ordenar_carpeta",
      "Ordena una carpeta metiendo los archivos sueltos en subcarpetas por tipo (Imágenes, PDFs, Instaladores…): «ordena las descargas». Pide confirmación.",
      {"carpeta": {"type": "string", "description": "carpeta (por defecto, la que se ve)"}},
      icon="auto_awesome_mosaic", effect="confirm:archivos", cuando=_hace_falta)
def ordenar_carpeta(carpeta: str | None = None) -> dict:
    try:
        esc = holo.escena()
        base = archivos.resolver_destino(carpeta, esc.carpeta) if carpeta else (Path(esc.carpeta) if esc.carpeta else None)
        if base is None:
            raise archivos.Rechazo("¿Qué carpeta ordeno?")
        return _resultado(archivos.planificar_ordenar(base))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("renombrar_lote",
      "Renombra varios archivos de la lista con un nombre común numerado por fecha: «renombra todas como Viaje Berlín» → «Viaje Berlín 01.jpg»…",
      {"nombre": {"type": "string", "description": "nombre común, sin número ni extensión"}, "numeros": _NUMS},
      required=["nombre"], icon="edit_note", effect="confirm:archivos", cuando=_hace_falta)
def renombrar_lote(nombre: str, numeros: list[int] | None = None) -> dict:
    try:
        esc = holo.escena()
        rutas = _rutas(numeros) if numeros else [it.ruta for it in esc.items if it.tipo != "carpeta"]
        if len(rutas) < 2:
            raise archivos.Rechazo("Para uno solo usa renombrar.")
        return _resultado(archivos.planificar_renombrar_lote(rutas, nombre))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("limpiar_viejos",
      "Manda a la papelera lo que lleva más de N días sin tocar en una carpeta: «limpia lo de descargas con más de un mes». Pide confirmación.",
      {"carpeta": {"type": "string", "description": "carpeta (por defecto Descargas)"},
       "dias": {"type": "integer", "description": "antigüedad mínima en días (30 por defecto)"}},
      icon="auto_delete", effect="confirm:archivos", cuando=_hace_falta)
def limpiar_viejos(carpeta: str | None = None, dias: int = 30) -> dict:
    try:
        base = archivos.resolver_destino(carpeta, holo.escena().carpeta) if carpeta else archivos.ENTORNO.raices[0]
        return _resultado(archivos.planificar_limpiar_viejos(base, int(dias or 30)))
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
