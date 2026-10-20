"""Memoria persistente de Laura: hechos sobre Alberto en SQLite."""
from __future__ import annotations

import re
import sqlite3
import threading
import unicodedata
from datetime import datetime

from .config import DATA_DIR

_DB = DATA_DIR / "memoria.db"
_lock = threading.Lock()
MAX_ALL = 20     # hasta este número de hechos se inyectan todos
MAX_RELEVANT = 8


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(_DB)
    c.execute("CREATE TABLE IF NOT EXISTS hechos ("
              "id INTEGER PRIMARY KEY AUTOINCREMENT, texto TEXT NOT NULL, creado TEXT NOT NULL)")
    return c


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(ch for ch in s if unicodedata.category(ch) != "Mn")


def _words(s: str) -> set[str]:
    return {w for w in re.findall(r"[a-z0-9ñ]+", _norm(s)) if len(w) >= 4}


def all_facts() -> list[tuple[int, str]]:
    with _lock, _conn() as c:
        return list(c.execute("SELECT id, texto FROM hechos ORDER BY id"))


def add(texto: str) -> bool:
    """Guarda un hecho. False si ya existía uno igual."""
    texto = texto.strip()
    if not texto:
        return False
    with _lock, _conn() as c:
        if c.execute("SELECT 1 FROM hechos WHERE lower(texto)=lower(?)", (texto,)).fetchone():
            return False
        c.execute("INSERT INTO hechos (texto, creado) VALUES (?, ?)",
                  (texto, datetime.now().isoformat(timespec="seconds")))
    return True


def forget(consulta: str) -> list[str]:
    """Borra los hechos que contienen la consulta (o comparten palabras con ella)."""
    q = _norm(consulta.strip())
    qw = _words(consulta)
    borrados = []
    with _lock, _conn() as c:
        for i, t in list(c.execute("SELECT id, texto FROM hechos")):
            if (q and q in _norm(t)) or (qw and qw <= _words(t)):
                c.execute("DELETE FROM hechos WHERE id=?", (i,))
                borrados.append(t)
    return borrados


def prompt_block(user_text: str = "") -> str:
    """Bloque corto para el system prompt: todos los hechos si son pocos; si no,
    los que comparten palabras con la frase de Alberto."""
    facts = [t for _, t in all_facts()]
    if not facts:
        return ""
    if len(facts) > MAX_ALL:
        uw = _words(user_text)
        scored = sorted(((len(uw & _words(t)), t) for t in facts), reverse=True)
        facts = [t for n, t in scored if n > 0][:MAX_RELEVANT]
        if not facts:
            return ""
    return ("Lo que sabes de Alberto (úsalo con naturalidad, sin recitarlo):\n"
            + "\n".join(f"- {t}" for t in facts))
