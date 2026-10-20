#!/usr/bin/env python3
"""Examen de modelos locales para Laura. Ver README.md.

No ejecuta herramientas: solo mira que tool_calls pide el modelo en la primera ronda.
"""
import argparse
import json
import statistics
import sys
import time
import tomllib
import unicodedata
from datetime import datetime
from pathlib import Path

import requests

HERE = Path(__file__).resolve().parent
ASSISTANT = HERE.parent
sys.path.insert(0, str(ASSISTANT))
from tools import TOOLS  # noqa: E402

CFG = tomllib.loads((ASSISTANT / "config.toml").read_text())["llm"]


def norm(s):
    s = unicodedata.normalize("NFD", str(s).lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn").strip()


def args_ok(want, got):
    for k, v in (want or {}).items():
        g = (got or {}).get(k)
        if g is None:
            return False
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            try:
                if float(g) != float(v):
                    return False
            except (TypeError, ValueError):
                return False
        elif norm(v) not in norm(g):
            return False
    return True


def installed():
    try:
        r = requests.get(CFG["url"].replace("/api/chat", "/api/tags"), timeout=10)
        return {m["name"] for m in r.json().get("models", [])}
    except Exception:
        return set()


def chat(model, texto, think=False):
    body = {
        "model": model, "stream": True, "tools": TOOLS,
        "messages": [{"role": "system", "content": CFG["system_prompt"]},
                     {"role": "user", "content": texto}],
        "options": {"num_ctx": CFG.get("num_ctx", 4096)},
        "keep_alive": "10m",
    }
    if think is not None:
        body["think"] = think
    t0 = time.perf_counter()
    first = None
    content, calls = "", []
    with requests.post(CFG["url"], json=body, stream=True, timeout=CFG.get("timeout", 45) * 3) as r:
        if r.status_code != 200:
            raise RuntimeError(r.text[:200])
        for line in r.iter_lines():
            if not line:
                continue
            d = json.loads(line)
            m = d.get("message", {})
            if first is None and (m.get("content") or m.get("tool_calls")):
                first = time.perf_counter() - t0
            content += m.get("content") or ""
            calls += m.get("tool_calls") or []
    total = time.perf_counter() - t0
    return content, calls, (first if first is not None else total), total


def ask(model, texto, state):
    if state["think"] is False:
        try:
            return chat(model, texto, False)
        except RuntimeError:
            state["think"] = None  # el modelo no soporta think: reintenta sin el campo
    return chat(model, texto, state["think"])


def evaluar(model, frases, repeat):
    state = {"think": False}
    try:
        ask(model, "hola", state)  # calentamiento (carga el modelo en VRAM)
        ask(model, "hola", state)
    except Exception as e:
        print(f"  calentamiento fallido: {e}")
        return None
    res = []
    for i, f in enumerate(frases, 1):
        for _ in range(repeat):
            try:
                content, calls, ttft, total = ask(model, f["texto"], state)
            except Exception as e:
                content, calls, ttft, total = f"[ERROR {e}]", [], 0, 0
            got = [c["function"]["name"] for c in calls]
            gargs = [c["function"].get("arguments") or {} for c in calls]
            want = f["espera"]
            ok_t = got == want
            ok_a = None
            if want and ok_t and f.get("args"):
                ok_a = all(args_ok(w, g) for w, g in zip(f["args"], gargs))
            res.append(dict(f=f, got=got, gargs=gargs, ok_t=ok_t, ok_a=ok_a,
                            fp=(not want and bool(got)), content=content,
                            ttft=ttft, total=total))
        print(f"  [{i}/{len(frases)}] {'ok ' if res[-1]['ok_t'] else 'MAL'} {f['texto'][:60]}")
    return res


def resumen(model, res):
    n = len(res)
    pos = [r for r in res if r["f"]["espera"]]
    neg = [r for r in res if not r["f"]["espera"]]
    con_args = [r for r in res if r["ok_a"] is not None]
    habladas = [len(r["content"]) for r in neg if not r["got"]]
    ttft = sorted(r["ttft"] for r in res)
    tot = [r["total"] for r in res]
    return {
        "modelo": model, "n": n,
        "herr": sum(r["ok_t"] for r in res) / n * 100,
        "args": (sum(r["ok_a"] for r in con_args) / len(con_args) * 100) if con_args else float("nan"),
        "fp": sum(r["fp"] for r in neg),
        "nneg": len(neg),
        "ttft": statistics.median(ttft),
        "ttft95": ttft[min(n - 1, int(n * 0.95))],
        "total": statistics.median(tot),
        "chars": statistics.mean(habladas) if habladas else float("nan"),
        "largas": sum(1 for c in habladas if c > 200),
        "npos": len(pos),
    }


def tabla(rows):
    h = ["modelo", "herr%", "args%", "falsos+", "ttft med", "ttft p95", "total med", "chars resp", "resp>200"]
    out = [h]
    for s in rows:
        out.append([s["modelo"], f"{s['herr']:.0f}", f"{s['args']:.0f}", f"{s['fp']}/{s['nneg']}",
                    f"{s['ttft']:.2f}s", f"{s['ttft95']:.2f}s", f"{s['total']:.2f}s",
                    f"{s['chars']:.0f}", str(s["largas"])])
    w = [max(len(r[i]) for r in out) for i in range(len(h))]
    return "\n".join("| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |"
                     for r in out[:1] + [["-" * x for x in w]] + out[1:])


def informe(model, s, res, ruta):
    L = [f"# Examen Laura: {model}", "", f"Fecha: {datetime.now():%Y-%m-%d %H:%M}  |  frases: {s['n']}", "",
         tabla([s]), "", "## Fallos", ""]
    fallos = [r for r in res if not r["ok_t"] or r["ok_a"] is False]
    if not fallos:
        L.append("Ninguno.")
    for r in fallos:
        f = r["f"]
        L += [f"- **{f['texto']}**",
              f"  - esperado: `{f['espera']}` args `{f.get('args', '')}`",
              f"  - obtenido: `{r['got']}` args `{json.dumps(r['gargs'], ensure_ascii=False)}`"
              + (f" respuesta: «{r['content'][:120]}»" if r["content"] and not r["got"] else "")]
    ruta.write_text("\n".join(L) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", action="append", help="repetible")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--limit", type=int, default=0, help="solo las N primeras frases")
    ap.add_argument("--frases", default=str(HERE / "frases.toml"))
    a = ap.parse_args()
    models = a.model or [CFG["model"]]
    frases = tomllib.loads(Path(a.frases).read_text())["frase"]
    if a.limit:
        frases = frases[:a.limit]
    have = installed()
    rows = []
    for m in models:
        if have and m not in have and f"{m}:latest" not in have:
            print(f"AVISO: {m} no está descargado (ollama list); se salta.")
            continue
        print(f"== {m} ({len(frases)} frases x{a.repeat})")
        res = evaluar(m, frases, a.repeat)
        if not res:
            continue
        s = resumen(m, res)
        rows.append(s)
        (HERE / "results").mkdir(exist_ok=True)
        informe(m, s, res, HERE / "results" / f"{datetime.now():%Y-%m-%d}-{m.replace(':', '_').replace('/', '_')}.md")
    if rows:
        print("\n" + tabla(rows))


if __name__ == "__main__":
    main()
