from datetime import datetime

from laura import holo
from laura.holo import Escena
from laura.tools import holo as tholo
from laura.tools import workspace as tws


def _escena(monkeypatch):
    evs = []
    e = Escena(emit=lambda **ev: evs.append(ev))
    monkeypatch.setattr(holo, "escena", lambda: e)
    return e, evs


def test_vista_previa_evento_marca_choques(monkeypatch):
    e, _ = _escena(monkeypatch)
    ini = datetime(2026, 11, 12, 10, 0).astimezone()
    fin = datetime(2026, 11, 12, 11, 0).astimezone()
    dia = [{"titulo": "Clase", "inicio": "2026-11-12T10:30:00+01:00", "fin": "2026-11-12T12:00:00+01:00"},
           {"titulo": "Gym", "inicio": "2026-11-12T18:00:00+01:00", "fin": "2026-11-12T19:00:00+01:00"}]
    tws._holo_evento("Reunión", ini, fin, dia)
    evs = e.paneles["agenda"]["payload"]["dias"][0]["eventos"]
    por = {x["titulo"]: x for x in evs}
    assert por["Reunión"]["nuevo"] and por["Reunión"]["choca"]
    assert por["Clase"]["choca"] and not por["Gym"]["choca"]
    assert [x["titulo"] for x in evs] == ["Reunión", "Clase", "Gym"]


def test_mostrar_nota_abre_panel_markdown(monkeypatch):
    e, evs = _escena(monkeypatch)
    r = tholo.mostrar_nota("Lista de la compra", "- leche\n- pan")
    assert r["ok"]
    (p,) = e.paneles.values()
    assert p["payload"] == {"tipo": "texto", "formato": "markdown", "texto": "- leche\n- pan", "truncado": False}
    assert evs[-1]["op"] == "open"


def test_abrir_correo_sin_lista():
    tws._ULTIMOS_CORREOS.clear()
    assert not tws.abrir_correo(1)["ok"]
