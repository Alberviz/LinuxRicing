"""Vista previa de archivos para los hologramas de Laura (sin pdftoppm real)."""
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura import holo_preview as hp  # noqa: E402


@pytest.fixture(autouse=True)
def cache(tmp_path, monkeypatch):
    monkeypatch.setattr(hp, "CACHE", tmp_path / "cache")


@pytest.mark.parametrize("nombre,tipo", [
    ("a.PNG", "imagen"), ("b.jpeg", "imagen"), ("c.pdf", "pdf"), ("d.mp4", "video"),
    ("e.ogg", "audio"), ("f.md", "texto"), ("g.py", "texto"), ("h.torrent", "otro"),
])
def test_tipo_por_extension(tmp_path, nombre, tipo):
    p = tmp_path / nombre
    p.write_bytes(b"x")
    assert hp.tipo_de(str(p)) == tipo


def test_texto_truncado_y_formato(tmp_path):
    p = tmp_path / "notas.md"
    p.write_text("\n".join(f"línea {i}" for i in range(500)), encoding="utf-8")
    d = hp.preparar(str(p), "texto")
    assert d["tipo"] == "texto" and d["formato"] == "markdown" and d["truncado"]
    assert d["texto"].count("\n") <= 200
    q = tmp_path / "main.py"
    q.write_text("print('hola')\n")
    d = hp.preparar(str(q), "texto")
    assert d["formato"] == "mono" and not d["truncado"] and "hola" in d["texto"]


def test_inexistente(tmp_path):
    d = hp.preparar(str(tmp_path / "nada.png"), "imagen")
    assert d == {"tipo": "otro", "mime": "", "icono": "error", "aviso": "Ya no existe"}


def test_imagen_con_tamano(tmp_path):
    from PIL import Image
    p = tmp_path / "c.png"
    Image.new("RGB", (30, 20)).save(p)
    d = hp.preparar(str(p), "imagen")
    assert d == {"tipo": "imagen", "src": str(p), "w": 30, "h": 20}


def test_pdf_sin_poppler_es_otro(tmp_path, monkeypatch):
    p = tmp_path / "x.pdf"
    p.write_bytes(b"%PDF-1.4")
    monkeypatch.setattr(hp.shutil, "which", lambda _: None)
    d = hp.preparar(str(p), "pdf")
    assert d["tipo"] == "otro" and d.get("aviso")


def test_pdf_con_poppler_falso(tmp_path, monkeypatch):
    p = tmp_path / "x.pdf"
    p.write_bytes(b"%PDF-1.4")
    llamadas = []

    def run(cmd, **kw):
        llamadas.append(cmd)
        class R:
            returncode = 0
            stdout = "Title: x\nPages:          12\n"
        if cmd[0].endswith("pdftoppm"):
            Path(cmd[-1] + ".png").parent.mkdir(parents=True, exist_ok=True)
            Path(cmd[-1] + ".png").write_bytes(b"png")
        return R()
    monkeypatch.setattr(hp.shutil, "which", lambda b: f"/usr/bin/{b}")
    monkeypatch.setattr(hp.subprocess, "run", run)
    d = hp.preparar(str(p), "pdf")
    assert d["tipo"] == "pdf" and d["paginas"] == 12 and d["pagina"] == 1 and d["src"].endswith("-p1.png")
    assert hp.pagina_pdf(str(p), 3).endswith("-p3.png")
    n = len(llamadas)
    hp.pagina_pdf(str(p), 3)          # en caché: no vuelve a llamar a pdftoppm
    assert len(llamadas) == n


def test_audio(tmp_path):
    p = tmp_path / "cancion.mp3"
    p.write_bytes(b"ID3")
    d = hp.preparar(str(p), "audio")
    assert d == {"tipo": "audio", "src": str(p)}


def test_video_con_y_sin_thumbnailer(tmp_path, monkeypatch):
    p = tmp_path / "clip.mp4"
    p.write_bytes(b"video")

    # Sin ffmpegthumbnailer
    monkeypatch.setattr(hp.shutil, "which", lambda _: None)
    d = hp.preparar(str(p), "video")
    assert d == {"tipo": "video", "src": str(p), "poster": ""}

    # Con ffmpegthumbnailer falso
    def fake_which(cmd):
        return f"/usr/bin/{cmd}"

    def fake_run(cmd, **kw):
        if "ffmpegthumbnailer" in cmd[0]:
            # El flag -o indica la ruta del poster
            idx = cmd.index("-o")
            out_file = Path(cmd[idx + 1])
            out_file.parent.mkdir(parents=True, exist_ok=True)
            out_file.write_bytes(b"poster")
        class R:
            returncode = 0
            stdout = ""
        return R()

    monkeypatch.setattr(hp.shutil, "which", fake_which)
    monkeypatch.setattr(hp.subprocess, "run", fake_run)
    d2 = hp.preparar(str(p), "video")
    assert d2["tipo"] == "video" and d2["src"] == str(p) and d2["poster"].endswith("-poster.png")


def test_archivo_demasiado_grande(tmp_path, monkeypatch):
    p = tmp_path / "grande.iso"
    p.write_bytes(b"iso")
    # Simulamos tamaño > 2 GB
    monkeypatch.setattr(os.path, "getsize", lambda _: 3 * 1024 * 1024 * 1024)
    d = hp.preparar(str(p), "otro")
    assert d["tipo"] == "otro" and d["aviso"] == "Demasiado grande para previsualizar"


def test_iconos_otro(tmp_path):
    archivos = [
        ("archivo.zip", "folder_zip"),
        ("documento.docx", "description"),
        ("hoja.xlsx", "table"),
        ("algo.torrent", "download"),
        ("desconocido.bin", "draft"),
    ]
    for nom, icono_esperado in archivos:
        p = tmp_path / nom
        p.write_bytes(b"datos")
        d = hp.preparar(str(p), "otro")
        assert d["tipo"] == "otro" and d["icono"] == icono_esperado


def test_tipo_sin_extension_detectado_por_file(tmp_path):
    # Archivo sin extensión que contiene un script de shell
    p = tmp_path / "mi_script"
    p.write_text("#!/bin/bash\necho test\n", encoding="utf-8")
    assert hp.tipo_de(str(p)) == "texto"


def test_limpiar_cache(tmp_path):
    c = tmp_path / "cache"
    c.mkdir(parents=True, exist_ok=True)
    f1 = c / "item1.png"
    f1.write_bytes(b"x" * 100)
    # Sin forzar y menor que 200MB no borra
    hp.limpiar_cache(forzar=False)
    assert f1.exists()
    # Con forzar borra el contenido
    hp.limpiar_cache(forzar=True)
    assert not f1.exists()
