"""Tool de Spotify (Spotify Connect): poner canciones/playlists/álbumes/artistas en la tele o en el PC, pasar la
música entre ambos y todos los mandos (aleatorio, repetir, volumen, me gusta, cola, temporizador…).

Envuelve el CLI `spotify-tele` (widgets/), que controla el cliente de escritorio de Spotify por CDP + Spicetify.
Si Spotify no está abierto, el CLI lo abre."""
from __future__ import annotations

import json
import re
import shutil
import socket
import subprocess
import time
import unicodedata
from pathlib import Path

from . import tool

_ACCIONES = ["poner", "buscar", "poner_lo_encontrado", "poner_a_continuacion", "anadir_a_la_cola", "pasar_a_tele", "pasar_al_pc", "que_suena",
             "reiniciar_cancion", "aleatorio_si",
             "aleatorio_no", "repetir_lista", "repetir_cancion", "repetir_no", "volumen", "subir", "bajar",
             "me_gusta", "no_me_gusta", "temporizador", "cola_nueva", "cola_limpiar", "crear_playlist", "anadir_a_playlist", "sincronizar_youtube"]
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
# El modelo a veces mete el tipo dentro de `que` («playlist: RealG4Life», «mi playlist de X»); con el prefijo la
# búsqueda en la biblioteca ya no coincide. Se quita y pasa a `tipo`.
_PREFIJO = re.compile(r"^\s*(?:(?:mi|la)\s+)?(?:(?P<pl>playlist|lista)\s*(?::|\s+de\s+|\s+)|"
                      r"(?P<otro>canci[oó]n|tema|[aá]lbum|disco|artista)\s*:\s*)", re.I)
_TIPO_PREFIJO = {"cancion": "cancion", "canción": "cancion", "tema": "cancion", "album": "album",
                 "álbum": "album", "disco": "album", "artista": "artista"}


def _limpiar_que(que: str, tipo: str | None) -> tuple[str, str | None]:
    m = _PREFIJO.match(que)
    if not m or not que[m.end():].strip():
        return que.strip(), tipo
    t = "playlist" if m.group("pl") else _TIPO_PREFIJO.get(m.group("otro").lower())
    return que[m.end():].strip().strip("«»\"'"), (tipo if tipo in _TIPOS and tipo != "auto" else t)


# --- Alias de playlists ([spotify.alias] en config.toml) -------------------------------------------------------------
# Se comparan por «clave»: sin tildes, en minúsculas y sin palabras de relleno, para que «mi playlist de reguetón»,
# «la playlist de reggaeton» o «reguetón» den lo mismo.
_RELLENO = {"mi", "mis", "la", "el", "lo", "los", "las", "de", "del", "playlist", "lista", "musica", "con", "que",
            "tengo", "esa", "esta", "pon", "ponme"}


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return " ".join(re.sub(r"[^a-z0-9ñ]+", " ", s).split())


def _clave(s: str) -> str:
    return " ".join(w for w in _norm(s).split() if w not in _RELLENO)


def _alias() -> dict[str, str]:
    try:
        from ..config import CFG
        tabla = (CFG.get("spotify") or {}).get("alias") or {}
    except Exception:  # noqa: BLE001 — sin config, sin alias
        tabla = {}
    return {_clave(k): v for k, v in tabla.items() if _clave(k)}


# «lo más nuevo de X», «las últimas (añadidas) de X» → la playlist X empezando por lo último que añadiste.
_RECIENTES = re.compile(r"^\s*(?:lo|las?|los)\s+(?:m[aá]s\s+(?:nuev[oa]s?|recientes?)|[uú]ltim[oa]s?)"
                        r"(?:\s+(?:añadidas?|canciones|temas))?\s+(?:de|del)\s+(?P<resto>.+)$", re.I)
# «el último álbum / disco / single / lanzamiento de ARTISTA» → buscarlo y preguntar antes de ponerlo.
_ULTIMO = re.compile(r"^\s*(?:(?:el|la|lo)\s+)?[uú]ltim[oa]\s+(?P<clase>[aá]lbum|disco|single|sencillo|"
                     r"lanzamiento|canci[oó]n|tema|ep|trabajo)\s+(?:de|del)\s+(?P<art>.+)$", re.I)
_MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
          "noviembre", "diciembre"]

# Lo último que Laura encontró y propuso («¿lo pongo?»), para poner_lo_encontrado tras el «sí».
_PENDIENTE: dict = {}
_CADUCA_S = 15 * 60


def _lugar(a: dict) -> str:
    dev = a.get("dispositivo") or ""
    return "" if not dev else (" en este PC" if dev.lower() == socket.gethostname().lower() else f" en la tele ({dev})")


def _hablable(s: str) -> str:
    """Sin emojis (la voz los lee mal o se los come a medias)."""
    return " ".join("".join(c for c in s if unicodedata.category(c) not in ("So", "Sk", "Cf")).split())


def _describir(it: dict) -> str:
    n, de, t = _hablable(it.get("nombre") or ""), it.get("de") or "", it.get("tipo")
    if it.get("clase"):
        fecha = ""
        if it.get("anio"):
            fecha = f", salió en {it['anio']}"
            if it.get("mes"):
                fecha = f", salió en {_MESES[it['mes'] - 1]} de {it['anio']}"
                if it.get("dia"):
                    fecha = f", salió el {it['dia']} de {_MESES[it['mes'] - 1]} de {it['anio']}"
        return f"el último {it['clase']} de {de}: se llama «{n}»{fecha}"
    if t == "playlist":
        return f"la playlist «{n}»" + ("" if de in ("", "tu biblioteca") else f" de {de}")
    if t == "artista":
        return f"a {n}"
    return f"«{n}»" + (f" de {de}" if de else "")


def _proponer(it: dict, donde: str | None) -> dict:
    _PENDIENTE.clear()
    _PENDIENTE.update(item=it, donde=donde, t=time.monotonic())
    return {"ok": True, "encontrado": it, "resumen": f"Encontrado: {it.get('nombre')}"[:48],
            "decir": f"He encontrado {_describir(it)}. ¿" + ("La" if it.get("tipo") in ("playlist", "cancion") else "Lo") + " pongo?",
            "nota": "Espera la respuesta de Alberto; si dice que sí, llama a spotify con accion=poner_lo_encontrado."}


def _buscar_ultimo(artista: str, clase: str | None, donde: str | None) -> dict:
    c = "album" if clase and _norm(clase) in ("album", "disco", "trabajo") else "cualquiera"
    r = _cmd("ultimo", artista, "--clase", c)
    if not r.get("ok"):
        # ¿No era un artista sino una playlist tuya? Entonces «lo último» = lo último que añadiste.
        e = _cmd("encontrar", artista, "--tipo", "playlist")
        if e.get("ok") and (e.get("encontrado") or {}).get("tipo") == "playlist":
            it = e["encontrado"]
            return _poner(it["uri"], "playlist", donde, recientes=True, nombre=it.get("nombre"))
        return r
    return _proponer(r["encontrado"], donde)


def _poner(que: str, tipo: str | None, donde: str | None, desde_inicio: bool | None = None,
           recientes: bool = False, nombre: str | None = None, aleatorio: bool | None = None) -> dict:
    args = ["poner", que, "--tipo", tipo if tipo in _TIPOS else "auto", "--donde", donde or "actual"]
    if recientes:
        args += ["--orden", "recientes", "--desde-inicio"]
    elif desde_inicio:
        args.append("--desde-inicio")
    if aleatorio is not None and not (recientes or desde_inicio):
        args.append("--aleatorio" if aleatorio else "--en-orden")
    r = _cmd(*args)
    if not r.get("ok"):
        if r.get("candidatos"):
            c = r["candidatos"]
            r["decir"] = (f"No tengo ninguna playlist «{que}». ¿Te refieres a "
                          + (c[0] if len(c) == 1 else ", ".join(c[:-1]) + " o " + c[-1]) + "?")
        return r
    p, a = r.get("puesto") or {}, r.get("ahora") or {}
    nombre = nombre or (p.get("nombre") if not str(p.get("nombre", "")).startswith("spotify:") else None) or que
    lugar = _lugar(a)
    out = {"ok": True, "resumen": f"Spotify: {nombre}"[:48],
           "decir": f"Poniendo {_hablable(nombre)}" + (", lo último que añadiste," if recientes else "") + f"{lugar}.", "ahora": a}
    if "tele" in lugar and isinstance(a.get("volumen"), (int, float)) and a["volumen"] < 10:
        out["decir"] += f" Ojo, la tele está al {a['volumen']} % de volumen."
    return out


