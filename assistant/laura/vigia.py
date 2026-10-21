"""Vigía: Laura se levanta sola para avisar de correo, agenda y tareas.

Un hilo del daemon que cada `[vigia] cada_min`:
  - pregunta a Aurora (sesión propia `laura-vigia`) por lo NUEVO en Gmail/Calendar, JSON estricto;
  - mira en local (sin LLM) tareas en curso estancadas y trabajos fallidos sin leer.
Deduplica por id en ~/.local/share/laura/vigia.json. No corre con batería, en horas de
silencio, con No molestar o con `[vigia] enabled = false`. Los avisos son trabajos
`origen=laura, tipo=aviso` que nacen en `done` (ver JobManager.post_aviso).
La primera revisión tras arrancar el daemon solo anota lo existente como visto."""
from __future__ import annotations

import json
import re
import subprocess
import threading
import time
from datetime import datetime
from pathlib import Path

from .config import CFG, DATA_DIR, log

_STATE = DATA_DIR / "vigia.json"
SESSION = "laura-vigia"
VIGIA: "Vigia | None" = None

_PROMPT = """Eres el vigía de Laura. Revisa el Gmail y el Google Calendar de Alberto y responde
SOLO con un objeto JSON válido, sin texto antes ni después, sin markdown. Formato exacto:
{{"correos":[{{"id":"<id del mensaje>","de":"<remitente>","asunto":"<asunto>","resumen":"<una frase>","url":"<URL de Gmail o vacío>","urgente":<true|false>}}],
"eventos":[{{"id":"<id del evento>","titulo":"<título>","inicio":"<ISO 8601>","url":"<URL de Calendar o vacío>"}}]}}
Reglas:
- correos: solo NO LEÍDOS de las últimas 24 h que importen: personas reales, universidad, trabajo,
  plazos, pagos, viajes. Nada de spam, newsletters ni promociones. urgente=true solo si hay un plazo
  o pago inminente o alguien espera respuesta ya. Máximo 5.
- eventos: solo los que EMPIEZAN en los próximos {mins} minutos (ahora son las {ahora}). Máximo 3.
- Si no hay nada, devuelve {{"correos":[],"eventos":[]}}.
- No hagas ningún cambio: solo lectura.
Ya avisados (ignóralos): {vistos}"""


def _cfg() -> dict:
    return CFG.get("vigia", {})


def _load() -> dict:
    try:
        return json.loads(_STATE.read_text())
    except (OSError, ValueError):
        return {"vistos": {}, "ultima": 0}


def _save(st: dict) -> None:
    vistos = st["vistos"]
    if len(vistos) > 500:  # podar los más antiguos
        for k in sorted(vistos, key=vistos.get)[:len(vistos) - 400]:
            del vistos[k]
    _STATE.write_text(json.dumps(st, ensure_ascii=False))


def on_battery() -> bool:
    for f in Path("/sys/class/power_supply").glob("*/online"):
        try:
            if f.parent.joinpath("type").read_text().strip() == "Mains":
                return f.read_text().strip() == "0"
        except OSError:
            continue
    return False


def in_quiet_hours(now: datetime | None = None) -> bool:
    c = _cfg()
    now = now or datetime.now()
    try:
        a = datetime.strptime(c.get("silencio_desde", "23:30"), "%H:%M").time()
        b = datetime.strptime(c.get("silencio_hasta", "08:00"), "%H:%M").time()
    except ValueError:
        return False
    t = now.time()
    return (t >= a or t < b) if a > b else (a <= t < b)


_URGENCIA = re.compile(r"\b(plazo|entrega|pago|factura|examen|urgente|vuelo|hoy|mañana|manana|vence|caduca)\b", re.I)


def prioridad_correo(m: dict, cuerpo: str, c: dict) -> str:
    """normal para la bandeja principal, baja para Notificaciones; alta con palabras de urgencia
    o remitente importante (p. ej. la universidad)."""
    de = m.get("de", "").lower()
    if any(x.lower() in de for x in c.get("remitentes_importantes", [])) or \
            _URGENCIA.search(f"{m.get('asunto', '')} {cuerpo[:300]}"):
        return "alta"
    return "baja" if "CATEGORY_UPDATES" in m.get("etiquetas", "") else "normal"


