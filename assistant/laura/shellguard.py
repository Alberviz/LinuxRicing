"""Guarda para `ejecutar_comando`: clasifica un comando como bloqueado, de solo lectura
(se ejecuta directo) o que requiere confirmación de Alberto."""
from __future__ import annotations

import os
import re
import shlex
import subprocess
from pathlib import Path

BLOQUEADO, DIRECTO, CONFIRMAR = "bloqueado", "directo", "confirmar"

_HARD = [
    (r"\brm\s+(-\w+\s+)*(/|~|\$HOME|/home/?)(\s|/?$|\*)", "borrar / o el home"),
    (r"\brm\s+.*-\w*[rf]\w*.*\s(/|~|\$HOME)(\s|$)", "borrar / o el home"),
    (r"\bmkfs", "formatear discos"),
    (r"\bdd\b.*\bof=/dev/", "escribir en discos"),
    (r"\b(shutdown|reboot|poweroff|halt)\b|systemctl\s+(poweroff|reboot|halt|suspend)", "apagar o reiniciar"),
    (r"(curl|wget)\b.*\|\s*(sudo\s+)?(ba|z)?sh\b", "ejecutar scripts descargados"),
    (r"\.ssh|\.credentials|aurora\.env|\.gnupg|\.aws|\.netrc|id_rsa|id_ed25519", "ficheros de credenciales"),
    (r":\(\)\s*\{", "fork bomb"),
]

_SECRET = re.compile(r"(\.env|\.ssh|\.credentials|\.gnupg|\.aws|\.netrc|aurora\.env|key|secret|token|passw)", re.I)
_BAD_CHARS = re.compile(r"[;&`<>]|\$\(|\|\||\n")
_READ_FILES = {"cat", "head", "tail"}
_SIMPLE = {"uptime", "free", "df", "ps", "ls", "nvidia-smi", "du", "lsblk", "date", "whoami", "uname"}


def _file_ok(arg: str) -> bool:
    if arg.startswith("-"):
        return True
    p = Path(os.path.expanduser(arg))
    try:
        p = p.resolve()
    except OSError:
        return False
    if not str(p).startswith(str(Path.home()) + os.sep) or _SECRET.search(str(p)):
        return False
    return True


def _safe_single(argv: list[str]) -> bool:
    if not argv:
        return False
    c, a = argv[0], argv[1:]
    if c in _SIMPLE:
        return not (c == "du" and any(not x.startswith("-") and not x.startswith(("/", "~", ".")) for x in a))
    if c == "git":
        return bool(a) and a[0] in {"status", "log", "diff", "branch", "show", "remote"} and \
            not any(x in {"-D", "-d", "-m", "--delete"} for x in a)
    if c == "systemctl":
        return len(a) >= 2 and a[0] == "--user" and a[1] in {"status", "is-active", "list-units", "is-failed",
                                                                 "--failed", "list-timers"}
    if c == "journalctl":
        return any(x == "-n" or x.startswith("-n") or x.startswith("--lines") for x in a) and \
            not any(x.startswith(("--vacuum", "--rotate", "--flush")) for x in a)
    if c == "top":
        return a == ["-bn1"]
    if c == "ip":
        return bool(a) and a[0] in {"a", "addr", "address", "r", "route", "link"} and "flush" not in a
    if c == "nmcli":
        return bool(a) and not any(x in {"connect", "up", "down", "delete", "modify", "add", "radio", "con", "connection"}
                                    and i > 0 and a[0] != "-t" for i, x in enumerate(a)) and \
            a[0] in {"device", "dev", "general", "-t", "connection", "con"} and \
            not any(x in {"up", "down", "delete", "modify", "add", "reload", "wifi"} and x != "list" for x in a[1:2] if a[0] in {"connection", "con"}) \
            and not (a[0] in {"connection", "con"} and (len(a) < 2 or a[1] not in {"show"}))
    if c == "pactl":
        return bool(a) and a[0] == "list" or a[:1] == ["info"]
    if c == "wpctl":
        return a[:1] in (["status"], ["get-volume"])
    if c == "hyprctl":
        return bool(a) and a[0] in {"monitors", "workspaces", "clients", "activewindow", "devices", "version",
                                     "-j", "activeworkspace", "layers"} and "dispatch" not in a
    if c in _READ_FILES:
        files = [x for x in a if not x.startswith("-")]
        return bool(files) and all(_file_ok(x) for x in files)
    return False


def clasificar(cmd: str) -> tuple[str, str]:
    """-> (nivel, motivo). nivel: bloqueado | directo | confirmar."""
    cmd = cmd.strip()
    if not cmd:
        return BLOQUEADO, "comando vacío"
    for rx, motivo in _HARD:
        if re.search(rx, cmd):
            return BLOQUEADO, motivo
    if _BAD_CHARS.search(cmd):
        return CONFIRMAR, "operadores de shell"
    # tuberías permitidas: solo | head, | tail, | grep simples (cada tramo seguro)
    partes = [p.strip() for p in cmd.split("|")]
    try:
        argvs = [shlex.split(p) for p in partes]
    except ValueError:
        return CONFIRMAR, "comillas sin cerrar"
    if any("$" in p for p in partes):
        return CONFIRMAR, "expansión de variables"
    if not _safe_single(argvs[0]):
        return CONFIRMAR, "no es de solo lectura"
    for av in argvs[1:]:
        if not av or av[0] not in {"head", "tail", "grep"} or any(x.startswith("-f") for x in av[1:]) or \
                (av[0] == "grep" and any(not x.startswith("-") and os.path.exists(os.path.expanduser(x)) for x in av[1:])):
            return CONFIRMAR, "tubería no permitida"
    return DIRECTO, ""


def ejecutar(cmd: str, timeout: float = 12) -> dict:
    """Ejecuta ya (sin comprobar nada más que lo duro): para el camino confirmado y el directo."""
    nivel, motivo = clasificar(cmd)
    if nivel == BLOQUEADO:
        return {"ok": False, "error": f"comando bloqueado ({motivo})", "resumen": "Comando bloqueado"}
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "el comando tardó más de 12 segundos y se canceló"}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": str(e)}
    out, err = (r.stdout or "").strip(), (r.stderr or "").strip()
    if r.returncode != 0:
        return {"ok": False, "codigo": r.returncode, "error": (err or out or "comando falló")[:300],
                "resumen": "Error en comando"}
    return {"ok": True, "codigo": 0, "salida": out[:1200],
            "resumen": out.splitlines()[0][:60] if out else "Comando ejecutado",
            "nota": "Resume el resultado a Alberto de forma breve y clara en una frase para leerse en voz alta."}
