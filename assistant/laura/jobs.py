"""Trabajos en segundo plano: escaladas a Gemini (agy) y a Claude Code, investigaciones
y peticiones a Aurora.

Cada trabajo es un hilo con una máquina de estados que se publica en el bus como
evento `job` (protocolo fijado en docs/laura-v2/PLAN-ORBE.md):

    started -> waiting (agente externo) -> confirm (sí/no, por voz o `job-confirm`)
            -> done | failed | cancelled

Deja `jobs/<id>.json` (metadatos), `jobs/<id>.md` (salida en bruto) en
~/.local/share/laura/ y, al terminar, una nota de Obsidian (laura.notes). La
frase final hablada es de una sola frase y solo si Laura está libre."""
from __future__ import annotations

import json
import os
import re
import shutil
import signal
import subprocess
import threading
import time
import uuid
from pathlib import Path

from .config import CFG, DATA_DIR, bus, log, notify
from . import notes
from .llm import summarize_for_voice

JOBS_DIR = DATA_DIR / "jobs"
JOBS_DIR.mkdir(parents=True, exist_ok=True)

NOMBRES = {"gemini": "Gemini", "claude": "Claude"}

_GEMINI_BRIEF = """Eres un agente de código (Gemini, vía Antigravity) invocado por Laura, el
asistente de voz local de Alberto, para una tarea que Laura no puede resolver
por sí misma.

Contexto del repositorio:
- Repo: ~/LinuxRicing — dotfiles y "rice" de escritorio Linux (Hyprland +
  Quickshell/Caelestia, tema matugen, control RGB, este mismo asistente de
  voz en assistant/).
- Lee CLAUDE.md (y GEMINI.md) en la raíz del repo: ahí están las convenciones
  del proyecto (flujo de ramas, qué carpetas toca cada agente, backlog vivo
  en vault/, obligación de reiniciar el shell de Quickshell tras tocar UI).
- Si el cambio es sustancial, créate una rama dedicada para el trabajo (no
  hace falta pedir permiso); si es un arreglo mínimo, ir directo a la rama
  activa está bien.
- No reinicies tú el shell de Quickshell ni hagas instalaciones de sistema:
  eso lo hace Alberto a mano.

Petición original de Alberto (transcrita de su voz, tal cual):
"{peticion}"

Por qué Laura no puede resolver esto ella misma:
{motivo}

Instrucciones:
1. Interpreta la petición y haz el cambio necesario en el repo de verdad (no
   te limites a proponerlo).
2. Sé conciso y ve al grano.
3. Termina con un párrafo corto (2-3 frases) resumiendo qué has hecho y qué
   archivos has tocado — Laura se lo va a leer a Alberto en voz alta, así que
   nada de markdown, listas ni bloques de código en ese resumen final.
"""

_CLAUDE_BRIEF = """Eres Claude Code, invocado por Laura (el asistente de voz local de
Alberto) para una tarea grande que ella no puede resolver por sí misma.

Contexto:
- Repo: ~/LinuxRicing — dotfiles y "rice" de escritorio Linux (Hyprland +
  Quickshell/Caelestia, control RGB, el asistente de voz en assistant/).
- Sigue CLAUDE.md en la raíz del repo: convenciones, reparto de carpetas entre
  agentes y, sobre todo, el flujo de ramas. Si es una feature o trabajo
  sustancial, crea una rama dedicada, trabaja ahí y mergéala de vuelta al
  terminar; un arreglo suelto puede ir directo a la rama activa.
- No hagas instalaciones de sistema ni reinicios que correspondan a Alberto, y
  commitea solo rutas concretas (nunca `git add -A`: hay otros agentes
  trabajando).

Petición original de Alberto (transcrita de su voz, tal cual):
"{peticion}"

Por qué Laura no puede resolver esto ella misma:
{motivo}

Haz el trabajo de verdad (no te limites a proponerlo). Termina con un párrafo
corto (2-3 frases) que diga qué has hecho y qué archivos has tocado — Laura se
lo leerá a Alberto en voz alta, así que sin markdown, listas ni bloques de
código en ese resumen final.
"""

_MOTIVO_DEF = ("Laura ha juzgado que esto se sale de lo que sabe o puede hacer "
               "ella misma.")


