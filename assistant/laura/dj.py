"""DJ de Laura: un subagente barato elige las canciones y `spotify-tele cola` las pone.

Laura (qwen3 4B, sin Internet) no sabe bastante música para montar una cola decente: se inventa títulos y
tarda en escribir 15 canciones como argumento de una tool. Así que Laura solo hace de puente:
  «ponme 10 canciones de reggaeton antiguo en la cola»
    → tool cola_dj → trabajo en segundo plano (kind="dj")
    → Gemini Flash (effort low, sin herramientas, carpeta vacía) devuelve un JSON con títulos y artistas
      (si falla, Claude Haiku sin herramientas)
    → spotify-tele cola nueva|anadir … → Laura avisa «Ya está: cola X, empieza con Y».

Coste: un prompt de ~150 tokens y ~400 de respuesta; sin contexto de repo ni herramientas.
"""
from __future__ import annotations

import json
import os
import re
import threading

from .config import CFG, DATA_DIR, log

_BRIEF = """Eres el DJ de Alberto. Elige {n} canciones para este pedido: «{pedido}».
{contexto}Reglas: canciones REALES que estén en Spotify, con el título y el artista principal exactos; sin repetir
canción; variado (como mucho 2 del mismo artista, salvo que el pedido sea de un artista); en un orden que fluya.
No uses herramientas ni busques nada. Responde SOLO con JSON, sin markdown ni texto alrededor:
{{"titulo": "<nombre corto para la cola>", "canciones": [{{"titulo": "...", "artista": "..."}}]}}"""

_REFIERE_A_LO_QUE_SUENA = re.compile(r"\b(esto|esta|este|lo que suena|parecid|similar|como (esta|este|la que))", re.I)
_POR_DEFECTO = 15
_MAX = 40


def cantidad(n) -> int:
    try:
        n = int(n)
    except (TypeError, ValueError):
        return _POR_DEFECTO
    return max(3, min(_MAX, n))


def prompt(pedido: str, n: int, sonando: dict | None = None) -> str:
    ctx = ""
    if sonando and sonando.get("cancion") and _REFIERE_A_LO_QUE_SUENA.search(pedido):
        ctx = f"Ahora mismo suena «{sonando['cancion']}» de {sonando.get('artista') or 'alguien'}.\n"
    return _BRIEF.format(n=n, pedido=pedido.strip(), contexto=ctx)


def parse(texto: str) -> dict | None:
    """Saca el JSON de la respuesta (tolera ```json``` y texto alrededor)."""
    if not texto:
        return None
    i, j = texto.find("{"), texto.rfind("}")
    if i < 0 or j <= i:
        return None
    try:
        d = json.loads(texto[i:j + 1])
    except ValueError:
        return None
    if isinstance(d.get("result"), str):  # salida --output-format json de Claude
        return parse(d["result"])
    vistas, canciones = set(), []
    for c in d.get("canciones") or []:
        if not isinstance(c, dict):
            continue
        t, a = str(c.get("titulo") or "").strip(), str(c.get("artista") or "").strip()
        clave = (t.lower(), a.lower())
        if t and clave not in vistas:
            vistas.add(clave)
            canciones.append({"titulo": t, "artista": a})
    if not canciones:
        return None
    return {"titulo": str(d.get("titulo") or "").strip() or "Cola del DJ", "canciones": canciones}


def _carpeta_vacia() -> str:
    """El subagente arranca en una carpeta vacía: nada de repo que indexar ni CLAUDE.md que leer."""
    d = DATA_DIR / "dj"
    d.mkdir(parents=True, exist_ok=True)
    return str(d)


def _motores() -> list[dict]:
    cfg = CFG.get("dj", {})
    ecfg = CFG.get("escalation", {})
    gemini = {"motor": "gemini", "modelo": cfg.get("modelo_gemini") or ecfg.get("model_auto", "gemini-3.8-flash-low"),
              "effort": cfg.get("effort_gemini", "low")}
    claude = {"motor": "claude", "modelo": cfg.get("modelo_claude", "haiku")}
    orden = [cfg.get("motor", "gemini"), cfg.get("respaldo", "claude")]
    por = {"gemini": gemini, "claude": claude}
    return [por[m] for m in dict.fromkeys(orden) if m in por]


