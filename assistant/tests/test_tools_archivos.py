"""Tools de archivos: solo planifican; el LLM nunca ejecuta un borrado."""
import pytest

from conftest import crear
from laura import archivos as a
from laura import holo
from laura.tools import archivos as t
from laura import tools as tools_mod
from test_holo import nueva


@pytest.fixture
def entorno(env, monkeypatch):
    esc, bus, _ = nueva()
    esc.retraso_relistado = 0
    monkeypatch.setattr(holo, "escena", lambda: esc)
    fs = [crear(env, f"Descargas/f{i}.txt") for i in range(3)]
    esc.listar("Descargas", [{"ruta": str(f), "nombre": f.name, "tamano": 4, "modificado": 1.0} for f in fs],
               carpeta=str(env / "Descargas"))
    esc.listador = lambda ruta: {"ok": True, "candidatos": []}
    return env, esc, bus, fs


def test_efectos_registrados():
    for n in ("borrar_archivos", "mover_archivos", "renombrar_archivo"):
        assert tools_mod.effect_of(n) == "confirm:archivos"
    assert tools_mod.effect_of("crear_carpeta") is None and tools_mod.effect_of("deshacer_archivos") is None


def test_borrar_solo_planifica(entorno):
    env, esc, bus, fs = entorno
    r = t.borrar_archivos(numeros=[2])
    assert r["ok"] and r["confirmar"] is True and fs[1].exists()
    assert a.pendiente().id == r["plan"] and "confirmar" in esc.paneles
    assert r["decir"].startswith("Voy a mandar a la papelera un archivo")


def test_borrar_sin_numero_usa_el_seleccionado(entorno):
    env, esc, bus, fs = entorno
    esc.seleccionar(3)
    assert t.borrar_archivos()["confirmar"] and a.pendiente().ops[0].origen == str(fs[2])


def test_borrar_sin_nada_seleccionado(entorno):
    r = t.borrar_archivos()
    assert r["ok"] is False and "seleccionado" in r["error"]


def test_numero_fuera_de_rango(entorno):
    assert t.borrar_archivos(numeros=[9])["error"] == "No veo la número 9."


def test_mover_uno_se_hace_directo(entorno):
    env, esc, bus, fs = entorno
    r = t.mover_archivos("Documentos", numeros=[1])
    assert r["ok"] and not r.get("confirmar") and (env / "Documentos" / "f0.txt").exists()
    assert "fx" in bus.ops()


def test_mover_a_carpeta_inexistente(entorno):
    assert "No encuentro" in t.mover_archivos("Nada", numeros=[1])["error"]


def test_mover_fuera_de_las_raices(entorno):
    env, *_ = entorno
    assert "fuera de tus carpetas" in t.mover_archivos(str(env / "otro"), numeros=[1])["error"]


def test_renombrar(entorno):
    env, esc, bus, fs = entorno
    r = t.renombrar_archivo("nuevo.txt", numero=1)
    assert r["ok"] and (env / "Descargas" / "nuevo.txt").exists()


def test_crear_carpeta_en_la_carpeta_de_la_lista(entorno):
    env, *_ = entorno
    r = t.crear_carpeta("Facturas")
    assert r["ok"] and (env / "Descargas" / "Facturas").is_dir()
    assert "Ya existe" in t.crear_carpeta("Facturas")["error"]


def test_crear_carpeta_en_otra(entorno):
    env, *_ = entorno
    assert t.crear_carpeta("Uni", en="Documentos")["ok"] and (env / "Documentos" / "Uni").is_dir()


def test_deshacer(entorno):
    env, esc, bus, fs = entorno
    assert t.deshacer_archivos()["ok"] is False
    t.renombrar_archivo("nuevo.txt", numero=1)
    r = t.deshacer_archivos()
    assert r["ok"] and fs[0].exists()


def test_confirmar_y_borrar_de_verdad(entorno):
    env, esc, bus, fs = entorno
    plan_id = t.borrar_archivos(numeros=[1, 3])["plan"]
    assert fs[0].exists() and fs[2].exists()                 # planificar no borra
    esc.control("holo-confirm", plan_id)
    assert not fs[0].exists() and not fs[2].exists() and fs[1].exists()