def build_gemini_prompt(peticion: str, motivo: str) -> str:
    return _GEMINI_BRIEF.format(peticion=peticion, motivo=motivo or _MOTIVO_DEF)


def build_claude_prompt(peticion: str, motivo: str) -> str:
    return _CLAUDE_BRIEF.format(peticion=peticion, motivo=motivo or _MOTIVO_DEF)


def _matar(proc: subprocess.Popen) -> None:
    """Termina el proceso y todo su grupo (el agente puede lanzar hijos) y lo recoge."""
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        proc.terminate()
    try:
        proc.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            proc.kill()
        proc.communicate()


def _exec(cmd: list[str], timeout: float, cwd: str | None = None,
          cancel: threading.Event | None = None, quien: str = "El agente") -> dict:
    """Ejecuta `cmd` y devuelve {"ok": True, "texto": stdout} o {"ok": False,
    "error": ...}. No lanza excepciones: binario ausente, timeout, cancelado o
    exit code != 0 se traducen a ok=False."""
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                stdin=subprocess.DEVNULL, text=True, cwd=cwd,
                                start_new_session=True)
    except FileNotFoundError:
        return {"ok": False, "error": f"no encuentro el binario '{cmd[0]}' (¿está en el PATH?)"}
    except NotADirectoryError:
        return {"ok": False, "error": f"el directorio de trabajo no existe: {cwd}"}
    t0 = time.monotonic()
    while True:
        try:
            out, err = proc.communicate(timeout=0.2)
            break
        except subprocess.TimeoutExpired:
            pass
        if cancel is not None and cancel.is_set():
            _matar(proc)
            return {"ok": False, "error": "cancelado"}
        if time.monotonic() - t0 > timeout:
            _matar(proc)
            return {"ok": False, "error": f"{quien} no respondió en {timeout:.0f} s"}
    if proc.returncode != 0:
        return {"ok": False, "error": (err or out or f"{cmd[0]} falló").strip()[:400]}
    out = out.strip()
    if not out:
        return {"ok": False, "error": f"{quien} no devolvió nada"}
    return {"ok": True, "texto": out}


_KNOWN_PROJECTS = {
    "krakount": os.path.expanduser("~/proyectos/krakount"),
    "cracount": os.path.expanduser("~/proyectos/krakount"),
    "linuxricing": os.path.expanduser("~/LinuxRicing"),
    "minecraft": os.path.expanduser("~/minecraft-server"),
    "gym": os.path.expanduser("~/gym-bot"),
    "universidad": os.path.expanduser("~/Documentos/Universidad"),
    "barberbot": os.path.expanduser("~/barber-bot"),
    "vuelosviajes": os.path.expanduser("~/vuelos-viajes"),
    "weblaura": os.path.expanduser("~/web-laura"),
}


def _detect_project_dir(text: str) -> str | None:
    t = text.lower()
    for k, p in _KNOWN_PROJECTS.items():
        if k in t:
            return p
    return None


def run_agy(prompt: str, model: str, effort: str, timeout: float,
            add_dir: str | list[str] | None = None,
            cancel: threading.Event | None = None,
            readonly: bool = False) -> dict:
    """Lanza `agy -p <prompt> --model ... --effort ...`. `readonly`: investigación sin
    tocar nada (el prompt lo prohíbe y se añade --sandbox)."""
    ecfg = CFG.get("escalation", {})
    agy_bin = os.path.expanduser(ecfg.get("agy_bin", "~/.local/bin/agy"))
    if not os.path.isabs(agy_bin) and "/" not in agy_bin:
        cand = (shutil.which(agy_bin) or
                shutil.which(agy_bin, path=f"{os.path.expanduser('~/.local/bin')}:{os.environ.get('PATH', '')}"))
        if cand:
            agy_bin = cand
        elif os.path.exists(os.path.expanduser(f"~/.local/bin/{agy_bin}")):
            agy_bin = os.path.expanduser(f"~/.local/bin/{agy_bin}")
    cmd = [agy_bin, "-p", prompt, "--model", model, "--effort", effort,
           "--dangerously-skip-permissions"]
    if add_dir:
        dirs = [add_dir] if isinstance(add_dir, str) else add_dir
        for d in dirs:
            cmd += ["--add-dir", os.path.expanduser(d)]
    if readonly:
        cmd += ["--sandbox"]
    log(f"agy: {model}/{effort} -> {prompt[:80]!r}…")
    return _exec(cmd, timeout, cancel=cancel, quien="Gemini")


