"""Tools que lanzan trabajos en segundo plano: investigar y pedir_a_aurora."""
from __future__ import annotations

from ..config import CFG
from . import tool


def _manager():
    from .. import jobs
    if jobs.MANAGER is None:
        raise RuntimeError("el gestor de trabajos no está activo")
    return jobs.MANAGER


@tool("investigar",
      "Investiga un tema en Internet EN SEGUNDO PLANO y deja el resultado en el panel y en una nota («investiga qué es X», «averigua cómo funciona Y a fondo»). No es para datos rápidos (usa buscar_web).",
      {"tema": {"type": "string", "description": "qué investigar, en una frase"}},
      required=["tema"], icon="travel_explore")
def investigar(tema: str) -> dict:
    destino = CFG.get("background", {}).get("investigar", "gemini")
    if destino not in ("gemini", "laura"):
        destino = "gemini"
    jid = _manager().start(destino, tema, kind="investigar", titulo=f"Investigar: {tema}")
    return {"ok": True, "id": jid, "resumen": "Investigando en segundo plano",
            "nota": "Dile a Alberto solo «Me pongo con ello» (una frase); el resultado le llegará al panel."}


@tool("pedir_a_aurora",
      "Pide algo a Aurora, la asistente personal de Alberto: Google Calendar, correo, Drive, recados y cualquier cosa larga («pregúntale a Aurora qué tengo mañana», «dile a Aurora que me cree un evento»). Va en segundo plano.",
      {"peticion": {"type": "string", "description": "lo que Alberto quiere, tal cual"}},
      required=["peticion"], icon="support_agent")
def pedir_a_aurora(peticion: str) -> dict:
    jid = _manager().start("aurora", peticion, kind="aurora", titulo=f"Aurora: {peticion}")
    return {"ok": True, "id": jid, "resumen": "Se lo pido a Aurora",
            "nota": "Dile a Alberto solo «Se lo pido a Aurora» (una frase)."}


_FORMATO = ("Responde en español, MUY corto (máximo 4 líneas), sin saludos ni relleno. "
            "Cuando puedas, incluye al final la URL directa de Gmail o Google Calendar de "
            "cada elemento relevante, una por línea. ")


@tool("correo",
      "Mira el correo de Alberto (Gmail) en segundo plano: «mírame los correos», «¿tengo algo de la universidad?». Sin consulta resume los no leídos importantes.",
      {"consulta": {"type": "string", "description": "qué buscar (opcional), p. ej. «de la universidad»"}},
      icon="mail")
def correo(consulta: str = "") -> dict:
    if consulta.strip():
        p = (f"Busca en el Gmail de Alberto: {consulta}. Resume lo que encuentres (remitente, asunto, "
             "una frase). " + _FORMATO + "No envíes ni borres nada.")
    else:
        p = ("Mira en el Gmail de Alberto los correos NO LEÍDOS importantes (personas reales, universidad, "
             "trabajo, plazos, pagos, viajes; ignora spam y newsletters). Resume los más relevantes "
             "(remitente, asunto, una frase). " + _FORMATO + "No envíes ni borres nada.")
    jid = _manager().start("aurora", p, kind="aurora", titulo=f"Correo: {consulta or 'no leídos'}", prompt=p)
    return {"ok": True, "id": jid, "resumen": "Mirando el correo"}


@tool("agenda",
      "Consulta el calendario de Alberto (Google Calendar) en segundo plano: «qué tengo mañana», «qué hay esta semana», «cuál es mi próximo evento».",
      {"cuando": {"type": "string", "enum": ["hoy", "mañana", "semana", "próximo"], "description": "periodo"}},
      icon="event")
def agenda(cuando: str = "hoy") -> dict:
    p = (f"Dime los eventos del Google Calendar de Alberto para: {cuando} "
         "(si es «próximo», solo el siguiente evento). Hora y título de cada uno. " + _FORMATO +
         "No crees ni modifiques nada.")
    jid = _manager().start("aurora", p, kind="aurora", titulo=f"Agenda: {cuando}", prompt=p)
    return {"ok": True, "id": jid, "resumen": "Mirando la agenda"}


@tool("redactar_correo",
      "Prepara un BORRADOR de correo en Gmail (no lo envía): «redáctale un correo a Marta sobre la reunión». Enviarlo pedirá confirmación.",
      {"para": {"type": "string", "description": "destinatario (nombre o email)"},
       "asunto": {"type": "string", "description": "asunto"},
       "idea": {"type": "string", "description": "qué quiere decir Alberto"}},
      required=["para", "idea"], icon="drafts")
def redactar_correo(para: str, idea: str, asunto: str = "") -> dict:
    p = (f"Redacta un correo para {para}" + (f" con asunto «{asunto}»" if asunto else "") +
         f" con esta idea: {idea}. Crea SOLO UN BORRADOR en Gmail; NO lo envíes. "
         "Cuando esté, muestra el texto del borrador y termina preguntando «¿Lo envío?». "
         "Solo si Alberto responde que sí, envíalo. " + _FORMATO)
    jid = _manager().start("aurora", p, kind="aurora", titulo=f"Borrador para {para}", prompt=p)
    return {"ok": True, "id": jid, "resumen": "Preparando el borrador"}


@tool("novedades",
      "Revisa ahora si hay algo nuevo (correos importantes, eventos próximos, tareas estancadas): «¿hay algo nuevo?», «novedades».",
      icon="notifications")
def novedades() -> dict:
    from .. import vigia
    if vigia.VIGIA is None:
        return {"ok": False, "error": "el vigía no está activo"}
    vigia.VIGIA.now()
    return {"ok": True, "resumen": "Revisando novedades"}
