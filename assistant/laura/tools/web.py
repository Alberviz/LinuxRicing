"""Tools de Internet sin clave: el tiempo (open-meteo) y búsqueda web (DuckDuckGo)."""
from __future__ import annotations

import html
import json
import re
import urllib.parse
import urllib.request

from ..config import CFG, DATA_DIR
from . import tool

_UA = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
_LOC_CACHE = DATA_DIR / "ubicacion.json"

_WMO = {0: "despejado", 1: "casi despejado", 2: "parcialmente nublado", 3: "nublado",
        45: "niebla", 48: "niebla con escarcha", 51: "llovizna ligera", 53: "llovizna",
        55: "llovizna intensa", 56: "llovizna helada", 57: "llovizna helada intensa",
        61: "lluvia ligera", 63: "lluvia", 65: "lluvia fuerte", 66: "lluvia helada",
        67: "lluvia helada fuerte", 71: "nevada ligera", 73: "nevada", 75: "nevada fuerte",
        77: "granizo fino", 80: "chubascos ligeros", 81: "chubascos", 82: "chubascos fuertes",
        85: "chubascos de nieve", 86: "chubascos de nieve fuertes", 95: "tormenta",
        96: "tormenta con granizo", 99: "tormenta fuerte con granizo"}


def _get_json(url: str, timeout: float = 8) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": _UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def _mi_ubicacion() -> dict | None:
    """[ubicacion] de config.toml; si está vacía, geolocaliza por IP una vez y cachea."""
    u = CFG.get("ubicacion", {})
    try:
        if str(u.get("lat", "")).strip() and str(u.get("lon", "")).strip():
            return {"ciudad": u.get("ciudad") or "tu zona",
                    "lat": float(u["lat"]), "lon": float(u["lon"])}
    except ValueError:
        pass
    try:
        return json.loads(_LOC_CACHE.read_text())
    except (OSError, ValueError):
        pass
    try:
        d = _get_json("https://ipwho.is/")
        if not d.get("success", True):
            return None
        loc = {"ciudad": d.get("city") or "tu zona", "lat": d["latitude"], "lon": d["longitude"]}
        _LOC_CACHE.write_text(json.dumps(loc, ensure_ascii=False))
        return loc
    except Exception:  # noqa: BLE001
        return None


def _geocodificar(lugar: str) -> dict | None:
    q = urllib.parse.quote(lugar)
    d = _get_json(f"https://geocoding-api.open-meteo.com/v1/search?name={q}&count=1&language=es")
    r = (d.get("results") or [None])[0]
    if not r:
        return None
    return {"ciudad": r["name"], "lat": r["latitude"], "lon": r["longitude"]}


@tool("tiempo",
      "Dice el tiempo actual y la previsión de hoy. Úsala para «qué tiempo hace», «va a llover», «cuánto calor hace». Sin lugar usa la ubicación de Alberto.",
      {"lugar": {"type": "string", "description": "ciudad (opcional); vacío = donde vive Alberto"}},
      icon="partly_cloudy_day")
def tiempo(lugar: str = "") -> dict:
    try:
        loc = _geocodificar(lugar) if lugar.strip() else _mi_ubicacion()
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"no pude localizar «{lugar}»: {e}"}
    if not loc:
        return {"ok": False, "error": "no encuentro el lugar; rellena [ubicacion] en config.toml"}
    url = ("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
           "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m"
           "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max"
           "&timezone=auto&forecast_days=1" % (loc["lat"], loc["lon"]))
    try:
        d = _get_json(url)
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"no pude consultar el tiempo: {e}"}
    c, dd = d["current"], d["daily"]
    return {"ok": True, "lugar": loc["ciudad"],
            "ahora": _WMO.get(c["weather_code"], "variable"),
            "temperatura_c": round(c["temperature_2m"]),
            "sensacion_c": round(c["apparent_temperature"]),
            "viento_kmh": round(c["wind_speed_10m"]),
            "maxima_c": round(dd["temperature_2m_max"][0]),
            "minima_c": round(dd["temperature_2m_min"][0]),
            "prob_lluvia_pct": dd["precipitation_probability_max"][0],
            "resumen": f"Tiempo en {loc['ciudad']}",
            "nota": "Responde en una o dos frases cortas con lo esencial."}


def _limpia(s: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()


def _ddg(consulta: str) -> list[dict]:
    data = urllib.parse.urlencode({"q": consulta, "kl": "es-es"}).encode()
    req = urllib.request.Request("https://html.duckduckgo.com/html/", data=data,
                                 headers={"User-Agent": _UA})
    with urllib.request.urlopen(req, timeout=10) as r:
        page = r.read().decode("utf-8", "replace")
    titulos = re.findall(r'<a[^>]*class="result__a"[^>]*>(.*?)</a>', page, re.S)
    frags = re.findall(r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>', page, re.S)
    out = []
    for i, t in enumerate(titulos[:5]):
        out.append({"titulo": _limpia(t), "fragmento": _limpia(frags[i]) if i < len(frags) else ""})
    return out


@tool("buscar_web",
      "Busca en Internet (DuckDuckGo) y devuelve los primeros resultados. Úsala para datos que no sabes o que cambian: noticias, quién/qué es algo, resultados, precios. Resume el resultado en una o dos frases.",
      {"consulta": {"type": "string", "description": "qué buscar, en pocas palabras"}},
      required=["consulta"], icon="travel_explore")
def buscar_web(consulta: str) -> dict:
    try:
        res = _ddg(consulta)
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"no pude buscar: {e}"}
    if not res:
        return {"ok": False, "error": "la búsqueda no devolvió resultados"}
    return {"ok": True, "resultados": res, "resumen": f"Buscar «{consulta}»",
            "nota": "Resume lo esencial en una o dos frases para leerlo en voz alta, sin leer títulos ni enlaces."}
