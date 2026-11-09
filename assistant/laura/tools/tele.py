"""Tool de la tele (Chromecast de casa): estado y mandos. Envuelve el CLI `cast-helper`, que habla por socket unix con
su daemon en este mismo PC (no pasa por la red ni por Olimpo; el móvil sí va por Olimpo, v2.11).

`mandar_a_tele` lanza contenido: el vídeo que suena ahora en el PC (navegador/mpv vía MPRIS, o el enlace copiado),
un enlace o archivo concreto, la pantalla o un escritorio (espejo)."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import urllib.parse
from pathlib import Path

from . import tool

_ESTADOS = {"PLAYING": "reproduciendo", "PAUSED": "en pausa", "BUFFERING": "cargando", "IDLE": "en reposo"}
_ACCIONES = ["estado", "pausar", "reanudar", "alternar", "parar", "silenciar", "volumen", "saltar", "ir_a"]


def _bin() -> str | None:
    return shutil.which("cast-helper") or (str(Path.home() / ".local/bin/cast-helper")
                                           if (Path.home() / ".local/bin/cast-helper").exists() else None)


def _estado() -> dict | None:
    ruta = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "cast-helper" / "state.json"
    try:
        return json.loads(ruta.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _mmss(s: float) -> str:
    s = int(max(0, s))
    return f"{s // 3600} h {s % 3600 // 60} min" if s >= 3600 else f"{s // 60} min {s % 60} s"


def _cmd(*args: str) -> dict:
    exe = _bin()
    if not exe:
        return {"ok": False, "error": "no encuentro cast-helper"}
    try:
        r = subprocess.run([exe, *args], capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "cast-helper no responde"}
    try:
        d = json.loads(r.stdout.strip().splitlines()[-1])
    except (IndexError, ValueError):
        return {"ok": False, "error": (r.stderr or "cast-helper no respondió").strip()[:200]}
    return d if d.get("ok") else {"ok": False, "error": str(d.get("error") or "cast-helper falló")[:200]}


@tool("tele", "Controla la tele (Chromecast): ver qué suena, pausar, reanudar, parar, volumen, silenciar, saltar o ir a un punto. Para MANDAR algo a la tele usa mandar_a_tele.",
      {"accion": {"type": "string", "enum": _ACCIONES},
       "valor": {"type": "number", "description": "volumen: 0 a 100; saltar: segundos (negativo = atrás); ir_a: segundo absoluto"}},
      required=["accion"], icon="tv")
def tele(accion: str, valor: float | None = None) -> dict:
    est = _estado()
    act = (est or {}).get("active")
    if accion == "estado":
        if est is None:
            return {"ok": False, "error": "no encuentro el estado de la tele: ¿está cast-helper en marcha?"}
        if not act:
            return {"ok": True, "decir": "La tele está en reposo.", "resumen": "Estado de la tele"}
        e = _ESTADOS.get(str(act.get("state")).upper(), "en reposo")
        dur = f" de {_mmss(act['duration'])}" if act.get("duration") else ""
        return {"ok": True, "titulo": act.get("title"), "estado": e, "volumen": act.get("volume"),
                "decir": f"{act.get('title') or 'Algo'}, {e}, por el minuto {_mmss(act.get('position') or 0)}{dur}, "
                         f"volumen {act.get('volume')}.", "resumen": "Estado de la tele"}
    if accion not in _ACCIONES:
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    if not act:
        return {"ok": False, "error": "no hay nada reproduciendo en la tele"}
    if accion in ("volumen", "saltar", "ir_a") and valor is None:
        return {"ok": False, "error": f"«{accion}» necesita un valor"}
    if accion == "volumen":
        if not 0 <= valor <= 100:
            return {"ok": False, "error": "el volumen va de 0 a 100"}
        r, res = _cmd("volume", str(int(valor))), f"Volumen de la tele al {int(valor)}"
    elif accion == "saltar":
        pos = max(0.0, float(act.get("position") or 0) + float(valor))
        if act.get("duration"):
            pos = min(pos, max(0.0, float(act["duration"]) - 1))
        r, res = _cmd("seek", str(int(pos))), ("Adelante" if valor >= 0 else "Atrás") + f" {int(abs(valor))} s en la tele"
    elif accion == "ir_a":
        r, res = _cmd("seek", str(int(max(0, valor)))), "Tele al minuto " + _mmss(valor)
    else:
        cmd = {"pausar": "pause", "reanudar": "play", "alternar": "toggle", "parar": "stop", "silenciar": "mute"}[accion]
        r, res = _cmd(cmd), {"pausar": "Tele en pausa", "reanudar": "Tele reanudada", "alternar": "Tele alternada",
                             "parar": "Tele parada", "silenciar": "Silencio de la tele"}[accion]
    return {"ok": True, "resumen": res} if r.get("ok") else r


# ───────────── Mandar cosas a la tele ─────────────
_QUE = ["video", "pantalla", "escritorio"]


def _sh(*cmd: str) -> str:
    try:
        r = subprocess.run(list(cmd), capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


def _dispositivo() -> str | None:
    devs = ((_estado() or {}).get("devices") or [])
    if not devs:
        devs = _cmd("devices").get("devices") or []
    return (devs[0].get("name") or devs[0].get("uuid")) if devs else None


def _reproductor_actual() -> dict | None:
    """El vídeo que suena en el PC: primero el reproductor en marcha, luego uno en pausa. Devuelve
    {player, fuente (url o ruta), posicion, titulo} o None. Spotify se marca aparte (no es un vídeo)."""
    players = [p for p in _sh("playerctl", "-l").splitlines() if p]
    estado = {p: _sh("playerctl", "-p", p, "status") for p in players}
    for p in sorted(players, key=lambda p: estado[p] != "Playing"):
        if estado[p] not in ("Playing", "Paused"):
            continue
        url = _sh("playerctl", "-p", p, "metadata", "xesam:url")
        if p.startswith("spotify") or url.startswith("https://open.spotify.com"):
            return {"player": p, "spotify": True}
        if url.startswith("file://"):
            fuente = urllib.parse.unquote(urllib.parse.urlparse(url).path)
        elif url.startswith(("http://", "https://")):
            fuente = url
        else:
            continue
        try:
            pos = float(_sh("playerctl", "-p", p, "position") or 0)
        except ValueError:
            pos = 0.0
        return {"player": p, "fuente": fuente, "posicion": pos,
                "titulo": _sh("playerctl", "-p", p, "metadata", "xesam:title")}
    return None


def _del_portapapeles() -> str | None:
    t = _sh("wl-paste", "-n").strip()
    if t.startswith(("http://", "https://")) and " " not in t:
        return t
    if t.startswith("file://"):
        t = urllib.parse.unquote(urllib.parse.urlparse(t.splitlines()[0]).path)
    return t if t and os.path.isfile(os.path.expanduser(t)) else None


@tool("mandar_a_tele",
      "Manda a la tele (Chromecast): que=video («manda este vídeo»: el que suena en el PC; destino=url/ruta opcional), "
      "que=pantalla («proyecta la pantalla»), que=escritorio (destino=número).",
      {"que": {"type": "string", "enum": _QUE},
       "destino": {"type": "string"}},
      required=["que"], icon="cast")
def mandar_a_tele(que: str, destino: str | None = None) -> dict:
    if que not in _QUE:
        return {"ok": False, "error": f"no sé mandar «{que}» a la tele"}
    destino = (destino or "").strip() or None
    if que in ("pantalla", "escritorio"):
        args = ["mirror", "start"]
        if que == "escritorio":
            ws = destino
            if not ws:
                try:
                    ws = str(json.loads(_sh("hyprctl", "activeworkspace", "-j") or "{}").get("id") or "")
                except ValueError:
                    ws = ""
            if not ws or not ws.isdigit():
                return {"ok": False, "error": "¿qué escritorio? dime el número"}
            args += ["--source", f"workspace:{ws}"]
        else:
            args += ["--source", "monitor"]
        r = _cmd(*args)
        if not r.get("ok"):
            return r
        res = "Pantalla en la tele" if que == "pantalla" else f"Escritorio {args[-1].split(':')[1]} en la tele"
        return {"ok": True, "resumen": res, "decir": "Proyectando en la tele."}

    dev = _dispositivo()
    if not dev:
        return {"ok": False, "error": "no encuentro la tele: ¿está encendida y cast-helper en marcha?"}
    rep, inicio, titulo = None, 0.0, None
    fuente = destino
    if fuente:
        if not fuente.startswith(("http://", "https://")):
            fuente = os.path.expanduser(fuente)
            if not os.path.isfile(fuente):
                return {"ok": False, "error": f"no encuentro el archivo {destino}"}
    else:
        rep = _reproductor_actual()
        if rep and rep.get("spotify"):
            return {"ok": False, "error": "lo que suena es Spotify, no un vídeo: Spotify todavía no sé pasarlo a la tele"}
        if rep:
            fuente, inicio, titulo = rep["fuente"], rep["posicion"], rep["titulo"] or None
        else:
            fuente = _del_portapapeles()
        if not fuente:
            return {"ok": False, "error": "no sé qué vídeo: ponlo a reproducir en el PC o copia su enlace"}
    args = ["cast", dev, fuente]
    if inicio > 5:
        args += ["--start", str(int(inicio))]
    if titulo:
        args += ["--title", titulo]
    r = _cmd(*args)
    if not r.get("ok"):
        return r
    if rep:  # que no suene a la vez en el PC
        _sh("playerctl", "-p", rep["player"], "pause")
    nombre = titulo or ("el vídeo" if fuente.startswith("http") else os.path.basename(fuente))
    return {"ok": True, "resumen": "A la tele: " + nombre[:40], "decir": "Mandado a la tele."}
