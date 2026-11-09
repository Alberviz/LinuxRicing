"""Vista previa y detección de tipo de archivos para los paneles holográficos de Laura."""
from __future__ import annotations

import hashlib
import mimetypes
import os
import shutil
import subprocess
from pathlib import Path

# Inicializar tipos mime del sistema si no están cargados
if not mimetypes.inited:
    mimetypes.init()


def _default_cache_dir() -> Path:
    xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
    if xdg_runtime:
        return Path(xdg_runtime) / "laura-holo"
    uid = os.getuid() if hasattr(os, "getuid") else 1000
    return Path(f"/tmp/laura-holo-{uid}")


# Carpeta de caché de miniaturas y páginas de PDF
CACHE: Path = _default_cache_dir()

# Extensiones reconocidas por categoría
EXT_IMAGEN = {"png", "jpg", "jpeg", "webp", "gif", "bmp", "avif"}
EXT_PDF = {"pdf"}
EXT_VIDEO = {"mp4", "mkv", "webm", "mov", "avi", "m4v"}
EXT_AUDIO = {"mp3", "ogg", "oga", "opus", "wav", "flac", "m4a"}
EXT_TEXTO = {
    "md", "txt", "py", "json", "toml", "sh", "fish", "qml", "js", "ts",
    "css", "html", "yaml", "yml", "cfg", "ini", "log", "csv", "conf",
    "rs", "c", "h", "cpp", "go", "java", "kt", "lua", "sql", "xml",
}


def _detectar_mime_file(ruta: str) -> str:
    """Detecta el tipo MIME de un archivo mediante el comando `file` o `mimetypes`."""
    try:
        cmd = ["file", "--brief", "--mime-type", ruta]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        if res.returncode == 0:
            mime = res.stdout.strip().lower()
            if mime:
                return mime
    except Exception:
        pass
    guessed, _ = mimetypes.guess_type(ruta)
    return (guessed or "application/octet-stream").lower()


def tipo_de(ruta: str) -> str:
    """Clasifica una ruta en: carpeta, imagen, pdf, texto, video, audio u otro."""
    if os.path.isdir(ruta):
        return "carpeta"
    ext = Path(ruta).suffix.lower().lstrip(".")

    if ext in EXT_IMAGEN:
        return "imagen"
    if ext in EXT_PDF:
        return "pdf"
    if ext in EXT_VIDEO:
        return "video"
    if ext in EXT_AUDIO:
        return "audio"
    if ext in EXT_TEXTO:
        return "texto"

    # Si tiene una extensión conocida no-multimedia en mimetypes, se clasifica como otro
    guessed, _ = mimetypes.guess_type(ruta)
    if ext and guessed and not (
        guessed.startswith("image/")
        or guessed.startswith("video/")
        or guessed.startswith("audio/")
        or guessed.startswith("text/")
        or guessed == "application/pdf"
    ):
        return "otro"

    # Sin extensión o extensión desconocida: detección por contenido mediante file
    mime = _detectar_mime_file(ruta)
    if mime.startswith("image/"):
        return "imagen"
    if mime == "application/pdf":
        return "pdf"
    if mime.startswith("video/"):
        return "video"
    if mime.startswith("audio/"):
        return "audio"
    if mime.startswith("text/"):
        return "texto"

    return "otro"


def icono_de(ruta: str) -> str:
    """Devuelve el nombre del icono Material Symbols correspondiente para archivos 'otro'."""
    ext = Path(ruta).suffix.lower().lstrip(".")
    if ext in {"zip", "tar", "gz", "7z", "rar", "bz2", "xz"}:
        return "folder_zip"
    if ext in {"doc", "docx", "odt", "rtf"}:
        return "description"
    if ext in {"xls", "xlsx", "ods", "csv"}:
        return "table"
    if ext == "torrent":
        return "download"
    return "draft"


def _payload_otro(ruta: str, aviso: str | None = None) -> dict:
    """Construye un payload de tipo 'otro'."""
    res = {
        "tipo": "otro",
        "mime": _detectar_mime_file(ruta) if os.path.exists(ruta) else "",
        "icono": icono_de(ruta),
    }
    if aviso:
        res["aviso"] = aviso
    return res


def limpiar_cache(forzar: bool = False) -> None:
    """Borra el contenido de la caché si supera 200 MB o si forzar=True."""
    try:
        if not CACHE.exists():
            return
        total = sum(f.stat().st_size for f in CACHE.iterdir() if f.is_file())
        limite = 200 * 1024 * 1024  # 200 MB
        if forzar or total > limite:
            for item in CACHE.iterdir():
                try:
                    if item.is_file() or item.is_symlink():
                        item.unlink()
                    elif item.is_dir():
                        shutil.rmtree(item)
                except OSError:
                    pass
    except OSError:
        pass


