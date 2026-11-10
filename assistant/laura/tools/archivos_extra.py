"""Laura Archivos fases 2-4 (lo seguro): buscar por contenido, duplicados, grandes/viejos,
comprimir y leer para resumir. Nada destruye: borrar lo que salga sigue pasando por
borrar_archivos (con confirmación)."""
from __future__ import annotations

import hashlib
import subprocess
import time
import zipfile
from pathlib import Path

from .. import archivos, holo
from . import tool

_OCULTO = ("/.", "/node_modules/", "/__pycache__/", "/.venv/")


def _carpeta(nombre: str | None) -> Path:
    if nombre:
        return archivos.resolver_destino(nombre, holo.escena().carpeta)
    if holo.escena().carpeta:
        return Path(holo.escena().carpeta)
    return archivos.ENTORNO.raices[0]


def _ficheros(base: Path, maximo: int = 5000):
    n = 0
    for p in base.rglob("*"):
        if n >= maximo:
            return
        s = str(p)
        if any(o in s for o in _OCULTO) or not p.is_file() or p.is_symlink():
            continue
        n += 1
        yield p


def _entrada(p: Path) -> dict:
    st = p.stat()
    return {"ruta": str(p), "nombre": p.name, "tamano": st.st_size, "modificado": st.st_mtime}


def _mostrar(titulo: str, rutas: list[Path], carpeta: Path | None = None) -> int:
    holo.escena().listar(titulo, [_entrada(p) for p in rutas[:12]], str(carpeta) if carpeta else None)
    return min(len(rutas), 12)


def _err(e: Exception) -> dict:
    return {"ok": False, "error": str(e)}


@tool("buscar_contenido",
      "Busca archivos por lo que pone DENTRO de ellos («el archivo que HABLA DE X», «en qué documento puse lo de la hipoteca»). Si nombra el archivo o su tipo («el pdf de redes», «la foto de…») usa mostrar_archivos, no esta.",
      {"texto": {"type": "string", "description": "qué pone dentro"},
       "carpeta": {"type": "string", "description": "carpeta (opcional): descargas, documentos…"}},
      required=["texto"], icon="manage_search")
def buscar_contenido(texto: str, carpeta: str = "") -> dict:
    try:
        base = _carpeta(carpeta) if carpeta else None
    except archivos.Rechazo as e:
        return _err(e)
    bases = [base] if base else list(archivos.ENTORNO.raices)
    hallados: list[Path] = []
    for b in bases:
        if not b.exists():
            continue
        r = subprocess.run(["rg", "-l", "-i", "-F", "--max-filesize", "5M", "-g", "!*.lock", texto, str(b)],
                           capture_output=True, text=True, timeout=20)
        hallados += [Path(x) for x in r.stdout.splitlines() if x]
        for pdf in list(b.rglob("*.pdf"))[:150]:  # rg no mira dentro de los PDF
            if len(hallados) >= 24:
                break
            try:
                t = subprocess.run(["pdftotext", "-l", "15", str(pdf), "-"], capture_output=True, text=True, timeout=8).stdout
            except subprocess.TimeoutExpired:
                continue
            if texto.lower() in t.lower():
                hallados.append(pdf)
    hallados = sorted(set(hallados), key=lambda p: -p.stat().st_mtime)
    n = _mostrar(f"«{texto}» dentro", hallados, base)
    return {"ok": True, "n": n, "resumen": f"{n} archivos con «{texto}»",
            "decir": f"He encontrado {len(hallados)} archivos que hablan de {texto}." if hallados else f"Ningún archivo habla de {texto}."}


@tool("duplicados",
      "Busca archivos repetidos (mismo contenido) en una carpeta y enseña las copias sobrantes («hay duplicados en descargas»). Para borrarlas, luego borrar_archivos.",
      {"carpeta": {"type": "string", "description": "carpeta (opcional)"}}, icon="content_copy")
def duplicados(carpeta: str = "") -> dict:
    try:
        base = _carpeta(carpeta)
    except archivos.Rechazo as e:
        return _err(e)
    por_tam: dict[int, list[Path]] = {}
    for p in _ficheros(base):
        sz = p.stat().st_size
        if sz > 0:
            por_tam.setdefault(sz, []).append(p)
    copias: list[Path] = []
    for grupo in (g for g in por_tam.values() if len(g) > 1):
        por_hash: dict[str, list[Path]] = {}
        for p in grupo:
            h = hashlib.blake2b(p.read_bytes() if p.stat().st_size < 64 << 20 else p.open("rb").read(64 << 20)).hexdigest()
            por_hash.setdefault(h, []).append(p)
        for g in por_hash.values():
            if len(g) > 1:
                g.sort(key=lambda p: (p.stat().st_mtime, len(p.name)))  # se queda el más antiguo
                copias += g[1:]
    sobra = sum(p.stat().st_size for p in copias)
    n = _mostrar(f"Duplicados · {base.name}", copias, base)
    return {"ok": True, "n": n, "total": len(copias), "resumen": f"{len(copias)} duplicados",
            "decir": (f"Hay {len(copias)} copias repetidas que ocupan {archivos._tam_humano(sobra)}; están en pantalla."
                      if copias else f"No hay duplicados en {base.name}.")}