def _lanzar(m: dict, texto: str, timeout: float, cancel: threading.Event | None) -> dict:
    from .jobs import _exec
    cwd = _carpeta_vacia()
    if m["motor"] == "gemini":
        agy = os.path.expanduser(CFG.get("escalation", {}).get("agy_bin", "~/.local/bin/agy"))
        cmd = [agy, "-p", texto, "--model", m["modelo"], "--effort", m["effort"], "--sandbox",
               "--disable-slash-commands"]
        return _exec(cmd, timeout, cwd=cwd, cancel=cancel, quien="Gemini")
    claude = os.path.expanduser(CFG.get("escalation", {}).get("claude", {}).get("bin", "claude"))
    cmd = [claude, "-p", texto, "--model", m["modelo"], "--tools", "", "--strict-mcp-config",
           "--output-format", "json"]
    return _exec(cmd, timeout, cwd=cwd, cancel=cancel, quien="Claude")


def elegir(pedido: str, n: int, sonando: dict | None = None,
           cancel: threading.Event | None = None) -> dict:
    """Pide la lista al primer motor que conteste bien. {"ok", "titulo", "canciones", "motor"} o error."""
    texto = prompt(pedido, n, sonando)
    timeout = float(CFG.get("dj", {}).get("timeout", 90))
    errores = []
    for m in _motores():
        if cancel is not None and cancel.is_set():
            return {"ok": False, "error": "cancelado"}
        log(f"dj: {m['motor']}/{m['modelo']} -> {pedido!r} ({n})")
        r = _lanzar(m, texto, timeout, cancel)
        lista = parse(r.get("texto", "")) if r.get("ok") else None
        if lista:
            return {"ok": True, "motor": m["motor"], **lista}
        errores.append(f"{m['motor']}: {r.get('error') or 'respuesta sin canciones'}")
    return {"ok": False, "error": "; ".join(errores) or "no hay motor de DJ configurado"}


def ejecutar(pedido: str, n=None, modo: str | None = None, donde: str | None = None,
             cancel: threading.Event | None = None) -> dict:
    """Trabajo completo: estado actual → lista del subagente → cola en Spotify. Formato de jobs (texto/resumen)."""
    from .tools.spotify import _cmd, _hablable
    n = cantidad(n)
    est = _cmd("estado", timeout=20)
    sonando = est if est.get("ok") and est.get("abierto") else None
    if modo not in ("nueva", "anadir"):
        # «Ponme X en la cola» con algo sonando = detrás de lo que suena; si no suena nada, empieza ya.
        modo = "anadir" if sonando and sonando.get("sonando") else "nueva"
    lista = elegir(pedido, n, sonando, cancel)
    if not lista.get("ok"):
        return lista
    qs = [f"{c['titulo']} {c['artista']}".strip() for c in lista["canciones"]]
    args = ["cola", modo, *qs]
    if modo == "nueva" and donde in ("tele", "pc"):
        args += ["--donde", donde]
    r = _cmd(*args, timeout=60 + 6 * len(qs))
    if not r.get("ok"):
        return {"ok": False, "error": r.get("error") or "Spotify no ha aceptado la cola"}
    puestas = ([r["reproduciendo"]] if r.get("reproduciendo") else []) + list(r.get("encoladas") or [])
    total = r.get("total") or len(puestas)
    faltan = len(qs) - total
    titulo = _hablable(lista["titulo"])
    lineas = [f"{i}. {p.get('nombre')} — {p.get('de') or ''}".rstrip(" —") for i, p in enumerate(puestas, 1)]
    texto = (f"Cola «{lista['titulo']}» ({total} canciones, elegidas por {lista['motor']}, "
             f"{'empieza ya' if modo == 'nueva' else 'detrás de lo que sonaba'}):\n\n" + "\n".join(lineas))
    if faltan > 0:
        texto += f"\n\nNo encontradas en Spotify: {faltan}."
    if modo == "nueva" and puestas:
        resumen = f"Cola «{titulo}» puesta: {total} canciones, empieza con {_hablable(puestas[0].get('nombre') or '')}."
    else:
        resumen = f"He añadido {total} canciones a la cola: «{titulo}»."
    return {"ok": True, "texto": texto, "resumen": resumen}
