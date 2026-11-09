"""Confirmación por voz o panel: nada se ejecuta sin un sí explícito."""
import pytest

from conftest import crear
from laura import archivos as a
from laura import confirmar_archivos as c
from test_holo import nueva


@pytest.mark.parametrize("texto,esperado", [
    ("sí", True), ("vale, hazlo", True), ("Sí, Laura", True), ("confirmo", True),
    ("no", False), ("mejor no", False), ("cancela", False), ("no, déjalo",  False),
    ("el martes quedamos para comer", None), ("", None), ("bórralo todo y también la carpeta", None)])
def test_interpretar(texto, esperado):
    assert c.interpretar(texto) is esperado


def montar(env):
    esc, bus, _ = nueva()
    esc.retraso_relistado = 0
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    esc.mostrar_confirmacion(plan)
    dicho = []
    return esc, plan, f, dicho


def test_voz_si_ejecuta(env):
    esc, plan, f, dicho = montar(env)
    est = c.confirmar(plan, esc, dicho.append, lambda ev: "sí, adelante")
    assert est == "ejecutado" and not f.exists()
    assert dicho[0].startswith("Voy a mandar a la papelera") and "papelera" in dicho[-1]


def test_voz_no_o_ambigua_no_ejecuta(env):
    for frase in ("no", "mejor lo dejamos para otro día"):
        esc, plan, f, dicho = montar(env)
        est = c.confirmar(plan, esc, dicho.append, lambda ev, fr=frase: fr)
        assert est == "cancelado" and f.exists()
        a._PLANES.clear()
        f.unlink()


def test_el_panel_resuelve_mientras_escucha(env):
    esc, plan, f, dicho = montar(env)

    def escuchar(ev):
        esc.control("holo-confirm", plan.id)       # clic mientras Laura escucha
        return None

    est = c.confirmar(plan, esc, dicho.append, escuchar)
    assert est == "ejecutado" and not f.exists()
    assert dicho[-1].startswith("Hecho")           # y lo dice, sin ejecutar dos veces
    assert len(list((env / "Trash" / "files").iterdir())) == 1


def test_silencio_deja_pendiente(env):
    esc, plan, f, dicho = montar(env)
    est = c.confirmar(plan, esc, dicho.append, lambda ev: None)
    assert est == "pendiente" and f.exists() and a.pendiente() is plan
    assert dicho[-1] == "Lo dejo pendiente en el panel."


def test_cancelado_por_atajo_cancela_el_plan(env):
    esc, plan, f, dicho = montar(env)
    est = c.confirmar(plan, esc, dicho.append, lambda ev: "sí", cancelado=lambda: True)
    assert est == "cancelado" and f.exists()


def test_responder_pendiente_tarde(env):
    esc, plan, f, dicho = montar(env)
    assert c.responder_pendiente("qué hora es", esc, dicho.append) is False and f.exists()
    assert c.responder_pendiente("vale", esc, dicho.append) is True and not f.exists()
    assert c.responder_pendiente("vale", esc, dicho.append) is False       # ya no hay nada pendiente