def run_claude(prompt: str, cancel: threading.Event | None = None,
               cwd: str | None = None) -> dict:
    """Lanza `claude -p <brief> --output-format json --permission-mode acceptEdits`
    en el cwd configurado ([escalation.claude])."""
    ccfg = CFG.get("escalation", {}).get("claude", {})
    cmd = [os.path.expanduser(ccfg.get("bin", "claude")), "-p", prompt,
           "--output-format", "json", "--permission-mode", "acceptEdits"]
    if ccfg.get("model"):
        cmd += ["--model", ccfg["model"]]
    work_dir = os.path.expanduser(cwd or ccfg.get("cwd", "~/LinuxRicing"))
    log(f"claude: {ccfg.get('model')} en {work_dir} -> {prompt[:80]!r}…")
    r = _exec(cmd, float(ccfg.get("timeout", 1800)), cwd=work_dir, cancel=cancel, quien="Claude")
    if not r["ok"]:
        return r
    try:
        d = json.loads(r["texto"])
    except ValueError:
        return r  # salida no JSON: úsala tal cual
    texto = (d.get("result") or "").strip()
    if d.get("is_error"):
        return {"ok": False, "error": texto or "Claude terminó con error"}
    if not texto:
        return {"ok": False, "error": "Claude no devolvió nada"}
    return {"ok": True, "texto": texto}


_INVESTIGAR_BRIEF = """Eres un investigador invocado por Laura, el asistente de voz de Alberto.
Investiga en Internet el tema siguiente y entrega un resultado útil y verificable.

Tema: "{tema}"

REGLAS: es una tarea de SOLO LECTURA. No modifiques, crees ni borres ningún archivo, no
ejecutes comandos que cambien nada, no instales nada. Solo busca y lee.
Formato de salida (markdown, en español):
- Primero un párrafo de 2-3 frases con la respuesta directa.
- Después los detalles que merezcan la pena, en pocas viñetas.
- Termina con una sección «## Fuentes» con enlaces markdown [título](url).
"""

FINAL = ("done", "failed", "cancelled")


def build_investigar_prompt(tema: str) -> str:
    return _INVESTIGAR_BRIEF.format(tema=tema)


