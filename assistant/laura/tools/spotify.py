"""Tool de Spotify (Spotify Connect): poner canciones/playlists/álbumes/artistas en la tele o en el PC, pasar la
música entre ambos y todos los mandos (aleatorio, repetir, volumen, me gusta, cola, temporizador…).

Envuelve el CLI `spotify-tele` (widgets/), que controla el cliente de escritorio de Spotify por CDP + Spicetify.
Si Spotify no está abierto, el CLI lo abre."""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

from . import tool

_ACCIONES = ["poner", "poner_a_continuacion", "anadir_a_la_cola", "pasar_a_tele", "pasar_al_pc", "que_suena",
             "reiniciar_cancion", "aleatorio_si",
             "aleatorio_no", "repetir_lista", "repetir_cancion", "repetir_no", "volumen", "subir", "bajar",
             "me_gusta", "no_me_gusta", "temporizador"]
# acción de Laura -> (acción del CLI, valor fijo). Acciones explícitas: el modelo pequeño confundía
# «aleatorio no» con «repetir lista» y «pon después X» con «poner X».
# pausar/siguiente/anterior NO están aquí: los lleva control_musica (playerctl), que también manda en Spotify
# aunque suene en la tele, y así no le quitan esas frases a los vídeos del navegador.
_CONTROL = {"reiniciar_cancion": ("reiniciar", None),
            "aleatorio_si": ("aleatorio", "si"), "aleatorio_no": ("aleatorio", "no"),
            "repetir_lista": ("repetir", "lista"), "repetir_cancion": ("repetir", "cancion"),
            "repetir_no": ("repetir", "no"), "volumen": ("volumen", None), "subir": ("subir", None),
            "bajar": ("bajar", None), "me_gusta": ("me_gusta", None), "no_me_gusta": ("no_me_gusta", None),
            "anadir_a_la_cola": ("cola", None), "poner_a_continuacion": ("despues", None),
            "temporizador": ("temporizador", None)}
_TIPOS = ["auto", "playlist", "cancion", "album", "artista"]


def _bin() -> str | None:
    p = Path.home() / ".local/bin/spotify-tele"
    return shutil.which("spotify-tele") or (str(p) if p.exists() else None)


def _cmd(*args: str, timeout: int = 75) -> dict:
    exe = _bin()
    if not exe:
        return {"ok": False, "error": "no encuentro spotify-tele"}
    try:
        r = subprocess.run([exe, *args], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "Spotify no responde"}
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except (IndexError, ValueError):
        return {"ok": False, "error": (r.stderr or "spotify-tele falló").strip()[:200]}


def _suena(a: dict | None) -> str:
    if not a or not a.get("cancion"):
        return "No suena nada en Spotify."
    donde = f" en {a['dispositivo']}" if a.get("dispositivo") else ""
    return f"{a['cancion']} de {a.get('artista') or 'alguien'}{donde}" + ("" if a.get("sonando") else ", en pausa") + "."


@tool("spotify",
      "Spotify. poner: que=canción/playlist/álbum/artista, donde=tele|pc («manda la playlist X a la tele»). "
      "poner_a_continuacion («pon después X») y anadir_a_la_cola usan que. volumen: valor 0-100; temporizador: minutos. "
      "Pausa/siguiente/anterior: control_musica.",
      {"accion": {"type": "string", "enum": _ACCIONES},
       "que": {"type": "string"},
       "tipo": {"type": "string", "enum": _TIPOS},
       "donde": {"type": "string", "enum": ["tele", "pc", "actual"]},
       "desde_inicio": {"type": "boolean", "description": "primera canción, sin aleatorio"},
       "valor": {"type": "string"}},
      required=["accion"], icon="music_note")
def spotify(accion: str, que: str | None = None, tipo: str | None = None, donde: str | None = None,
            desde_inicio: bool | None = None, valor: str | int | float | None = None) -> dict:
    if accion not in _ACCIONES:
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    valor = None if valor is None else str(valor)
    if accion == "poner":
        if not que:
            return {"ok": False, "error": "¿qué pongo?"}
        args = ["poner", que, "--tipo", tipo if tipo in _TIPOS else "auto", "--donde", donde or "actual"]
        if desde_inicio:
            args.append("--desde-inicio")
        r = _cmd(*args)
        if not r.get("ok"):
            return r
        p, a = r.get("puesto") or {}, r.get("ahora") or {}
        lugar = f" en {a['dispositivo']}" if a.get("dispositivo") else ""
        return {"ok": True, "resumen": f"Spotify: {p.get('nombre', que)}"[:48],
                "decir": f"Poniendo {p.get('nombre', que)}{lugar}.", "ahora": a}
    if accion in ("pasar_a_tele", "pasar_al_pc"):
        r = _cmd("pasar", "tele" if accion == "pasar_a_tele" else "pc")
        if not r.get("ok"):
            return r
        return {"ok": True, "resumen": "Spotify a la tele" if accion == "pasar_a_tele" else "Spotify al PC",
                "decir": "Hecho, " + _suena(r.get("ahora")).lower()}
    if accion == "que_suena":
        r = _cmd("estado", timeout=20)
        if not r.get("ok"):
            return r
        if not r.get("abierto"):
            return {"ok": True, "decir": "Spotify está cerrado.", "resumen": "Spotify cerrado"}
        return {"ok": True, "decir": _suena(r), "resumen": "Qué suena", "ahora": r}
    cli, fijo = _CONTROL[accion]
    if fijo is not None:
        valor = fijo
    if cli in ("cola", "despues"):
        valor = que or valor
        if not valor:
            return {"ok": False, "error": "¿qué canción añado?"}
    if cli in ("volumen", "temporizador") and valor is None:
        return {"ok": False, "error": f"«{accion}» necesita un valor"}
    r = _cmd("control", cli, *([valor] if valor is not None else []))
    if not r.get("ok"):
        return r
    res = {"volumen": f"Volumen Spotify {valor}", "temporizador": f"Temporizador {valor} min",
           "cola": "Añadido a la cola", "despues": "Suena después"}.get(cli, accion.replace("_", " ").capitalize())
    out = {"ok": True, "resumen": res, "ahora": r.get("ahora")}
    if cli in ("siguiente", "anterior"):
        out["decir"] = _suena(r.get("ahora"))
    if cli in ("cola", "despues") and r.get("encolado"):
        out["decir"] = f"{r['encolado'].get('nombre')} " + ("a continuación." if cli == "despues" else "añadida a la cola.")
    return out
