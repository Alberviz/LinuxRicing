"""La escena holográfica con planes de archivos: panel de confirmación, clic, fx y relistado."""
from conftest import crear
from laura import archivos as a
from test_holo import nueva


def preparar(env, n=3):
    esc, bus, _ = nueva()
    esc.retraso_relistado = 0
    fs = [crear(env, f"Descargas/f{i}.txt") for i in range(n)]
    esc.listar("Descargas", [{"ruta": str(f), "nombre": f.name, "tamano": 4, "modificado": 1.0} for f in fs],
               carpeta=str(env / "Descargas"))
    return esc, bus, fs


def test_mostrar_confirmacion(env):
    esc, bus, fs = preparar(env)
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    panel = esc.mostrar_confirmacion(plan)
    assert panel["kind"] == "confirmar" and panel["payload"]["plan"] == plan.id
    assert bus.ev[-1]["op"] == "confirm" and "confirmar" in esc.paneles


def test_clic_confirmar_ejecuta_anima_y_relista(env):
    esc, bus, fs = preparar(env)
    esc.listador = lambda ruta: {"ok": True, "candidatos": [
        {"ruta": str(f), "nombre": f.name, "tamano": 4, "modificado": 1.0} for f in fs[1:]]}
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    esc.mostrar_confirmacion(plan)
    r = esc.control("holo-confirm", plan.id)
    assert r["ok"] and r["estado"] == "ejecutado" and not fs[0].exists()
    assert "confirmar" not in esc.paneles
    fx = next(e for e in bus.ev if e["op"] == "fx")
    assert fx["fx"] == "borrar" and fx["filas"] == [1]
    assert [it.nombre for it in esc.items] == ["f1.txt", "f2.txt"]     # relistado
    assert bus.ops()[-1] == "list"


def test_clic_cancelar_no_toca_nada(env):
    esc, bus, fs = preparar(env)
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    esc.mostrar_confirmacion(plan)
    r = esc.control("holo-cancel", plan.id)
    assert r["ok"] and r["estado"] == "cancelado" and fs[0].exists()
    assert "confirmar" not in esc.paneles and "fx" not in bus.ops()


def test_confirmar_plan_desconocido_o_repetido(env):
    esc, bus, fs = preparar(env)
    assert esc.control("holo-confirm", "nope")["ok"] is False
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    esc.control("holo-confirm", plan.id)
    assert esc.control("holo-confirm", plan.id)["ok"] is False          # no se ejecuta dos veces


def test_confirmacion_sola_vacia_la_escena(env):
    esc, bus, _ = nueva()
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    esc.mostrar_confirmacion(plan)
    esc.resolver_plan(plan.id, False)
    assert esc.paneles == {} and bus.ops()[-1] == "clear"


def test_caducar_quita_el_panel_de_un_plan_vencido(env, monkeypatch):
    esc, bus, fs = preparar(env)
    t = {"v": 1000.0}
    monkeypatch.setattr(a, "ahora", lambda: t["v"])
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    esc.mostrar_confirmacion(plan)
    t["v"] += 61
    esc.caducar()
    assert "confirmar" not in esc.paneles and "lista" in esc.paneles


def test_operacion_directa_sin_confirmacion_anima_y_relista(env):
    esc, bus, fs = preparar(env)
    esc.listador = lambda ruta: {"ok": True, "candidatos": []}
    plan = a.planificar_renombrar(str(fs[1]), "otro.txt")
    a.ejecutar(plan)
    esc.tras_plan(plan)
    assert next(e for e in bus.ev if e["op"] == "fx")["filas"] == [2]
