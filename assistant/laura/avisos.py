"""Temporizadores y recordatorios: almacén JSON (sobrevive a reinicios) y
planificador. Las tools solo escriben el JSON; el hilo del daemon lo relee
(por mtime) y dispara lo vencido, así funciona aunque la tool se ejecute en
otro proceso (p. ej. `laurad.py --text`)."""
from __future__ import annotations

import fcntl
import json
import threading
import time
import uuid
from datetime import datetime, timedelta

from .config import DATA_DIR, log

_FILE = DATA_DIR / "avisos.json"
_LOCK = DATA_DIR / "avisos.lock"


class _Locked:
    def __enter__(self):
        self._f = open(_LOCK, "w")
        fcntl.flock(self._f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        fcntl.flock(self._f, fcntl.LOCK_UN)
        self._f.close()


def _read() -> list[dict]:
    try:
        return json.loads(_FILE.read_text())
    except (OSError, ValueError):
        return []


def _write(items: list[dict]) -> None:
    tmp = _FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(items, ensure_ascii=False, indent=1))
    tmp.replace(_FILE)


def listar() -> list[dict]:
    with _Locked():
        return sorted(_read(), key=lambda a: a["due"])


def crear(tipo: str, texto: str, due: float) -> dict:
    a = {"id": uuid.uuid4().hex[:6], "tipo": tipo, "texto": texto, "due": due}
    with _Locked():
        items = _read()
        items.append(a)
        _write(items)
    return a


def cancelar(consulta: str) -> list[dict]:
    """Cancela por id exacto o por texto (subcadena). Devuelve los cancelados."""
    q = consulta.strip().lower()
    with _Locked():
        items = _read()
        quitar = [a for a in items if a["id"] == q or (q and q in a["texto"].lower())]
        if q in ("todos", "todo", "todas") or not q:
            quitar = list(items)
        if quitar:
            ids = {a["id"] for a in quitar}
            _write([a for a in items if a["id"] not in ids])
    return quitar


def pop_vencidos(now: float | None = None) -> list[dict]:
    now = time.time() if now is None else now
    with _Locked():
        items = _read()
        vencidos = [a for a in items if a["due"] <= now]
        if vencidos:
            _write([a for a in items if a["due"] > now])
    return vencidos


def parse_cuando(valor: str | float | int) -> float:
    """'HH:MM' -> próxima ocurrencia de esa hora; número -> minutos desde ahora.
    Devuelve el instante (epoch). Lanza ValueError si no se entiende."""
    s = str(valor).strip().lower().replace(",", ".")
    if ":" in s:
        hh, _, mm = s.partition(":")
        h, m = int(hh), int(mm or 0)
        if not (0 <= h < 24 and 0 <= m < 60):
            raise ValueError(f"hora no válida: {valor}")
        now = datetime.now()
        t = now.replace(hour=h, minute=m, second=0, microsecond=0)
        if t <= now:
            t += timedelta(days=1)
        return t.timestamp()
    minutos = float(s)
    if minutos < 0:
        raise ValueError("los minutos no pueden ser negativos")
    return time.time() + minutos * 60


class Scheduler:
    """Hilo que mira el JSON cada segundo y llama a `on_due(aviso)` por cada
    aviso vencido. Cualquier excepción del callback se registra y sigue."""

    def __init__(self, on_due) -> None:
        self._on_due = on_due
        self._stop = threading.Event()
        self._t = threading.Thread(target=self._loop, daemon=True)

    def start(self) -> None:
        self._t.start()

    def stop(self) -> None:
        self._stop.set()

    def _loop(self) -> None:
        while not self._stop.wait(1.0):
            try:
                for a in pop_vencidos():
                    log(f"aviso vencido: {a['tipo']} «{a['texto']}»")
                    try:
                        self._on_due(a)
                    except Exception as e:  # noqa: BLE001
                        log(f"error al avisar: {e}")
            except Exception as e:  # noqa: BLE001
                log(f"planificador: {e}")
