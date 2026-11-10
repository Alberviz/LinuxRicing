"""Tools de Google Workspace: correo y agenda directos (workspace-mcp local, sin LLM) con respaldo a
Aurora; crear_evento y redactar_correo siempre con confirmación."""
from __future__ import annotations

import re
from datetime import datetime, timedelta

from .. import holo, resumen_correo, workspace
from ..config import log
from . import tool
from .segundo_plano import _FORMATO, _manager

_MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
          "octubre", "noviembre", "diciembre"]


def _nombre(de: str) -> str:
    """«Juan Pérez <juan@x.com>» -> «Juan Pérez»; solo email -> la parte local."""
    m = re.match(r'\s*"?([^"<]+?)"?\s*<', de)
    if m:
        return m.group(1).strip()
    return de.split("@")[0].strip("<> ") or "alguien"


def _hora(s: str) -> str:
    m = re.search(r"[T ](\d{2}):(\d{2})", s)
    return f"{int(m.group(1))}:{m.group(2)}" if m else "todo el día"


# -------------------------------------------------------------------- respaldo Aurora
def _correo_aurora(consulta: str) -> dict:
    if consulta.strip():
        p = (f"Busca en el Gmail de Alberto: {consulta}. Resume lo que encuentres (remitente, asunto, "
             "una frase). " + _FORMATO + "No envíes ni borres nada.")
    else:
        p = ("Mira en el Gmail de Alberto los correos NO LEÍDOS importantes (bandeja principal y "
             "notificaciones; ignora spam y promociones). Resume los más relevantes (remitente, asunto, "
             "una frase). " + _FORMATO + "No envíes ni borres nada.")
    jid = _manager().start("aurora", p, kind="aurora", titulo=f"Correo: {consulta or 'no leídos'}", prompt=p)
    return {"ok": True, "id": jid, "resumen": "Mirando el correo", "via": "aurora"}


def _agenda_aurora(cuando: str) -> dict:
    p = (f"Dime los eventos del Google Calendar de Alberto para: {cuando} "
         "(si es «próximo», solo el siguiente evento). Hora y título de cada uno. " + _FORMATO +
         "No crees ni modifiques nada.")
    jid = _manager().start("aurora", p, kind="aurora", titulo=f"Agenda: {cuando}", prompt=p)
    return {"ok": True, "id": jid, "resumen": "Mirando la agenda", "via": "aurora"}


# -------------------------------------------------------------------- hologramas
_DIAS = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]


def _hhmm(s: str) -> str:
    m = re.search(r"[T ](\d{2}):(\d{2})", s or "")
    return f"{m.group(1)}:{m.group(2)}" if m else ""


def _holo_agenda(cuando: str) -> None:
    """Panel con la agenda: «semana» = 7 columnas; hoy/mañana = el día entero (también lo ya pasado)."""
    try:
        hoy = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
        d0 = hoy + timedelta(days=1) if cuando in ("mañana", "manana") else hoy
        n = 7 if cuando == "semana" else 1
        evs = workspace.eventos(d0, d0 + timedelta(days=n), 40)
        dias = []
        for i in range(n):
            d = d0 + timedelta(days=i)
            clave = d.strftime("%Y-%m-%d")
            dias.append({"fecha": clave, "dia": _DIAS[d.weekday()], "num": d.day,
                         "hoy": d == hoy,
                         "eventos": [{"titulo": e["titulo"], "ini": _hhmm(e["inicio"]), "fin": _hhmm(e["fin"])}
                                     for e in evs if e["inicio"][:10] == clave]})
        titulo = {"semana": "Esta semana", "mañana": "Mañana"}.get(cuando, "Hoy")
        titulo += f" · {d0.day} de {_MESES[d0.month - 1]}" if n == 1 else ""
        holo.escena().mostrar_datos("agenda", titulo, {"tipo": "agenda", "vista": "semana" if n > 1 else "dia",
                                                      "dias": dias}, "calendar_month")
    except Exception as e:  # noqa: BLE001 — el panel es un extra: nunca rompe la respuesta hablada
        log(f"agenda: holo no disponible ({e})")


