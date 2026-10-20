"""Trabajos en segundo plano: escaladas a Gemini (agy) y a Claude Code.

Tras el «sí» de Alberto el proceso se lanza en un hilo, sin bloquear el ciclo.
Cada trabajo deja `jobs/<id>.json` (metadatos) y `jobs/<id>.md` (salida
completa) en ~/.local/share/laura/. Al terminar: evento `job` al overlay,
notify y un resumen hablado que se encola en el anunciador del daemon (habla
cuando Laura está libre)."""
from __future__ import annotations

import json
import os
import subprocess
import threading
import time
import uuid
from pathlib import Path

from .config import CFG, DATA_DIR, bus, log, notify
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


def _exec(cmd: list[str], timeout: float, cwd: str | None = None,
          cancel: threading.Event | None = None, quien: str = "El agente") -> dict:
    """Ejecuta `cmd` y devuelve {"ok": True, "texto": stdout} o {"ok": False,
    "error": ...}. No lanza excepciones: binario ausente, timeout, cancelado o
    exit code != 0 se traducen a ok=False."""
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                stdin=subprocess.DEVNULL, text=True, cwd=cwd)
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
            proc.terminate()
            return {"ok": False, "error": "cancelado"}
        if time.monotonic() - t0 > timeout:
            proc.terminate()
            return {"ok": False, "error": f"{quien} no respondió en {timeout:.0f} s"}
    if proc.returncode != 0:
        return {"ok": False, "error": (err or out or f"{cmd[0]} falló").strip()[:400]}
    out = out.strip()
    if not out:
        return {"ok": False, "error": f"{quien} no devolvió nada"}
    return {"ok": True, "texto": out}


def run_agy(prompt: str, model: str, effort: str, timeout: float,
            add_dir: str | None = None,
            cancel: threading.Event | None = None) -> dict:
    """Lanza `agy -p <prompt> --model ... --effort ...`."""
    ecfg = CFG.get("escalation", {})
    agy_bin = os.path.expanduser(ecfg.get("agy_bin", "agy"))
    cmd = [agy_bin, "-p", prompt, "--model", model, "--effort", effort,
           "--dangerously-skip-permissions"]
    if add_dir:
        cmd += ["--add-dir", os.path.expanduser(add_dir)]
    log(f"agy: {model}/{effort} -> {prompt[:80]!r}…")
    return _exec(cmd, timeout, cancel=cancel, quien="Gemini")


def run_claude(prompt: str, cancel: threading.Event | None = None) -> dict:
    """Lanza `claude -p <brief> --output-format json --permission-mode acceptEdits`
    en el cwd configurado ([escalation.claude])."""
    ccfg = CFG.get("escalation", {}).get("claude", {})
    cmd = [os.path.expanduser(ccfg.get("bin", "claude")), "-p", prompt,
           "--output-format", "json", "--permission-mode", "acceptEdits"]
    if ccfg.get("model"):
        cmd += ["--model", ccfg["model"]]
    cwd = os.path.expanduser(ccfg.get("cwd", "~/LinuxRicing"))
    log(f"claude: {ccfg.get('model')} en {cwd} -> {prompt[:80]!r}…")
    r = _exec(cmd, float(ccfg.get("timeout", 1800)), cwd=cwd, cancel=cancel, quien="Claude")
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


# ---------------------------------------------------------------- gestor de jobs
def _meta_path(jid: str) -> Path:
    return JOBS_DIR / f"{jid}.json"


def _save(meta: dict) -> None:
    _meta_path(meta["id"]).write_text(json.dumps(meta, ensure_ascii=False, indent=1))


def list_jobs(limit: int = 10) -> list[dict]:
    metas = []
    for f in JOBS_DIR.glob("*.json"):
        try:
            metas.append(json.loads(f.read_text()))
        except (OSError, ValueError):
            pass
    metas.sort(key=lambda m: m.get("inicio", 0), reverse=True)
    return metas[:limit]


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
    """Al arrancar el daemon: los trabajos «en curso» cuyo daemon dueño ya no
    existe (reinicio, caída) pasan a fallido. Devuelve cuántos."""
    n = 0
    for m in list_jobs(1000):
        if m.get("estado") != "en curso":
            continue
        if m.get("pid") != os.getpid() and _alive(m.get("pid")):
            continue  # lo lleva otro daemon vivo
        m.update(estado="fallido", fin=time.time(),
                 resumen="Interrumpido: el daemon se reinició antes de que terminara.")
        _save(m)
        bus.emit(type="job", value="failed", id=m["id"], destino=m.get("destino"),
                 titulo=m.get("peticion", "")[:80])
        n += 1
    return n


class JobManager:
    """`announce(texto)` encola una frase para que Laura la diga cuando esté libre."""

    def __init__(self, announce) -> None:
        self._announce = announce

    def start(self, destino: str, peticion: str, motivo: str = "") -> str:
        jid = uuid.uuid4().hex[:6]
        meta = {"id": jid, "destino": destino, "peticion": peticion,
                "estado": "en curso", "inicio": time.time(), "pid": os.getpid()}
        _save(meta)
        bus.emit(type="job", value="started", id=jid, destino=destino, titulo=peticion[:80])
        threading.Thread(target=self._run, args=(meta, motivo), daemon=True).start()
        return jid

    def _run(self, meta: dict, motivo: str) -> None:
        destino, peticion = meta["destino"], meta["peticion"]
        nombre = NOMBRES.get(destino, destino)
        ecfg = CFG.get("escalation", {})
        try:
            if destino == "claude":
                result = run_claude(build_claude_prompt(peticion, motivo))
            else:
                result = run_agy(build_gemini_prompt(peticion, motivo),
                                 model=ecfg.get("model_confirm", "gemini-3.1-pro-high"),
                                 effort=ecfg.get("effort_confirm", "medium"),
                                 timeout=ecfg.get("timeout_confirm", 180),
                                 add_dir=ecfg.get("add_dir") or None)
        except Exception as e:  # noqa: BLE001
            result = {"ok": False, "error": str(e)}
        meta["fin"] = time.time()
        ok = bool(result.get("ok"))
        cuerpo = result["texto"] if ok else f"ERROR: {result.get('error', 'desconocido')}"
        (JOBS_DIR / f"{meta['id']}.md").write_text(
            f"# {nombre}: {peticion}\n\n{cuerpo}\n")
        if ok:
            frase = summarize_for_voice(result["texto"], nombre)
            meta.update(estado="hecho", resumen=frase)
        else:
            frase = f"{nombre} no ha podido completar el encargo: {result.get('error', 'error desconocido')}"
            meta.update(estado="fallido", resumen=frase)
        _save(meta)
        log(f"job {meta['id']} ({destino}) {meta['estado']}: {frase}")
        bus.emit(type="job", value="done" if ok else "failed", id=meta["id"],
                 destino=destino, titulo=peticion[:80])
        notify("Laura", frase)
        self._announce(frase)
