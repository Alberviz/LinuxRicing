"""Explica los correos en lenguaje natural: una sola llamada al LLM local con todos, JSON
[{id, frase, importante}], cacheado por id en SQLite. Sin LLM (o si tarda > ~8 s) cae a un formato
limpio (remitente + asunto sin números largos ni dominios)."""
from __future__ import annotations

import json
import re
import sqlite3
import threading
import urllib.request

from .config import CFG, DATA_DIR, log

_DB = DATA_DIR / "correos.db"
_lock = threading.Lock()
TIMEOUT = 8.0


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(_DB)
    c.execute("CREATE TABLE IF NOT EXISTS frases (id TEXT PRIMARY KEY, frase TEXT, importante INTEGER)")
    return c


def nombre(de: str) -> str:
    """«"HONORSTORE.PL" <x@y>» -> «Honorstore»; sin dominio ni extensiones."""
    m = re.match(r'\s*"?([^"<]+?)"?\s*<', de)
    n = m.group(1).strip() if m else de.split("@")[0]
    n = re.sub(r"\.(com|es|pl|org|net|eu)\b", "", n, flags=re.I).strip("<> ")
    n = n.title() if n.isupper() else n
    if len(n) > 8 and n.lower().endswith(("store", "shop")):
        n = n[:-5]
    return n or "alguien"


def limpiar(t: str) -> str:
    """Quita números largos, códigos, URLs y dominios."""
    t = re.sub(r"https?://\S+|\b[\w.-]+\.(com|es|pl|org|net|eu)\b", "", t, flags=re.I)
    t = re.sub(r"\b[A-Z0-9]{2,}[-_][A-Z0-9-_]+\b", "", t)  # códigos tipo HS-9911
    t = re.sub(r"\b\w*\d{4,}\w*\b|#\s*\d+|\bnr\.?\s*\d+", "", t, flags=re.I)
    return re.sub(r"\s+", " ", t).strip(" :-·,.")


def frase_basica(m: dict) -> str:
    asunto = limpiar(m.get("asunto", "")) or "sin asunto"
    return f"un correo de {nombre(m.get('de', ''))}: {asunto}"


_PROMPT = """Resume cada correo para leerlo en voz alta a Alberto. Devuelve SOLO un objeto JSON:
{{"correos": [{{"id": "<id>", "frase": "<frase>", "importante": <true|false>}}]}}
La frase: una locución en español de 6 a 14 palabras que empieza con artículo, p. ej. «un pedido de Honor de un cargador»,
«una alerta de seguridad de Google por un inicio de sesión nuevo», «un correo de Marta preguntando por la reunión».
Reglas: sin números de pedido, códigos, URLs ni dominios; traduce lo que esté en polaco o inglés; el remitente con su
nombre humano o de marca («Honor», «la universidad», «Marta»); di qué es y de qué trata. importante=true si es de una
persona, la universidad, un pago, un plazo o seguridad de la cuenta; false para pedidos, avisos automáticos y boletines.
Correos:
{lista}"""


def _llm(correos: list[dict]) -> dict[str, dict]:
    lista = "\n".join(
        f"- id={m['id']} | de: {nombre(m['de'])} | asunto: {limpiar(m['asunto'])[:90]} | texto: {limpiar(m.get('cuerpo', ''))[:350]}"
        for m in correos)
    body = {"model": CFG["llm"]["model"], "stream": False, "format": "json",
            "messages": [{"role": "user", "content": _PROMPT.format(lista=lista)}],
            "options": {"temperature": 0.2, "num_predict": 45 * len(correos) + 40,
                        "num_ctx": CFG["llm"].get("num_ctx", 4096)}}
    req = urllib.request.Request(CFG["llm"]["url"], data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        txt = json.loads(r.read())["message"]["content"]
    data = json.loads(txt)
    items = data.get("correos") if isinstance(data, dict) else data
    out = {}
    for it in items or []:
        if isinstance(it, dict) and it.get("id") and str(it.get("frase", "")).strip():
            out[str(it["id"])] = {"frase": limpiar(str(it["frase"])).strip(), "importante": bool(it.get("importante"))}
    return out


def resumir(correos: list[dict]) -> dict[str, dict]:
    """correos: [{id, de, asunto, cuerpo?}] -> {id: {frase, importante}} (cacheado; con respaldo limpio)."""
    res: dict[str, dict] = {}
    with _lock, _conn() as c:
        for m in correos:
            row = c.execute("SELECT frase, importante FROM frases WHERE id=?", (m["id"],)).fetchone()
            if row:
                res[m["id"]] = {"frase": row[0], "importante": bool(row[1])}
        faltan = [m for m in correos if m["id"] not in res]
        if faltan:
            try:
                nuevos = _llm(faltan)
                for m in faltan:
                    if m["id"] in nuevos:
                        res[m["id"]] = nuevos[m["id"]]
                        c.execute("INSERT OR REPLACE INTO frases VALUES (?,?,?)",
                                  (m["id"], nuevos[m["id"]]["frase"], int(nuevos[m["id"]]["importante"])))
            except Exception as e:  # noqa: BLE001
                log(f"resumen de correos: LLM no disponible ({type(e).__name__}); formato básico")
        for m in faltan:
            res.setdefault(m["id"], {"frase": frase_basica(m), "importante": False, "basica": True})
    return res


def decir(items: list[dict]) -> str:
    """items: [{frase, importante}] -> frase hablada: importantes primero, máx. 4 y «y N más»."""
    its = sorted(items, key=lambda i: not i.get("importante"))
    n = len(its)
    if n == 0:
        return "No tienes correos nuevos importantes."
    vistas: dict[str, int] = {}
    for i in its:
        vistas[i["frase"]] = vistas.get(i["frase"], 0) + 1
    its = list({i["frase"]: i for i in its}.values())
    top = [i["frase"] + (" (dos)" if vistas[i["frase"]] == 2 else f" ({vistas[i['frase']]})" if vistas[i["frase"]] > 2 else "")
           for i in its[:4]]
    n = len(its)
    lista = top[0] if len(top) == 1 else ", ".join(top[:-1]) + " y " + top[-1] if n <= 4 else ", ".join(top) + f" y {n - 4} más"
    return f"Tienes {n} correo{'s' if n != 1 else ''}: {lista}."
