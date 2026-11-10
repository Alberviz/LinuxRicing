"""Registro de interacciones de Laura en JSONL para dataset y análisis."""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from .config import DATA_DIR, log


def apuntar(**campos) -> None:
    """Escribe una línea JSONL en DATA_DIR/interacciones.jsonl. Nunca falla."""
    try:
        from . import config
        archivo = config.DATA_DIR / "interacciones.jsonl"
        archivo.parent.mkdir(parents=True, exist_ok=True)
        registro = {
            "fecha": datetime.now().isoformat(timespec="seconds"),
            **campos,
        }
        with open(archivo, "a", encoding="utf-8") as f:
            f.write(json.dumps(registro, ensure_ascii=False) + "\n")
    except Exception as e:  # noqa: BLE001
        log(f"registro de interacción: {e}")
