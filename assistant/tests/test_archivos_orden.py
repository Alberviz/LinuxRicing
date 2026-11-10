import os

import pytest

from laura import archivos


@pytest.fixture
def base(tmp_path, monkeypatch):
    monkeypatch.setattr(archivos.ENTORNO, "raices", [tmp_path])
    for n in ("foto.JPG", "doc.pdf", "setup.AppImage", "raro.xyz"):
        (tmp_path / n).write_text(n)
    (tmp_path / "sub").mkdir()
    return tmp_path


def test_ordenar_por_tipo_y_deshacer(base, monkeypatch):
    monkeypatch.setattr(archivos.ENTORNO, "diario", base / "diario.jsonl")
    plan = archivos.planificar_ordenar(base)
    assert plan.requiere_confirmacion
    destinos = {os.path.basename(o.origen): os.path.basename(os.path.dirname(o.destino)) for o in plan.ops}
    assert destinos == {"foto.JPG": "Imágenes", "doc.pdf": "PDFs", "setup.AppImage": "Instaladores", "raro.xyz": "Otros"}
    assert archivos.ejecutar(plan)["ok"]
    assert (base / "PDFs" / "doc.pdf").exists() and not (base / "doc.pdf").exists()
    assert archivos.deshacer()["ok"]
    assert (base / "doc.pdf").exists()


def test_renombrar_lote_numera_por_fecha(base):
    a, b = base / "foto.JPG", base / "doc.pdf"
    os.utime(b, (1, 1))
    plan = archivos.planificar_renombrar_lote([str(a), str(b)], "Viaje")
    assert [os.path.basename(o.destino) for o in plan.ops] == ["Viaje 01.pdf", "Viaje 02.jpg"]


def test_limpiar_viejos(base):
    os.utime(base / "raro.xyz", (1, 1))
    plan = archivos.planificar_limpiar_viejos(base, 30)
    assert plan.accion == "borrar" and [os.path.basename(o.origen) for o in plan.ops] == ["raro.xyz"]
    with pytest.raises(archivos.Rechazo):
        archivos.planificar_limpiar_viejos(base, 2)
