"""Herramientas locales que Aurora puede ejecutar (fase 4, set inicial).

Cada función devuelve un dict serializable. El esquema de abajo es el que se le
pasa a Ollama (formato estilo OpenAI). Añadir una herramienta = una función + su
entrada en TOOLS.
"""
from __future__ import annotations

import shutil
import subprocess
import urllib.parse


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def control_musica(accion: str) -> dict:
    """accion: reproducir_pausar | siguiente | anterior | parar"""
    mapa = {
        "reproducir_pausar": "play-pause",
        "siguiente": "next",
        "anterior": "previous",
        "parar": "stop",
    }
    sub = mapa.get(accion)
    if not sub:
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    r = _run(["playerctl", sub])
    if r.returncode != 0:
        return {"ok": False, "error": "no hay ningún reproductor activo"}
    resumen = {
        "reproducir_pausar": "Reproducir / pausar",
        "siguiente": "Siguiente canción",
        "anterior": "Canción anterior",
        "parar": "Parar música",
    }[accion]
    return {"ok": True, "accion": accion, "resumen": resumen}


def volumen(porcentaje: int) -> dict:
    """Cambia el volumen. porcentaje: entero, positivo sube y negativo baja."""
    signo = "+" if porcentaje >= 0 else "-"
    _run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
    r = _run(["wpctl", "set-volume", "-l", "1.4", "@DEFAULT_AUDIO_SINK@",
              f"{abs(int(porcentaje))}%{signo}"])
    resumen = "Subir volumen" if porcentaje >= 0 else "Bajar volumen"
    return {"ok": r.returncode == 0, "resumen": resumen}


def silenciar() -> dict:
    """Silencia o quita el silencio del audio."""
    r = _run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    return {"ok": r.returncode == 0, "resumen": "Silenciar / activar audio"}


def abrir_web(consulta: str) -> dict:
    """Abre una URL en el navegador, o una búsqueda en Google si es texto libre."""
    primera = consulta.split()[0] if consulta.split() else ""
    if consulta.startswith("http://") or consulta.startswith("https://"):
        url = consulta
    elif "." in primera and " " not in consulta:
        url = "https://" + consulta
    else:
        url = "https://www.google.com/search?q=" + urllib.parse.quote(consulta)
    subprocess.Popen(["xdg-open", url],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    es_busqueda = "google.com/search" in url
    return {"ok": True, "url": url,
            "resumen": f"Buscar «{consulta}»" if es_busqueda else "Abrir web"}


def abrir_app(nombre: str, _apps: dict | None = None) -> dict:
    """Abre una aplicación por su nombre (ver [apps] en config.toml)."""
    apps = _apps or {}
    comando = apps.get(nombre.strip().lower(), nombre.strip().lower())
    partes = comando.split()
    if shutil.which(partes[0]) is None:
        return {"ok": False, "error": f"no encuentro la aplicación '{partes[0]}'"}
    subprocess.Popen(partes, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "app": comando, "resumen": f"Abrir {nombre.strip()}"}


def captura_pantalla() -> dict:
    """Hace una captura de pantalla."""
    subprocess.Popen(["caelestia", "screenshot"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "resumen": "Captura de pantalla"}


def bloquear_pantalla() -> dict:
    """Bloquea la sesión."""
    subprocess.Popen(["loginctl", "lock-session"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "resumen": "Bloquear pantalla"}


def copiar_al_portapapeles(texto: str) -> dict:
    """Copia un texto al portapapeles del sistema (Wayland, wl-copy)."""
    if shutil.which("wl-copy") is None:
        return {"ok": False, "error": "no encuentro 'wl-copy' en el sistema"}
    subprocess.run(["wl-copy"], input=texto, text=True)
    return {"ok": True, "resumen": "Copiado al portapapeles"}


# Icono (Material Symbols) para la píldora de acción del overlay.
TOOL_ICONS = {
    "control_musica": "music_note",
    "volumen": "volume_up",
    "silenciar": "volume_off",
    "abrir_web": "public",
    "abrir_app": "open_in_new",
    "captura_pantalla": "screenshot_monitor",
    "bloquear_pantalla": "lock",
    "copiar_al_portapapeles": "content_copy",
}


def accion_overlay(name: str, result: dict) -> dict:
    """Traduce un tool_call ejecutado a `{icon, text}` para el overlay."""
    return {
        "icon": TOOL_ICONS.get(name, "bolt"),
        "text": result.get("resumen") or name.replace("_", " ").capitalize(),
    }


DISPATCH = {
    "control_musica": control_musica,
    "volumen": volumen,
    "silenciar": silenciar,
    "abrir_web": abrir_web,
    "abrir_app": abrir_app,
    "captura_pantalla": captura_pantalla,
    "bloquear_pantalla": bloquear_pantalla,
    "copiar_al_portapapeles": copiar_al_portapapeles,
}

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "control_musica",
            "description": "Controla la reproducción de música/vídeo del sistema.",
            "parameters": {
                "type": "object",
                "properties": {
                    "accion": {
                        "type": "string",
                        "enum": ["reproducir_pausar", "siguiente", "anterior", "parar"],
                    }
                },
                "required": ["accion"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "volumen",
            "description": "Sube o baja el volumen del sistema en un porcentaje.",
            "parameters": {
                "type": "object",
                "properties": {
                    "porcentaje": {
                        "type": "integer",
                        "description": "positivo sube, negativo baja (p.ej. 10 o -10)",
                    }
                },
                "required": ["porcentaje"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "silenciar",
            "description": "Silencia o quita el silencio del audio del sistema.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "abrir_web",
            "description": "Abre una web en el navegador, o busca en Google si es texto.",
            "parameters": {
                "type": "object",
                "properties": {
                    "consulta": {
                        "type": "string",
                        "description": "una URL (google.com) o algo que buscar",
                    }
                },
                "required": ["consulta"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "abrir_app",
            "description": "Abre una aplicación instalada por su nombre.",
            "parameters": {
                "type": "object",
                "properties": {
                    "nombre": {
                        "type": "string",
                        "description": "navegador, terminal, spotify, discord, editor, archivos…",
                    }
                },
                "required": ["nombre"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "captura_pantalla",
            "description": "Hace una captura de pantalla.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "bloquear_pantalla",
            "description": "Bloquea la sesión (pantalla de bloqueo).",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "copiar_al_portapapeles",
            "description": "Copia un texto al portapapeles del sistema. Úsalo cuando Alberto pida que le redactes/generes un texto, un mensaje, código, o una respuesta larga para pegarla en otro sitio.",
            "parameters": {
                "type": "object",
                "properties": {
                    "texto": {
                        "type": "string",
                        "description": "el texto completo que se copia al portapapeles",
                    }
                },
                "required": ["texto"],
            },
        },
    },
]


def run_tool(name: str, args: dict, apps: dict) -> dict:
    fn = DISPATCH.get(name)
    if fn is None:
        return {"ok": False, "error": f"herramienta desconocida: {name}"}
    try:
        if name == "abrir_app":
            return fn(args.get("nombre", ""), apps)
        return fn(**args)
    except Exception as e:  # noqa: BLE001 — queremos que un fallo no tumbe el daemon
        return {"ok": False, "error": str(e)}