def _cuando_correo(fecha: str) -> str:
    """Cabecera Date -> «14:03» si es de hoy, «lun 9» si no."""
    from email.utils import parsedate_to_datetime
    try:
        d = parsedate_to_datetime(fecha).astimezone()
    except (TypeError, ValueError):
        return ""
    if d.date() == datetime.now().date():
        return d.strftime("%H:%M")
    return f"{_DIAS[d.weekday()]} {d.day}"


def _falta(inicio: str) -> str:
    """«en 25 min», «en 3 h», «mañana», «el jue 12» o «ahora»."""
    d = _parse_dt(inicio)
    if d is None:
        return ""
    if d.tzinfo is None:
        d = d.astimezone()
    seg = (d - datetime.now().astimezone()).total_seconds()
    if seg <= 0:
        return "ahora"
    if seg < 3600:
        return f"en {max(1, round(seg / 60))} min"
    if d.date() == datetime.now().date():
        return f"en {seg / 3600:.0f} h" if seg >= 5400 else "en 1 h"
    if (d.date() - datetime.now().date()).days == 1:
        return "mañana"
    return f"el {_DIAS[d.weekday()]} {d.day}"


_ULTIMOS_CORREOS: list[dict] = []


def _holo_correo(items: list[dict], consulta: str) -> None:
    _ULTIMOS_CORREOS[:] = items[:10]
    try:
        holo.escena().mostrar_datos("correo", f"«{consulta}»" if consulta.strip() else "Sin leer", {
            "tipo": "correo",
            "items": [{"n": k + 1, "de": i["de"], "asunto": i["asunto"], "frase": i["frase"],
                       "importante": i["importante"], "hora": _cuando_correo(i["fecha"])}
                      for k, i in enumerate(items[:10])]}, "mail")
    except Exception as e:  # noqa: BLE001
        log(f"correo: holo no disponible ({e})")


def _holo_evento(titulo: str, ini: datetime, fin: datetime, dia: list[dict]) -> None:
    """Vista previa: el día con el evento nuevo ya colocado y los que se solapan marcados."""
    try:
        evs = []
        for e in dia:
            a, b = _parse_dt(e["inicio"]), _parse_dt(e["fin"])
            choca = bool(a and b and a.tzinfo and a < fin.astimezone() and ini.astimezone() < b)
            evs.append({"titulo": e["titulo"], "ini": _hhmm(e["inicio"]), "fin": _hhmm(e["fin"]), "choca": choca})
        evs.append({"titulo": titulo, "ini": ini.strftime("%H:%M"), "fin": fin.strftime("%H:%M"), "nuevo": True,
                    "choca": any(e["choca"] for e in evs)})
        evs.sort(key=lambda e: e["ini"] or "00:00")
        d0 = ini.replace(hour=0, minute=0, second=0, microsecond=0)
        hoy = d0.date() == datetime.now().date()
        holo.escena().mostrar_datos("agenda", f"¿Crear? · {_DIAS[d0.weekday()]} {d0.day} de {_MESES[d0.month - 1]}", {
            "tipo": "agenda", "vista": "dia", "propuesta": True,
            "dias": [{"fecha": d0.strftime("%Y-%m-%d"), "dia": _DIAS[d0.weekday()], "num": d0.day, "hoy": hoy,
                      "eventos": evs}]}, "event_available")
    except Exception as e:  # noqa: BLE001
        log(f"crear_evento: holo no disponible ({e})")


# -------------------------------------------------------------------- tools
@tool("abrir_correo",
      "Abre en pantalla un correo ENTERO de la lista de correos que se ve («ábreme el correo 2», «abre el de Marta», «léeme el de la universidad»).",
      {"numero": {"type": "integer", "description": "número del correo en la lista (1 = el primero)"},
       "remitente": {"type": "string", "description": "o parte del remitente/asunto si no dice número"}},
      icon="mark_email_read")