def extract_sources(texto: str, limite: int = 8) -> list[dict]:
    """Enlaces markdown [título](url) y URLs sueltas del texto, sin repetir."""
    out, vistas = [], set()
    for t, u in re.findall(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", texto):
        if u not in vistas:
            vistas.add(u)
            out.append({"titulo": t.strip(), "url": u})
    for u in re.findall(r"(?<![\(\[])\bhttps?://[^\s)>\]]+", texto):
        u = u.rstrip(".,;")
        if u not in vistas:
            vistas.add(u)
            out.append({"titulo": re.sub(r"^https?://(www\.)?", "", u).split("/")[0], "url": u})
    return out[:limite]


def _primera_frase(t: str, n: int = 160) -> str:
    t = re.sub(r"[#*_`>]+", "", t).strip()
    t = re.sub(r"\s+", " ", t)
    m = re.match(r"(.+?[.!?])(\s|$)", t)
    f = m.group(1) if m else t
    return f if len(f) <= n else f[:n].rsplit(" ", 1)[0] + "…"


# ---------------------------------------------------------------- gestor de jobs
def _meta_path(jid: str) -> Path:
    return JOBS_DIR / f"{jid}.json"


def _save(meta: dict) -> None:
    tmp = _meta_path(meta["id"]).with_suffix(".tmp")
    tmp.write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    tmp.replace(_meta_path(meta["id"]))


_LEGACY = {"en curso": "waiting", "hecho": "done", "fallido": "failed"}


def _load(f: Path) -> dict | None:
    try:
        m = json.loads(f.read_text())
    except (OSError, ValueError):
        return None
    m["estado"] = _LEGACY.get(m.get("estado"), m.get("estado"))
    m.setdefault("titulo", (m.get("peticion") or "")[:80])
    for k, v in (("resumen", ""), ("pregunta", ""), ("nota", ""), ("fuentes", []), ("leido", False), ("fin", None)):
        m.setdefault(k, v)
    return m


def list_jobs(limit: int = 10, horas: float | None = None) -> list[dict]:
    metas = [m for f in JOBS_DIR.glob("*.json") if (m := _load(f))]
    if horas is not None:
        corte = time.time() - horas * 3600
        metas = [m for m in metas if (m.get("inicio") or 0) >= corte]
    metas.sort(key=lambda m: m.get("inicio", 0), reverse=True)
    return metas[:limit]


def get_job(jid: str) -> dict | None:
    return _load(_meta_path(jid))


def to_event(meta: dict) -> dict:
    """Job -> evento del protocolo (el mismo formato sirve para el comando `jobs`)."""
    return {"type": "job", "value": meta["estado"], "id": meta["id"], "destino": meta["destino"],
            "titulo": meta["titulo"][:80], "resumen": meta.get("resumen", ""),
            "pregunta": meta.get("pregunta", ""), "nota": meta.get("nota", ""),
            "fuentes": meta.get("fuentes", []), "inicio": meta["inicio"],
            "fin": meta.get("fin"), "leido": bool(meta.get("leido"))}


def _alive(pid: int | None) -> bool:
    """¿Sigue vivo ese pid y es un laurad? (evita falsos vivos por reutilización de pid)"""
    if not pid:
        return False
    try:
        cmd = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return False
    return b"laura" in cmd


def reap_orphans() -> int:
    """Al arrancar el daemon: los trabajos no terminados cuyo daemon dueño ya no
    existe (reinicio, caída) pasan a fallido. Devuelve cuántos."""
    n = 0
    for m in list_jobs(1000):
        if m.get("estado") in FINAL:
            continue
        if m.get("pid") != os.getpid() and _alive(m.get("pid")):
            continue  # lo lleva otro daemon vivo
        m.update(estado="failed", fin=time.time(), pregunta="",
                 resumen="Interrumpido: el daemon se reinició antes de que terminara.")
        _save(m)
        bus.emit(**to_event(m))
        n += 1
    return n


class _Live:
    """Estado en memoria de un trabajo vivo."""

    def __init__(self) -> None:
        self.cancel = threading.Event()
        self.answered = threading.Event()
        self.answer: bool | None = None
        self.stop_remote = None  # callable para parar un run remoto (Aurora)


class JobManager:
    """`announce(texto)` encola una frase corta hablada (solo si Laura está libre).
    `on_confirm(meta)` se llama cuando un trabajo ya en marcha necesita un sí/no por voz
    (el daemon abre una pregunta hablada); los que nacen en un ciclo la hacen ellos mismos."""

    def __init__(self, announce, on_confirm=None) -> None:
        self._announce = announce
        self.on_confirm = on_confirm
        self._live: dict[str, _Live] = {}
        self._lock = threading.Lock()
        self.launched = 0  # trabajos lanzados en esta vida del daemon (el ciclo lo usa para cerrarse)

    # -- API pública
    def start(self, destino: str, peticion: str, motivo: str = "", *, kind: str = "agent",
              pregunta: str = "", ask_voice: bool = True, titulo: str = "") -> str:
        """Crea el trabajo y lo lanza en un hilo. Con `pregunta`, nace en `confirm` y solo
        arranca tras un sí. kind: agent (gemini/claude) | investigar | aurora."""
        self.launched += 1
        jid = uuid.uuid4().hex[:6]
        meta = {"id": jid, "destino": destino, "kind": kind, "peticion": peticion,
                "titulo": (titulo or peticion)[:80], "estado": "started", "resumen": "",
                "pregunta": "", "nota": "", "fuentes": [], "leido": False,
                "inicio": time.time(), "fin": None, "pid": os.getpid()}
        live = _Live()
        with self._lock:
            self._live[jid] = live
        if pregunta:
            live.answered.clear()
            meta["pregunta"] = pregunta
            self._set(meta, "confirm")
        else:
            self._set(meta, "started")
        threading.Thread(target=self._run, args=(meta, live, motivo, pregunta, ask_voice),
                         daemon=True).start()
        return jid

    def answered_event(self, jid: str) -> threading.Event | None:
        live = self._live.get(jid)
        return live.answered if live else None

    def confirm(self, jid: str, yes: bool) -> dict:
        live = self._live.get(jid)
        m = get_job(jid)
        if not live or not m or m["estado"] != "confirm":
            return {"ok": False, "error": "ese trabajo no espera confirmación"}
        live.answer = bool(yes)
        live.answered.set()
        return {"ok": True}

    def cancel(self, jid: str) -> dict:
        live = self._live.get(jid)
        m = get_job(jid)
        if not m:
            return {"ok": False, "error": "no existe ese trabajo"}
        if m["estado"] in FINAL:
            return {"ok": False, "error": "ya había terminado"}
        if not live:
            return {"ok": False, "error": "ese trabajo lo lleva otro proceso"}
        live.cancel.set()
        live.answered.set()  # despierta una espera de confirmación
        if live.stop_remote:
            try:
                live.stop_remote()
            except Exception as e:  # noqa: BLE001
                log(f"cancelar remoto: {e}")
        return {"ok": True}

    def read(self, jid: str) -> dict:
        m = get_job(jid)
        if not m:
            return {"ok": False, "error": "no existe ese trabajo"}
        m["leido"] = True
        _save(m)
        bus.emit(**to_event(m))
        return {"ok": True}

    def active(self) -> int:
        return sum(1 for m in list_jobs(100) if m["estado"] not in FINAL and m["id"] in self._live)

    def wait_all(self, timeout: float = 900) -> None:
        t0 = time.monotonic()
        while self.active() and time.monotonic() - t0 < timeout:
            time.sleep(0.5)

    # -- internos
    def _set(self, meta: dict, estado: str, **cambios) -> None:
        meta.update(cambios)
        meta["estado"] = estado
        _save(meta)
        bus.emit(**to_event(meta))

    def _ask(self, meta: dict, live: _Live, pregunta: str, ask_voice: bool,
             ya_en_confirm: bool = False) -> bool | None:
        """Pasa a `confirm` y espera sí/no (voz o tarjeta). True/False, None si cancelado."""
        previo = "started" if ya_en_confirm else meta["estado"]
        if not ya_en_confirm:
            live.answered.clear()
            live.answer = None
            self._set(meta, "confirm", pregunta=pregunta)
        if ask_voice and self.on_confirm:
            try:
                self.on_confirm(dict(meta))
            except Exception as e:  # noqa: BLE001
                log(f"on_confirm: {e}")
        limite = float(CFG.get("background", {}).get("confirm_timeout", 600))
        live.answered.wait(timeout=limite)
        if live.cancel.is_set():
            return None
        if live.answer is None:  # sin respuesta a tiempo
            return None
        self._set(meta, previo if previo != "confirm" else "waiting", pregunta="")
        return live.answer

    def _run(self, meta: dict, live: _Live, motivo: str, pregunta: str, ask_voice: bool) -> None:
        try:
            if pregunta:
                r = self._ask(meta, live, pregunta, ask_voice, ya_en_confirm=True)
                if r is None:
                    return self._finish(meta, live, {"ok": False, "error": "cancelado"}, cancelado=True)
                if not r:
                    return self._finish(meta, live, {"ok": False, "error": "cancelado"}, cancelado=True)
            result = self._execute(meta, live, motivo)
        except Exception as e:  # noqa: BLE001
            result = {"ok": False, "error": str(e)}
        self._finish(meta, live, result)

    def _execute(self, meta: dict, live: _Live, motivo: str) -> dict:
        kind, destino, peticion = meta["kind"], meta["destino"], meta["peticion"]
        ecfg = CFG.get("escalation", {})
        if kind == "aurora":
            from . import aurora
            self._set(meta, "waiting")
            live_run = {}
            live.stop_remote = lambda: aurora.stop(live_run.get("id", ""))

            def on_confirm(q: str):
                if live.cancel.is_set():
                    return None
                r = self._ask(meta, live, q, True)
                return r

            r = aurora.run(peticion, live.cancel, on_confirm,
                           on_run=lambda rid: live_run.__setitem__("id", rid))
            if r.get("denegado"):
                r["cancelado"] = True
            return r
        if kind == "investigar":
            if destino == "gemini":
                self._set(meta, "waiting")
                return run_agy(build_investigar_prompt(peticion),
                               model=ecfg.get("model_confirm", "gemini-4-argon-high"),
                               effort=ecfg.get("effort_confirm", "high"),
                               timeout=ecfg.get("timeout_confirm", 180) * 2,
                               cancel=live.cancel, readonly=True)
            return self._investigar_local(peticion, live)
        self._set(meta, "waiting")
        proj_dir = _detect_project_dir(peticion)
        if destino == "claude":
            return run_claude(build_claude_prompt(peticion, motivo), live.cancel, cwd=proj_dir)
        extra_dirs = [ecfg.get("add_dir", "~/LinuxRicing")]
        if proj_dir and proj_dir not in extra_dirs:
            extra_dirs.append(proj_dir)
        return run_agy(build_gemini_prompt(peticion, motivo),
                       model=ecfg.get("model_confirm", "gemini-4-argon-high"),
                       effort=ecfg.get("effort_confirm", "high"),
                       timeout=ecfg.get("timeout_confirm", 180),
                       add_dir=extra_dirs, cancel=live.cancel)

    def _investigar_local(self, tema: str, live: _Live) -> dict:
        """Laura sola: buscar_web + resumen con el modelo local."""
        from .llm import answer_from_sources
        from .tools.web import _ddg
        try:
            res = _ddg(tema)
        except Exception as e:  # noqa: BLE001
            return {"ok": False, "error": f"no pude buscar: {e}"}
        if live.cancel.is_set():
            return {"ok": False, "error": "cancelado"}
        if not res:
            return {"ok": False, "error": "la búsqueda no devolvió resultados"}
        cuerpo = answer_from_sources(tema, res)
        fuentes = "\n".join(f"- [{r['titulo']}]({r['url']}) — {r['fragmento']}" for r in res if r.get("url"))
        return {"ok": True, "texto": f"{cuerpo}\n\n## Fuentes\n\n{fuentes}", "fuentes": [
            {"titulo": r["titulo"], "url": r["url"]} for r in res if r.get("url")], "resumen": _primera_frase(cuerpo)}

    def _finish(self, meta: dict, live: _Live, result: dict, cancelado: bool = False) -> None:
        nombre = NOMBRES.get(meta["destino"], meta["destino"].capitalize())
        cancelado = cancelado or live.cancel.is_set() or bool(result.get("cancelado"))
        ok = bool(result.get("ok")) and not cancelado
        if ok:
            texto = result["texto"]
            resumen = result.get("resumen") or summarize_for_voice(texto, nombre)
            fuentes = result.get("fuentes") or extract_sources(texto)
            estado = "done"
        elif cancelado:
            texto = result.get("error", "cancelado")
            resumen = "Cancelado" if live.cancel.is_set() or texto == "cancelado" else texto
            fuentes, estado = [], "cancelled"
        else:
            texto = f"ERROR: {result.get('error', 'desconocido')}"
            resumen = f"{nombre} no ha podido completar el encargo: {result.get('error', 'error desconocido')}"
            fuentes, estado = [], "failed"
        meta.update(fin=time.time(), resumen=resumen, fuentes=fuentes, pregunta="")
        (JOBS_DIR / f"{meta['id']}.md").write_text(f"# {nombre}: {meta['peticion']}\n\n{texto}\n")
        if estado != "cancelled":
            meta["estado"] = estado
            try:
                meta["nota"] = notes.write_note(meta, texto)
            except Exception as e:  # noqa: BLE001
                log(f"nota de Obsidian: {e}")
        self._set(meta, estado)
        log(f"job {meta['id']} ({meta['destino']}) {estado}: {resumen[:120]}")
        with self._lock:
            self._live.pop(meta["id"], None)
        if estado != "cancelled":
            notify("Laura", resumen)
            frase = (f"Ya está: {_primera_frase(resumen, 110)} Te lo dejo en el panel."
                     if ok else f"No ha podido ser: {_primera_frase(resumen, 110)}")
            self._announce(frase)


MANAGER: JobManager | None = None


def set_manager(m: JobManager) -> None:
    global MANAGER
    MANAGER = m
