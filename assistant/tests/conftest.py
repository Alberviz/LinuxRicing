"""Fixtures compartidas de los tests de Laura."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura import archivos  # noqa: E402


@pytest.fixture
def env(tmp_path, monkeypatch):
    """Raíces falsas (Descargas, Documentos, proyectos), papelera y diario en tmp_path."""
    raices = []
    for nombre in ("Descargas", "Documentos", "proyectos"):
        d = tmp_path / nombre
        d.mkdir()
        raices.append(d)
    entorno = archivos.Entorno(raices=raices, diario=tmp_path / "estado" / "archivos.jsonl",
                               papelera=tmp_path / "Trash", max_ops=50, ttl=60.0)
    monkeypatch.setattr(archivos, "ENTORNO", entorno)
    monkeypatch.setattr(archivos, "_PLANES", {})
    return tmp_path


def crear(base: Path, nombre: str, contenido: str = "hola") -> Path:
    p = base / nombre
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(contenido)
    return p