def _entender(que: str, tipo: str | None, recientes: bool | None) -> tuple[str, str | None, bool, bool]:
    """Limpia `que` y aplica alias. Devuelve (que, tipo, recientes, es_alias)."""
    que, tipo = _limpiar_que(que, tipo)
    m = _RECIENTES.match(que)
    if m:
        que, recientes = m.group("resto").strip(), True
        que, tipo = _limpiar_que(que, tipo)
    real = _alias().get(_clave(que))
    if real:
        return real, "playlist", bool(recientes), True
    return que, tipo, bool(recientes), False


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
    dev = a.get("dispositivo")
    donde = "" if not dev else (" en este PC" if dev.lower() == socket.gethostname().lower() else f" en la tele ({dev})")
    return f"{a['cancion']} de {a.get('artista') or 'alguien'}{donde}" + ("" if a.get("sonando") else ", en pausa") + "."


@tool("spotify",
      "Spotify. poner: que=SOLO el nombre (el tipo va en tipo), donde=tele|pc («manda la playlist X a la tele»). "
      "Si dice «en la tele» o «manda Spotify a la tele», donde=tele. Si devuelve candidatos, pregunta cuál. "
      "Pasa SIEMPRE donde=tele si Alberto dice «en la tele», también en buscar. "
      "«Sin aleatorio / en orden» = aleatorio=false; «en aleatorio» = aleatorio=true. "
      "«Lo más nuevo de X», «por orden de añadido», «lo último que añadí» = poner con recientes=true. "
      "«El último álbum de ARTISTA» o «busca X» = buscar (ultimo=true para lo último de un artista): di el «decir» "
      "y, si Alberto dice que sí, poner_lo_encontrado. "
      "«Quita la música de la tele / que suene en mis altavoces» = pasar_al_pc. "
      "poner_a_continuacion («pon después X») y anadir_a_la_cola usan que. volumen: valor 0-100 (solo si dice un número); «sube/baja un poco» = subir/bajar sin valor; temporizador: minutos. "
      "cola_nueva: que=canciones CONCRETAS separadas por comas. Si pide un TIPO de música o N canciones sin "
      "nombrarlas, usa cola_dj. Pausa/siguiente/anterior: control_musica.",
      {"accion": {"type": "string", "enum": _ACCIONES},
       "que": {"type": "string"},
       "tipo": {"type": "string", "enum": _TIPOS},
       "donde": {"type": "string", "enum": ["tele", "pc", "actual"]},
       "desde_inicio": {"type": "boolean", "description": "primera canción, sin aleatorio"},
       "recientes": {"type": "boolean", "description": "playlist empezando por las últimas añadidas"},
       "aleatorio": {"type": "boolean", "description": "poner: false = en orden, true = aleatorio"},
       "ultimo": {"type": "boolean", "description": "buscar: el último lanzamiento del artista que=…"},
       "valor": {"type": "string"}},
      required=["accion"], icon="music_note")
