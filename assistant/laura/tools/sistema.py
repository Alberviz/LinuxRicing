"""Tools de sistema: música, volumen, apps, portapapeles, pantalla, ventanas, hora."""
from __future__ import annotations

import json
import shutil
import subprocess
import urllib.parse
from datetime import datetime

from . import tool


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


@tool("control_musica", "Controla la reproducción de música/vídeo del sistema.",
      {"accion": {"type": "string", "enum": ["reproducir_pausar", "siguiente", "anterior", "parar"]}},
      required=["accion"], icon="music_note")
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


@tool("volumen", "Sube o baja el volumen del sistema en un porcentaje.",
      {"porcentaje": {"type": "integer", "description": "positivo sube, negativo baja (p.ej. 10 o -10)"}},
      required=["porcentaje"], icon="volume_up")
def volumen(porcentaje: int) -> dict:
    """Cambia el volumen. porcentaje: entero, positivo sube y negativo baja."""
    signo = "+" if porcentaje >= 0 else "-"
    _run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
    r = _run(["wpctl", "set-volume", "-l", "1.4", "@DEFAULT_AUDIO_SINK@",
              f"{abs(int(porcentaje))}%{signo}"])
    resumen = "Subir volumen" if porcentaje >= 0 else "Bajar volumen"
    return {"ok": r.returncode == 0, "resumen": resumen}


@tool("silenciar", "Silencia o quita el silencio del audio del sistema.", icon="volume_off")
def silenciar() -> dict:
    """Silencia o quita el silencio del audio."""
    r = _run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    return {"ok": r.returncode == 0, "resumen": "Silenciar / activar audio"}


@tool("abrir_web", "Abre una web en el navegador, o busca en Google si es texto.",
      {"consulta": {"type": "string", "description": "una URL (google.com) o algo que buscar"}},
      required=["consulta"], icon="public")
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


@tool("abrir_app", "Abre una aplicación instalada por su nombre.",
      {"nombre": {"type": "string", "description": "navegador, terminal, spotify, discord, editor, archivos…"}},
      required=["nombre"], icon="open_in_new", wants_apps=True)
def abrir_app(nombre: str, _apps: dict | None = None) -> dict:
    """Abre una aplicación por su nombre (ver [apps] en config.toml)."""
    apps = _apps or {}
    comando = apps.get(nombre.strip().lower(), nombre.strip().lower())
    partes = comando.split()
    if shutil.which(partes[0]) is None:
        return {"ok": False, "error": f"no encuentro la aplicación '{partes[0]}'"}
    subprocess.Popen(partes, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "app": comando, "resumen": f"Abrir {nombre.strip()}"}


