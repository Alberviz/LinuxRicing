"""Tools de Laura para Elysium, el modo consola del shell (modules/elysium)."""
from __future__ import annotations

import subprocess

from . import tool


def _ipc(*args: str) -> tuple[bool, str]:
    try:
        r = subprocess.run(["qs", "-c", "caelestia", "ipc", "call", "elysium", *args],
                           capture_output=True, text=True, timeout=5)
        return r.returncode == 0, r.stdout.strip()
    except Exception as e:  # noqa: BLE001
        return False, str(e)


@tool("elysium",
      "Abre o cierra Elysium, el modo consola a pantalla completa para jugar con mando (como el Big Picture de Steam). "
      "«abre Elysium», «modo consola», «quiero jugar con el mando», «sal de Elysium», «vuelve al escritorio». "
      "Para lanzar un juego concreto usa jugar. Para el modo juego normal (seguir trabajando) usa modo_juego.",
      {"accion": {"type": "string", "enum": ["abrir", "cerrar", "estado", "listar_juegos"]}},
      required=["accion"], icon="stadia_controller")
def elysium(accion: str) -> dict:
    cmd = {"abrir": "enter", "cerrar": "leave", "estado": "status", "listar_juegos": "list"}.get(accion)
    if not cmd:
        return {"ok": False, "error": f"acción desconocida: {accion}"}
    ok, out = _ipc(cmd)
    resumen = {"abrir": "Elysium abierto.", "cerrar": "Has vuelto al escritorio."}.get(accion, out)
    return {"ok": ok, "resumen": resumen, "salida": out}


@tool("jugar",
      "Lanza un juego en Elysium (entra en el modo consola si hace falta). «ponme el Zelda», «quiero jugar al Ocarina», «abre Hookshot».",
      {"juego": {"type": "string", "description": "nombre o parte del nombre: zelda, ocarina, hookshot…"}},
      required=["juego"], icon="sports_esports")
def jugar(juego: str) -> dict:
    ok, out = _ipc("play", juego)
    if ok and out:
        return {"ok": True, "resumen": f"Lanzando {out}. ¡A jugar!"}
    _, lista = _ipc("list")
    return {"ok": False, "resumen": f"No encuentro «{juego}» en Elysium.", "juegos": lista.splitlines()}