def extract_json(texto: str) -> dict | None:
    m = re.search(r"\{.*\}", texto, re.S)
    if not m:
        return None
    try:
        d = json.loads(m.group(0))
    except ValueError:
        return None
    return d if isinstance(d, dict) else None


class Vigia:
    def __init__(self, jobs, ui: dict) -> None:
        self.jobs = jobs
        self.ui = ui  # {"dnd": bool, "fullscreen": bool}, lo actualiza el daemon
        self._lock = threading.Lock()
        self._wake = threading.Event()
        self._forced = False
        self._t = threading.Thread(target=self._loop, daemon=True)

    def start(self) -> None:
        if _cfg().get("enabled", True):
            self._t.start()
        else:
            log("vigía desactivado ([vigia] enabled = false)")

    def now(self) -> None:
        """Fuerza una revisión (comando vigia-now, tool novedades): ignora batería y silencio."""
        self._forced = True
        self._wake.set()
        if not self._t.is_alive():
            threading.Thread(target=self._loop_once_forced, daemon=True).start()

    def _loop_once_forced(self) -> None:
        self._forced = False
        self.check(silent=False)

    def silenced(self) -> str | None:
        if not _cfg().get("enabled", True):
            return "desactivado"
        if on_battery():
            return "con batería"
        if in_quiet_hours():
            return "horas de silencio"
        if self.ui.get("dnd"):
            return "no molestar"
        return None

    def _loop(self) -> None:
        # primera revisión: como mucho 2 min tras arrancar; solo anota lo existente
        self._wake.wait(timeout=60)
        primera = True
        while True:
            forced, self._forced = self._forced, False
            motivo = None if forced else self.silenced()
            if motivo:
                log(f"vigía: no reviso ({motivo})")
            else:
                try:
                    self.check(silent=primera and not forced)
                except Exception as e:  # noqa: BLE001
                    log(f"vigía: {e}")
                primera = False if not forced else primera
            self._wake.clear()
            self._wake.wait(timeout=float(_cfg().get("cada_min", 20)) * 60)

    # -- revisión
    def check(self, silent: bool = False) -> int:
        """Una pasada. Devuelve cuántos avisos nuevos. `silent`: solo marcar como visto."""
        with self._lock:
            st = _load()
            vistos = st["vistos"]
            nuevos = 0

            def aviso(clave: str, titulo: str, resumen: str, prioridad: str, fuentes=None, cuerpo=""):
                nonlocal nuevos
                if clave in vistos:
                    return
                vistos[clave] = time.time()
                if silent:
                    return
                nuevos += 1
                self.jobs.post_aviso(titulo, resumen, prioridad, fuentes, cuerpo)

            for c in self._remoto(vistos):
                aviso(*c)
            for c in self._local():
                aviso(*c)
            st["ultima"] = time.time()
            _save(st)
            log(f"vigía: revisión hecha, {nuevos} aviso(s) nuevo(s){' (inicial, silenciosa)' if silent else ''}")
            return nuevos

    def _remoto(self, vistos: dict) -> list[tuple]:
        """Workspace directo (sin LLM); si el servidor no responde, el respaldo de siempre: Aurora."""
        from . import workspace
        if workspace.enabled():
            try:
                return self._workspace(vistos)
            except workspace.WorkspaceUnavailable as e:
                log(f"vigía: Workspace no disponible ({e}); respaldo a Aurora")
        return self._aurora(vistos)

    def _workspace(self, vistos: dict) -> list[tuple]:
        from datetime import timedelta

        from . import workspace
        c = _cfg()
        out: list[tuple] = []
        msgs = workspace.buscar_correos(workspace.combinar("is:unread newer_than:1d"), 10)
        for m in msgs:
            clave = f"mail:{m['id']}"
            if clave in vistos:
                continue
            try:
                cuerpo = workspace.leer_correo(m["id"], 400)
            except workspace.WorkspaceUnavailable:
                cuerpo = ""
            prio = prioridad_correo(m, cuerpo, c)
            fu = [{"titulo": "Abrir en Gmail", "url": m["url"]}] if m.get("url") else []
            de = m["de"].split("<")[0].strip().strip('"') or m["de"]
            out.append((clave, f"Correo de {de}", f"Correo de {de}: {m['asunto']}", prio, fu,
                        f"De: {m['de']}\nAsunto: {m['asunto']}\nFecha: {m['fecha']}\n\n{cuerpo}"))
        ahora = datetime.now().astimezone()
        mins = int(c.get("aviso_evento_min", 30))
        for e in workspace.eventos(ahora, ahora + timedelta(minutes=mins), 5):
            if not re.search(r"[T ]\d{2}:\d{2}", e["inicio"]):
                continue  # evento de todo el día
            hora = re.search(r"[T ](\d{2}:\d{2})", e["inicio"]).group(1)
            fu = [{"titulo": "Ver evento", "url": e["url"]}] if e.get("url") else []
            out.append((f"ev:{e['id']}:{e['inicio']}", f"Evento: {e['titulo']}",
                        f"Evento a las {hora}: {e['titulo']}", "alta", fu, json.dumps(e, ensure_ascii=False, indent=1)))
        return out

    def _aurora(self, vistos: dict) -> list[tuple]:
        from . import aurora
        c = _cfg()
        prompt = _PROMPT.format(mins=c.get("aviso_evento_min", 30), ahora=datetime.now().strftime("%H:%M"),
                                vistos=", ".join(list(vistos)[-30:]) or "ninguno")
        r = aurora.run(prompt, threading.Event(), lambda q: False, session_key=SESSION)
        if not r.get("ok"):
            log(f"vigía: Aurora no respondió: {r.get('error')}")
            return []
        d = extract_json(r["texto"])
        if d is None:
            log("vigía: la respuesta de Aurora no era JSON")
            return []
        out = []
        for m in d.get("correos") or []:
            if not isinstance(m, dict) or not m.get("id"):
                continue
            fu = [{"titulo": "Abrir en Gmail", "url": m["url"]}] if m.get("url") else []
            out.append((f"mail:{m['id']}", f"Correo de {m.get('de', '?')}",
                        f"Correo de {m.get('de', '?')}: {m.get('asunto', '')}. {m.get('resumen', '')}".strip(),
                        "alta" if m.get("urgente") else "normal", fu, json.dumps(m, ensure_ascii=False, indent=1)))
        for e in d.get("eventos") or []:
            if not isinstance(e, dict) or not e.get("id"):
                continue
            hora = (e.get("inicio") or "")[11:16]
            fu = [{"titulo": "Ver evento", "url": e["url"]}] if e.get("url") else []
            out.append((f"ev:{e['id']}:{e.get('inicio', '')}", f"Evento: {e.get('titulo', '')}",
                        f"Evento a las {hora}: {e.get('titulo', '')}".strip(), "alta", fu,
                        json.dumps(e, ensure_ascii=False, indent=1)))
        return out

    def _local(self) -> list[tuple]:
        from . import jobs as J
        out = []
        dias = float(_cfg().get("tareas_estancadas_dias", 5))
        hoy = datetime.now().strftime("%Y-%m-%d")
        try:
            p = subprocess.run([str(Path.home() / ".local/bin/tasks-index"), "scan", "--print"],
                               capture_output=True, text=True, timeout=20)
            repos = json.loads(p.stdout)["repos"]
        except Exception as e:  # noqa: BLE001
            log(f"vigía: tasks-index: {e}")
            repos = []
        est = []
        for r in repos:
            for t in r["tareas"]:
                if t["estado"] != "en-curso":
                    continue
                try:
                    edad = (time.time() - Path(t["ruta"]).stat().st_mtime) / 86400
                except OSError:
                    continue
                if edad >= dias:
                    est.append(f"{t['titulo']} ({r['nombre']}, {int(edad)} días)")
        if est:
            res = f"Tienes {len(est)} tarea(s) en curso sin tocar desde hace días: " + "; ".join(est[:3]) + "."
            out.append((f"estancadas:{hoy}", "Tareas estancadas", res, "baja", [], "\n".join(f"- {e}" for e in est)))
        for m in J.list_jobs(50, horas=24):
            if m["estado"] == "failed" and not m.get("leido") and m.get("tipo", "trabajo") == "trabajo":
                out.append((f"fallo:{m['id']}", f"Falló: {m['titulo']}",
                            f"Un trabajo falló: {m['titulo'][:60]}", "normal", [], m.get("resumen", "")))
        return out
