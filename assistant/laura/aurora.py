"""Aurora: asistente personal (Hermes) en la Raspberry Pi, vía su API server (Runs API).

    POST /v1/runs                      crea el run -> {run_id}
    GET  /v1/runs/{id}                 estado (sondeo): running | waiting_for_approval | completed | ...
    POST /v1/runs/{id}/approval        {request_id, execution_generation, choice: once|deny}
    POST /v1/runs/{id}/stop            cancelar

Cabeceras: `Authorization: Bearer $AURORA_API_KEY` y `X-Hermes-Session-Key: laura-escritorio`
(sesión fija: Aurora conserva contexto entre peticiones de Laura). La clave nunca se loguea.

Confirmaciones: Aurora puede pedirlas de dos formas y ambas se tratan igual (`on_confirm`):
  1. de forma formal: el run queda en `waiting_for_approval` (evento approval.request);
  2. conversacional: el run TERMINA con un texto que acaba preguntando «¿Confirmas…?».
     Un «sí» se manda como nueva petición en la misma sesión; un «no» no manda nada.
"""
from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.request

from .config import CFG, log

_ASK = re.compile(r"(confirm|proced|adelante|autoriz|de acuerdo|quieres que|lo hago|te parece|continu)", re.I)


def _cfg() -> dict:
    return CFG.get("aurora", {})


def _headers() -> dict:
    key = os.environ.get("AURORA_API_KEY", "")
    if not key:
        raise RuntimeError("falta AURORA_API_KEY (~/.config/laura/aurora.env)")
    return {"Authorization": f"Bearer {key}", "Content-Type": "application/json",
            "X-Hermes-Session-Key": _cfg().get("session_key", "laura-escritorio")}


def _call(method: str, path: str, body: dict | None = None, timeout: float = 20):
    url = _cfg().get("url", "http://100.82.69.90:8642").rstrip("/") + path
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers=_headers(), method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}


def pregunta_final(texto: str) -> str | None:
    """Si el texto termina con una pregunta de confirmación, la devuelve (último párrafo)."""
    t = texto.strip()
    if not t.endswith(("?", "?»", "?\"")):
        return None
    partes = [p.strip() for p in t.split("\n\n") if p.strip()]
    ultimo = partes[-1]
    if not _ASK.search(ultimo):
        return None
    if len(ultimo) < 80 and len(partes) > 1:  # «¿Confirmas?» suelto: añadir el párrafo previo
        ultimo = partes[-2] + "\n\n" + ultimo
    return ultimo[-400:]


def stop(run_id: str) -> None:
    try:
        _call("POST", f"/v1/runs/{run_id}/stop", {}, timeout=10)
    except Exception as e:  # noqa: BLE001
        log(f"aurora: no pude parar {run_id}: {e}")


def _approval_body(status: dict, choice: str) -> dict:
    body: dict = {"choice": choice}
    pc = status.get("pending_controls") or []
    p = (pc[0] if isinstance(pc, list) and pc else pc) if pc else {}
    if isinstance(p, dict):
        rid = p.get("prompt_id") or p.get("request_id")
        if rid:
            body["request_id"] = rid
        if p.get("execution_generation") is not None:
            body["execution_generation"] = p["execution_generation"]
    return body


def _approval_question(status: dict) -> str:
    pc = status.get("pending_controls") or []
    p = pc[0] if isinstance(pc, list) and pc else (pc if isinstance(pc, dict) else {})
    for k in ("question", "prompt", "description", "message", "command", "preview"):
        if isinstance(p, dict) and p.get(k):
            return f"Aurora pide permiso: {p[k]}"
    return "Aurora pide permiso para hacer un cambio. ¿Lo autorizo?"


def run(peticion: str, cancel, on_confirm, on_run=None) -> dict:
    """Ejecuta una petición. `cancel`: objeto con is_set(). `on_confirm(pregunta)` devuelve
    True (sí), False (no) o None (cancelado/sin respuesta). `on_run(run_id)` avisa del id
    para poder cancelarlo. Devuelve {"ok": True, "texto": ...} o {"ok": False, "error": ...}."""
    timeout = float(_cfg().get("timeout", 600))
    t0 = time.monotonic()
    entrada = peticion
    for _ronda in range(4):
        try:
            st, d = _call("POST", "/v1/runs", {"input": entrada})
        except (OSError, RuntimeError) as e:
            return {"ok": False, "error": f"no llego a Aurora: {e}"}
        if st not in (200, 202) or "run_id" not in d:
            return {"ok": False, "error": f"Aurora rechazó la petición ({st})"}
        rid = d["run_id"]
        if on_run:
            on_run(rid)
        out = None
        while True:
            if cancel.is_set():
                stop(rid)
                return {"ok": False, "error": "cancelado"}
            if time.monotonic() - t0 > timeout:
                stop(rid)
                return {"ok": False, "error": f"Aurora no respondió en {timeout:.0f} s"}
            try:
                st, s = _call("GET", f"/v1/runs/{rid}")
            except OSError as e:
                log(f"aurora: sondeo falló ({e}); reintento")
                time.sleep(2)
                continue
            status = s.get("status")
            if status == "waiting_for_approval":
                r = on_confirm(_approval_question(s))
                if r is None:
                    stop(rid)
                    return {"ok": False, "error": "cancelado"}
                _call("POST", f"/v1/runs/{rid}/approval", _approval_body(s, "once" if r else "deny"))
                time.sleep(1)
                continue
            if status == "completed":
                out = (s.get("output") or "").strip()
                break
            if status in ("failed", "cancelled", "interrupted"):
                return {"ok": False, "error": (s.get("error") or f"Aurora terminó: {status}")}
            time.sleep(1.5)
        q = pregunta_final(out)
        if q is None:
            return {"ok": True, "texto": out or "(sin respuesta)"}
        r = on_confirm(q)
        if r is None:
            return {"ok": False, "error": "cancelado"}
        if not r:
            try:  # que la sesión de Aurora no se quede con la pregunta colgada
                _call("POST", "/v1/runs", {"input": "No, no lo hagas. Olvida esa petición: no hagas ningún cambio."})
            except (OSError, RuntimeError):
                pass
            return {"ok": False, "error": "no autorizado: no se ha hecho ningún cambio", "denegado": True}
        entrada = "Sí, adelante. Confirmo."
    return {"ok": False, "error": "Aurora pidió confirmación demasiadas veces"}