def pagina_pdf(ruta: str, p: int) -> str | None:
    """Devuelve la ruta al PNG generado en caché para la página p (1-based), o None."""
    try:
        if not os.path.isfile(ruta):
            return None
        mtime = os.path.getmtime(ruta)
        h = hashlib.sha1(f"{ruta}{mtime}".encode("utf-8")).hexdigest()[:16]
        png_path = CACHE / f"{h}-p{p}.png"
        if png_path.is_file():
            return str(png_path)

        pdftoppm = shutil.which("pdftoppm")
        if not pdftoppm:
            return None

        CACHE.mkdir(parents=True, exist_ok=True)
        out_prefix = CACHE / f"{h}-p{p}"
        cmd = [
            pdftoppm,
            "-r", "110",
            "-f", str(p),
            "-l", str(p),
            "-png",
            "-singlefile",
            ruta,
            str(out_prefix),
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        if png_path.is_file():
            return str(png_path)
    except Exception:
        pass
    return None


def _paginas_pdf(ruta: str) -> int | None:
    """Lee el número total de páginas de un PDF mediante pdfinfo."""
    pdfinfo = shutil.which("pdfinfo")
    if not pdfinfo:
        return None
    try:
        res = subprocess.run([pdfinfo, ruta], capture_output=True, text=True, timeout=20)
        if res.returncode != 0:
            return None
        for line in res.stdout.splitlines():
            if line.startswith("Pages:"):
                partes = line.split()
                if len(partes) >= 2 and partes[1].isdigit():
                    return int(partes[1])
    except Exception:
        pass
    return None


def _poster_video(ruta: str) -> str:
    """Genera una miniatura de vídeo con ffmpegthumbnailer y devuelve su ruta o cadena vacía."""
    try:
        th = shutil.which("ffmpegthumbnailer")
        if not th:
            return ""
        mtime = os.path.getmtime(ruta)
        h = hashlib.sha1(f"{ruta}{mtime}".encode("utf-8")).hexdigest()[:16]
        poster_path = CACHE / f"{h}-poster.png"
        if poster_path.is_file():
            return str(poster_path)
        CACHE.mkdir(parents=True, exist_ok=True)
        cmd = [th, "-i", ruta, "-o", str(poster_path), "-s", "640"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        if poster_path.is_file():
            return str(poster_path)
    except Exception:
        pass
    return ""


def preparar(ruta: str, tipo: str | None = None) -> dict:
    """Prepara el payload del visor holográfico para un archivo determinado."""
    try:
        # Comprobar existencia
        if not os.path.exists(ruta):
            return {"tipo": "otro", "mime": "", "icono": "error", "aviso": "Ya no existe"}

        # Comprobar límite de 2 GB
        try:
            tamano = os.path.getsize(ruta)
            if tamano > 2 * 1024 * 1024 * 1024:
                return _payload_otro(ruta, aviso="Demasiado grande para previsualizar")
        except OSError:
            pass

        if tipo is None:
            tipo = tipo_de(ruta)

        if tipo == "carpeta":
            return {"tipo": "otro", "mime": "inode/directory", "icono": "folder"}

        if tipo == "imagen":
            w, h = 0, 0
            try:
                from PIL import Image
                with Image.open(ruta) as im:
                    w, h = im.size
            except Exception:
                pass
            return {"tipo": "imagen", "src": ruta, "w": int(w), "h": int(h)}

        if tipo == "pdf":
            if not shutil.which("pdfinfo") or not shutil.which("pdftoppm"):
                return _payload_otro(ruta, aviso="Falta poppler-utils para previsualizar el PDF")
            paginas = _paginas_pdf(ruta)
            if not paginas or paginas < 1:
                return _payload_otro(ruta, aviso="No se pudo leer la información del PDF")
            src = pagina_pdf(ruta, 1)
            if not src:
                return _payload_otro(ruta, aviso="No se pudo generar la vista previa del PDF")
            return {
                "tipo": "pdf",
                "src": src,
                "pagina": 1,
                "paginas": paginas,
            }

        if tipo == "video":
            return {
                "tipo": "video",
                "src": ruta,
                "poster": _poster_video(ruta),
            }

        if tipo == "audio":
            return {
                "tipo": "audio",
                "src": ruta,
            }

        if tipo == "texto":
            ext = Path(ruta).suffix.lower().lstrip(".")
            formato = "markdown" if ext in {"md", "markdown"} else "mono"
            with open(ruta, "rb") as f:
                raw = f.read(16384 + 1)
            mas_de_16k = len(raw) > 16384
            raw = raw[:16384]
            texto = raw.decode("utf-8", errors="replace")
            lineas = texto.splitlines(keepends=True)
            mas_de_200 = len(lineas) > 200
            if mas_de_200:
                lineas = lineas[:200]
                texto = "".join(lineas)
            truncado = mas_de_16k or mas_de_200
            return {
                "tipo": "texto",
                "texto": texto,
                "formato": formato,
                "truncado": truncado,
            }

        return _payload_otro(ruta)

    except Exception as ex:
        return _payload_otro(ruta, aviso=str(ex))
