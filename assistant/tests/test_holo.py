"""Escena de hologramas de Laura: numeración, «esa», eventos y caducidad."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura.holo import Escena  # noqa: E402


def cand(*nombres):
    return [{"ruta": f"/h/Descargas/{n}", "nombre": n, "tamano": 10, "modificado": 1.0} for n in nombres]


class Bus:
    def __init__(self):
        self.ev = []

    def __call__(self, **e):
        self.ev.append(e)

    def ops(self):
        return [e["op"] for e in self.ev]


def nueva(**kw):
    bus = Bus()
    t = {"now": 0.0}
    e = Escena(emit=bus, reloj=lambda: t["now"], preparar=lambda r, tipo: {"tipo": tipo, "src": r}, **kw)
    return e, bus, t


def test_listar_numera_y_emite():
    e, bus, _ = nueva()
    items = e.listar("Descargas", cand("a.png", "b.pdf", "c.md"))
    assert [(i.n, i.tipo) for i in items] == [(1, "imagen"), (2, "pdf"), (3, "texto")]
    ev = bus.ev[-1]
    assert ev["type"] == "holo" and ev["op"] == "list" and ev["panel"]["id"] == "lista"
    assert [p["id"] for p in ev["paneles"]] == ["lista"] and len(ev["items"]) == 3


def test_listar_tope_12():
    e, _, _ = nueva()
    assert len(e.listar("X", cand(*[f"{i}.txt" for i in range(20)]))) == 12


def test_abrir_varios_y_esa():
    e, bus, _ = nueva()
    e.listar("Descargas", cand("a.png", "b.pdf"))
    r = e.abrir([1, 2])
    assert r["ok"] and [i.n for i in r["abiertos"]] == [1, 2]
    assert bus.ops()[-2:] == ["open", "open"]
    assert bus.ev[-1]["panel"] == {"id": "v2", "kind": "visor", "titulo": "b.pdf", "item_n": 2,
                                  "payload": {"tipo": "pdf", "src": "/h/Descargas/b.pdf"}}
    assert e.resolver(None).n == 2          # «esa» = la última abierta
    e.seleccionar(1)
    assert e.resolver(None).n == 1 and bus.ops()[-1] == "select"


def test_abrir_fuera_de_rango_y_sin_lista():
    e, _, _ = nueva()
    assert e.abrir([1]) == {"ok": False, "error": "No hay ninguna lista en pantalla."}
    e.listar("D", cand("a.png"))
    assert e.abrir([5]) == {"ok": False, "error": "Solo hay 1."}


def test_abrir_no_duplica():
    e, bus, _ = nueva()
    e.listar("D", cand("a.png"))
    e.abrir([1])
    e.abrir([1])
    assert [p["id"] for p in bus.ev[-1]["paneles"]].count("v1") == 1


def test_abrir_ruta_suelta_sin_lista():
    e, _, _ = nueva()
    r = e.abrir(ruta="/h/Imágenes/foto.jpg")
    assert r["ok"] and r["abiertos"][0].n == 1
    assert e.snapshot()["paneles"][0]["id"] == "lista"


def test_nueva_lista_cierra_visores():
    e, bus, _ = nueva()
    e.listar("D", cand("a.png", "b.pdf"))
    e.abrir([1])
    e.listar("Documentos", cand("x.md"))
    assert [p["id"] for p in bus.ev[-1]["paneles"]] == ["lista"] and e.resolver(None) is None


def test_cerrar_y_vaciar():
    e, bus, _ = nueva()
    e.listar("D", cand("a.png", "b.pdf"))
    e.abrir([1, 2])
    assert e.cerrar([1]) == 1 and bus.ev[-1]["op"] == "close" and bus.ev[-1]["ids"] == ["v1"]
    assert e.cerrar(todo=True) == 2 and bus.ev[-1]["op"] == "clear"
    assert e.contexto() == "" and e.snapshot()["items"] == []


def test_contexto():
    e, _, _ = nueva()
    e.listar("Descargas", cand("WhatsApp 21.04.jpg", "practica3.pdf"))
    e.abrir([2])
    c = e.contexto()
    assert "Descargas" in c and "1 WhatsApp 21.04.jpg" in c and "Abiertos: 2" in c and "Seleccionado: 2" in c


def test_caducidad():
    e, bus, t = nueva(ttl=600)
    e.listar("D", cand("a.png"))
    t["now"] = 599
    assert not e.caducar()
    t["now"] = 1300
    assert e.caducar() and bus.ev[-1]["op"] == "clear" and e.contexto() == ""


def test_control_y_envio():
    e, bus, _ = nueva()
    enviados = []
    e.enviar_por_warp = lambda n: (enviados.append(n), e.marcar_enviado(n), {"ok": True})[-1]
    e.listar("D", cand("a.png", "b.pdf"))
    assert e.control("holo-open", "2")["ok"] and e.resolver(None).n == 2
    assert e.control("holo-select", "1")["ok"] and e.resolver(None).n == 1
    assert e.control("holo-send", "1")["ok"] and enviados == [1]
    assert bus.ev[-1]["op"] == "sent" and bus.ev[-1]["items"][0]["enviado"]
    assert e.control("holo-close", "v2")["ok"]
    assert e.control("holo-close", "all")["ok"] and bus.ev[-1]["op"] == "clear"
    assert not e.control("holo-nada", "")["ok"]


def test_pagina_pdf(monkeypatch):
    from laura import holo
    e, bus, _ = nueva()
    e.preparar = lambda r, t: {"tipo": "pdf", "src": "/c/p1.png", "pagina": 1, "paginas": 3}
    monkeypatch.setattr(holo.holo_preview, "pagina_pdf", lambda ruta, p: f"/c/p{p}.png")
    e.listar("D", cand("b.pdf"))
    e.abrir([1])
    e.pagina("v1", 9)
    ev = bus.ev[-1]
    assert ev["op"] == "page" and ev["panel"]["payload"]["pagina"] == 3 and ev["panel"]["payload"]["src"] == "/c/p3.png"


def test_contexto_recorta_nombre_largo():
    e, _, _ = nueva()
    nombre_largo = "archivo_con_un_nombre_extremadamente_largo_para_probar_el_recorte.txt"
    e.listar("D", cand(nombre_largo))
    c = e.contexto()
    assert "…" in c
    assert nombre_largo not in c


def test_control_holo_ext():
    e, _, _ = nueva()
    abiertos_ext = []
    e.abrir_externo = lambda r: (abiertos_ext.append(r), {"ok": True})[-1]
    e.listar("D", cand("a.png"))
    res = e.control("holo-ext", "1")
    assert res["ok"] and abiertos_ext == ["/h/Descargas/a.png"]
    res_v = e.control("holo-ext", "v1")
    assert res_v["ok"] and abiertos_ext == ["/h/Descargas/a.png", "/h/Descargas/a.png"]
    res_err = e.control("holo-ext", "99")
    assert not res_err["ok"]


def test_control_holo_page(monkeypatch):
    from laura import holo
    e, bus, _ = nueva()
    e.preparar = lambda r, t: {"tipo": "pdf", "src": "/c/p1.png", "pagina": 1, "paginas": 5}
    monkeypatch.setattr(holo.holo_preview, "pagina_pdf", lambda ruta, p: f"/c/p{p}.png")
    e.listar("D", cand("doc.pdf"))
    e.abrir([1])
    res = e.control("holo-page", "v1 3")
    assert res["ok"] and res["pagina"] == 3
    assert bus.ev[-1]["panel"]["payload"]["pagina"] == 3


def test_cerrar_panel_lista():
    e, bus, _ = nueva()
    e.listar("D", cand("a.png", "b.pdf"))
    e.abrir([1])
    assert e.cerrar_panel("lista") == 2
    assert bus.ev[-1]["op"] == "clear"
    assert e.contexto() == ""


def test_abrir_carpeta_entra_y_lista(tmp_path):
    sub = tmp_path / "Universidad"
    sub.mkdir()
    e, bus, _ = nueva()
    visto = {}

    def listador(ruta):
        visto["ruta"] = ruta
        return {"ok": True, "candidatos": cand("a.pdf", "b.pdf")}

    e.listador = listador
    e.listar("Documentos", [{"ruta": str(sub), "nombre": "Universidad", "tamano": 0, "modificado": 1.0}])
    assert e.items[0].tipo == "carpeta"
    res = e.abrir([1])
    assert res["ok"] and res["carpeta"] == "Universidad" and res["n"] == 2
    assert visto["ruta"] == str(sub)
    assert [it.nombre for it in e.items] == ["a.pdf", "b.pdf"]
    assert e.paneles["lista"]["titulo"] == "Universidad"
    assert list(e.paneles) == ["lista"]          # no se abre ningún visor para la carpeta


def test_abrir_mezcla_ignora_carpetas(tmp_path):
    sub = tmp_path / "Carpeta"
    sub.mkdir()
    f = tmp_path / "nota.txt"
    f.write_text("hola")
    e, _, _ = nueva()
    e.listar("X", [{"ruta": str(sub), "nombre": "Carpeta"}, {"ruta": str(f), "nombre": "nota.txt"}])
    res = e.abrir([1, 2])
    assert res["ok"] and [it.nombre for it in res["abiertos"]] == ["nota.txt"]


def test_mostrar_datos_reemplaza_panel():
    from laura.holo import Escena
    evs = []
    e = Escena(emit=lambda **ev: evs.append(ev))
    e.mostrar_datos("agenda", "Hoy", {"tipo": "agenda", "vista": "dia", "dias": []})
    e.mostrar_datos("agenda", "Esta semana", {"tipo": "agenda", "vista": "semana", "dias": []})
    assert [ev["op"] for ev in evs] == ["open", "close", "open"]
    assert list(e.paneles) == ["agenda"] and e.paneles["agenda"]["titulo"] == "Esta semana"
    assert e.cerrar_panel("agenda") == 1 and evs[-1]["op"] == "clear"
