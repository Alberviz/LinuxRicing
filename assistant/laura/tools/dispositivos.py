"""Tools de dispositivos: luces, teclado, pantallas, brillo, batería, wifi, bluetooth.
Envuelven CLIs existentes; nada destructivo."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

from . import tool

_REPO = Path(__file__).resolve().parents[3]  # raíz del repo (assistant/laura/tools -> ..)

_COLORES = {"rojo": "ff0000", "verde": "00ff00", "azul": "0000ff", "amarillo": "ffff00",
            "naranja": "ff7800", "morado": "b400ff", "violeta": "b400ff", "rosa": "ff00b4",
            "cian": "00ffff", "blanco": "ffffff", "magenta": "ff00ff"}
_EN = {"rojo": "red", "verde": "green", "azul": "blue", "amarillo": "yellow",
       "naranja": "orange", "morado": "purple", "violeta": "purple", "rosa": "pink",
       "cian": "cyan", "blanco": "white", "magenta": "magenta"}


def _run(cmd: list[str], timeout: float = 10) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def _find(nombre: str, *rutas: str) -> str | None:
    p = shutil.which(nombre)
    if p:
        return p
    for r in rutas:
        c = _REPO / r
        if c.exists():
            return str(c)
    return None


def _hex(color: str) -> str | None:
    c = color.strip().lower().lstrip("#")
    c = _COLORES.get(c, c)
    return c if re.fullmatch(r"[0-9a-f]{6}", c) else None


@tool("luces", "Tira de luces LED: encender, apagar, alternar, color o estado.",
      {"accion": {"type": "string", "enum": ["estado", "encender", "apagar", "alternar", "color"]},
       "color": {"type": "string", "description": "con accion=color: nombre (rojo, azul…) o hex (#ff8800)"}},
      required=["accion"], icon="lightbulb")
def luces(accion: str, color: str = "") -> dict:
    exe = _find("magichome-control", "widgets/magichome-control")
    if not exe:
        return {"ok": False, "error": "no encuentro magichome-control"}
    args = {"estado": [], "encender": ["--on"], "apagar": ["--off"], "alternar": ["--toggle"]}.get(accion)
    if accion == "color":
        h = _hex(color)
        if not h:
            return {"ok": False, "error": f"color no válido: {color}"}
        args = ["--color", h]
    if args is None:
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    try:
        r = _run(["python3", exe, *args], timeout=15)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "la tira de luces no responde (¿apagada o fuera de la red?)"}
    try:
        d = json.loads(r.stdout.strip().splitlines()[-1])
    except (IndexError, ValueError):
        return {"ok": False, "error": (r.stderr or "magichome-control no respondió").strip()[:200]}
    if not d.get("success", False):
        return {"ok": False, "error": d.get("error", "no pude hablar con la tira de luces")}
    return {"ok": True, "encendida": d.get("is_on"), "color": d.get("color"),
            "resumen": {"estado": "Estado de las luces", "encender": "Luces encendidas",
                        "apagar": "Luces apagadas", "alternar": "Luces alternadas",
                        "color": "Color de las luces"}[accion]}


@tool("teclado_color", "Cambia el color de la iluminación del teclado.",
      {"color": {"type": "string", "description": "nombre (rojo, azul, cian…) o hex (#ff8800)"},
       "color_lateral": {"type": "string", "description": "color de la tira lateral (opcional)"}},
      required=["color"], icon="keyboard")
def teclado_color(color: str, color_lateral: str = "") -> dict:
    exe = _find("akko-rgb", "rgb/akko-rgb")
    if not exe:
        return {"ok": False, "error": "no encuentro akko-rgb"}
    cols = []
    for c in (color, color_lateral):
        if not c:
            continue
        h = _hex(c)
        if not h:
            return {"ok": False, "error": f"color no válido: {c}"}
        cols.append("#" + h)
    r = _run(["python3", exe, *cols], timeout=20)
    if r.returncode != 0:
        return {"ok": False, "error": (r.stderr or r.stdout or "akko-rgb falló").strip()[-200:]}
    return {"ok": True, "resumen": "Color del teclado"}


@tool("selector_pantallas", "Abre el selector de proyección de pantallas.", icon="monitor")
def selector_pantallas() -> dict:
    exe = _find("display-selector", "widgets/display-selector")
    if not exe:
        return {"ok": False, "error": "no encuentro display-selector"}
    subprocess.Popen([exe], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "resumen": "Selector de pantallas"}


@tool("brillo", "Sube/baja el brillo de pantalla, o dice el actual (cambio=0).",
      {"cambio": {"type": "integer", "description": "puntos de porcentaje: positivo sube, negativo baja, 0 solo consulta"}},
      icon="brightness_6")
def brillo(cambio: int = 0) -> dict:
    if not shutil.which("brightnessctl"):
        return {"ok": False, "error": "falta brightnessctl"}
    cambio = int(cambio)
    if cambio:
        # nunca por debajo del 5 %: evita dejar la pantalla negra
        if cambio < 0:
            cur = _run(["brightnessctl", "-m"]).stdout.split(",")
            actual = int(cur[3].rstrip("%")) if len(cur) > 3 else 100
            cambio = max(cambio, 5 - actual)
        if cambio:
            _run(["brightnessctl", "set", f"{abs(cambio)}%{'+' if cambio > 0 else '-'}"])
    m = _run(["brightnessctl", "-m"]).stdout.split(",")
    pct = int(m[3].rstrip("%")) if len(m) > 3 else None
    return {"ok": True, "brillo_pct": pct, "resumen": f"Brillo al {pct} %" if pct is not None else "Brillo"}


@tool("bateria", "Nivel y estado de la batería («cuánta batería queda»).", icon="battery_full")
def bateria() -> dict:
    if not shutil.which("upower"):
        return {"ok": False, "error": "falta upower"}
    devs = _run(["upower", "-e"]).stdout.split()
    bat = next((d for d in devs if "battery" in d), None)
    if not bat:
        return {"ok": False, "error": "no hay batería"}
    t = _run(["upower", "-i", bat]).stdout
    pct = re.search(r"percentage:\s*(\d+)%", t)
    est = re.search(r"state:\s*(\S+)", t)
    resto = re.search(r"time to (?:empty|full):\s*(.+)", t)
    return {"ok": True, "porcentaje": int(pct.group(1)) if pct else None,
            "estado": est.group(1) if est else None,
            "tiempo_restante": resto.group(1).strip() if resto else None,
            "resumen": f"Batería al {pct.group(1)} %" if pct else "Batería"}


@tool("wifi", "Consulta, enciende o apaga el wifi («tengo wifi», «apaga el wifi»).",
      {"accion": {"type": "string", "enum": ["estado", "encender", "apagar"]}},
      required=["accion"], icon="wifi")
def wifi(accion: str) -> dict:
    if not shutil.which("nmcli"):
        return {"ok": False, "error": "falta nmcli"}
    if accion in ("encender", "apagar"):
        _run(["nmcli", "radio", "wifi", "on" if accion == "encender" else "off"])
    elif accion != "estado":
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    on = _run(["nmcli", "radio", "wifi"]).stdout.strip() == "enabled"
    red = ""
    if on:
        for ln in _run(["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"]).stdout.splitlines():
            if ln.startswith("yes:") or ln.startswith("sí:"):
                red = ln.split(":", 1)[1]
                break
    return {"ok": True, "encendido": on, "red": red,
            "resumen": "Wifi " + ("encendido" if on else "apagado")}


@tool("bluetooth", "Consulta, enciende o apaga el bluetooth («apaga el bluetooth»).",
      {"accion": {"type": "string", "enum": ["estado", "encender", "apagar"]}},
      required=["accion"], icon="bluetooth")
def bluetooth(accion: str) -> dict:
    if not shutil.which("bluetoothctl"):
        return {"ok": False, "error": "falta bluetoothctl"}
    if accion in ("encender", "apagar"):
        _run(["bluetoothctl", "power", "on" if accion == "encender" else "off"])
    elif accion != "estado":
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    on = "Powered: yes" in _run(["bluetoothctl", "show"]).stdout
    return {"ok": True, "encendido": on, "resumen": "Bluetooth " + ("encendido" if on else "apagado")}
