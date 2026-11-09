"""Motor de archivos de Laura: planifica (sin tocar el disco), ejecuta con papelera y deshace.

El LLM nunca ejecuta: las tools (`tools/archivos.py`) solo crean un `Plan`. Un plan que
requiere confirmación queda `pendiente` hasta que `resolver()` lo confirma o cancela
(voz o panel holográfico) o caduca. Todo lo que se borra va a la papelera freedesktop
(`~/.local/share/Trash`, compatible con los gestores de archivos) y cada acción queda en
un diario para poder deshacerla incluso tras reiniciar.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
import unicodedata
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from urllib.parse import quote

MAX_OPS_DEFECTO = 50
TTL_DEFECTO = 60.0
UMBRAL_LOTE = 5          # mover/renombrar más de 5 elementos pide confirmación


class Rechazo(Exception):
    """Algo que no se puede hacer; el mensaje es apto para decirlo en voz alta."""


def ahora() -> float:
    return time.time()


# ------------------------------------------------------------------------- entorno

def _xdg(nombre: str, defecto: str) -> Path:
    try:
        r = subprocess.run(["xdg-user-dir", nombre], capture_output=True, text=True, timeout=3)
        p = Path(r.stdout.strip())
        if r.returncode == 0 and r.stdout.strip() and p != Path.home():
            return p
    except (OSError, subprocess.SubprocessError):
        pass
    return Path.home() / defecto


@dataclass
class Entorno:
    raices: list[Path]
    diario: Path
    papelera: Path
    max_ops: int = MAX_OPS_DEFECTO
    ttl: float = TTL_DEFECTO


def entorno_por_defecto() -> Entorno:
    try:
        from .config import CFG
        cfg = CFG.get("archivos", {})
    except Exception:  # noqa: BLE001 — sin config (tests sueltos) se usan los valores por defecto
        cfg = {}
    if cfg.get("raices"):
        raices = [Path(os.path.expanduser(r)) for r in cfg["raices"]]
    else:
        raices = [_xdg("DOWNLOAD", "Descargas"), _xdg("DOCUMENTS", "Documentos"),
                  _xdg("DESKTOP", "Escritorio"), _xdg("PICTURES", "Imágenes"),
                  _xdg("VIDEOS", "Vídeos"), _xdg("MUSIC", "Música"), Path.home() / "proyectos"]
    estado = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "laura"
    datos = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "Trash"
    return Entorno(raices, estado / "archivos.jsonl", datos,
                   int(cfg.get("max_ops", MAX_OPS_DEFECTO)), float(cfg.get("ttl", TTL_DEFECTO)))


ENTORNO = entorno_por_defecto()


# ---------------------------------------------------------------------- validación

def _plano(s: str) -> str:
    """Minúsculas y sin tildes, para comparar nombres de carpeta dichos de viva voz."""
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c)).strip()


def ruta_permitida(p, permitir_raiz: bool = False) -> Path:
    """Ruta real (symlinks resueltos) si se puede tocar; si no, lanza `Rechazo`.

    Debe estar dentro de una raíz permitida. Las raíces mismas solo valen como destino
    (`permitir_raiz`). Se rechazan componentes ocultos, `.git` y cualquier `vault`."""
    real = Path(os.path.realpath(os.path.expanduser(str(p))))
    for raiz in ENTORNO.raices:
        r = Path(os.path.realpath(raiz))
        if real == r:
            if permitir_raiz:
                return real
            raise Rechazo(f"No toco la carpeta {r.name} entera.")
        if real.is_relative_to(r):
            partes = real.relative_to(r).parts
            if any(x.startswith(".") for x in partes):
                raise Rechazo("No toco archivos ocultos.")
            if any(x.lower() == "vault" for x in partes):
                raise Rechazo("No toco el vault.")
            return real
    raise Rechazo("No puedo tocar eso: está fuera de tus carpetas.")


def _nombre_valido(nombre: str) -> str:
    n = (nombre or "").strip()
    if not n or "/" in n or n in (".", "..") or n.startswith(".") or len(n) > 200:
        raise Rechazo("Ese nombre no vale.")
    return n


def _tam(p: Path) -> int:
    try:
        if p.is_dir() and not p.is_symlink():
            total = 0
            for d, _, fs in os.walk(p):
                for f in fs:
                    try:
                        total += os.path.getsize(os.path.join(d, f))
                    except OSError:
                        pass
            return total
        return p.lstat().st_size
    except OSError:
        return 0


def _tam_humano(b: int) -> str:
    if b >= 1 << 30:
        return f"{b / (1 << 30):.1f} gigas".replace(".", ",")
    if b >= 1 << 20:
        return f"{round(b / (1 << 20))} megas"
    if b >= 1 << 10:
        return f"{round(b / (1 << 10))} kilos"
    return "unos pocos bytes"


_PALABRAS = {1: "un", 2: "dos", 3: "tres", 4: "cuatro", 5: "cinco", 6: "seis", 7: "siete",
             8: "ocho", 9: "nueve", 10: "diez", 11: "once", 12: "doce"}


# ------------------------------------------------------------------------ el plan

@dataclass
class Op:
    origen: str
    destino: str | None = None
    tamano: int = 0
    es_dir: bool = False
    real_destino: str | None = None   # dónde quedó de verdad (tras evitar colisiones)
    trash_files: str | None = None
    trash_info: str | None = None


@dataclass
class Plan:
    accion: str                       # borrar | mover | renombrar | crear_carpeta
    ops: list[Op]
    requiere_confirmacion: bool
    carpeta: str | None = None        # carpeta de contexto (destino o carpeta de la lista)
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:8])
    creado: float = field(default_factory=lambda: ahora())
    estado: str = "pendiente"         # pendiente | ejecutado | cancelado | caducado | fallido
    mensaje: str = ""                 # lo que Laura debe decir al resolverse
    evento: threading.Event = field(default_factory=threading.Event, repr=False, compare=False)

    @property
    def total_bytes(self) -> int:
        return sum(o.tamano for o in self.ops)

    @property
    def expira(self) -> float:
        return self.creado + ENTORNO.ttl

    def _cuantos(self) -> str:
        n = len(self.ops)
        dirs = sum(o.es_dir for o in self.ops)
        cosa = ("carpeta", "carpetas") if dirs == n else ("archivo", "archivos") if dirs == 0 else ("elemento", "elementos")
        return f"{_PALABRAS.get(n, str(n))} {cosa[0] if n == 1 else cosa[1]}"

    def titulo(self) -> str:
        return {"borrar": f"Borrar {self._cuantos()}", "mover": f"Mover {self._cuantos()}",
                "renombrar": "Renombrar", "crear_carpeta": "Crear carpeta"}[self.accion]

    def pregunta(self) -> str:
        if self.accion == "borrar":
            return f"Voy a mandar a la papelera {self._cuantos()}, {_tam_humano(self.total_bytes)}. ¿Confirmas?"
        if self.accion == "mover":
            return f"Voy a mover {self._cuantos()} a {Path(self.ops[0].destino).parent.name}. ¿Confirmas?"
        if self.accion == "renombrar":
            o = self.ops[0]
            return f"Voy a renombrar {Path(o.origen).name} a {Path(o.destino).name}. ¿Confirmas?"
        return f"Voy a crear la carpeta {Path(self.ops[0].destino).name}. ¿Confirmas?"

    def a_payload(self) -> dict:
        """Lo que pinta el panel holográfico de confirmación."""
        return {
            "plan": self.id, "accion": self.accion, "titulo": self.titulo(),
            "items": [{"nombre": Path(o.origen).name, "tamano": o.tamano, "es_dir": o.es_dir,
                       "nuevo": Path(o.destino).name if self.accion == "renombrar" and o.destino else None}
                      for o in self.ops[:6]],
            "mas": max(0, len(self.ops) - 6),
            "total_bytes": self.total_bytes,
            "destino": Path(self.ops[0].destino).parent.name if self.accion == "mover" else None,
            "segundos": int(ENTORNO.ttl), "expira": self.expira,
        }


# ------------------------------------------------------------------ planificación
# Ninguna de estas funciones toca el disco.

def _validar_n(n: int) -> None:
    if n == 0:
        raise Rechazo("No hay nada que hacer.")
    if n > ENTORNO.max_ops:
        raise Rechazo("Son demasiados de golpe; hazlo en tandas.")


def _ops_existentes(rutas: list[str]) -> list[Op]:
    """Ops de origen para rutas que existen y se pueden tocar. La ruta de la op es la
    absoluta SIN resolver (un enlace dentro de las carpetas se trata como el enlace)."""
    vistos: set[str] = set()
    ops: list[Op] = []
    for r in rutas:
        real = ruta_permitida(r)
        absoluta = Path(os.path.abspath(os.path.expanduser(str(r))))
        if not absoluta.exists() and not absoluta.is_symlink():
            raise Rechazo(f"{absoluta.name} ya no existe.")
        if str(absoluta) in vistos:
            continue
        vistos.add(str(absoluta))
        ops.append(Op(origen=str(absoluta), tamano=_tam(real), es_dir=real.is_dir()))
    return ops


def planificar_borrar(rutas: list[str], carpeta: str | None = None) -> Plan:
    ops = _ops_existentes(rutas)
    _validar_n(len(ops))
    return Plan("borrar", ops, True, carpeta)


def planificar_mover(rutas: list[str], destino_dir) -> Plan:
    dest = ruta_permitida(destino_dir, permitir_raiz=True)
    if not dest.is_dir():
        raise Rechazo(f"{dest.name} no es una carpeta.")
    ops = _ops_existentes(rutas)
    _validar_n(len(ops))
    for op in ops:
        o = Path(op.origen)
        real_o = os.path.realpath(o)
        if str(dest) == real_o or str(dest).startswith(real_o + os.sep):
            raise Rechazo("No puedo meter una carpeta dentro de sí misma.")
        if Path(os.path.realpath(o.parent)) == dest:
            raise Rechazo(f"{o.name} ya está en {dest.name}.")
        op.destino = str(dest / o.name)
    return Plan("mover", ops, len(ops) > UMBRAL_LOTE, str(dest))


def planificar_renombrar(ruta: str, nombre: str) -> Plan:
    nuevo = _nombre_valido(nombre)
    ops = _ops_existentes([ruta])
    o = Path(ops[0].origen)
    if nuevo == o.name:
        raise Rechazo("Ya se llama así.")
    ops[0].destino = str(o.with_name(nuevo))
    ruta_permitida(ops[0].destino)
    return Plan("renombrar", ops, False, str(o.parent))


def planificar_crear_carpeta(nombre: str, en) -> Plan:
    nuevo = _nombre_valido(nombre)
    base = ruta_permitida(en, permitir_raiz=True)
    if not base.is_dir():
        raise Rechazo(f"{base.name} no es una carpeta.")
    destino = base / nuevo
    ruta_permitida(destino)
    if destino.exists():
        raise Rechazo(f"Ya existe {nuevo}.")
    return Plan("crear_carpeta", [Op(origen=str(destino), destino=str(destino), es_dir=True)], False, str(base))


def _buscar_carpeta(buscado: str, bases: list[Path], profundidad: int = 2) -> Path | None:
    visitadas = 0
    nivel = [b for b in bases if b.is_dir()]
    for _ in range(profundidad):
        siguiente: list[Path] = []
        for base in nivel:
            try:
                hijos = sorted(base.iterdir())
            except OSError:
                continue
            for h in hijos:
                if h.name.startswith(".") or not h.is_dir():
                    continue
                visitadas += 1
                if _plano(h.name) == buscado:
                    return h
                siguiente.append(h)
            if visitadas > 800:
                return None
        nivel = siguiente
    return None


def resolver_destino(nombre: str, carpeta_actual: str | None = None) -> Path:
    """«Documentos», «Universidad» o una ruta -> carpeta real. Busca primero en la carpeta de
    la lista que se ve y luego en las raíces (dos niveles)."""
    n = os.path.expanduser((nombre or "").strip())
    if not n:
        raise Rechazo("¿A qué carpeta?")
    if os.path.isabs(n):
        return Path(n)
    buscado = _plano(n)
    for r in ENTORNO.raices:
        if _plano(r.name) == buscado:
            return r
    bases = ([Path(carpeta_actual)] if carpeta_actual else []) + list(ENTORNO.raices)
    hallada = _buscar_carpeta(buscado, bases)
    if hallada is None:
        raise Rechazo(f"No encuentro la carpeta {nombre}.")
    return hallada


# -------------------------------------------------------------------- papelera

def _libre(directorio: Path, nombre: str, es_dir: bool = False, extra=None) -> Path:
    """`directorio/nombre`, o `nombre (2).ext`, `(3)`… si ya está ocupado. Nunca sobrescribe."""
    def ocupado(c: Path) -> bool:
        return c.exists() or c.is_symlink() or bool(extra and extra(c))

    cand = directorio / nombre
    if not ocupado(cand):
        return cand
    stem, suf = (nombre, "") if es_dir else (Path(nombre).stem, Path(nombre).suffix)
    i = 2
    while True:
        cand = directorio / f"{stem} ({i}){suf}"
        if not ocupado(cand):
            return cand
        i += 1


def _a_papelera(origen: Path, es_dir: bool) -> tuple[Path, Path]:
    base = ENTORNO.papelera
    files, info = base / "files", base / "info"
    files.mkdir(parents=True, exist_ok=True)
    info.mkdir(parents=True, exist_ok=True)
    destino = _libre(files, origen.name, es_dir, extra=lambda c: (info / (c.name + ".trashinfo")).exists())
    ficha = info / (destino.name + ".trashinfo")
    ficha.write_text("[Trash Info]\nPath=%s\nDeletionDate=%s\n"
                     % (quote(str(origen), safe="/"), datetime.now().strftime("%Y-%m-%dT%H:%M:%S")))
    try:
        shutil.move(str(origen), str(destino))
    except Exception:
        ficha.unlink(missing_ok=True)
        raise
    return destino, ficha


# ------------------------------------------------------------------- ejecución

def _hacer(accion: str, op: Op) -> None:
    o = Path(op.origen)
    if accion == "crear_carpeta":
        d = Path(op.destino)
        d.mkdir()
        op.real_destino = str(d)
        return
    if not o.exists() and not o.is_symlink():
        raise Rechazo(f"{o.name} ya no existe.")
    if accion == "borrar":
        f, i = _a_papelera(o, op.es_dir)
        op.trash_files, op.trash_info = str(f), str(i)
    else:  # mover | renombrar
        d = _libre(Path(op.destino).parent, Path(op.destino).name, op.es_dir)
        shutil.move(str(o), str(d))
        op.real_destino = str(d)


def ejecutar(plan: Plan) -> dict:
    """Ejecuta el plan (sin pedir nada: eso ya lo hizo quien llama). Anota el diario."""
    hechas: list[Op] = []
    omitidas: list[str] = []
    errores: list[str] = []
    for op in plan.ops:
        try:
            _hacer(plan.accion, op)
            hechas.append(op)
        except Rechazo as e:
            omitidas.append(str(e))
        except OSError as e:
            errores.append(f"{Path(op.origen).name}: {e.strerror or e}")
    if not hechas:
        plan.estado = "fallido"
        motivo = (omitidas + errores or ["no se pudo"])[0]
        return {"ok": False, "error": f"No he podido: {motivo}"}
    _anotar(plan, hechas)
    plan.estado = "ejecutado"
    if plan.accion == "borrar":
        decir = f"Hecho: {Plan(plan.accion, hechas, True)._cuantos()} a la papelera."
    elif plan.accion == "mover":
        decir = f"Hecho: {Plan(plan.accion, hechas, True)._cuantos()} movidos a {Path(hechas[0].real_destino).parent.name}."
    elif plan.accion == "renombrar":
        decir = f"Hecho: ahora se llama {Path(hechas[0].real_destino).name}."
    else:
        decir = f"Hecho: carpeta {Path(hechas[0].real_destino).name} creada."
    if omitidas:
        decir += f" {len(omitidas)} ya no existían."
    if errores:
        decir += f" {len(errores)} han fallado."
    if plan.accion != "crear_carpeta":
        decir += " Dime «deshaz» si te arrepientes."
    return {"ok": True, "decir": decir, "hechas": len(hechas), "omitidas": omitidas, "errores": errores}


# ---------------------------------------------------------------------- diario

def _anotar(plan: Plan, hechas: list[Op]) -> None:
    ENTORNO.diario.parent.mkdir(parents=True, exist_ok=True)
    linea = {"id": plan.id, "ts": ahora(), "accion": plan.accion, "deshecha": False,
             "ops": [asdict(o) for o in hechas]}
    with ENTORNO.diario.open("a", encoding="utf-8") as f:
        f.write(json.dumps(linea, ensure_ascii=False) + "\n")


def _leer_diario() -> list[dict]:
    if not ENTORNO.diario.exists():
        return []
    lineas = []
    for t in ENTORNO.diario.read_text(encoding="utf-8").splitlines():
        try:
            lineas.append(json.loads(t))
        except ValueError:
            continue
    return lineas


def _escribir_diario(lineas: list[dict]) -> None:
    tmp = ENTORNO.diario.with_suffix(".tmp")
    tmp.write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in lineas), encoding="utf-8")
    os.replace(tmp, ENTORNO.diario)


def _revertir(accion: str, op: Op) -> None:
    origen = Path(op.origen)
    if accion == "crear_carpeta":
        Path(op.real_destino or op.destino).rmdir()      # OSError si ya no está vacía
        return
    if accion == "borrar":
        fuente = Path(op.trash_files or "")
        if not fuente.exists():
            raise Rechazo(f"{origen.name} ya no está en la papelera.")
    else:
        fuente = Path(op.real_destino or op.destino or "")
        if not fuente.exists():
            raise Rechazo(f"{fuente.name} ya no está donde lo dejé.")
    origen.parent.mkdir(parents=True, exist_ok=True)
    destino = _libre(origen.parent, origen.name, op.es_dir)
    shutil.move(str(fuente), str(destino))
    if accion == "borrar" and op.trash_info:
        Path(op.trash_info).unlink(missing_ok=True)


def deshacer() -> dict:
    """Revierte la última acción completa que no esté ya deshecha."""
    lineas = _leer_diario()
    idx = next((i for i in range(len(lineas) - 1, -1, -1) if not lineas[i].get("deshecha")), None)
    if idx is None:
        return {"ok": False, "error": "No tengo nada que deshacer."}
    acc = lineas[idx]
    hechas, avisos = 0, []
    for d in reversed(acc["ops"]):
        try:
            _revertir(acc["accion"], Op(**d))
            hechas += 1
        except (OSError, Rechazo) as e:
            avisos.append(str(e.strerror if isinstance(e, OSError) and e.strerror else e))
    if hechas == 0:
        return {"ok": False, "error": "No he podido deshacerlo: " + (avisos[0] if avisos else "no queda nada")}
    lineas[idx]["deshecha"] = True
    _escribir_diario(lineas)
    verbo = {"borrar": "Recuperado de la papelera", "mover": "Devuelto a su sitio",
             "renombrar": "Devuelto a su nombre", "crear_carpeta": "Carpeta eliminada"}[acc["accion"]]
    decir = f"Hecho. {verbo}."
    if avisos:
        decir += f" {len(avisos)} no se han podido."
    carpeta = str(Path(acc["ops"][0]["origen"]).parent)
    return {"ok": True, "decir": decir, "n": hechas, "accion": acc["accion"], "carpeta": carpeta}


# ------------------------------------------------- planes pendientes (confirmación)

_PLANES: dict[str, Plan] = {}
_LOCK = threading.RLock()


def registrar(plan: Plan) -> Plan:
    """Deja el plan pendiente. Solo hay uno a la vez: el anterior se cancela."""
    with _LOCK:
        for p in _PLANES.values():
            if p.estado == "pendiente":
                p.estado = "cancelado"
                p.mensaje = "Sustituido por otra petición."
                p.evento.set()
        for pid in [k for k, p in _PLANES.items() if p.estado != "pendiente" and ahora() - p.creado > 600]:
            del _PLANES[pid]
        _PLANES[plan.id] = plan
        return plan


def _caducar_si_toca(plan: Plan) -> None:
    if plan.estado == "pendiente" and ahora() > plan.expira:
        plan.estado = "caducado"
        plan.mensaje = "Se me pasó el tiempo; vuelve a pedírmelo."
        plan.evento.set()


def plan_por_id(plan_id: str) -> Plan | None:
    with _LOCK:
        p = _PLANES.get(plan_id)
        if p is not None:
            _caducar_si_toca(p)
        return p


def pendiente() -> Plan | None:
    with _LOCK:
        res = None
        for p in _PLANES.values():
            _caducar_si_toca(p)
            if p.estado == "pendiente":
                res = p
        return res


def resolver(plan_id: str, si: bool) -> dict:
    """Confirma (ejecuta) o cancela un plan pendiente. Idempotente: solo actúa una vez."""
    with _LOCK:
        plan = _PLANES.get(plan_id)
        if plan is None:
            return {"ok": False, "error": "No hay nada pendiente."}
        _caducar_si_toca(plan)
        if plan.estado != "pendiente":
            return {"ok": False, "estado": plan.estado, "plan": plan,
                    "error": plan.mensaje or f"Eso ya está {plan.estado}."}
        if si:
            res = ejecutar(plan)
        else:
            plan.estado = "cancelado"
            res = {"ok": True, "decir": "Vale, no hago nada."}
        plan.mensaje = res.get("decir") or res.get("error") or ""
        plan.evento.set()
        return {**res, "estado": plan.estado, "plan": plan}