@tool("grandes_viejos",
      "Enseña lo que más ocupa o lo más antiguo sin tocar de una carpeta («qué ocupa más en descargas», «qué hay viejo en descargas»).",
      {"criterio": {"type": "string", "enum": ["grandes", "viejos"]},
       "carpeta": {"type": "string", "description": "carpeta (opcional)"}},
      required=["criterio"], icon="data_usage")
def grandes_viejos(criterio: str, carpeta: str = "") -> dict:
    try:
        base = _carpeta(carpeta)
    except archivos.Rechazo as e:
        return _err(e)
    fs = list(_ficheros(base))
    if criterio == "viejos":
        fs.sort(key=lambda p: p.stat().st_mtime)
        titulo = f"Lo más viejo · {base.name}"
    else:
        fs.sort(key=lambda p: -p.stat().st_size)
        titulo = f"Lo que más ocupa · {base.name}"
    top = fs[:12]
    n = _mostrar(titulo, top, base)
    if not top:
        return {"ok": True, "n": 0, "decir": f"{base.name} está vacía."}
    if criterio == "viejos":
        dias = int((time.time() - top[0].stat().st_mtime) / 86400)
        decir = f"Lo más antiguo es {top[0].name}, de hace {dias} días."
    else:
        decir = f"Lo que más ocupa es {top[0].name}, {archivos._tam_humano(top[0].stat().st_size)}; entre los {n} suman {archivos._tam_humano(sum(p.stat().st_size for p in top))}."
    return {"ok": True, "n": n, "resumen": titulo, "decir": decir}


@tool("comprimir",
      "Comprime en un .zip los archivos de la lista en pantalla («comprime la 1 y la 2», «hazme un zip con esas»). No borra los originales.",
      {"numeros": {"type": "array", "items": {"type": "integer"}, "description": "números de la lista"},
       "nombre": {"type": "string", "description": "nombre del zip (opcional)"}},
      icon="folder_zip")
def comprimir(numeros: list[int] | None = None, nombre: str = "") -> dict:
    esc = holo.escena()
    nums = numeros or ([esc.seleccionado] if esc.seleccionado else [it.n for it in esc.items])
    rutas = [Path(it.ruta) for n in nums if (it := esc.resolver(n))]
    if not rutas:
        return {"ok": False, "error": "no veo archivos en pantalla"}
    dest_dir = rutas[0].parent
    base = (nombre or (rutas[0].stem if len(rutas) == 1 else "comprimido")).removesuffix(".zip")
    dest = archivos._libre(dest_dir, base + ".zip")
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        for r in rutas:
            if r.is_dir():
                for f in r.rglob("*"):
                    if f.is_file():
                        z.write(f, f.relative_to(r.parent))
            else:
                z.write(r, r.name)
    if esc.carpeta:
        esc.refrescar(esc.carpeta)
    return {"ok": True, "zip": str(dest), "resumen": f"{dest.name} creado",
            "decir": f"Hecho, {dest.name}, {archivos._tam_humano(dest.stat().st_size)}."}


@tool("leer_archivo",
      "Lee un ARCHIVO de la lista de archivos en pantalla para resumirlo («resúmeme la 2», «resume la tres», «de qué va ese pdf»). Si el resumen es largo, ponlo con mostrar_nota.",
      {"numero": {"type": "integer", "description": "número de la lista (vacío = el seleccionado)"}},
      icon="article")
def leer_archivo(numero: int = 0) -> dict:
    it = holo.escena().resolver(numero or None)
    if it is None:
        return {"ok": False, "error": "no veo ese archivo"}
    p = Path(it.ruta)
    if it.tipo not in ("texto", "pdf"):
        return {"ok": False, "error": f"{p.name} no es un texto ni un PDF; no lo puedo leer"}
    try:
        if p.suffix.lower() == ".pdf":
            txt = subprocess.run(["pdftotext", "-l", "12", str(p), "-"], capture_output=True, text=True, timeout=15).stdout
        else:
            txt = p.read_text(errors="replace")[:20000]
    except (OSError, subprocess.TimeoutExpired) as e:
        return _err(e)
    txt = " ".join(txt.split())
    return {"ok": True, "nombre": p.name, "texto": txt[:3500], "recortado": len(txt) > 3500,
            "resumen": f"Leyendo {p.name}",
            "nota": "Resume en 2-3 frases; si piden detalle o es largo, usa mostrar_nota con un resumen en markdown."}
