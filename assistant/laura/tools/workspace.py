"""Tools de Google Workspace: correo y agenda directos (workspace-mcp local, sin LLM) con respaldo a
Aurora; crear_evento y redactar_correo siempre con confirmación."""
from __future__ import annotations

import re
from datetime import datetime, timedelta

from .. import workspace
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
      "Mira el correo de Alberto (bandeja principal y notificaciones, sin spam): «mírame los correos», «¿tengo algo de X?». Sin consulta, los no leídos. Di el campo «decir» tal cual.",
      {"consulta": {"type": "string", "description": "qué buscar (opcional), p. ej. «de la universidad»"}},
      icon="mail")
def correo(consulta: str = "") -> dict:
    if not workspace.enabled():
        return _correo_aurora(consulta)
    try:
        msgs = workspace.buscar_correos(workspace.combinar(consulta if consulta.strip() else "is:unread newer_than:7d"), 5)
        items = []
        for m in msgs[:5]:
            frag = ""
            if len(items) < 3:
                try:
                    frag = workspace.leer_correo(m["id"], 110)
                except workspace.WorkspaceUnavailable:
                    pass
            items.append({"de": _nombre(m["de"]), "asunto": m["asunto"], "fragmento": frag,
                          "fecha": m["fecha"], "id": m["id"]})
    except workspace.WorkspaceUnavailable as e:
        log(f"correo: Workspace no disponible ({e}); respaldo a Aurora")
        return _correo_aurora(consulta)
    if not items:
        decir = "No tienes correos nuevos importantes." if not consulta.strip() else "No encuentro nada con eso."
    else:
        partes = [f"{it['de']}: {it['asunto']}" for it in items[:3]]
        decir = (f"Tienes {len(items)} correo{'s' if len(items) != 1 else ''}. "
                 + "; ".join(partes) + ("." if partes else ""))
    return {"ok": True, "correos": items, "decir": decir, "resumen": "Correo revisado",
            "nota": "Di el campo «decir» tal cual, sin añadir nada."}


@tool("agenda",
      "Consulta el calendario de Alberto (Google Calendar): «qué tengo mañana», «qué hay esta semana», «cuál es mi próximo evento». Di el campo «decir» tal cual.",
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
        decir = f"Tu próximo evento es {e['titulo']}, a las {_hora(e['inicio'])}."
    else:
        partes = [f"a las {_hora(e['inicio'])} {e['titulo']}" for e in evs[:4]]
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
      "Crea un evento en el calendario de Alberto: «apúntame una reunión mañana a las 10». Pide confirmación con el evento exacto. Fechas en formato ISO local (2026-10-22T10:00).",
      {"titulo": {"type": "string", "description": "título del evento"},
       "inicio": {"type": "string", "description": "inicio ISO local, p. ej. 2026-10-22T10:00"},
       "fin": {"type": "string", "description": "fin ISO local (opcional si das duracion_min)"},
       "duracion_min": {"type": "integer", "description": "duración en minutos (por defecto 60)"},
       "descripcion": {"type": "string", "description": "notas (opcional)"}},
      required=["titulo", "inicio"], icon="event_available")
def crear_evento(titulo: str, inicio: str, fin: str = "", duracion_min: int = 60, descripcion: str = "") -> dict:
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
      "Redacta un correo de Alberto con Gemini y se lo enseña antes de enviarlo: «redáctale un correo a Marta diciéndole que llego tarde». Solo se envía si él confirma.",
      {"para": {"type": "string", "description": "destinatario (nombre o email)"},
       "idea": {"type": "string", "description": "qué quiere decir Alberto"},
       "asunto": {"type": "string", "description": "asunto (opcional)"}},
      required=["para", "idea"], icon="drafts")
def redactar_correo(para: str, idea: str, asunto: str = "") -> dict:
    jid = _manager().start("gemini", f"Redactar correo a {para}: {idea}", kind="redactar",
                           titulo=f"Correo para {para}", data={"para": para, "idea": idea, "asunto": asunto})
    return {"ok": True, "id": jid, "resumen": "Redactando el correo"}
