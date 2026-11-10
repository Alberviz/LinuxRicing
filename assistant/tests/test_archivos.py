"""Motor de archivos: validación, planes, ejecución con papelera, diario y deshacer."""
import json
import os

import pytest

from conftest import crear
from laura import archivos as a


# ---------------------------------------------------------------- validador

def test_ruta_fuera_de_las_raices_rechazada(env):
    fuera = crear(env, "fuera/x.txt")
    with pytest.raises(a.Rechazo, match="fuera de tus carpetas"):
        a.ruta_permitida(fuera)


def test_la_raiz_misma_solo_vale_como_destino(env):
    with pytest.raises(a.Rechazo, match="entera"):
        a.ruta_permitida(env / "Descargas")
    assert a.ruta_permitida(env / "Descargas", permitir_raiz=True) == (env / "Descargas").resolve()


@pytest.mark.parametrize("ruta", ["Descargas/.oculto", "proyectos/app/.git/config", "proyectos/LinuxRicing/vault/nota.md",
                                  "Documentos/Vault/x.md"])
def test_ocultos_git_y_vault_rechazados(env, ruta):
    with pytest.raises(a.Rechazo):
        a.ruta_permitida(env / ruta)


def test_symlink_que_escapa_rechazado(env):
    fuera = crear(env, "fuera/secreto.txt")
    enlace = env / "Descargas" / "atajo"
    enlace.symlink_to(fuera)
    with pytest.raises(a.Rechazo, match="fuera de tus carpetas"):
        a.planificar_borrar([str(enlace)])
    assert fuera.exists()


# ------------------------------------------------------------- planificación

