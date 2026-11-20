"""Tools de sistema: música, volumen, apps, portapapeles, pantalla, ventanas, hora."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
import urllib.parse
from datetime import datetime

from . import tool


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


@tool("control_musica", "Controla la música/vídeo del PC (reproductor genérico): pausar o reanudar, siguiente, anterior, parar («quita la música» = parar). Para poner algo concreto de Spotify o mandarlo a la tele usa spotify.",
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

    fmt = "{{title}}|||{{artist}}|||{{album}}|||{{mpris:artUrl}}"

    def meta() -> tuple[str, str, str]:
        r = _run(["playerctl", "metadata", "--format", fmt])
        p = (r.stdout.strip().split("|||") + ["", "", "", ""])[:4] if r.returncode == 0 else ["", "", "", ""]
        return p[0], p[1], p[3]

    prev_title, prev_artist, prev_art = meta()
    prev_st = _run(["playerctl", "status"]).stdout.strip().lower()

    r = _run(["playerctl", sub])
    if r.returncode != 0:
        return {"ok": False, "error": "no hay ningún reproductor activo"}

    motion = None
    if accion in ("siguiente", "anterior"):
        # Spotify tarda ~100-300 ms en publicar la pista nueva por MPRIS
        new_title, new_artist, new_art = prev_title, prev_artist, prev_art
        for _ in range(12):
            time.sleep(0.05)
            new_title, new_artist, new_art = meta()
            if new_title and new_title != prev_title:
                break
        motion = {
            "tipo": "track_slide",
            "direccion": "next" if accion == "siguiente" else "prev",
            "prev_title": prev_title or "Pista anterior",
            "prev_artist": prev_artist,
            "next_title": new_title or ("Siguiente pista" if accion == "siguiente" else "Pista anterior"),
            "next_artist": new_artist,
            "art": new_art or prev_art,
            "prev_art": prev_art,
        }
        resumen = f"Pista: {new_title}" if new_title else ("Siguiente canción" if accion == "siguiente" else "Canción anterior")
    else:
        # el estado tras el toggle llega con retraso: se deduce del de antes
        estado = "pause" if (accion == "parar" or prev_st == "playing") else "play"
        motion = {
            "tipo": "playback_impact",
            "estado": estado,
            "titulo": prev_title or "Música",
            "artista": prev_artist,
            "art": prev_art,
        }
        resumen = "Música pausada" if estado == "pause" else "Reproduciendo música"

    return {"ok": True, "accion": accion, "resumen": resumen, "motion": motion}


@tool("volumen", "Sube o baja el volumen del sistema en un porcentaje.",
      {"porcentaje": {"type": "integer", "description": "positivo sube, negativo baja (p.ej. 10 o -10)"}},
      required=["porcentaje"], icon="volume_up")
def volumen(porcentaje: int) -> dict:
    """Cambia el volumen. porcentaje: entero, positivo sube y negativo baja."""
    import re
    r_v0 = _run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    v0 = 50
    m0 = re.search(r"Volume:\s*([\d\.]+)", r_v0.stdout)
    if m0:
        v0 = round(float(m0.group(1)) * 100)

    signo = "+" if porcentaje >= 0 else "-"
    _run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
    r = _run(["wpctl", "set-volume", "-l", "1.4", "@DEFAULT_AUDIO_SINK@",
              f"{abs(int(porcentaje))}%{signo}"])

    r_v1 = _run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    v1 = v0 + porcentaje
    m1 = re.search(r"Volume:\s*([\d\.]+)", r_v1.stdout)
    if m1:
        v1 = round(float(m1.group(1)) * 100)

    resumen = f"Volumen al {v1}%"
    motion = {
        "tipo": "delta_meter",
        "medidor": "volumen",
        "from": v0,
        "to": v1,
        "direccion": "up" if v1 >= v0 else "down"
    }
    return {"ok": r.returncode == 0, "resumen": resumen, "motion": motion}


@tool("silenciar", "Silencia o quita el silencio del audio («mutea», «calla el sonido»).", icon="volume_off")
def silenciar() -> dict:
    """Silencia o quita el silencio del audio."""
    import re
    r_prev = _run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    v0 = 50
    m0 = re.search(r"Volume:\s*([\d\.]+)", r_prev.stdout)
    if m0:
        v0 = round(float(m0.group(1)) * 100)

    r = _run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    r_now = _run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    now_muted = "[MUTED]" in r_now.stdout
    v1 = 0 if now_muted else v0
    resumen = "Audio silenciado" if now_muted else f"Audio activado ({v1}%)"
    motion = {
        "tipo": "delta_meter",
        "medidor": "volumen",
        "from": v0 if now_muted else 0,
        "to": 0 if now_muted else v1,
        "direccion": "down" if now_muted else "up",
        "silenciado": now_muted
    }
    return {"ok": r.returncode == 0, "resumen": resumen, "motion": motion}


@tool("abrir_web", "Abre un sitio web (youtube, github.com) en el navegador, o busca en Google si es texto. Para sitios web usa ESTA, no abrir_app.",
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


@tool("abrir_app", "Abre un programa instalado por su nombre (terminal, archivos, spotify, discord, editor, navegador).",
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
    motion = {
        "tipo": "system_action",
        "accion": "captura",
        "titulo": "Captura de Pantalla",
        "icono": "screenshot_monitor"
    }
    return {"ok": True, "resumen": "Captura de pantalla", "motion": motion}


@tool("bloquear_pantalla", "Bloquea la sesión (pantalla de bloqueo).", icon="lock")
def bloquear_pantalla() -> dict:
    """Bloquea la sesión."""
    subprocess.Popen(["loginctl", "lock-session"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    motion = {
        "tipo": "system_action",
        "accion": "bloqueo",
        "titulo": "Pantalla Bloqueada",
        "icono": "lock"
    }
    return {"ok": True, "resumen": "Bloquear pantalla", "motion": motion}


@tool("copiar_al_portapapeles",
      "Copia un texto al portapapeles. Úsala cuando pida redactar o generar un texto para pegarlo en otro sitio.",
      {"texto": {"type": "string", "description": "el texto completo que se copia al portapapeles"}},
      required=["texto"], icon="content_copy")
def copiar_al_portapapeles(texto: str) -> dict:
    """Copia un texto al portapapeles del sistema (Wayland, wl-copy)."""
    if shutil.which("wl-copy") is None:
        return {"ok": False, "error": "no encuentro 'wl-copy' en el sistema"}
    subprocess.run(["wl-copy"], input=texto, text=True)
    return {"ok": True, "resumen": "Copiado al portapapeles"}


@tool("leer_portapapeles",
      "Lee el portapapeles («traduce esto», «resume lo que he copiado», «qué tengo copiado»).",
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
      "Escribe un texto en la ventana con foco («pega esto», «escríbelo aquí»).",
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
      "Hace OCR de la pantalla: «qué dice este error», «lee lo que hay en pantalla».",
      {"zona": {"type": "string", "enum": ["ventana", "todo", "seleccion"],
                "description": "ventana (por defecto) | todo | seleccion"}},
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
      "Lista las ventanas abiertas («qué tengo abierto», «en qué estaba»).",
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


@tool("hora_fecha", "Hora y fecha actuales: «qué hora es», «qué día es hoy».",
      icon="schedule")
def hora_fecha() -> dict:
    n = datetime.now()
    hora = f"{n.hour}:{n.minute:02d}"
    fecha = f"{_DIAS[n.weekday()]} {n.day} de {_MESES[n.month - 1]} de {n.year}"
    return {"ok": True, "hora": hora, "fecha": fecha, "resumen": f"Son las {hora}",
            "nota": "Responde a Alberto en una frase natural con lo que pidió (hora o fecha)."}


@tool("ejecutar_comando",
      "Ejecuta un comando de terminal para consultar o hacer algo en el sistema (git, servicios, procesos, disco…). Los de solo lectura van directos; los demás piden confirmación a Alberto.",
      {"comando": {"type": "string", "description": "comando bash"}},
      required=["comando"], icon="terminal", effect="confirm:comando")
def ejecutar_comando(comando: str) -> dict:
    """Solo clasifica: lo bloqueado se rechaza, lo de solo lectura se ejecuta y lo demás
    devuelve `confirmar` para que converse() lo pase por confirmación (ver laura.jobs)."""
    from .. import shellguard
    nivel, motivo = shellguard.clasificar(comando)
    if nivel == shellguard.BLOQUEADO:
        return {"ok": False, "error": f"comando bloqueado por seguridad ({motivo})", "resumen": "Comando bloqueado"}
    if nivel == shellguard.DIRECTO:
        return shellguard.ejecutar(comando)
    return {"ok": True, "confirmar": True, "comando": comando, "resumen": "Pido confirmación"}


@tool("modo_juego",
      "Controla el modo juego del sistema. Úsalo cuando Alberto diga que va a jugar («voy a jugar», «activa el modo juego», «pon el modo juego», «modo gaming») o que ha terminado («ya he jugado», «quita el modo juego», «desactiva modo juego»). Libera la memoria de vídeo de la gráfica (VRAM) para el juego, pausa la detección continua de voz para que no interfiera con el sonido o partidas online, y optimiza Hyprland.",
      {"accion": {"type": "string", "enum": ["activar", "desactivar", "alternar", "estado"]}},
      required=["accion"], icon="sports_esports")
def modo_juego(accion: str) -> dict:
    """accion: activar | desactivar | alternar | estado"""
    cmd_map = {
        "activar": "on",
        "desactivar": "off",
        "alternar": "toggle",
        "estado": "status",
    }
    sub = cmd_map.get(accion)
    if not sub:
        return {"ok": False, "error": f"acción desconocida: {accion}"}

    script = os.path.expanduser("~/.local/bin/modo-juego")
    res = subprocess.run([script, sub], capture_output=True, text=True)

    if accion == "activar":
        resumen = "Modo juego activado. VRAM liberada y sistema optimizado."
    elif accion == "desactivar":
        resumen = "Modo juego desactivado. Sistema restaurado."
    elif accion == "alternar":
        resumen = "Modo juego alternado."
    else:
        resumen = "Modo juego: " + (res.stdout.strip() or "consultado.")

    return {"ok": res.returncode == 0, "accion": accion, "resumen": resumen, "salida": res.stdout.strip()}

