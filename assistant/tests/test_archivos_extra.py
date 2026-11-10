import os
import zipfile

from laura import archivos, holo
from laura.holo import Escena
from laura.tools import archivos_extra as ax


def _prep(tmp_path, monkeypatch):
    e = Escena(emit=lambda **ev: None)
    monkeypatch.setattr(holo, "escena", lambda: e)
    monkeypatch.setattr(archivos.ENTORNO, "raices", [tmp_path])
    (tmp_path / "a.txt").write_text("hola hipoteca")
    (tmp_path / "b.txt").write_text("hola hipoteca")
    (tmp_path / "grande.bin").write_bytes(b"x" * 5000)
    os.utime(tmp_path / "grande.bin", (1, 1))
    return e


def test_duplicados_deja_el_original(tmp_path, monkeypatch):
    e = _prep(tmp_path, monkeypatch)
    r = ax.duplicados(str(tmp_path))
    assert r["total"] == 1 and len(e.items) == 1


def test_grandes_y_viejos(tmp_path, monkeypatch):
    e = _prep(tmp_path, monkeypatch)
    ax.grandes_viejos("grandes", str(tmp_path))
    assert e.items[0].nombre == "grande.bin"
    ax.grandes_viejos("viejos", str(tmp_path))
    assert e.items[0].nombre == "grande.bin"


def test_buscar_contenido_y_comprimir_y_leer(tmp_path, monkeypatch):
    e = _prep(tmp_path, monkeypatch)
    r = ax.buscar_contenido("hipoteca", str(tmp_path))
    assert r["n"] == 2
    assert "hipoteca" in ax.leer_archivo(1)["texto"]
    z = ax.comprimir([1, 2], "pack")
    assert z["ok"] and len(zipfile.ZipFile(z["zip"]).namelist()) == 2 and z["zip"].endswith("pack.zip")
    assert not ax.leer_archivo(1)["ok"]  # tras relistar, la 1 es el zip
