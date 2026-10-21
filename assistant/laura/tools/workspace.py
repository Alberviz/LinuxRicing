"""Tools de Google Workspace: correo y agenda directos (workspace-mcp local, sin LLM) con respaldo a
Aurora; crear_evento y redactar_correo siempre con confirmación."""
from __future__ import annotations

import re
from datetime import datetime, timedelta

from .. import resumen_correo, workspace
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


# -------------------------------------------------------------------- tools
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
    if cuando in ("próximo", "proximo"):
        evs = evs[:1]
    etiqueta = {"hoy": "hoy", "mañana": "mañana", "semana": "esta semana", "próximo": "lo siguiente"}.get(cuando, cuando)
    if not evs:
        decir = f"No tienes nada {etiqueta}." if cuando != "próximo" else "No tienes eventos próximos."
    elif cuando in ("próximo", "proximo"):
        e = evs[0]
        h = _hora(e["inicio"])
        decir = f"Tu próximo evento es {e['titulo']}, " + ("todo el día." if h == "todo el día" else f"a las {h}.")
    else:
        partes = [(f"todo el día {e['titulo']}" if _hora(e["inicio"]) == "todo el día"
                   else f"a las {_hora(e['inicio'])} {e['titulo']}") for e in evs[:4]]
        decir = f"{etiqueta.capitalize()} tienes {len(evs)} evento{'s' if len(evs) != 1 else ''}: " + ", ".join(partes) + "."
    return {"ok": True, "eventos": evs[:6], "decir": decir, "resumen": "Agenda revisada",
            "nota": "Di el campo «decir» tal cual, sin añadir nada."}


def _parse_dt(s: str) -> datetime | None:
    s = (s or "").strip().replace(" ", "T", 1) if re.match(r"\d{4}-\d{2}-\d{2} \d", (s or "").strip()) else (s or "").strip()
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


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
            "descripcion": descripcion}
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
