#!/usr/bin/env python
"""Valida data/train.jsonl: JSON correcto, herramientas y argumentos existentes, y que NINGUNA
frase held-out (ni casi idéntica) esté en el entrenamiento.   uso: check_dataset.py [dir]"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_dataset import TOOLS, jaccard, norm, words  # noqa: E402

d = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent / "data")
props = {t["function"]["name"]: t["function"]["parameters"].get("properties", {}) for t in TOOLS}
req = {t["function"]["name"]: t["function"]["parameters"].get("required", []) for t in TOOLS}
held = json.loads((d / "heldout.json").read_text())
hw = [words(h) for h in held]
hn = {norm(h) for h in held}
n = bad = leak = 0
tools_ok = True
for line in open(d / "train.jsonl"):
    r = json.loads(line)
    n += 1
    user = next(m["content"] for m in r["messages"] if m["role"] == "user")
    if norm(user) in hn or any(jaccard(words(user), h) >= 0.7 for h in hw):
        leak += 1
        print("FUGA:", user)
    for m in r["messages"]:
        for c in m.get("tool_calls") or []:
            f = c["function"]
            a = json.loads(f["arguments"])
            if f["name"] not in props or set(a) - set(props[f["name"]]) or set(req[f["name"]]) - set(a):
                bad += 1
                tools_ok = False
                print("TOOL/ARGS MAL:", f["name"], a)
print(f"{n} ejemplos | herramientas/argumentos inválidos: {bad} | frases held-out en train: {leak} | held-out: {len(held)}")
sys.exit(0 if tools_ok and not leak else 1)