@tool("captura_pantalla", "Hace una captura de pantalla.", icon="screenshot_monitor")
def captura_pantalla() -> dict:
    """Hace una captura de pantalla."""
    subprocess.Popen(["caelestia", "screenshot"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "resumen": "Captura de pantalla"}


@tool("bloquear_pantalla", "Bloquea la sesión (pantalla de bloqueo).", icon="lock")
def bloquear_pantalla() -> dict:
    """Bloquea la sesión."""
    subprocess.Popen(["loginctl", "lock-session"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "resumen": "Bloquear pantalla"}


@tool("copiar_al_portapapeles",
      "Copia un texto al portapapeles del sistema. Úsalo cuando Alberto pida que le redactes/generes un texto, un mensaje, código, o una respuesta larga para pegarla en otro sitio.",
      {"texto": {"type": "string", "description": "el texto completo que se copia al portapapeles"}},
      required=["texto"], icon="content_copy")
def copiar_al_portapapeles(texto: str) -> dict:
    """Copia un texto al portapapeles del sistema (Wayland, wl-copy)."""
    if shutil.which("wl-copy") is None:
        return {"ok": False, "error": "no encuentro 'wl-copy' en el sistema"}
    subprocess.run(["wl-copy"], input=texto, text=True)
    return {"ok": True, "resumen": "Copiado al portapapeles"}


@tool("leer_portapapeles",
      "Lee lo que hay ahora mismo en el portapapeles. Úsalo cuando Alberto diga «traduce esto», «resume lo que he copiado», «qué tengo copiado».",
      icon="content_paste")
def leer_portapapeles() -> dict:
    """Devuelve el texto que hay ahora mismo en el portapapeles."""
    if shutil.which("wl-paste") is None:
        return {"ok": False, "error": "no encuentro 'wl-paste' en el sistema"}
    r = _run(["wl-paste", "--no-newline"])
    if r.returncode != 0:
        return {"ok": False, "error": "el portapapeles está vacío o no es texto"}
    return {"ok": True, "texto": r.stdout, "resumen": "Leí el portapapeles"}


@tool("pegar_texto",
      "Escribe un texto en la aplicación que tiene el foco (lo teclea de verdad). Úsalo cuando Alberto pida «pega esto», «escríbelo aquí», «pon el resultado en el documento».",
      {"texto": {"type": "string", "description": "el texto que se pega en la ventana activa"}},
      required=["texto"], icon="content_paste_go")
def pegar_texto(texto: str) -> dict:
    """Escribe `texto` en la aplicación que tiene el foco (lo copia y hace
    Ctrl+V con ydotool). Útil para 'traduce el portapapeles y pégalo'."""
    if shutil.which("wl-copy") is None or shutil.which("ydotool") is None:
        return {"ok": False, "error": "falta 'wl-copy' o 'ydotool'"}
    subprocess.run(["wl-copy"], input=texto, text=True)
    # 29 = LEFTCTRL, 47 = V (códigos de tecla del kernel de Linux).
    r = _run(["ydotool", "key", "29:1", "47:1", "47:0", "29:0"])
    if r.returncode != 0:
        # El texto sí quedó en el portapapeles: que Alberto lo pegue a mano.
        return {"ok": True, "resumen": "Copiado (pega tú con Ctrl+V)",
                "nota": "No pude pegarlo yo (ydotoold no está corriendo). El "
                        "texto está en el portapapeles; dile a Alberto que lo "
                        "pegue él con Ctrl+V."}
    return {"ok": True, "resumen": "Pegado en la ventana activa"}


def _active_window_geom() -> str | None:
    """Geometría 'X,Y WxH' de la ventana con foco, para acotar la captura."""
    r = _run(["hyprctl", "-j", "activewindow"])
    try:
        w = json.loads(r.stdout)
        (x, y), (aw, ah) = w["at"], w["size"]
        return f"{x},{y} {aw}x{ah}"
    except (ValueError, KeyError, TypeError):
        return None


@tool("leer_pantalla",
      "Hace una captura y le pasa OCR para leer el texto que se ve en pantalla. Úsalo para «qué dice este error», «resume lo que hay en pantalla», «saca el código que se ve».",
      {"zona": {"type": "string", "enum": ["ventana", "todo", "seleccion"],
                "description": "ventana = la que tiene el foco (por defecto, rápido); todo = pantalla entera; seleccion = Alberto elige un recuadro con el ratón"}},
      icon="document_scanner")
def leer_pantalla(zona: str = "ventana") -> dict:
    """Captura y OCR (tesseract). `zona`: ventana (la que tiene foco, rápido) |
    todo (pantalla entera) | seleccion (recuadro con el ratón). Devuelve el
    texto reconocido para que Laura responda sobre él."""
    if shutil.which("grim") is None:
        return {"ok": False, "error": "no encuentro 'grim'"}
    if shutil.which("tesseract") is None:
        return {"ok": False, "error": "falta 'tesseract' (instala tesseract y "
                                     "tesseract-data-spa para el OCR)"}
    png = "/tmp/laura_ocr.png"
    geom = None
    if zona == "seleccion" and shutil.which("slurp"):
        sel = _run(["slurp"])
        if sel.returncode != 0 or not sel.stdout.strip():
            return {"ok": False, "error": "selección cancelada"}
        geom = sel.stdout.strip()
    elif zona != "todo":
        geom = _active_window_geom()
    cap = _run(["grim", "-g", geom, png] if geom else ["grim", png])
    if cap.returncode != 0:
        return {"ok": False, "error": "no pude capturar la pantalla"}
    # --oem 1 (solo LSTM) es más rápido; acotar a la ventana activa reduce
    # mucho el área a procesar, que es lo que más pesa en el OCR.
    ocr = _run(["tesseract", png, "-", "-l", "spa+eng", "--oem", "1", "--psm", "6",
                "-c", "preserve_interword_spaces=1"])
    texto = ocr.stdout.strip()
    if len(texto) < 3:
        return {"ok": False, "error": "no reconocí texto en la pantalla"}
    return {"ok": True, "texto": texto, "resumen": "Leí la pantalla",
            "nota": ("Texto extraído por OCR: puede tener erratas (letras/números "
                     "sueltos mal, símbolos raros). Interprétalo con sentido "
                     "común y responde a lo que Alberto pidió; no digas que no "
                     "puedes leerlo salvo que esté completamente vacío.")}


@tool("ventanas_abiertas",
      "Lista las ventanas abiertas (título, aplicación, espacio). Sin capturar nada. Para «qué tengo abierto», «en qué estaba».",
      icon="select_window")
def ventanas_abiertas() -> dict:
    """Lista las ventanas abiertas (título, aplicación y espacio de trabajo),
    sin capturar nada. Para 'a qué he dejado abierto' o dar contexto a Laura."""
    if shutil.which("hyprctl") is None:
        return {"ok": False, "error": "no encuentro 'hyprctl'"}
    r = _run(["hyprctl", "-j", "clients"])
    try:
        data = json.loads(r.stdout)
    except (ValueError, TypeError):
        return {"ok": False, "error": "no pude leer las ventanas"}
    vs = [{"titulo": c.get("title", ""), "app": c.get("class", ""),
           "espacio": (c.get("workspace") or {}).get("name", "")}
          for c in data if c.get("mapped") and c.get("title")]
    return {"ok": True, "ventanas": vs, "resumen": f"{len(vs)} ventanas abiertas"}


_DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
_MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
          "agosto", "septiembre", "octubre", "noviembre", "diciembre"]


def fecha_hora_texto() -> str:
    n = datetime.now()
    return (f"{_DIAS[n.weekday()]} {n.day} de {_MESES[n.month - 1]} de {n.year}, "
            f"{n.hour}:{n.minute:02d}")


@tool("hora_fecha", "Dice la hora y la fecha actuales. Úsala SIEMPRE para «qué hora es», «qué día es hoy», «a cuánto estamos».",
      icon="schedule")
def hora_fecha() -> dict:
    n = datetime.now()
    hora = f"{n.hour}:{n.minute:02d}"
    fecha = f"{_DIAS[n.weekday()]} {n.day} de {_MESES[n.month - 1]} de {n.year}"
    return {"ok": True, "hora": hora, "fecha": fecha, "resumen": f"Son las {hora}",
            "nota": "Responde a Alberto en una frase natural con lo que pidió (hora o fecha)."}