def spotify(accion: str, que: str | None = None, tipo: str | None = None, donde: str | None = None,
            desde_inicio: bool | None = None, recientes: bool | None = None, ultimo: bool | None = None,
            aleatorio: bool | None = None, valor: str | int | float | None = None) -> dict:
    if accion not in _ACCIONES:
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    valor = None if valor is None else str(valor)
    if accion == "poner_lo_encontrado":
        if not _PENDIENTE or time.monotonic() - _PENDIENTE.get("t", 0) > _CADUCA_S:
            return {"ok": False, "error": "no tengo nada encontrado pendiente; usa buscar primero"}
        it, donde = _PENDIENTE["item"], donde or _PENDIENTE.get("donde")
        _PENDIENTE.clear()
        t = it.get("tipo") if it.get("tipo") in _TIPOS else "auto"
        return _poner(it["uri"], t, donde, nombre=it.get("nombre"))
    if accion in ("poner", "buscar"):
        if not que:
            return {"ok": False, "error": "¿qué pongo?" if accion == "poner" else "¿qué busco?"}
        m = _ULTIMO.match(_limpiar_que(que, tipo)[0])
        if m:
            return _buscar_ultimo(m.group("art").strip(), m.group("clase"), donde)
        que, tipo, recientes, es_alias = _entender(que, tipo, recientes)
        if es_alias and (ultimo or recientes):
            # «Lo último / lo más nuevo de lo de siempre»: un alias es una playlist tuya, no un artista.
            return _poner(que, "playlist", donde, recientes=True)
        if accion == "buscar":
            if ultimo:
                return _buscar_ultimo(que, "album" if tipo == "album" else None, donde)
            r = _cmd("encontrar", que, "--tipo", tipo if tipo in _TIPOS else "auto")
            if not r.get("ok"):
                return r
            return _proponer(r["encontrado"], donde)
        if recientes and not es_alias:
            # «Lo más nuevo de X»: si X es una playlist, empezar por lo último añadido; si es un artista, su
            # último lanzamiento (preguntando antes, como con «el último álbum de…»).
            r = _cmd("encontrar", que, "--tipo", tipo if tipo in _TIPOS else "auto")
            if not r.get("ok"):
                return r
            it = r["encontrado"]
            if it.get("tipo") == "artista":
                return _buscar_ultimo(it.get("nombre") or que, None, donde)
            if it.get("tipo") != "playlist":
                return _proponer(it, donde)
            return _poner(it["uri"], "playlist", donde, recientes=True, nombre=it.get("nombre"))
        return _poner(que, tipo, donde, desde_inicio, recientes=recientes, aleatorio=aleatorio)
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
    if accion == "crear_playlist":
        if not que:
            return {"ok": False, "error": "¿cómo llamo a la playlist?"}
        r = _cmd("playlist", "crear", que)
        if not r.get("ok"):
            return r
        return {"ok": True, "resumen": f"Playlist {que} creada", "decir": f"He creado la playlist «{que}» en tu Spotify."}
    if accion == "anadir_a_playlist":
        if not que:
            return {"ok": False, "error": "¿qué canción añado?"}
        pl = valor or "Favoritos"
        r = _cmd("playlist", "anadir", pl, que)
        if not r.get("ok"):
            return r
        return {"ok": True, "resumen": f"Añadido a {pl}", "decir": f"Añadida «{que}» a la playlist «{pl}»."}
    if accion == "cola_nueva":
        if not que:
            return {"ok": False, "error": "¿qué canciones pongo en la cola?"}
        temas = [t.strip() for t in que.split(",") if t.strip()] or [que.strip()]
        args = ["cola", "nueva", *temas]
        if donde:
            args.extend(["--donde", donde])
        r = _cmd(*args)
        if not r.get("ok"):
            return r
        tot = r.get("total", len(temas))
        rep = (r.get("reproduciendo") or {}).get("nombre") or "la primera canción"
        return {"ok": True, "resumen": f"Cola con {tot} canciones", "decir": f"Puesta la cola con {tot} canciones. Empieza con {rep}."}
    if accion == "cola_limpiar":
        r = _cmd("cola", "limpiar")
        if not r.get("ok"):
            return r
        return {"ok": True, "resumen": "Cola vaciada", "decir": "Cola de reproducción vaciada."}
    if accion == "sincronizar_youtube":
        if que and valor:
            r = _cmd("playlist", "sync-youtube", que, valor)
        else:
            r = _cmd("playlist", "sync-todo")
        if not r.get("ok"):
            return r
        anad = r.get("anadidas", 0)
        return {"ok": True, "resumen": "Playlists sincronizadas", "decir": f"Sincronización completada: {anad} canciones añadidas a Spotify."}
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
