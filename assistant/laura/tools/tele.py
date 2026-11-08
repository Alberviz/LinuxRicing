"""Tool de la tele (Chromecast de casa): estado y mandos. Envuelve el CLI `cast-helper`, que habla por socket unix con
su daemon en este mismo PC (no pasa por la red ni por Olimpo; el móvil sí va por Olimpo, v2.11). No lanza contenido:
eso se hace desde el panel o `cast-helper cast`."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
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


@tool("tele", "Controla la tele (Chromecast): ver qué suena, pausar, reanudar, parar, volumen, silenciar, saltar o ir a un punto.",
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
