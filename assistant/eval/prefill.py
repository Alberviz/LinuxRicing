#!/usr/bin/env python3
"""Medición del tiempo de prefill de Ollama para Laura.

Comprueba el efecto de la caché de prompt en tres casos:
1. Modelo frío: sin caché previa en VRAM.
2. Mismo minuto: mismo prefijo exacto (aprovecha la caché KV).
3. Minuto cambiado: el system prompt cambia de minuto (rompe la caché antes de Tarea 2).

Usa llm._ollama_body real con num_predict=1.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
ASSISTANT = HERE.parent
sys.path.insert(0, str(ASSISTANT))

from laura import llm  # noqa: E402
from laura.config import CFG  # noqa: E402
from laura.tools import sistema  # noqa: E402


def descargar_modelo(url: str, model: str) -> None:
    """Descarga el modelo de VRAM (keep_alive: 0) para simular arranque en frío."""
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps({"model": model, "keep_alive": 0}).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10):
            pass
        time.sleep(1.0)
    except Exception:
        pass


def preparar_cuerpo(session: llm.Session) -> dict:
    """Genera el cuerpo real de Ollama con num_predict=1."""
    body = json.loads(llm._ollama_body(session, False).decode())
    body.setdefault("options", {})["num_predict"] = 1
    return body


def medir(body: dict, url: str) -> dict:
    t0 = time.perf_counter()
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=CFG["llm"].get("timeout", 45) * 2) as resp:
        res = json.loads(resp.read())
    wall = time.perf_counter() - t0
    count = res.get("prompt_eval_count", 0)
    dur_ns = res.get("prompt_eval_duration", 0)
    dur_s = dur_ns / 1e9 if dur_ns else 0.0
    return {
        "count": count,
        "prefill_s": dur_s,
        "wall_s": wall,
        "raw": res,
    }


def fecha_falsa(delta_minutos: int = 0) -> str:
    n = datetime.now() + timedelta(minutes=delta_minutos)
    return (f"{sistema._DIAS[n.weekday()]} {n.day} de "
            f"{sistema._MESES[n.month - 1]} de {n.year}, "
            f"{n.hour}:{n.minute:02d}")


def main() -> None:
    url = CFG["llm"]["url"]
    model = CFG["llm"]["model"]

    print(f"Midiendo prefill en {url} con modelo {model}...")

    # Caso 1: Modelo frío
    print("\n1. Caso frío (descargando modelo previo si estaba en VRAM)...")
    descargar_modelo(url, model)

    sistema.fecha_hora_texto = lambda: fecha_falsa(0)
    session1 = llm.Session()
    session1.refresh_system("hola")
    session1.add("user", "hola")
    body1 = preparar_cuerpo(session1)

    r1 = medir(body1, url)
    print(f"   Prefill: {r1['count']} tok en {r1['prefill_s']:.2f} s  (reloj total: {r1['wall_s']:.2f} s)")

    # Caso 2: Mismo minuto (mismo prefijo)
    print("\n2. Caso mismo minuto (prefijo idéntico)...")
    r2 = medir(body1, url)
    print(f"   Prefill: {r2['count']} tok en {r2['prefill_s']:.2f} s  (reloj total: {r2['wall_s']:.2f} s)")

    # Caso 3: Minuto cambiado
    print("\n3. Caso minuto cambiado (+1 minuto)...")
    sistema.fecha_hora_texto = lambda: fecha_falsa(1)
    session3 = llm.Session()
    session3.refresh_system("hola")
    session3.add("user", "hola")
    body3 = preparar_cuerpo(session3)

    r3 = medir(body3, url)
    print(f"   Prefill: {r3['count']} tok en {r3['prefill_s']:.2f} s  (reloj total: {r3['wall_s']:.2f} s)")

    print("\nResumen:")
    print(f"  Frío:            {r1['prefill_s']:.2f} s")
    print(f"  Mismo minuto:    {r2['prefill_s']:.2f} s")
    print(f"  Minuto cambiado: {r3['prefill_s']:.2f} s")


if __name__ == "__main__":
    main()