def abrir_correo(numero: int = 0, remitente: str = "") -> dict:
    if not _ULTIMOS_CORREOS:
        return {"ok": False, "error": "no hay correos en pantalla; pide antes «mírame los correos»"}
    m = None
    if numero and 1 <= int(numero) <= len(_ULTIMOS_CORREOS):
        m = _ULTIMOS_CORREOS[int(numero) - 1]
    elif remitente:
        q = remitente.lower()
        m = next((c for c in _ULTIMOS_CORREOS if q in c["de"].lower() or q in c["asunto"].lower()), None)
    if m is None:
        return {"ok": False, "error": "no encuentro ese correo en la lista"}
    try:
        cuerpo = workspace.leer_correo(m["id"], 6000)
    except workspace.WorkspaceUnavailable as e:
        return {"ok": False, "error": f"no puedo leer el correo ({e})"}
    texto = f"**{m['de']}** · {_cuando_correo(m['fecha'])}\n\n## {m['asunto']}\n\n{cuerpo.strip()}"
    holo.escena().mostrar_datos(f"correo-{m['id'][:8]}", m["asunto"][:60] or "Correo",
                                {"tipo": "texto", "formato": "markdown", "texto": texto, "truncado": len(cuerpo) >= 6000},
                                "mail")
    return {"ok": True, "resumen": f"Correo de {m['de']}", "frase": m.get("frase", ""),
            "nota": "Ya está en pantalla; di en una frase de qué va, no lo leas entero."}


@tool("correo",
      "Mira el correo de Alberto: «mírame los correos», «¿tengo algo de X?». Di «decir» tal cual.",
      {"consulta": {"type": "string", "description": "qué buscar (opcional)"}},
      icon="mail")
def correo(consulta: str = "") -> dict:
    if not workspace.enabled():
        return _correo_aurora(consulta)
    try:
        msgs = workspace.buscar_correos(workspace.combinar(consulta if consulta.strip() else "is:unread newer_than:7d"), 10)
        try:
            cuerpos = workspace.leer_correos_lote([m["id"] for m in msgs], 800)
        except workspace.WorkspaceUnavailable:
            cuerpos = {}
    except workspace.WorkspaceUnavailable as e:
        log(f"correo: Workspace no disponible ({e}); respaldo a Aurora")
        return _correo_aurora(consulta)
    # solo se explican los 6 primeros (una llamada corta); del resto basta con contarlos
    fr = resumen_correo.resumir([dict(m, cuerpo=cuerpos.get(m["id"], "")) for m in msgs[:6]])
    for m in msgs[6:]:
        fr[m["id"]] = {"frase": resumen_correo.frase_basica(m), "importante": False}
    items = [{"de": resumen_correo.nombre(m["de"]), "asunto": resumen_correo.limpiar(m["asunto"]),
              "frase": fr[m["id"]]["frase"], "importante": fr[m["id"]]["importante"],
              "fecha": m["fecha"], "id": m["id"]} for m in msgs]
    decir = resumen_correo.decir(items) if consulta.strip() == "" or items else "No encuentro nada con eso."
    if not items and consulta.strip():
        decir = "No encuentro nada con eso."
    if items:
        _holo_correo(items, consulta)
    return {"ok": True, "total": len(items), "decir": decir, "resumen": "Correo revisado",
            "nota": "Di el campo «decir» tal cual, sin añadir nada."}


@tool("agenda",
      "Consulta el calendario: «qué tengo mañana», «cuál es mi próximo evento». Di «decir» tal cual.",
      {"cuando": {"type": "string", "enum": ["hoy", "mañana", "semana", "próximo"], "description": "periodo"}},
      icon="event")
def agenda(cuando: str = "hoy") -> dict:
    if not workspace.enabled():
        return _agenda_aurora(cuando)
    try:
        d, h = workspace.rango(cuando)
        evs = workspace.eventos(d, h, 15)
    except workspace.WorkspaceUnavailable as e:
        log(f"agenda: Workspace no disponible ({e}); respaldo a Aurora")
        return _agenda_aurora(cuando)
    motion = None
    if cuando in ("próximo", "proximo"):
        evs = evs[:1]
    else:
        _holo_agenda(cuando)
    etiqueta = {"hoy": "hoy", "mañana": "mañana", "semana": "esta semana", "próximo": "lo siguiente"}.get(cuando, cuando)
    if not evs:
        decir = f"No tienes nada {etiqueta}." if cuando != "próximo" else "No tienes eventos próximos."
    elif cuando in ("próximo", "proximo"):
        e = evs[0]
        h = _hora(e["inicio"])
        decir = f"Tu próximo evento es {e['titulo']}, " + ("todo el día." if h == "todo el día" else f"a las {h}.")
        motion = {"tipo": "next_event", "titulo": e["titulo"], "hora": _hhmm(e["inicio"]), "falta": _falta(e["inicio"])}
    else:
        partes = [(f"todo el día {e['titulo']}" if _hora(e["inicio"]) == "todo el día"
                   else f"a las {_hora(e['inicio'])} {e['titulo']}") for e in evs[:4]]
        decir = f"{etiqueta.capitalize()} tienes {len(evs)} evento{'s' if len(evs) != 1 else ''}: " + ", ".join(partes) + "."
    return {"ok": True, "eventos": evs[:6], "decir": decir, "resumen": "Agenda revisada", "motion": motion,
            "nota": "Di el campo «decir» tal cual, sin añadir nada."}