def test_planificar_no_toca_el_disco(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.planificar_borrar([str(f)])
    assert f.exists() and plan.estado == "pendiente" and plan.accion == "borrar"
    assert plan.ops[0].tamano == 4


def test_cuando_pide_confirmacion(env):
    uno = crear(env, "Descargas/uno.txt")
    assert a.planificar_borrar([str(uno)]).requiere_confirmacion
    assert not a.planificar_mover([str(uno)], env / "Documentos").requiere_confirmacion
    seis = [str(crear(env, f"Descargas/f{i}.txt")) for i in range(6)]
    assert a.planificar_mover(seis, env / "Documentos").requiere_confirmacion
    assert not a.planificar_renombrar(str(uno), "dos.txt").requiere_confirmacion
    assert not a.planificar_crear_carpeta("Facturas", env / "Descargas").requiere_confirmacion


def test_tope_de_operaciones(env, monkeypatch):
    monkeypatch.setattr(a.ENTORNO, "max_ops", 3)
    rutas = [str(crear(env, f"Descargas/f{i}.txt")) for i in range(4)]
    with pytest.raises(a.Rechazo, match="demasiados"):
        a.planificar_borrar(rutas)


def test_origen_inexistente_y_duplicados(env):
    f = crear(env, "Descargas/a.txt")
    with pytest.raises(a.Rechazo, match="ya no existe"):
        a.planificar_borrar([str(env / "Descargas" / "no.txt")])
    assert len(a.planificar_borrar([str(f), str(f)]).ops) == 1


def test_mover_a_si_misma_o_donde_ya_esta(env):
    d = env / "Documentos" / "carpeta"
    d.mkdir()
    hija = d / "hija"
    hija.mkdir()
    with pytest.raises(a.Rechazo, match="dentro de sí misma"):
        a.planificar_mover([str(d)], hija)
    f = crear(env, "Documentos/x.txt")
    with pytest.raises(a.Rechazo, match="ya está en"):
        a.planificar_mover([str(f)], env / "Documentos")


@pytest.mark.parametrize("nombre", ["", "a/b", ".oculto", "..", "x" * 300])
def test_nombres_invalidos(env, nombre):
    f = crear(env, "Descargas/a.txt")
    with pytest.raises(a.Rechazo, match="no vale"):
        a.planificar_renombrar(str(f), nombre)


def test_crear_carpeta_existente(env):
    (env / "Descargas" / "Facturas").mkdir()
    with pytest.raises(a.Rechazo, match="Ya existe"):
        a.planificar_crear_carpeta("Facturas", env / "Descargas")


def test_textos_del_plan(env):
    fs = [str(crear(env, f"Descargas/f{i}.txt", "x" * 1024 * 1024)) for i in range(3)]
    p = a.planificar_borrar(fs)
    assert p.pregunta() == "Voy a mandar a la papelera tres archivos, 3 megas. ¿Confirmas?"
    assert p.titulo() == "Borrar tres archivos"
    assert p.a_payload()["items"][0]["nombre"] == "f0.txt" and p.a_payload()["mas"] == 0


def test_resolver_destino(env):
    (env / "Documentos" / "Universidad" / "Redes").mkdir(parents=True)
    assert a.resolver_destino("documentos") == env / "Documentos"
    assert a.resolver_destino("universidad") == env / "Documentos" / "Universidad"
    assert a.resolver_destino("Redes") == env / "Documentos" / "Universidad" / "Redes"
    with pytest.raises(a.Rechazo, match="No encuentro"):
        a.resolver_destino("inexistente")
    assert a.resolver_destino("/abs/ruta") == a.Path("/abs/ruta")


# ------------------------------------------------------ ejecutar y deshacer

def test_mover_y_deshacer(env):
    f = crear(env, "Descargas/a.txt")
    r = a.ejecutar(a.planificar_mover([str(f)], env / "Documentos"))
    assert r["ok"] and not f.exists() and (env / "Documentos" / "a.txt").exists()
    assert "deshaz" in r["decir"]
    d = a.deshacer()
    assert d["ok"] and f.exists() and not (env / "Documentos" / "a.txt").exists()
    assert not a.deshacer()["ok"]                      # ya está deshecho


def test_mover_no_sobrescribe(env):
    crear(env, "Documentos/a.txt", "viejo")
    f = crear(env, "Descargas/a.txt", "nuevo")
    a.ejecutar(a.planificar_mover([str(f)], env / "Documentos"))
    assert (env / "Documentos" / "a.txt").read_text() == "viejo"
    assert (env / "Documentos" / "a (2).txt").read_text() == "nuevo"


def test_renombrar_y_deshacer(env):
    f = crear(env, "Descargas/a.txt")
    r = a.ejecutar(a.planificar_renombrar(str(f), "b.txt"))
    assert r["ok"] and (env / "Descargas" / "b.txt").exists()
    a.deshacer()
    assert f.exists() and not (env / "Descargas" / "b.txt").exists()


def test_borrar_va_a_la_papelera_y_se_recupera(env):
    f = crear(env, "Descargas/a.txt", "contenido")
    r = a.ejecutar(a.planificar_borrar([str(f)]))
    assert r["ok"] and not f.exists()
    enpapelera = list((env / "Trash" / "files").iterdir())
    assert [p.name for p in enpapelera] == ["a.txt"]
    info = (env / "Trash" / "info" / "a.txt.trashinfo").read_text()
    assert info.startswith("[Trash Info]") and f"Path={f}" in info and "DeletionDate=" in info
    assert a.deshacer()["ok"]
    assert f.read_text() == "contenido" and not list((env / "Trash" / "info").iterdir())


def test_borrar_carpeta_con_contenido(env):
    d = env / "Descargas" / "viejo"
    crear(d, "x/y.txt", "1234")
    p = a.planificar_borrar([str(d)])
    assert p.ops[0].es_dir and p.ops[0].tamano == 4 and "carpeta" in p.pregunta()
    a.ejecutar(p)
    assert not d.exists()
    a.deshacer()
    assert (d / "x" / "y.txt").read_text() == "1234"


def test_crear_carpeta_y_deshacer_solo_si_vacia(env):
    r = a.ejecutar(a.planificar_crear_carpeta("Facturas", env / "Descargas"))
    nueva = env / "Descargas" / "Facturas"
    assert r["ok"] and nueva.is_dir() and "deshaz" not in r["decir"]
    crear(nueva, "dentro.txt")
    assert not a.deshacer()["ok"] and nueva.exists()   # no vacía: se conserva


def test_deshacer_revierte_la_ultima_accion_entera(env):
    fs = [crear(env, f"Descargas/f{i}.txt") for i in range(3)]
    a.ejecutar(a.planificar_borrar([str(x) for x in fs]))
    d = a.deshacer()
    assert d["ok"] and d["n"] == 3 and all(x.exists() for x in fs)
    assert d["carpeta"] == str(env / "Descargas")


def test_diario_sobrevive_al_reinicio(env):
    f = crear(env, "Descargas/a.txt")
    a.ejecutar(a.planificar_borrar([str(f)]))
    lineas = [json.loads(t) for t in (env / "estado" / "archivos.jsonl").read_text().splitlines()]
    assert lineas[0]["accion"] == "borrar" and lineas[0]["deshecha"] is False
    # «reinicio»: el motor no guarda nada en memoria que el deshacer necesite
    a._PLANES.clear()
    assert a.deshacer()["ok"] and f.exists()
    assert json.loads((env / "estado" / "archivos.jsonl").read_text().splitlines()[0])["deshecha"] is True


def test_origen_desaparecido_se_omite(env):
    f1, f2 = crear(env, "Descargas/a.txt"), crear(env, "Descargas/b.txt")
    plan = a.planificar_borrar([str(f1), str(f2)])
    f1.unlink()
    r = a.ejecutar(plan)
    assert r["ok"] and r["hechas"] == 1 and "1 ya no existían" in r["decir"]
    assert a.ejecutar(a.planificar_borrar([str(crear(env, "Descargas/c.txt"))]))["ok"]


def test_todo_falla(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.planificar_borrar([str(f)])
    f.unlink()
    r = a.ejecutar(plan)
    assert not r["ok"] and plan.estado == "fallido" and not (env / "estado" / "archivos.jsonl").exists()


# --------------------------------------------------------- planes pendientes

def test_nada_se_ejecuta_sin_resolver(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    assert a.pendiente() is plan and f.exists()


def test_resolver_si_ejecuta_una_sola_vez(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    r = a.resolver(plan.id, True)
    assert r["ok"] and r["estado"] == "ejecutado" and not f.exists() and plan.evento.is_set()
    assert plan.mensaje == r["decir"]
    r2 = a.resolver(plan.id, True)
    assert not r2["ok"] and r2["estado"] == "ejecutado"
    assert a.pendiente() is None


def test_resolver_no_cancela_sin_tocar(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    r = a.resolver(plan.id, False)
    assert r["ok"] and r["estado"] == "cancelado" and f.exists() and plan.evento.is_set()


def test_un_plan_nuevo_cancela_el_anterior(env):
    f = crear(env, "Descargas/a.txt")
    p1 = a.registrar(a.planificar_borrar([str(f)]))
    p2 = a.registrar(a.planificar_borrar([str(f)]))
    assert p1.estado == "cancelado" and p1.evento.is_set() and a.pendiente() is p2


def test_caducidad(env, monkeypatch):
    f = crear(env, "Descargas/a.txt")
    t = {"v": 1000.0}
    monkeypatch.setattr(a, "ahora", lambda: t["v"])
    plan = a.registrar(a.planificar_borrar([str(f)]))
    t["v"] += 61
    assert a.pendiente() is None and plan.estado == "caducado" and plan.evento.is_set()
    r = a.resolver(plan.id, True)
    assert not r["ok"] and "tiempo" in r["error"] and f.exists()


def test_resolver_desconocido(env):
    assert a.resolver("nope", True) == {"ok": False, "error": "No hay nada pendiente."}