def _parse_dt(s: str) -> datetime | None:
    s = (s or "").strip().replace(" ", "T", 1) if re.match(r"\d{4}-\d{2}-\d{2} \d", (s or "").strip()) else (s or "").strip()
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def _eventos_del_dia(ini: datetime) -> list[dict]:
    """Eventos que ya hay ese día (para la franja del cajón). Vacío si Workspace no responde."""
    if not workspace.enabled():
        return []
    try:
        d0 = ini.astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
        evs = workspace.eventos(d0, d0 + timedelta(days=1), 20)
    except Exception as e:  # noqa: BLE001
        log(f"crear_evento: no pude leer el día ({e})")
        return []
    return [{"titulo": e["titulo"], "inicio": e["inicio"], "fin": e["fin"]} for e in evs]


@tool("crear_evento",
      "Crea un evento en el calendario («apúntame una reunión mañana a las 10»); pide confirmación. Fechas ISO local (2026-10-22T10:00).",
      {"titulo": {"type": "string", "description": "título del evento"},
       "inicio": {"type": "string", "description": "ISO local"},
       "duracion_min": {"type": "integer", "description": "minutos (60 por defecto)"}},
      required=["titulo", "inicio"], icon="event_available")
def crear_evento(titulo: str, inicio: str, duracion_min: int = 60, fin: str = "", descripcion: str = "") -> dict:
    ini = _parse_dt(inicio)
    if ini is None:
        return {"ok": False, "error": f"no entiendo la fecha «{inicio}»; usa formato 2026-10-22T10:00"}
    end = _parse_dt(fin) if fin else None
    if end is None:
        end = ini + timedelta(minutes=int(duracion_min or 60))
    if end <= ini:
        return {"ok": False, "error": "el fin debe ser posterior al inicio"}
    cuando = f"{ini.day} de {_MESES[ini.month - 1]} a las {ini.hour}:{ini.minute:02d}"
    mins = int((end - ini).total_seconds() // 60)
    pregunta = f"Voy a crear el evento «{titulo}» el {cuando}, {mins} minutos. ¿Lo creo?"
    data = {"titulo": titulo, "inicio": ini.isoformat(timespec="minutes"), "fin": end.isoformat(timespec="minutes"),
            "descripcion": descripcion, "dia": _eventos_del_dia(ini)}
    _holo_evento(titulo, ini, end, data["dia"])
    jid = _manager().start("laura", f"Crear evento: {titulo}", kind="evento", pregunta=pregunta,
                           titulo=f"Evento: {titulo} ({cuando})", data=data)
    return {"ok": True, "id": jid, "resumen": "Pido confirmación del evento"}


@tool("redactar_correo",
      "Redacta un correo («escríbele/redáctale un correo a Marta diciéndole…»); solo se envía si Alberto confirma.",
      {"para": {"type": "string", "description": "destinatario"},
       "idea": {"type": "string", "description": "qué decir"},
       "asunto": {"type": "string", "description": "asunto (opcional)"}},
      required=["para", "idea"], icon="drafts")
def redactar_correo(para: str, idea: str, asunto: str = "") -> dict:
    jid = _manager().start("gemini", f"Redactar correo a {para}: {idea}", kind="redactar",
                           titulo=f"Correo para {para}", data={"para": para, "idea": idea, "asunto": asunto})
    return {"ok": True, "id": jid, "resumen": "Redactando el correo"}
