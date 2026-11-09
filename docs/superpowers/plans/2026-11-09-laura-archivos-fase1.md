# Laura Archivos — Fase 1 (núcleo seguro) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que Laura pueda borrar (a la papelera), mover, renombrar y crear carpetas por voz sobre la lista de hologramas, con confirmación por voz o clic, animaciones y «deshaz».

**Architecture:** Un motor puro (`laura/archivos.py`) que planifica sin tocar el disco y ejecuta con papelera freedesktop y diario. Las tools solo crean planes; el ciclo de voz pide la confirmación (voz o panel holográfico «confirmar», lo que llegue primero) y la escena de hologramas (`holo.py`) resuelve el plan una sola vez, anima y relista. Las tools de archivos son *contextuales*: solo se ofrecen al LLM si la frase las pide (el contexto de Ollama ya va al límite).

**Tech Stack:** Python 3.12 (daemon `laura`), pytest, QML/Quickshell (Qt 6), Ollama (qwen3:4b).

**Spec:** `docs/superpowers/specs/2026-11-09-laura-archivos-design.md`

## Global Constraints

- **Rama:** `feat/laura-archivos` (comprobar con `git branch --show-current`). Otros agentes (Gemini, Claude) tienen cambios sin commitear en el árbol: **commitea siempre con `git add <rutas concretas>`, nunca `git add -A`**.
- **Papelera:** todo borrado va a la papelera freedesktop (`$XDG_DATA_HOME/Trash`, formato `files/` + `info/*.trashinfo`). **Nunca `rm` ni borrado definitivo.** (Decisión: papelera propia en vez de `gio trash`, para conocer la ruta exacta de lo borrado y poder deshacerlo y probarlo sin `gio`; es compatible con los gestores de archivos.)
- **Alcance:** Descargas, Documentos, Escritorio, Imágenes, Vídeos, Música (según `xdg-user-dir`) y `~/proyectos`. Rechazar ocultos, `.git`, cualquier `vault`, symlinks que escapen y las raíces mismas (salvo como destino). Máximo 50 operaciones por plan.
- **Confirmación:** borrar siempre; mover/renombrar de más de 5 elementos. Plan caduca a los 60 s. Un solo plan pendiente a la vez. **Nada se ejecuta sin un `confirmar` explícito de ese plan.**
- **Idioma:** textos de Laura (lo que dice y los errores) en español natural, aptos para TTS. Respuestas de Claude al usuario: «Alberto» al principio.
- **QML:** tras tocar QML, sincronizar a `~/.config/quickshell/caelestia/` y **reinicio completo del shell** (`caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d`), comprobar `INFO: Configuration Loaded` sin `ReferenceError`/`TypeError`. Animaciones **one-shot**, sin `running: true` incondicional, sin `shadowBlur` en `Canvas`.
- **Cursor compartido:** no hagas clics reales con `ydotool`/`hyprctl` para probar; usa los IPC de demo (`holo demoConfirm`, `holo demoResolver`) y capturas con `grim`.
- **Contexto de Ollama:** el prompt (sistema + esquemas de tools) ya ocupa ~7.500 de 8.192 tokens (medido). No añadas tools de forma incondicional ni alargues el system prompt.
- **Tests del daemon:** `cd assistant && python3 -m pytest -q -p no:cacheprovider tests`. El entorno de tests no tiene `torch`/`soundfile`: **no importes `laura.escalation`, `laura.daemon`, `laura.audio` ni `laura.stt` desde los tests**; la lógica testeable vive en módulos puros.
- **Coordinación:** antes de editar `HoloLayer.qml`, `LauraOverlay.qml` o `Laura.qml` avisa a la sesión `linuxricing-12` (`SendMessage`). Esta fase solo toca `HoloLayer.qml` (Task 6).

## File Structure

| Archivo | Responsabilidad |
|---|---|
| `assistant/laura/archivos.py` (nuevo) | Motor: validación de rutas, `Plan`, planificar, papelera, ejecutar, diario, deshacer, planes pendientes |
| `assistant/laura/confirmar_archivos.py` (nuevo) | Lógica de confirmación voz/panel sin audio (funciones inyectadas) |
| `assistant/laura/tools/archivos.py` (nuevo) | 5 tools que solo planifican (+ `cuando` contextual) |
| `assistant/laura/holo.py` (mod.) | Panel `confirmar`, `resolver_plan`, `tras_plan`, `refrescar`, control `holo-confirm/cancel`, `carpeta` |
| `assistant/laura/tools/__init__.py`, `llm.py` (mod.) | Tools contextuales (`activas`), efecto `confirm:archivos` |
| `assistant/laura/escalation.py`, `daemon.py` (mod.) | `_confirm_archivos` en el ciclo de voz; respuesta tardía «sí/no» |
| `configs/quickshell/caelestia/modules/holo/HoloConfirm.qml` (nuevo) | Contenido del panel de confirmación |
| `HoloPanel.qml`, `HoloLayer.qml`, `HoloList.qml`, `HoloPlacer.js`, `assistant/HoloState.qml` (mod.) | Tipo de panel, animaciones (desintegrar, fila que se va, papelera), IPC de demo |
| `assistant/tests/…` (nuevos) | `conftest.py`, `test_archivos.py`, `test_holo_archivos.py`, `test_confirmar_archivos.py`, `test_tools_archivos.py`, `test_tools_activas.py` |

---

### Task 1: Motor de archivos (planificar, papelera, ejecutar, diario, deshacer)

**Files:**
- Create: `assistant/laura/archivos.py`
- Create: `assistant/tests/conftest.py`
- Test: `assistant/tests/test_archivos.py`

**Interfaces:**
- Produces (lo usan las tareas 2–5):
  - `Rechazo(Exception)`; `Entorno(raices, diario, papelera, max_ops, ttl)`; `ENTORNO` (global, los tests lo sustituyen con `monkeypatch.setattr(archivos, "ENTORNO", …)`); `ahora() -> float`.
  - `ruta_permitida(p, permitir_raiz=False) -> Path`
  - `Op`, `Plan` (`.accion`, `.ops`, `.requiere_confirmacion`, `.carpeta`, `.id`, `.estado`, `.mensaje`, `.evento`, `.total_bytes`, `.expira`, `.titulo()`, `.pregunta()`, `.a_payload()`)
  - `planificar_borrar(rutas, carpeta=None)`, `planificar_mover(rutas, destino_dir)`, `planificar_renombrar(ruta, nombre)`, `planificar_crear_carpeta(nombre, en)`, `resolver_destino(nombre, carpeta_actual=None) -> Path`
  - `ejecutar(plan) -> dict` (`{"ok", "decir", …}` o `{"ok": False, "error"}`), `deshacer() -> dict` (incluye `"carpeta"`)
  - `registrar(plan)`, `pendiente()`, `plan_por_id(id)`, `resolver(plan_id, si) -> dict` (incluye `"plan"`, `"estado"`)

- [ ] **Step 1: Confirmar la rama y escribir los tests (fixture compartida + tests del motor)**

```bash
git branch --show-current   # feat/laura-archivos
```

Crea `assistant/tests/conftest.py`:

````python
"""Fixtures compartidas de los tests de Laura."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura import archivos  # noqa: E402


@pytest.fixture
def env(tmp_path, monkeypatch):
    """Raíces falsas (Descargas, Documentos, proyectos), papelera y diario en tmp_path."""
    raices = []
    for nombre in ("Descargas", "Documentos", "proyectos"):
        d = tmp_path / nombre
        d.mkdir()
        raices.append(d)
    entorno = archivos.Entorno(raices=raices, diario=tmp_path / "estado" / "archivos.jsonl",
                               papelera=tmp_path / "Trash", max_ops=50, ttl=60.0)
    monkeypatch.setattr(archivos, "ENTORNO", entorno)
    monkeypatch.setattr(archivos, "_PLANES", {})
    return tmp_path


def crear(base: Path, nombre: str, contenido: str = "hola") -> Path:
    p = base / nombre
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(contenido)
    return p
````

Crea `assistant/tests/test_archivos.py`:

````python
"""Motor de archivos: validación, planes, ejecución con papelera, diario y deshacer."""
import json
import os

import pytest

from conftest import crear
from laura import archivos as a


# ---------------------------------------------------------------- validador

def test_ruta_fuera_de_las_raices_rechazada(env):
    fuera = crear(env, "fuera/x.txt")
    with pytest.raises(a.Rechazo, match="fuera de tus carpetas"):
        a.ruta_permitida(fuera)


def test_la_raiz_misma_solo_vale_como_destino(env):
    with pytest.raises(a.Rechazo, match="entera"):
        a.ruta_permitida(env / "Descargas")
    assert a.ruta_permitida(env / "Descargas", permitir_raiz=True) == (env / "Descargas").resolve()


@pytest.mark.parametrize("ruta", ["Descargas/.oculto", "proyectos/app/.git/config", "proyectos/LinuxRicing/vault/nota.md",
                                  "Documentos/Vault/x.md"])
def test_ocultos_git_y_vault_rechazados(env, ruta):
    with pytest.raises(a.Rechazo):
        a.ruta_permitida(env / ruta)


def test_symlink_que_escapa_rechazado(env):
    fuera = crear(env, "fuera/secreto.txt")
    enlace = env / "Descargas" / "atajo"
    enlace.symlink_to(fuera)
    with pytest.raises(a.Rechazo, match="fuera de tus carpetas"):
        a.planificar_borrar([str(enlace)])
    assert fuera.exists()


# ------------------------------------------------------------- planificación

def test_planificar_no_toca_el_disco(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.planificar_borrar([str(f)])
    assert f.exists() and plan.estado == "pendiente" and plan.accion == "borrar"
    assert plan.ops[0].tamano == 4


def test_cuando_pide_confirmacion(env):
    uno = crear(env, "Descargas/uno.txt")
    assert a.planificar_borrar([str(uno)]).requiere_confirmacion
    assert not a.planificar_mover([str(uno)], env / "Documentos").requiere_confirmacion
    seis = [str(crear(env, f"Descargas/f{i}.txt")) for i in range(6)]
    assert a.planificar_mover(seis, env / "Documentos").requiere_confirmacion
    assert not a.planificar_renombrar(str(uno), "dos.txt").requiere_confirmacion
    assert not a.planificar_crear_carpeta("Facturas", env / "Descargas").requiere_confirmacion


def test_tope_de_operaciones(env, monkeypatch):
    monkeypatch.setattr(a.ENTORNO, "max_ops", 3)
    rutas = [str(crear(env, f"Descargas/f{i}.txt")) for i in range(4)]
    with pytest.raises(a.Rechazo, match="demasiados"):
        a.planificar_borrar(rutas)


def test_origen_inexistente_y_duplicados(env):
    f = crear(env, "Descargas/a.txt")
    with pytest.raises(a.Rechazo, match="ya no existe"):
        a.planificar_borrar([str(env / "Descargas" / "no.txt")])
    assert len(a.planificar_borrar([str(f), str(f)]).ops) == 1


def test_mover_a_si_misma_o_donde_ya_esta(env):
    d = env / "Documentos" / "carpeta"
    d.mkdir()
    hija = d / "hija"
    hija.mkdir()
    with pytest.raises(a.Rechazo, match="dentro de sí misma"):
        a.planificar_mover([str(d)], hija)
    f = crear(env, "Documentos/x.txt")
    with pytest.raises(a.Rechazo, match="ya está en"):
        a.planificar_mover([str(f)], env / "Documentos")


@pytest.mark.parametrize("nombre", ["", "a/b", ".oculto", "..", "x" * 300])
def test_nombres_invalidos(env, nombre):
    f = crear(env, "Descargas/a.txt")
    with pytest.raises(a.Rechazo, match="no vale"):
        a.planificar_renombrar(str(f), nombre)


def test_crear_carpeta_existente(env):
    (env / "Descargas" / "Facturas").mkdir()
    with pytest.raises(a.Rechazo, match="Ya existe"):
        a.planificar_crear_carpeta("Facturas", env / "Descargas")


def test_textos_del_plan(env):
    fs = [str(crear(env, f"Descargas/f{i}.txt", "x" * 1024 * 1024)) for i in range(3)]
    p = a.planificar_borrar(fs)
    assert p.pregunta() == "Voy a mandar a la papelera tres archivos, 3 megas. ¿Confirmas?"
    assert p.titulo() == "Borrar tres archivos"
    assert p.a_payload()["items"][0]["nombre"] == "f0.txt" and p.a_payload()["mas"] == 0


def test_resolver_destino(env):
    (env / "Documentos" / "Universidad" / "Redes").mkdir(parents=True)
    assert a.resolver_destino("documentos") == env / "Documentos"
    assert a.resolver_destino("universidad") == env / "Documentos" / "Universidad"
    assert a.resolver_destino("Redes") == env / "Documentos" / "Universidad" / "Redes"
    with pytest.raises(a.Rechazo, match="No encuentro"):
        a.resolver_destino("inexistente")
    assert a.resolver_destino("/abs/ruta") == a.Path("/abs/ruta")


# ------------------------------------------------------ ejecutar y deshacer

def test_mover_y_deshacer(env):
    f = crear(env, "Descargas/a.txt")
    r = a.ejecutar(a.planificar_mover([str(f)], env / "Documentos"))
    assert r["ok"] and not f.exists() and (env / "Documentos" / "a.txt").exists()
    assert "deshaz" in r["decir"]
    d = a.deshacer()
    assert d["ok"] and f.exists() and not (env / "Documentos" / "a.txt").exists()
    assert not a.deshacer()["ok"]                      # ya está deshecho


def test_mover_no_sobrescribe(env):
    crear(env, "Documentos/a.txt", "viejo")
    f = crear(env, "Descargas/a.txt", "nuevo")
    a.ejecutar(a.planificar_mover([str(f)], env / "Documentos"))
    assert (env / "Documentos" / "a.txt").read_text() == "viejo"
    assert (env / "Documentos" / "a (2).txt").read_text() == "nuevo"


def test_renombrar_y_deshacer(env):
    f = crear(env, "Descargas/a.txt")
    r = a.ejecutar(a.planificar_renombrar(str(f), "b.txt"))
    assert r["ok"] and (env / "Descargas" / "b.txt").exists()
    a.deshacer()
    assert f.exists() and not (env / "Descargas" / "b.txt").exists()


def test_borrar_va_a_la_papelera_y_se_recupera(env):
    f = crear(env, "Descargas/a.txt", "contenido")
    r = a.ejecutar(a.planificar_borrar([str(f)]))
    assert r["ok"] and not f.exists()
    enpapelera = list((env / "Trash" / "files").iterdir())
    assert [p.name for p in enpapelera] == ["a.txt"]
    info = (env / "Trash" / "info" / "a.txt.trashinfo").read_text()
    assert info.startswith("[Trash Info]") and f"Path={f}" in info and "DeletionDate=" in info
    assert a.deshacer()["ok"]
    assert f.read_text() == "contenido" and not list((env / "Trash" / "info").iterdir())


def test_borrar_carpeta_con_contenido(env):
    d = env / "Descargas" / "viejo"
    crear(d, "x/y.txt", "1234")
    p = a.planificar_borrar([str(d)])
    assert p.ops[0].es_dir and p.ops[0].tamano == 4 and "carpeta" in p.pregunta()
    a.ejecutar(p)
    assert not d.exists()
    a.deshacer()
    assert (d / "x" / "y.txt").read_text() == "1234"


def test_crear_carpeta_y_deshacer_solo_si_vacia(env):
    r = a.ejecutar(a.planificar_crear_carpeta("Facturas", env / "Descargas"))
    nueva = env / "Descargas" / "Facturas"
    assert r["ok"] and nueva.is_dir() and "deshaz" not in r["decir"]
    crear(nueva, "dentro.txt")
    assert not a.deshacer()["ok"] and nueva.exists()   # no vacía: se conserva


def test_deshacer_revierte_la_ultima_accion_entera(env):
    fs = [crear(env, f"Descargas/f{i}.txt") for i in range(3)]
    a.ejecutar(a.planificar_borrar([str(x) for x in fs]))
    d = a.deshacer()
    assert d["ok"] and d["n"] == 3 and all(x.exists() for x in fs)
    assert d["carpeta"] == str(env / "Descargas")


def test_diario_sobrevive_al_reinicio(env):
    f = crear(env, "Descargas/a.txt")
    a.ejecutar(a.planificar_borrar([str(f)]))
    lineas = [json.loads(t) for t in (env / "estado" / "archivos.jsonl").read_text().splitlines()]
    assert lineas[0]["accion"] == "borrar" and lineas[0]["deshecha"] is False
    # «reinicio»: el motor no guarda nada en memoria que el deshacer necesite
    a._PLANES.clear()
    assert a.deshacer()["ok"] and f.exists()
    assert json.loads((env / "estado" / "archivos.jsonl").read_text().splitlines()[0])["deshecha"] is True


def test_origen_desaparecido_se_omite(env):
    f1, f2 = crear(env, "Descargas/a.txt"), crear(env, "Descargas/b.txt")
    plan = a.planificar_borrar([str(f1), str(f2)])
    f1.unlink()
    r = a.ejecutar(plan)
    assert r["ok"] and r["hechas"] == 1 and "1 ya no existían" in r["decir"]
    assert a.ejecutar(a.planificar_borrar([str(crear(env, "Descargas/c.txt"))]))["ok"]


def test_todo_falla(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.planificar_borrar([str(f)])
    f.unlink()
    r = a.ejecutar(plan)
    assert not r["ok"] and plan.estado == "fallido" and not (env / "estado" / "archivos.jsonl").exists()


# --------------------------------------------------------- planes pendientes

def test_nada_se_ejecuta_sin_resolver(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    assert a.pendiente() is plan and f.exists()


def test_resolver_si_ejecuta_una_sola_vez(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    r = a.resolver(plan.id, True)
    assert r["ok"] and r["estado"] == "ejecutado" and not f.exists() and plan.evento.is_set()
    assert plan.mensaje == r["decir"]
    r2 = a.resolver(plan.id, True)
    assert not r2["ok"] and r2["estado"] == "ejecutado"
    assert a.pendiente() is None


def test_resolver_no_cancela_sin_tocar(env):
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    r = a.resolver(plan.id, False)
    assert r["ok"] and r["estado"] == "cancelado" and f.exists() and plan.evento.is_set()


def test_un_plan_nuevo_cancela_el_anterior(env):
    f = crear(env, "Descargas/a.txt")
    p1 = a.registrar(a.planificar_borrar([str(f)]))
    p2 = a.registrar(a.planificar_borrar([str(f)]))
    assert p1.estado == "cancelado" and p1.evento.is_set() and a.pendiente() is p2


def test_caducidad(env, monkeypatch):
    f = crear(env, "Descargas/a.txt")
    t = {"v": 1000.0}
    monkeypatch.setattr(a, "ahora", lambda: t["v"])
    plan = a.registrar(a.planificar_borrar([str(f)]))
    t["v"] += 61
    assert a.pendiente() is None and plan.estado == "caducado" and plan.evento.is_set()
    r = a.resolver(plan.id, True)
    assert not r["ok"] and "tiempo" in r["error"] and f.exists()


def test_resolver_desconocido(env):
    assert a.resolver("nope", True) == {"ok": False, "error": "No hay nada pendiente."}
````

- [ ] **Step 2: Ejecutar los tests y verificar que fallan**

Run: `cd assistant && python3 -m pytest -q -p no:cacheprovider tests/test_archivos.py`
Expected: error de colección `ImportError: cannot import name 'archivos' from 'laura'` (el módulo no existe).

- [ ] **Step 3: Implementar el motor**

Crea `assistant/laura/archivos.py`:

````python
"""Motor de archivos de Laura: planifica (sin tocar el disco), ejecuta con papelera y deshace.

El LLM nunca ejecuta: las tools (`tools/archivos.py`) solo crean un `Plan`. Un plan que
requiere confirmación queda `pendiente` hasta que `resolver()` lo confirma o cancela
(voz o panel holográfico) o caduca. Todo lo que se borra va a la papelera freedesktop
(`~/.local/share/Trash`, compatible con los gestores de archivos) y cada acción queda en
un diario para poder deshacerla incluso tras reiniciar.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
import unicodedata
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from urllib.parse import quote

MAX_OPS_DEFECTO = 50
TTL_DEFECTO = 60.0
UMBRAL_LOTE = 5          # mover/renombrar más de 5 elementos pide confirmación


class Rechazo(Exception):
    """Algo que no se puede hacer; el mensaje es apto para decirlo en voz alta."""


def ahora() -> float:
    return time.time()


# ------------------------------------------------------------------------- entorno

def _xdg(nombre: str, defecto: str) -> Path:
    try:
        r = subprocess.run(["xdg-user-dir", nombre], capture_output=True, text=True, timeout=3)
        p = Path(r.stdout.strip())
        if r.returncode == 0 and r.stdout.strip() and p != Path.home():
            return p
    except (OSError, subprocess.SubprocessError):
        pass
    return Path.home() / defecto


@dataclass
class Entorno:
    raices: list[Path]
    diario: Path
    papelera: Path
    max_ops: int = MAX_OPS_DEFECTO
    ttl: float = TTL_DEFECTO


def entorno_por_defecto() -> Entorno:
    try:
        from .config import CFG
        cfg = CFG.get("archivos", {})
    except Exception:  # noqa: BLE001 — sin config (tests sueltos) se usan los valores por defecto
        cfg = {}
    if cfg.get("raices"):
        raices = [Path(os.path.expanduser(r)) for r in cfg["raices"]]
    else:
        raices = [_xdg("DOWNLOAD", "Descargas"), _xdg("DOCUMENTS", "Documentos"),
                  _xdg("DESKTOP", "Escritorio"), _xdg("PICTURES", "Imágenes"),
                  _xdg("VIDEOS", "Vídeos"), _xdg("MUSIC", "Música"), Path.home() / "proyectos"]
    estado = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "laura"
    datos = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "Trash"
    return Entorno(raices, estado / "archivos.jsonl", datos,
                   int(cfg.get("max_ops", MAX_OPS_DEFECTO)), float(cfg.get("ttl", TTL_DEFECTO)))


ENTORNO = entorno_por_defecto()


# ---------------------------------------------------------------------- validación

def _plano(s: str) -> str:
    """Minúsculas y sin tildes, para comparar nombres de carpeta dichos de viva voz."""
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c)).strip()


def ruta_permitida(p, permitir_raiz: bool = False) -> Path:
    """Ruta real (symlinks resueltos) si se puede tocar; si no, lanza `Rechazo`.

    Debe estar dentro de una raíz permitida. Las raíces mismas solo valen como destino
    (`permitir_raiz`). Se rechazan componentes ocultos, `.git` y cualquier `vault`."""
    real = Path(os.path.realpath(os.path.expanduser(str(p))))
    for raiz in ENTORNO.raices:
        r = Path(os.path.realpath(raiz))
        if real == r:
            if permitir_raiz:
                return real
            raise Rechazo(f"No toco la carpeta {r.name} entera.")
        if real.is_relative_to(r):
            partes = real.relative_to(r).parts
            if any(x.startswith(".") for x in partes):
                raise Rechazo("No toco archivos ocultos.")
            if any(x.lower() == "vault" for x in partes):
                raise Rechazo("No toco el vault.")
            return real
    raise Rechazo("No puedo tocar eso: está fuera de tus carpetas.")


def _nombre_valido(nombre: str) -> str:
    n = (nombre or "").strip()
    if not n or "/" in n or n in (".", "..") or n.startswith(".") or len(n) > 200:
        raise Rechazo("Ese nombre no vale.")
    return n


def _tam(p: Path) -> int:
    try:
        if p.is_dir() and not p.is_symlink():
            total = 0
            for d, _, fs in os.walk(p):
                for f in fs:
                    try:
                        total += os.path.getsize(os.path.join(d, f))
                    except OSError:
                        pass
            return total
        return p.lstat().st_size
    except OSError:
        return 0


def _tam_humano(b: int) -> str:
    if b >= 1 << 30:
        return f"{b / (1 << 30):.1f} gigas".replace(".", ",")
    if b >= 1 << 20:
        return f"{round(b / (1 << 20))} megas"
    if b >= 1 << 10:
        return f"{round(b / (1 << 10))} kilos"
    return "unos pocos bytes"


_PALABRAS = {1: "un", 2: "dos", 3: "tres", 4: "cuatro", 5: "cinco", 6: "seis", 7: "siete",
             8: "ocho", 9: "nueve", 10: "diez", 11: "once", 12: "doce"}


# ------------------------------------------------------------------------ el plan

@dataclass
class Op:
    origen: str
    destino: str | None = None
    tamano: int = 0
    es_dir: bool = False
    real_destino: str | None = None   # dónde quedó de verdad (tras evitar colisiones)
    trash_files: str | None = None
    trash_info: str | None = None


@dataclass
class Plan:
    accion: str                       # borrar | mover | renombrar | crear_carpeta
    ops: list[Op]
    requiere_confirmacion: bool
    carpeta: str | None = None        # carpeta de contexto (destino o carpeta de la lista)
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:8])
    creado: float = field(default_factory=lambda: ahora())
    estado: str = "pendiente"         # pendiente | ejecutado | cancelado | caducado | fallido
    mensaje: str = ""                 # lo que Laura debe decir al resolverse
    evento: threading.Event = field(default_factory=threading.Event, repr=False, compare=False)

    @property
    def total_bytes(self) -> int:
        return sum(o.tamano for o in self.ops)

    @property
    def expira(self) -> float:
        return self.creado + ENTORNO.ttl

    def _cuantos(self) -> str:
        n = len(self.ops)
        dirs = sum(o.es_dir for o in self.ops)
        cosa = ("carpeta", "carpetas") if dirs == n else ("archivo", "archivos") if dirs == 0 else ("elemento", "elementos")
        return f"{_PALABRAS.get(n, str(n))} {cosa[0] if n == 1 else cosa[1]}"

    def titulo(self) -> str:
        return {"borrar": f"Borrar {self._cuantos()}", "mover": f"Mover {self._cuantos()}",
                "renombrar": "Renombrar", "crear_carpeta": "Crear carpeta"}[self.accion]

    def pregunta(self) -> str:
        if self.accion == "borrar":
            return f"Voy a mandar a la papelera {self._cuantos()}, {_tam_humano(self.total_bytes)}. ¿Confirmas?"
        if self.accion == "mover":
            return f"Voy a mover {self._cuantos()} a {Path(self.ops[0].destino).parent.name}. ¿Confirmas?"
        if self.accion == "renombrar":
            o = self.ops[0]
            return f"Voy a renombrar {Path(o.origen).name} a {Path(o.destino).name}. ¿Confirmas?"
        return f"Voy a crear la carpeta {Path(self.ops[0].destino).name}. ¿Confirmas?"

    def a_payload(self) -> dict:
        """Lo que pinta el panel holográfico de confirmación."""
        return {
            "plan": self.id, "accion": self.accion, "titulo": self.titulo(),
            "items": [{"nombre": Path(o.origen).name, "tamano": o.tamano, "es_dir": o.es_dir,
                       "nuevo": Path(o.destino).name if self.accion == "renombrar" and o.destino else None}
                      for o in self.ops[:6]],
            "mas": max(0, len(self.ops) - 6),
            "total_bytes": self.total_bytes,
            "destino": Path(self.ops[0].destino).parent.name if self.accion == "mover" else None,
            "segundos": int(ENTORNO.ttl), "expira": self.expira,
        }


# ------------------------------------------------------------------ planificación
# Ninguna de estas funciones toca el disco.

def _validar_n(n: int) -> None:
    if n == 0:
        raise Rechazo("No hay nada que hacer.")
    if n > ENTORNO.max_ops:
        raise Rechazo("Son demasiados de golpe; hazlo en tandas.")


def _ops_existentes(rutas: list[str]) -> list[Op]:
    """Ops de origen para rutas que existen y se pueden tocar. La ruta de la op es la
    absoluta SIN resolver (un enlace dentro de las carpetas se trata como el enlace)."""
    vistos: set[str] = set()
    ops: list[Op] = []
    for r in rutas:
        real = ruta_permitida(r)
        absoluta = Path(os.path.abspath(os.path.expanduser(str(r))))
        if not absoluta.exists() and not absoluta.is_symlink():
            raise Rechazo(f"{absoluta.name} ya no existe.")
        if str(absoluta) in vistos:
            continue
        vistos.add(str(absoluta))
        ops.append(Op(origen=str(absoluta), tamano=_tam(real), es_dir=real.is_dir()))
    return ops


def planificar_borrar(rutas: list[str], carpeta: str | None = None) -> Plan:
    ops = _ops_existentes(rutas)
    _validar_n(len(ops))
    return Plan("borrar", ops, True, carpeta)


def planificar_mover(rutas: list[str], destino_dir) -> Plan:
    dest = ruta_permitida(destino_dir, permitir_raiz=True)
    if not dest.is_dir():
        raise Rechazo(f"{dest.name} no es una carpeta.")
    ops = _ops_existentes(rutas)
    _validar_n(len(ops))
    for op in ops:
        o = Path(op.origen)
        real_o = os.path.realpath(o)
        if str(dest) == real_o or str(dest).startswith(real_o + os.sep):
            raise Rechazo("No puedo meter una carpeta dentro de sí misma.")
        if Path(os.path.realpath(o.parent)) == dest:
            raise Rechazo(f"{o.name} ya está en {dest.name}.")
        op.destino = str(dest / o.name)
    return Plan("mover", ops, len(ops) > UMBRAL_LOTE, str(dest))


def planificar_renombrar(ruta: str, nombre: str) -> Plan:
    nuevo = _nombre_valido(nombre)
    ops = _ops_existentes([ruta])
    o = Path(ops[0].origen)
    if nuevo == o.name:
        raise Rechazo("Ya se llama así.")
    ops[0].destino = str(o.with_name(nuevo))
    ruta_permitida(ops[0].destino)
    return Plan("renombrar", ops, False, str(o.parent))


def planificar_crear_carpeta(nombre: str, en) -> Plan:
    nuevo = _nombre_valido(nombre)
    base = ruta_permitida(en, permitir_raiz=True)
    if not base.is_dir():
        raise Rechazo(f"{base.name} no es una carpeta.")
    destino = base / nuevo
    ruta_permitida(destino)
    if destino.exists():
        raise Rechazo(f"Ya existe {nuevo}.")
    return Plan("crear_carpeta", [Op(origen=str(destino), destino=str(destino), es_dir=True)], False, str(base))


def _buscar_carpeta(buscado: str, bases: list[Path], profundidad: int = 2) -> Path | None:
    visitadas = 0
    nivel = [b for b in bases if b.is_dir()]
    for _ in range(profundidad):
        siguiente: list[Path] = []
        for base in nivel:
            try:
                hijos = sorted(base.iterdir())
            except OSError:
                continue
            for h in hijos:
                if h.name.startswith(".") or not h.is_dir():
                    continue
                visitadas += 1
                if _plano(h.name) == buscado:
                    return h
                siguiente.append(h)
            if visitadas > 800:
                return None
        nivel = siguiente
    return None


def resolver_destino(nombre: str, carpeta_actual: str | None = None) -> Path:
    """«Documentos», «Universidad» o una ruta -> carpeta real. Busca primero en la carpeta de
    la lista que se ve y luego en las raíces (dos niveles)."""
    n = os.path.expanduser((nombre or "").strip())
    if not n:
        raise Rechazo("¿A qué carpeta?")
    if os.path.isabs(n):
        return Path(n)
    buscado = _plano(n)
    for r in ENTORNO.raices:
        if _plano(r.name) == buscado:
            return r
    bases = ([Path(carpeta_actual)] if carpeta_actual else []) + list(ENTORNO.raices)
    hallada = _buscar_carpeta(buscado, bases)
    if hallada is None:
        raise Rechazo(f"No encuentro la carpeta {nombre}.")
    return hallada


# -------------------------------------------------------------------- papelera

def _libre(directorio: Path, nombre: str, es_dir: bool = False, extra=None) -> Path:
    """`directorio/nombre`, o `nombre (2).ext`, `(3)`… si ya está ocupado. Nunca sobrescribe."""
    def ocupado(c: Path) -> bool:
        return c.exists() or c.is_symlink() or bool(extra and extra(c))

    cand = directorio / nombre
    if not ocupado(cand):
        return cand
    stem, suf = (nombre, "") if es_dir else (Path(nombre).stem, Path(nombre).suffix)
    i = 2
    while True:
        cand = directorio / f"{stem} ({i}){suf}"
        if not ocupado(cand):
            return cand
        i += 1


def _a_papelera(origen: Path, es_dir: bool) -> tuple[Path, Path]:
    base = ENTORNO.papelera
    files, info = base / "files", base / "info"
    files.mkdir(parents=True, exist_ok=True)
    info.mkdir(parents=True, exist_ok=True)
    destino = _libre(files, origen.name, es_dir, extra=lambda c: (info / (c.name + ".trashinfo")).exists())
    ficha = info / (destino.name + ".trashinfo")
    ficha.write_text("[Trash Info]\nPath=%s\nDeletionDate=%s\n"
                     % (quote(str(origen), safe="/"), datetime.now().strftime("%Y-%m-%dT%H:%M:%S")))
    try:
        shutil.move(str(origen), str(destino))
    except Exception:
        ficha.unlink(missing_ok=True)
        raise
    return destino, ficha


# ------------------------------------------------------------------- ejecución

def _hacer(accion: str, op: Op) -> None:
    o = Path(op.origen)
    if accion == "crear_carpeta":
        d = Path(op.destino)
        d.mkdir()
        op.real_destino = str(d)
        return
    if not o.exists() and not o.is_symlink():
        raise Rechazo(f"{o.name} ya no existe.")
    if accion == "borrar":
        f, i = _a_papelera(o, op.es_dir)
        op.trash_files, op.trash_info = str(f), str(i)
    else:  # mover | renombrar
        d = _libre(Path(op.destino).parent, Path(op.destino).name, op.es_dir)
        shutil.move(str(o), str(d))
        op.real_destino = str(d)


def ejecutar(plan: Plan) -> dict:
    """Ejecuta el plan (sin pedir nada: eso ya lo hizo quien llama). Anota el diario."""
    hechas: list[Op] = []
    omitidas: list[str] = []
    errores: list[str] = []
    for op in plan.ops:
        try:
            _hacer(plan.accion, op)
            hechas.append(op)
        except Rechazo as e:
            omitidas.append(str(e))
        except OSError as e:
            errores.append(f"{Path(op.origen).name}: {e.strerror or e}")
    if not hechas:
        plan.estado = "fallido"
        motivo = (omitidas + errores or ["no se pudo"])[0]
        return {"ok": False, "error": f"No he podido: {motivo}"}
    _anotar(plan, hechas)
    plan.estado = "ejecutado"
    if plan.accion == "borrar":
        decir = f"Hecho: {Plan(plan.accion, hechas, True)._cuantos()} a la papelera."
    elif plan.accion == "mover":
        decir = f"Hecho: {Plan(plan.accion, hechas, True)._cuantos()} movidos a {Path(hechas[0].real_destino).parent.name}."
    elif plan.accion == "renombrar":
        decir = f"Hecho: ahora se llama {Path(hechas[0].real_destino).name}."
    else:
        decir = f"Hecho: carpeta {Path(hechas[0].real_destino).name} creada."
    if omitidas:
        decir += f" {len(omitidas)} ya no existían."
    if errores:
        decir += f" {len(errores)} han fallado."
    if plan.accion != "crear_carpeta":
        decir += " Dime «deshaz» si te arrepientes."
    return {"ok": True, "decir": decir, "hechas": len(hechas), "omitidas": omitidas, "errores": errores}


# ---------------------------------------------------------------------- diario

def _anotar(plan: Plan, hechas: list[Op]) -> None:
    ENTORNO.diario.parent.mkdir(parents=True, exist_ok=True)
    linea = {"id": plan.id, "ts": ahora(), "accion": plan.accion, "deshecha": False,
             "ops": [asdict(o) for o in hechas]}
    with ENTORNO.diario.open("a", encoding="utf-8") as f:
        f.write(json.dumps(linea, ensure_ascii=False) + "\n")


def _leer_diario() -> list[dict]:
    if not ENTORNO.diario.exists():
        return []
    lineas = []
    for t in ENTORNO.diario.read_text(encoding="utf-8").splitlines():
        try:
            lineas.append(json.loads(t))
        except ValueError:
            continue
    return lineas


def _escribir_diario(lineas: list[dict]) -> None:
    tmp = ENTORNO.diario.with_suffix(".tmp")
    tmp.write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in lineas), encoding="utf-8")
    os.replace(tmp, ENTORNO.diario)


def _revertir(accion: str, op: Op) -> None:
    origen = Path(op.origen)
    if accion == "crear_carpeta":
        Path(op.real_destino or op.destino).rmdir()      # OSError si ya no está vacía
        return
    if accion == "borrar":
        fuente = Path(op.trash_files or "")
        if not fuente.exists():
            raise Rechazo(f"{origen.name} ya no está en la papelera.")
    else:
        fuente = Path(op.real_destino or op.destino or "")
        if not fuente.exists():
            raise Rechazo(f"{fuente.name} ya no está donde lo dejé.")
    origen.parent.mkdir(parents=True, exist_ok=True)
    destino = _libre(origen.parent, origen.name, op.es_dir)
    shutil.move(str(fuente), str(destino))
    if accion == "borrar" and op.trash_info:
        Path(op.trash_info).unlink(missing_ok=True)


def deshacer() -> dict:
    """Revierte la última acción completa que no esté ya deshecha."""
    lineas = _leer_diario()
    idx = next((i for i in range(len(lineas) - 1, -1, -1) if not lineas[i].get("deshecha")), None)
    if idx is None:
        return {"ok": False, "error": "No tengo nada que deshacer."}
    acc = lineas[idx]
    hechas, avisos = 0, []
    for d in reversed(acc["ops"]):
        try:
            _revertir(acc["accion"], Op(**d))
            hechas += 1
        except (OSError, Rechazo) as e:
            avisos.append(str(e.strerror if isinstance(e, OSError) and e.strerror else e))
    if hechas == 0:
        return {"ok": False, "error": "No he podido deshacerlo: " + (avisos[0] if avisos else "no queda nada")}
    lineas[idx]["deshecha"] = True
    _escribir_diario(lineas)
    verbo = {"borrar": "Recuperado de la papelera", "mover": "Devuelto a su sitio",
             "renombrar": "Devuelto a su nombre", "crear_carpeta": "Carpeta eliminada"}[acc["accion"]]
    decir = f"Hecho. {verbo}."
    if avisos:
        decir += f" {len(avisos)} no se han podido."
    carpeta = str(Path(acc["ops"][0]["origen"]).parent)
    return {"ok": True, "decir": decir, "n": hechas, "accion": acc["accion"], "carpeta": carpeta}


# ------------------------------------------------- planes pendientes (confirmación)

_PLANES: dict[str, Plan] = {}
_LOCK = threading.RLock()


def registrar(plan: Plan) -> Plan:
    """Deja el plan pendiente. Solo hay uno a la vez: el anterior se cancela."""
    with _LOCK:
        for p in _PLANES.values():
            if p.estado == "pendiente":
                p.estado = "cancelado"
                p.mensaje = "Sustituido por otra petición."
                p.evento.set()
        for pid in [k for k, p in _PLANES.items() if p.estado != "pendiente" and ahora() - p.creado > 600]:
            del _PLANES[pid]
        _PLANES[plan.id] = plan
        return plan


def _caducar_si_toca(plan: Plan) -> None:
    if plan.estado == "pendiente" and ahora() > plan.expira:
        plan.estado = "caducado"
        plan.mensaje = "Se me pasó el tiempo; vuelve a pedírmelo."
        plan.evento.set()


def plan_por_id(plan_id: str) -> Plan | None:
    with _LOCK:
        p = _PLANES.get(plan_id)
        if p is not None:
            _caducar_si_toca(p)
        return p


def pendiente() -> Plan | None:
    with _LOCK:
        res = None
        for p in _PLANES.values():
            _caducar_si_toca(p)
            if p.estado == "pendiente":
                res = p
        return res


def resolver(plan_id: str, si: bool) -> dict:
    """Confirma (ejecuta) o cancela un plan pendiente. Idempotente: solo actúa una vez."""
    with _LOCK:
        plan = _PLANES.get(plan_id)
        if plan is None:
            return {"ok": False, "error": "No hay nada pendiente."}
        _caducar_si_toca(plan)
        if plan.estado != "pendiente":
            return {"ok": False, "estado": plan.estado, "plan": plan,
                    "error": plan.mensaje or f"Eso ya está {plan.estado}."}
        if si:
            res = ejecutar(plan)
        else:
            plan.estado = "cancelado"
            res = {"ok": True, "decir": "Vale, no hago nada."}
        plan.mensaje = res.get("decir") or res.get("error") or ""
        plan.evento.set()
        return {**res, "estado": plan.estado, "plan": plan}
````

- [ ] **Step 4: Ejecutar los tests y verificar que pasan**

Run: `cd assistant && python3 -m pytest -q -p no:cacheprovider tests/test_archivos.py && python3 -m pytest -q -p no:cacheprovider tests`
Expected: `36 passed` en el primero y toda la suite en verde (los 121 previos + 36).

- [ ] **Step 5: Commit**

```bash
git add assistant/laura/archivos.py assistant/tests/conftest.py assistant/tests/test_archivos.py
git commit -m "feat(laura-archivos): motor de archivos con papelera, diario y deshacer"
```

---

### Task 2: La escena holográfica gestiona los planes (panel de confirmación, clic, fx, relistado)

**Files:**
- Modify: `assistant/laura/holo.py` (parche con anclas verificadas)
- Test: `assistant/tests/test_holo_archivos.py`

**Interfaces:**
- Consumes: `archivos.resolver`, `archivos.pendiente`, `Plan.titulo()`, `Plan.a_payload()` (Task 1); `Escena.listador` ya existente (`self._listar_default` → `warp._warp("listar", ruta)`).
- Produces: `Escena.carpeta`, `Escena.retraso_relistado`, `Escena.listar(titulo, entradas, carpeta=None)`, `Escena.mostrar_confirmacion(plan) -> dict`, `Escena.resolver_plan(plan_id, si) -> dict`, `Escena.tras_plan(plan)`, `Escena.refrescar(carpeta=None)`; comandos de control `holo-confirm <plan_id>` / `holo-cancel <plan_id>`; eventos `{"type":"holo","op":"confirm"|"fx",…}` (el `fx` lleva `fx`, `ids` y `filas`).

- [ ] **Step 1: Escribir los tests**

Crea `assistant/tests/test_holo_archivos.py`:

````python
"""La escena holográfica con planes de archivos: panel de confirmación, clic, fx y relistado."""
from conftest import crear
from laura import archivos as a
from test_holo import nueva


def preparar(env, n=3):
    esc, bus, _ = nueva()
    esc.retraso_relistado = 0
    fs = [crear(env, f"Descargas/f{i}.txt") for i in range(n)]
    esc.listar("Descargas", [{"ruta": str(f), "nombre": f.name, "tamano": 4, "modificado": 1.0} for f in fs],
               carpeta=str(env / "Descargas"))
    return esc, bus, fs


def test_mostrar_confirmacion(env):
    esc, bus, fs = preparar(env)
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    panel = esc.mostrar_confirmacion(plan)
    assert panel["kind"] == "confirmar" and panel["payload"]["plan"] == plan.id
    assert bus.ev[-1]["op"] == "confirm" and "confirmar" in esc.paneles


def test_clic_confirmar_ejecuta_anima_y_relista(env):
    esc, bus, fs = preparar(env)
    esc.listador = lambda ruta: {"ok": True, "candidatos": [
        {"ruta": str(f), "nombre": f.name, "tamano": 4, "modificado": 1.0} for f in fs[1:]]}
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    esc.mostrar_confirmacion(plan)
    r = esc.control("holo-confirm", plan.id)
    assert r["ok"] and r["estado"] == "ejecutado" and not fs[0].exists()
    assert "confirmar" not in esc.paneles
    fx = next(e for e in bus.ev if e["op"] == "fx")
    assert fx["fx"] == "borrar" and fx["filas"] == [1]
    assert [it.nombre for it in esc.items] == ["f1.txt", "f2.txt"]     # relistado
    assert bus.ops()[-1] == "list"


def test_clic_cancelar_no_toca_nada(env):
    esc, bus, fs = preparar(env)
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    esc.mostrar_confirmacion(plan)
    r = esc.control("holo-cancel", plan.id)
    assert r["ok"] and r["estado"] == "cancelado" and fs[0].exists()
    assert "confirmar" not in esc.paneles and "fx" not in bus.ops()


def test_confirmar_plan_desconocido_o_repetido(env):
    esc, bus, fs = preparar(env)
    assert esc.control("holo-confirm", "nope")["ok"] is False
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    esc.control("holo-confirm", plan.id)
    assert esc.control("holo-confirm", plan.id)["ok"] is False          # no se ejecuta dos veces


def test_confirmacion_sola_vacia_la_escena(env):
    esc, bus, _ = nueva()
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    esc.mostrar_confirmacion(plan)
    esc.resolver_plan(plan.id, False)
    assert esc.paneles == {} and bus.ops()[-1] == "clear"


def test_caducar_quita_el_panel_de_un_plan_vencido(env, monkeypatch):
    esc, bus, fs = preparar(env)
    t = {"v": 1000.0}
    monkeypatch.setattr(a, "ahora", lambda: t["v"])
    plan = a.registrar(a.planificar_borrar([str(fs[0])]))
    esc.mostrar_confirmacion(plan)
    t["v"] += 61
    esc.caducar()
    assert "confirmar" not in esc.paneles and "lista" in esc.paneles


def test_operacion_directa_sin_confirmacion_anima_y_relista(env):
    esc, bus, fs = preparar(env)
    esc.listador = lambda ruta: {"ok": True, "candidatos": []}
    plan = a.planificar_renombrar(str(fs[1]), "otro.txt")
    a.ejecutar(plan)
    esc.tras_plan(plan)
    assert next(e for e in bus.ev if e["op"] == "fx")["filas"] == [2]
````

- [ ] **Step 2: Verificar que fallan**

Run: `cd assistant && python3 -m pytest -q -p no:cacheprovider tests/test_holo_archivos.py`
Expected: FAIL (`AttributeError: … 'Escena' … no attribute 'mostrar_confirmacion'` / `TypeError: listar() got an unexpected keyword argument 'carpeta'`).

- [ ] **Step 3: Aplicar el parche a `holo.py`**

> `holo.py` puede tener cambios sin commitear de otro agente (p. ej. la serialización de `abiertos` en `holo-open`); el parche usa anclas exactas y no los toca. Si un `assert` de ancla falla, lee el archivo y adapta el ancla, no fuerces nada.

Guarda como `/tmp/p_holo.py` (o en el scratchpad) y ejecútalo desde `assistant/`: `python3 /tmp/p_holo.py`

````python
"""Parche: la escena holográfica gestiona planes de archivos. Ejecutar desde assistant/."""
from pathlib import Path


def parchear(ruta: str, cambios: list[tuple[str, str]]) -> None:
    p = Path(ruta)
    s = p.read_text()
    for viejo, nuevo in cambios:
        assert s.count(viejo) == 1, f"ancla no encontrada o repetida en {ruta}: {viejo!r}"
        s = s.replace(viejo, nuevo)
    p.write_text(s)


parchear("laura/holo.py", [
    ("from . import holo_preview\n", "from . import archivos, holo_preview\n"),
    ("        self.listador: Callable[[str], dict] = self._listar_default\n",
     """        self.listador: Callable[[str], dict] = self._listar_default
        self.carpeta: str | None = None        # carpeta de la lista que se ve (para relistar tras operar)
        self.retraso_relistado: float = 0.9    # deja que se vea la animación antes de relistar
"""),
    ('''        ids: list[str] | None = None,
    ) -> None:
        """Emite un evento de holograma con el estado completo de la escena."""''',
     '''        ids: list[str] | None = None,
        **extra,
    ) -> None:
        """Emite un evento de holograma con el estado completo de la escena."""'''),
    ('''            "ids": ids,
        }
        if self.emit is not None:''',
     '''            "ids": ids,
            **extra,
        }
        if self.emit is not None:'''),
    ('''    def listar(self, titulo: str, entradas: list[dict]) -> list[Item]:
        """Crea o sustituye la lista de archivos, cerrando los visores abiertos."""
        with self._lock:
            self._tocar()
            self.paneles.clear()''',
     '''    def listar(self, titulo: str, entradas: list[dict], carpeta: str | None = None) -> list[Item]:
        """Crea o sustituye la lista de archivos, cerrando los visores abiertos.
        `carpeta` (si se conoce) permite relistar tras mover, borrar o renombrar."""
        with self._lock:
            self._tocar()
            self.carpeta = carpeta
            self.paneles.clear()'''),
    ('        items = self.listar(item.nombre, d.get("candidatos") or [])\n',
     '        items = self.listar(item.nombre, d.get("candidatos") or [], carpeta=item.ruta)\n'),
    ('''    def caducar(self) -> bool:
        """Si ha vencido el tiempo de inactividad, vacía la escena y emite clear."""
        with self._lock:
''',
     '''    # ------------------------------------------------------------ archivos (planes)

    def _quitar_panel(self, pid: str) -> None:
        """Quita un panel (con el lock tomado); si era el último, vacía la escena."""
        if pid not in self.paneles:
            return
        del self.paneles[pid]
        if not self.paneles:
            self.items.clear()
            self.seleccionado = None
            self._emit("clear")
        else:
            self._emit("close", ids=[pid])

    def mostrar_confirmacion(self, plan) -> dict:
        """Panel holográfico de confirmación de un plan pendiente."""
        with self._lock:
            self._tocar()
            panel = {"id": "confirmar", "kind": "confirmar", "titulo": plan.titulo(),
                     "item_n": None, "payload": plan.a_payload()}
            self.paneles["confirmar"] = panel
            self._emit("confirm", panel=panel)
            return panel

    def resolver_plan(self, plan_id: str, si: bool) -> dict:
        """Confirma o cancela un plan (voz o clic): ejecuta una sola vez y actualiza la pantalla."""
        res = archivos.resolver(plan_id, si)
        plan = res.get("plan")
        if plan is not None:
            self.tras_plan(plan)
        return res

    def tras_plan(self, plan) -> None:
        """Quita el panel de confirmación y, si el plan se ejecutó, anima y relista."""
        with self._lock:
            self._tocar()
            self._quitar_panel("confirmar")
            if plan.estado != "ejecutado" or not self.paneles:
                return
            origenes = {o.origen for o in plan.ops}
            filas = [it.n for it in self.items if it.ruta in origenes]
            ids = [f"v{n}" for n in filas if f"v{n}" in self.paneles]
            self._emit("fx", ids=ids, fx=plan.accion, filas=filas)
            carpeta = plan.carpeta if plan.accion == "crear_carpeta" else str(Path(plan.ops[0].origen).parent)
        if self.retraso_relistado > 0:
            t = threading.Timer(self.retraso_relistado, self.refrescar, [carpeta])
            t.daemon = True
            t.start()
        else:
            self.refrescar(carpeta)

    def refrescar(self, carpeta: str | None = None) -> None:
        """Vuelve a listar la carpeta de la lista que se ve (los números cambian)."""
        with self._lock:
            destino = self.carpeta or carpeta
            if "lista" not in self.paneles or not destino:
                return
            d = self.listador(destino)
            if d.get("ok"):
                self.listar(self.paneles["lista"]["titulo"], d.get("candidatos") or [], carpeta=destino)

    def caducar(self) -> bool:
        """Si ha vencido el tiempo de inactividad, vacía la escena y emite clear."""
        with self._lock:
            if "confirmar" in self.paneles and archivos.pendiente() is None:
                self._quitar_panel("confirmar")
'''),
    ('''        if cmd == "holo-select":''',
     '''        if cmd in ("holo-confirm", "holo-cancel"):
            res = self.resolver_plan(arg.strip(), cmd == "holo-confirm")
            return {"ok": bool(res.get("ok")), "estado": res.get("estado"),
                    "error": res.get("error"), "decir": res.get("decir")}

        if cmd == "holo-select":'''),
])
print("parche de holo.py aplicado")
````

- [ ] **Step 4: Verificar que pasan y que no hay regresiones**

Run: `cd assistant && python3 -m pytest -q -p no:cacheprovider tests`
Expected: todo en verde (incluye los tests previos de `test_holo.py` y `test_tools_holo.py`).

- [ ] **Step 5: Commit**

```bash
git add assistant/laura/holo.py assistant/tests/test_holo_archivos.py
git commit -m "feat(laura-archivos): la escena holográfica gestiona planes (confirmar, fx, relistar)"
```

---

### Task 3: Confirmación por voz o panel (módulo puro)

**Files:**
- Create: `assistant/laura/confirmar_archivos.py`
- Test: `assistant/tests/test_confirmar_archivos.py`

**Interfaces:**
- Consumes: `archivos.pendiente()`, `Plan.pregunta()`, `Plan.evento`, `Plan.mensaje`, `Escena.resolver_plan(plan_id, si)` (Tasks 1–2).
- Produces: `interpretar(texto) -> bool | None`; `confirmar(plan, escena, decir, escuchar, cancelado=lambda: False) -> str` (estado final del plan); `responder_pendiente(texto, escena, decir) -> bool`.

- [ ] **Step 1: Escribir los tests**

Crea `assistant/tests/test_confirmar_archivos.py`:

````python
"""Confirmación por voz o panel: nada se ejecuta sin un sí explícito."""
import pytest

from conftest import crear
from laura import archivos as a
from laura import confirmar_archivos as c
from test_holo import nueva


@pytest.mark.parametrize("texto,esperado", [
    ("sí", True), ("vale, hazlo", True), ("Sí, Laura", True), ("confirmo", True),
    ("no", False), ("mejor no", False), ("cancela", False), ("no, déjalo",  False),
    ("el martes quedamos para comer", None), ("", None), ("bórralo todo y también la carpeta", None)])
def test_interpretar(texto, esperado):
    assert c.interpretar(texto) is esperado


def montar(env):
    esc, bus, _ = nueva()
    esc.retraso_relistado = 0
    f = crear(env, "Descargas/a.txt")
    plan = a.registrar(a.planificar_borrar([str(f)]))
    esc.mostrar_confirmacion(plan)
    dicho = []
    return esc, plan, f, dicho


def test_voz_si_ejecuta(env):
    esc, plan, f, dicho = montar(env)
    est = c.confirmar(plan, esc, dicho.append, lambda ev: "sí, adelante")
    assert est == "ejecutado" and not f.exists()
    assert dicho[0].startswith("Voy a mandar a la papelera") and "papelera" in dicho[-1]


def test_voz_no_o_ambigua_no_ejecuta(env):
    for frase in ("no", "mejor lo dejamos para otro día"):
        esc, plan, f, dicho = montar(env)
        est = c.confirmar(plan, esc, dicho.append, lambda ev, fr=frase: fr)
        assert est == "cancelado" and f.exists()
        a._PLANES.clear()
        f.unlink()


def test_el_panel_resuelve_mientras_escucha(env):
    esc, plan, f, dicho = montar(env)

    def escuchar(ev):
        esc.control("holo-confirm", plan.id)       # clic mientras Laura escucha
        return None

    est = c.confirmar(plan, esc, dicho.append, escuchar)
    assert est == "ejecutado" and not f.exists()
    assert dicho[-1].startswith("Hecho")           # y lo dice, sin ejecutar dos veces
    assert len(list((env / "Trash" / "files").iterdir())) == 1


def test_silencio_deja_pendiente(env):
    esc, plan, f, dicho = montar(env)
    est = c.confirmar(plan, esc, dicho.append, lambda ev: None)
    assert est == "pendiente" and f.exists() and a.pendiente() is plan
    assert dicho[-1] == "Lo dejo pendiente en el panel."


def test_cancelado_por_atajo_cancela_el_plan(env):
    esc, plan, f, dicho = montar(env)
    est = c.confirmar(plan, esc, dicho.append, lambda ev: "sí", cancelado=lambda: True)
    assert est == "cancelado" and f.exists()


def test_responder_pendiente_tarde(env):
    esc, plan, f, dicho = montar(env)
    assert c.responder_pendiente("qué hora es", esc, dicho.append) is False and f.exists()
    assert c.responder_pendiente("vale", esc, dicho.append) is True and not f.exists()
    assert c.responder_pendiente("vale", esc, dicho.append) is False       # ya no hay nada pendiente
````

- [ ] **Step 2: Verificar que fallan**

Run: `cd assistant && python3 -m pytest -q -p no:cacheprovider tests/test_confirmar_archivos.py`
Expected: FAIL `ImportError: cannot import name 'confirmar_archivos' from 'laura'`.

- [ ] **Step 3: Implementar el módulo**

Crea `assistant/laura/confirmar_archivos.py`:

````python
"""Confirmación de planes de archivos por voz o panel, sin audio ni STT (se inyectan).

`escalation.py` la usa con el micro y la voz reales; los tests, con funciones falsas."""
from __future__ import annotations

import re
from typing import Callable

from . import archivos

_SI = {"si", "sí", "vale", "adelante", "hazlo", "dale", "venga", "claro", "correcto", "confirmo",
       "confirmado", "ok", "perfecto"}
_NO = {"no", "nanay", "olvidalo", "olvídalo", "cancela", "cancelar", "cancélalo", "cancelalo",
       "mejor", "nada", "para"}


def interpretar(texto: str) -> bool | None:
    """«sí / vale / hazlo» -> True; «no / cancela / mejor no» -> False; otra cosa -> None.
    Solo frases cortas (máx. 4 palabras sin «Laura»): una frase larga no es un sí o no."""
    palabras = [w for w in re.findall(r"[\wáéíóúüñ]+", (texto or "").lower()) if w != "laura"]
    if not palabras or len(palabras) > 4:
        return None
    if palabras[0] in _NO:
        return False
    if any(w in _SI for w in palabras):
        return True
    return None


def confirmar(plan, escena, decir: Callable[[str], None],
              escuchar: Callable[[object], str | None],
              cancelado: Callable[[], bool] = lambda: False) -> str:
    """Pregunta, escucha un sí/no a la vez que espera al panel (`plan.evento`) y resuelve el plan.

    `decir(texto)` habla; `escuchar(evento)` devuelve la frase dicha, o None si hubo silencio o
    se activó `evento` (lo resolvió el panel). Devuelve el estado final del plan."""
    decir(plan.pregunta())
    if cancelado():
        escena.resolver_plan(plan.id, False)
        return plan.estado
    if not plan.evento.is_set():
        frase = escuchar(plan.evento)
        if cancelado():
            escena.resolver_plan(plan.id, False)
            return plan.estado
    else:
        frase = None
    if plan.evento.is_set():                       # lo resolvió el panel (o caducó)
        if plan.mensaje:
            decir(plan.mensaje)
        return plan.estado
    if not frase:
        decir("Lo dejo pendiente en el panel.")
        return plan.estado
    res = escena.resolver_plan(plan.id, bool(interpretar(frase)))   # ambiguo = no
    decir(res.get("decir") or res.get("error") or "Hecho.")
    return plan.estado


def responder_pendiente(texto: str, escena, decir: Callable[[str], None]) -> bool:
    """Si hay un plan pendiente y `texto` es un sí/no claro, lo resuelve sin pasar por el LLM.
    Devuelve True si lo ha gestionado (Alberto contestó tarde, tras «lo dejo pendiente»)."""
    plan = archivos.pendiente()
    if plan is None:
        return False
    r = interpretar(texto)
    if r is None:
        return False
    res = escena.resolver_plan(plan.id, r)
    decir(res.get("decir") or res.get("error") or "Hecho.")
    return True
````

- [ ] **Step 4: Verificar que pasan**

Run: `cd assistant && python3 -m pytest -q -p no:cacheprovider tests`
Expected: todo en verde.

- [ ] **Step 5: Commit**

```bash
git add assistant/laura/confirmar_archivos.py assistant/tests/test_confirmar_archivos.py
git commit -m "feat(laura-archivos): confirmación por voz o panel (sin ejecutar sin un sí explícito)"
```

---

### Task 4: Tools de archivos (contextuales) y efecto `confirm:archivos`

**Files:**
- Create: `assistant/laura/tools/archivos.py`
- Modify: `assistant/laura/tools/__init__.py`, `assistant/laura/llm.py` (parche)
- Modify: `assistant/config.toml` (`num_ctx`)
- Test: `assistant/tests/test_tools_archivos.py`, `assistant/tests/test_tools_activas.py`

**Interfaces:**
- Consumes: `archivos.*` (Task 1), `holo.escena()` con `carpeta`, `mostrar_confirmacion`, `tras_plan`, `refrescar` (Task 2).
- Produces: tools `borrar_archivos(numeros)`, `mover_archivos(destino, numeros)`, `renombrar_archivo(nombre, numero)`, `crear_carpeta(nombre, en)`, `deshacer_archivos()`; `tools.activas(texto) -> list[dict]`; `Tool.cuando`; el efecto `confirm:archivos` devuelve a `converse()` `{"destino": "archivos", "peticion": <plan_id>}` (lo recoge `escalation._confirm_and_run_escalation`, Task 5).

- [ ] **Step 1: Escribir los tests**

Crea `assistant/tests/test_tools_archivos.py`:

````python
"""Tools de archivos: solo planifican; el LLM nunca ejecuta un borrado."""
import pytest

from conftest import crear
from laura import archivos as a
from laura import holo
from laura.tools import archivos as t
from laura import tools as tools_mod
from test_holo import nueva


@pytest.fixture
def entorno(env, monkeypatch):
    esc, bus, _ = nueva()
    esc.retraso_relistado = 0
    monkeypatch.setattr(holo, "escena", lambda: esc)
    fs = [crear(env, f"Descargas/f{i}.txt") for i in range(3)]
    esc.listar("Descargas", [{"ruta": str(f), "nombre": f.name, "tamano": 4, "modificado": 1.0} for f in fs],
               carpeta=str(env / "Descargas"))
    esc.listador = lambda ruta: {"ok": True, "candidatos": []}
    return env, esc, bus, fs


def test_efectos_registrados():
    for n in ("borrar_archivos", "mover_archivos", "renombrar_archivo"):
        assert tools_mod.effect_of(n) == "confirm:archivos"
    assert tools_mod.effect_of("crear_carpeta") is None and tools_mod.effect_of("deshacer_archivos") is None


def test_borrar_solo_planifica(entorno):
    env, esc, bus, fs = entorno
    r = t.borrar_archivos(numeros=[2])
    assert r["ok"] and r["confirmar"] is True and fs[1].exists()
    assert a.pendiente().id == r["plan"] and "confirmar" in esc.paneles
    assert r["decir"].startswith("Voy a mandar a la papelera un archivo")


def test_borrar_sin_numero_usa_el_seleccionado(entorno):
    env, esc, bus, fs = entorno
    esc.seleccionar(3)
    assert t.borrar_archivos()["confirmar"] and a.pendiente().ops[0].origen == str(fs[2])


def test_borrar_sin_nada_seleccionado(entorno):
    r = t.borrar_archivos()
    assert r["ok"] is False and "seleccionado" in r["error"]


def test_numero_fuera_de_rango(entorno):
    assert t.borrar_archivos(numeros=[9])["error"] == "No veo la número 9."


def test_mover_uno_se_hace_directo(entorno):
    env, esc, bus, fs = entorno
    r = t.mover_archivos("Documentos", numeros=[1])
    assert r["ok"] and not r.get("confirmar") and (env / "Documentos" / "f0.txt").exists()
    assert "fx" in bus.ops()


def test_mover_a_carpeta_inexistente(entorno):
    assert "No encuentro" in t.mover_archivos("Nada", numeros=[1])["error"]


def test_mover_fuera_de_las_raices(entorno):
    env, *_ = entorno
    assert "fuera de tus carpetas" in t.mover_archivos(str(env / "otro"), numeros=[1])["error"]


def test_renombrar(entorno):
    env, esc, bus, fs = entorno
    r = t.renombrar_archivo("nuevo.txt", numero=1)
    assert r["ok"] and (env / "Descargas" / "nuevo.txt").exists()


def test_crear_carpeta_en_la_carpeta_de_la_lista(entorno):
    env, *_ = entorno
    r = t.crear_carpeta("Facturas")
    assert r["ok"] and (env / "Descargas" / "Facturas").is_dir()
    assert "Ya existe" in t.crear_carpeta("Facturas")["error"]


def test_crear_carpeta_en_otra(entorno):
    env, *_ = entorno
    assert t.crear_carpeta("Uni", en="Documentos")["ok"] and (env / "Documentos" / "Uni").is_dir()


def test_deshacer(entorno):
    env, esc, bus, fs = entorno
    assert t.deshacer_archivos()["ok"] is False
    t.renombrar_archivo("nuevo.txt", numero=1)
    r = t.deshacer_archivos()
    assert r["ok"] and fs[0].exists()


def test_confirmar_y_borrar_de_verdad(entorno):
    env, esc, bus, fs = entorno
    plan_id = t.borrar_archivos(numeros=[1, 3])["plan"]
    assert fs[0].exists() and fs[2].exists()                 # planificar no borra
    esc.control("holo-confirm", plan_id)
    assert not fs[0].exists() and not fs[2].exists() and fs[1].exists()
````

Crea `assistant/tests/test_tools_activas.py`:

````python
"""Las tools de archivos solo se ofrecen al LLM cuando la frase las pide (contexto justo)."""
import pytest

from laura import tools as tools_mod

ARCH = {"borrar_archivos", "mover_archivos", "renombrar_archivo", "crear_carpeta", "deshacer_archivos"}


def nombres(texto):
    return {t["function"]["name"] for t in tools_mod.activas(texto)}


@pytest.mark.parametrize("frase", ["borra la 2", "elimina esas tres", "mueve la 3 a Universidad",
                                   "renombra la uno a factura", "crea una carpeta que se llame Facturas",
                                   "deshaz lo último", "recupera el archivo", "pásala a Documentos",
                                   "cámbiale el nombre a la 1"])
def test_se_ofrecen_cuando_se_piden(frase):
    assert ARCH <= nombres(frase)


@pytest.mark.parametrize("frase", ["hola", "pon música", "qué tiempo hace", "abre la 2", "enséñame las descargas",
                                   "quita el volumen", "mándame la 3 al móvil"])
def test_no_gastan_contexto_si_no_se_piden(frase):
    assert not (ARCH & nombres(frase))


def test_las_de_siempre_estan_siempre():
    base = nombres("hola")
    assert {"mostrar_archivos", "abrir", "warp", "spotify"} <= base
    assert len(tools_mod.TOOLS) == len(base) + len(ARCH)
````

- [ ] **Step 2: Verificar que fallan**

Run: `cd assistant && python3 -m pytest -q -p no:cacheprovider tests/test_tools_archivos.py tests/test_tools_activas.py`
Expected: FAIL (`ImportError: cannot import name 'archivos' from 'laura.tools'` / `AttributeError: module 'laura.tools' has no attribute 'activas'`).

- [ ] **Step 3: Crear el módulo de tools**

Crea `assistant/laura/tools/archivos.py`:

````python
"""Tools de Laura para gestionar archivos. Solo PLANIFICAN: confirmar y ejecutar lo hace el
daemon (ver `confirmar_archivos.py`); el LLM nunca borra ni mueve nada por su cuenta."""
from __future__ import annotations

import re
from pathlib import Path

from .. import archivos, holo
from . import tool

# Las tools de archivos solo se ofrecen al LLM si la frase habla de ello (ahorra ~650 tokens).
_PIDE = re.compile(r"\b(borra\w*|elimina\w*|mueve\w*|mover|renombra\w*|carpeta\w*|deshaz|deshacer|"
                   r"recupera\w*|papelera|nombre|p[aá]sa(?:la|lo|las|los|r)\b)", re.I)


def _hace_falta(texto: str) -> bool:
    return bool(_PIDE.search(texto))


_NUMS = {"type": "array", "items": {"type": "integer"}, "description": "números de la lista en pantalla"}


def _rutas(numeros: list[int] | None) -> list[str]:
    esc = holo.escena()
    out: list[str] = []
    for n in numeros or []:
        it = esc.resolver(n)
        if it is None:
            raise archivos.Rechazo(f"No veo la número {n}.")
        out.append(it.ruta)
    if not out:
        it = esc.resolver(None)
        if it is None:
            raise archivos.Rechazo("¿Cuál? No veo ninguno seleccionado.")
        out.append(it.ruta)
    return out


def _resultado(plan: archivos.Plan) -> dict:
    esc = holo.escena()
    if plan.requiere_confirmacion:
        archivos.registrar(plan)
        esc.mostrar_confirmacion(plan)
        return {"ok": True, "confirmar": True, "plan": plan.id, "decir": plan.pregunta(),
                "resumen": plan.titulo()}
    res = archivos.ejecutar(plan)
    esc.tras_plan(plan)
    if not res.get("ok"):
        return {"ok": False, "error": res["error"]}
    return {"ok": True, "decir": res["decir"], "resumen": plan.titulo()}


@tool("borrar_archivos",
      "Borra (papelera, con confirmación del sistema): «borra la 2», «elimina esas». Sin números, el seleccionado.",
      {"numeros": _NUMS}, icon="delete", effect="confirm:archivos", cuando=_hace_falta)
def borrar_archivos(numeros: list[int] | None = None) -> dict:
    try:
        return _resultado(archivos.planificar_borrar(_rutas(numeros), holo.escena().carpeta))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("mover_archivos",
      "Mueve a otra carpeta: «mueve la 3 a Universidad».",
      {"destino": {"type": "string", "description": "carpeta: Documentos, Universidad…"}, "numeros": _NUMS},
      required=["destino"], icon="drive_file_move", effect="confirm:archivos", cuando=_hace_falta)
def mover_archivos(destino: str, numeros: list[int] | None = None) -> dict:
    try:
        carpeta = archivos.resolver_destino(destino, holo.escena().carpeta)
        return _resultado(archivos.planificar_mover(_rutas(numeros), carpeta))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("renombrar_archivo",
      "Renombra un archivo: «renombra la 1 a factura.pdf».",
      {"nombre": {"type": "string", "description": "nombre nuevo, con extensión"},
       "numero": {"type": "integer", "description": "número de la lista"}},
      required=["nombre"], icon="edit", effect="confirm:archivos", cuando=_hace_falta)
def renombrar_archivo(nombre: str, numero: int | None = None) -> dict:
    try:
        origen = _rutas([numero] if numero else None)[0]
        return _resultado(archivos.planificar_renombrar(origen, nombre))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("crear_carpeta",
      "Crea una carpeta: «crea una carpeta Facturas».",
      {"nombre": {"type": "string", "description": "nombre"},
       "en": {"type": "string", "description": "dónde (por defecto, la carpeta que se ve)"}},
      required=["nombre"], icon="create_new_folder", cuando=_hace_falta)
def crear_carpeta(nombre: str, en: str | None = None) -> dict:
    try:
        esc = holo.escena()
        if en:
            base = archivos.resolver_destino(en, esc.carpeta)
        elif esc.carpeta:
            base = Path(esc.carpeta)
        else:
            raise archivos.Rechazo("¿Dónde la creo?")
        return _resultado(archivos.planificar_crear_carpeta(nombre, base))
    except archivos.Rechazo as e:
        return {"ok": False, "error": str(e)}


@tool("deshacer_archivos",
      "Deshace lo último hecho con archivos: «deshaz», «recupéralo».",
      {}, icon="undo", cuando=_hace_falta)
def deshacer_archivos() -> dict:
    res = archivos.deshacer()
    if not res.get("ok"):
        return {"ok": False, "error": res["error"]}
    holo.escena().refrescar(res.get("carpeta"))
    return {"ok": True, "decir": res["decir"], "resumen": "Deshecho"}
````

- [ ] **Step 4: Aplicar el parche a `tools/__init__.py` y `llm.py`**

Guárdalo como `/tmp/p_tools.py` y ejecútalo desde `assistant/`: `python3 /tmp/p_tools.py`

````python
"""Parche: herramientas contextuales (solo se ofrecen al LLM si la frase las pide) y efecto
`confirm:archivos`. Ejecutar desde assistant/."""
from pathlib import Path


def parchear(ruta: str, cambios: list[tuple[str, str]]) -> None:
    p = Path(ruta)
    s = p.read_text()
    for viejo, nuevo in cambios:
        assert s.count(viejo) == 1, f"ancla no encontrada o repetida en {ruta}: {viejo!r}"
        s = s.replace(viejo, nuevo)
    p.write_text(s)


parchear("laura/tools/__init__.py", [
    ('''    effect: str | None = None
    wants_apps: bool = False
''', '''    effect: str | None = None
    wants_apps: bool = False
    cuando: Callable[[str], bool] | None = None   # herramienta contextual: solo se ofrece si esto es True
'''),
    ('''         effect: str | None = None, wants_apps: bool = False):''',
     '''         effect: str | None = None, wants_apps: bool = False,
         cuando: Callable[[str], bool] | None = None):'''),
    ('''        REGISTRY[name] = Tool(name, fn, schema, icon, effect, wants_apps)''',
     '''        REGISTRY[name] = Tool(name, fn, schema, icon, effect, wants_apps, cuando)'''),
    ('''def effect_of(name: str) -> str | None:''',
     '''def activas(texto: str) -> list[dict]:
    """Esquemas que se le pasan al LLM en esta petición. El contexto de Ollama va al límite
    (~7,5k de 8k tokens solo con las tools de siempre), así que las herramientas con `cuando`
    solo se ofrecen si la frase las menciona."""
    return [t.schema for t in REGISTRY.values() if t.cuando is None or t.cuando(texto or "")]


def effect_of(name: str) -> str | None:'''),
    ("spotify, dj, holo  # noqa", "spotify, dj, holo, archivos  # noqa"),
])

parchear("laura/llm.py", [
    ('''def _ollama_body(session: Session, stream: bool) -> bytes:
    return json.dumps({
        "model": session.model_now(),
        "messages": session.messages,
        "tools": tools_mod.TOOLS,''',
     '''def _ultimo_usuario(session: Session) -> str:
    return next((m.get("content") or "" for m in reversed(session.messages) if m.get("role") == "user"), "")


def _ollama_body(session: Session, stream: bool) -> bytes:
    return json.dumps({
        "model": session.model_now(),
        "messages": session.messages,
        "tools": tools_mod.activas(_ultimo_usuario(session)),'''),
    ('''            if eff == "confirm:comando" and result.get("confirmar"):
                return "", actions, {"destino": "comando", "peticion": result["comando"], "motivo": ""}
''',
     '''            if eff == "confirm:comando" and result.get("confirmar"):
                return "", actions, {"destino": "comando", "peticion": result["comando"], "motivo": ""}
            if eff == "confirm:archivos" and result.get("confirmar"):
                return "", actions, {"destino": "archivos", "peticion": result["plan"], "motivo": ""}
'''),
])
print("parche de tools/llm aplicado")
````

- [ ] **Step 5: Verificar que pasan toda la suite**

Run: `cd assistant && python3 -m pytest -q -p no:cacheprovider tests`
Expected: todo en verde.

- [ ] **Step 6: Presupuesto de contexto — medir y subir `num_ctx`**

Medido antes de este plan: 51 tools + system prompt + «hola» = **7.502 tokens** de 8.192; las 5 tools nuevas suman ~650. Como solo se ofrecen cuando la frase las pide, el uso normal no cambia, pero un turno de «borra la 2» necesita ~8.150 tokens + historial + respuesta. Hay que subir el contexto:

```bash
cd assistant
python3 - <<'EOF'
import re
p = "config.toml"
s = open(p).read()
assert "num_ctx = 8192" in s
s = s.replace("num_ctx = 8192", "num_ctx = 10240", 1)
open(p, "w").write(s)
EOF
grep -n '^num_ctx' config.toml
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader   # antes (~3,9 GB de 6,1 GB con Laura cargada)
systemctl --user restart laura && sleep 25
python3 - <<'EOF' 2>/dev/null
import json, requests
from laura.config import CFG
from laura import tools as T
def medir(texto):
    r = requests.post(CFG["llm"]["url"], json={"model": CFG["llm"]["model"], "stream": False, "tools": T.activas(texto),
        "messages": [{"role": "system", "content": CFG["llm"]["system_prompt"]}, {"role": "user", "content": texto}],
        "options": {"num_ctx": CFG["llm"]["num_ctx"], "num_predict": 1}}, timeout=180).json()
    return r.get("prompt_eval_count")
print("hola:", medir("hola"), "| borra la 2:", medir("borra la 2"), "| num_ctx:", CFG["llm"]["num_ctx"])
EOF
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader   # después
```

Expected: `hola` ≈ 7.5k y `borra la 2` ≈ 8.1k tokens, ambos < 10.240; la VRAM usada tras la petición queda **por debajo de ~5.600 MiB** (de 6.141). Si se pasa o hay OOM, **vuelve a `num_ctx = 8192`**, deja la tarea a medias y avisa a Alberto (habría que recortar el system prompt o las tools de siempre).

- [ ] **Step 7: Commit**

```bash
git add assistant/laura/tools/archivos.py assistant/laura/tools/__init__.py assistant/laura/llm.py \
        assistant/tests/test_tools_archivos.py assistant/tests/test_tools_activas.py assistant/config.toml
git commit -m "feat(laura-archivos): tools de archivos contextuales y efecto confirm:archivos"
```

---

### Task 5: Confirmación en el ciclo de voz (daemon)

**Files:**
- Modify: `assistant/laura/escalation.py`, `assistant/laura/daemon.py` (parche)

**Interfaces:**
- Consumes: `confirmar_archivos.confirmar/responder_pendiente` (Task 3), `archivos.plan_por_id` (Task 1), `Escena.resolver_plan` (Task 2), efecto `confirm:archivos` de `converse()` (Task 4), y de `escalation.py` ya existentes: `_say`, `listen`, `transcribe`, `bus`, `CFG`, `AnyEvent`.
- Produces: `escalation._confirm_archivos(session, plan_id, mode, cancel) -> bool` (siempre `False`: el ciclo sigue escuchando), `escalation.responder_pendiente_archivos(texto, mode, cancel) -> bool`, y el gancho en `daemon.cycle()` justo tras emitir el `transcript`.

Esta tarea no tiene test unitario (el módulo `escalation` arrastra audio y STT, que el entorno de tests no tiene); su lógica ya está cubierta en Task 3. Se verifica compilando y con una prueba real al final (Task 7).

- [ ] **Step 1: Aplicar el parche**

Guárdalo como `/tmp/p_daemon.py` y ejecútalo desde `assistant/`: `python3 /tmp/p_daemon.py`

````python
"""Parche: confirmación de planes de archivos en el ciclo de voz. Ejecutar desde assistant/."""
from pathlib import Path


def parchear(ruta: str, cambios: list[tuple[str, str]]) -> None:
    p = Path(ruta)
    s = p.read_text()
    for viejo, nuevo in cambios:
        assert s.count(viejo) == 1, f"ancla no encontrada o repetida en {ruta}: {viejo!r}"
        s = s.replace(viejo, nuevo)
    p.write_text(s)


parchear("laura/escalation.py", [
    # 1. Desvío al principio de la confirmación de escaladas
    ('''    destino = escalation.get("destino", "gemini")
    if destino == "comando":''',
     '''    destino = escalation.get("destino", "gemini")
    if destino == "archivos":
        return _confirm_archivos(session, escalation["peticion"], mode, cancel)
    if destino == "comando":'''),
    # 2. Funciones nuevas al final del archivo
    ('''    msg = "Vale, lo ejecuto." if r else "Vale, no lo ejecuto."
    session.add("assistant", msg)
    _say(msg, mode, cancel)
    return bool(r)
''',
     '''    msg = "Vale, lo ejecuto." if r else "Vale, no lo ejecuto."
    session.add("assistant", msg)
    _say(msg, mode, cancel)
    return bool(r)


def _confirm_archivos(session: Session, plan_id: str, mode: str, cancel: threading.Event) -> bool:
    """Un plan de archivos (borrar, mover en lote…) espera confirmación: Laura la pide por voz y
    escucha un sí/no a la vez que espera el clic del panel holográfico. Devuelve False: el ciclo
    sigue escuchando (no hay trabajo en segundo plano que lo releve)."""
    from . import archivos, confirmar_archivos
    from .holo import escena
    plan = archivos.plan_por_id(plan_id)
    if plan is None or plan.estado != "pendiente":
        return False

    def decir(texto: str) -> None:
        session.add("assistant", texto)
        _say(texto, mode, cancel)

    def escuchar(evento: threading.Event) -> str | None:
        bus.emit(type="state", value="listening", mode=mode)
        audio = listen(max_seconds=CFG["audio"]["max_seconds"], cancel=AnyEvent(cancel, evento),
                       start_grace=CFG["audio"].get("followup_seconds", 4))
        if cancel.is_set() or evento.is_set():
            return None
        bus.emit(type="state", value="thinking", mode=mode)
        frase = transcribe(audio)
        bus.emit(type="transcript", value=frase or "(sin respuesta)")
        return frase or None

    confirmar_archivos.confirmar(plan, escena(), decir, escuchar, cancelado=cancel.is_set)
    return False


def responder_pendiente_archivos(texto: str, mode: str, cancel: threading.Event) -> bool:
    """Alberto contesta «sí»/«no» tarde, tras «lo dejo pendiente en el panel»: se resuelve el plan
    sin pasar por el LLM. True si lo ha gestionado."""
    from . import confirmar_archivos
    from .holo import escena
    return confirmar_archivos.responder_pendiente(texto, escena(), lambda t: _say(t, mode, cancel))
'''),
])

parchear("laura/daemon.py", [
    ('''from .escalation import (_confirm_and_run_escalation, _handle_auto_escalation,
                         _match_auto_case, voice_yes_no)''',
     '''from .escalation import (_confirm_and_run_escalation, _handle_auto_escalation,
                         _match_auto_case, responder_pendiente_archivos, voice_yes_no)'''),
    ('''            bus.emit(type="transcript", value=text)
            bye = _is_farewell(text)
''',
     '''            bus.emit(type="transcript", value=text)
            bye = _is_farewell(text)

            # Un plan de archivos pendiente (borrar…) y Alberto contesta «sí»/«no» sin pasar por el LLM.
            if responder_pendiente_archivos(text, mode, turn_cancel):
                turns += 1
                if mode != "centro" or bye or turns >= max_turns:
                    break
                continue
'''),
])
print("parche de daemon aplicado")
````

- [ ] **Step 2: Comprobar que compila y que los tests siguen en verde**

Run: `cd assistant && python3 -m py_compile laura/escalation.py laura/daemon.py && python3 -m pytest -q -p no:cacheprovider tests`
Expected: sin salida de `py_compile` y todo en verde.

- [ ] **Step 3: Commit**

```bash
git add assistant/laura/escalation.py assistant/laura/daemon.py
git commit -m "feat(laura-archivos): confirmación de planes de archivos en el ciclo de voz"
```

---

### Task 6: Hologramas — panel «confirmar», animaciones y demo (QML)

**Files:**
- Create: `configs/quickshell/caelestia/modules/holo/HoloConfirm.qml`
- Modify: `HoloPanel.qml`, `HoloLayer.qml`, `HoloList.qml`, `HoloPlacer.js`, `test_placer.mjs` (en `configs/quickshell/caelestia/modules/holo/`) y `configs/quickshell/caelestia/modules/assistant/HoloState.qml` (parche)

**Interfaces:**
- Consumes: eventos `op:"confirm"` (panel `kind:"confirmar"`, payload de `Plan.a_payload()`) y `op:"fx"` (`fx`, `ids`, `filas`) de Task 2; control `holo-confirm`/`holo-cancel`.
- Produces: `HoloState.confirmar(plan)`, `HoloState.cancelar(plan)`, señal `HoloState.fx(ev)`, IPC `holo demoConfirm <borrar|mover>` y `holo demoResolver <true|false>`; `HoloPanel.desintegrar()` / `cerrarPanel()`.

- [ ] **Step 1: Avisar al otro agente**

```
SendMessage to=uds:/run/user/1000/cc-socks/134223.sock (linuxricing-12):
«Voy a editar HoloLayer.qml (fx de archivos y papelera) y HoloPanel/HoloList/HoloState para el panel de confirmación de archivos. No toco LauraOverlay.qml ni Laura.qml.»
```

- [ ] **Step 2: Test del placer (falla antes del parche)**

Añade primero la comprobación (la incluye el parche del Step 3). Para ver el fallo antes, ejecuta tras añadir solo el cambio de `test_placer.mjs`:

Run: `node configs/quickshell/caelestia/modules/holo/test_placer.mjs`
Expected (con solo el test nuevo): `ERROR: tamaño del panel de confirmación` y `FALLO`. Tras el Step 3: `OK`.

- [ ] **Step 3: Crear `HoloConfirm.qml` y aplicar el parche QML**

Crea `configs/quickshell/caelestia/modules/holo/HoloConfirm.qml`:

````qml
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Contenido del panel de confirmación de una acción sobre archivos (borrar, mover, renombrar…).
// Lista lo que se va a tocar, el tamaño total y dos botones. Una barra se vacía en un solo
// tramo hasta que el plan caduca (nada en bucle). También se puede decir «sí» / «no» por voz.
Item {
    id: root

    required property var panel

    readonly property var payload: panel?.payload ?? ({})
    readonly property bool borrar: payload.accion === "borrar"
    readonly property color acento: borrar ? Colours.palette.m3error : Colours.palette.m3primary
    // 1 = recién pedido, 0 = a punto de caducar
    property real restante: 1

    function tam(b: real): string {
        if (b >= 1073741824)
            return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576)
            return Math.round(b / 1048576) + " MB";
        if (b >= 1024)
            return Math.round(b / 1024) + " KB";
        return b + " B";
    }

    Component.onCompleted: {
        const total = Math.max(1, root.payload.segundos ?? 60);
        const queda = Math.max(0, (root.payload.expira ?? 0) - Date.now() / 1000);
        root.restante = Math.min(1, queda / total);
        cuenta.duration = queda * 1000;
        cuenta.start();
    }

    NumberAnimation {
        id: cuenta

        target: root
        property: "restante"
        to: 0
    }

    // Lo que se va a tocar
    Column {
        id: filas

        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14

        Repeater {
            model: root.payload.items ?? []

            Item {
                id: fila

                required property var modelData

                width: filas.width
                height: 26

                MaterialIcon {
                    id: ic

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: fila.modelData.es_dir ? "folder" : "draft"
                    fill: 1
                    fontStyle: Tokens.font.icon.size(16).build()
                    color: Qt.alpha(root.acento, 0.85)
                }
                StyledText {
                    anchors.left: ic.right
                    anchors.leftMargin: 8
                    anchors.right: tamTxt.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: fila.modelData.nuevo ? fila.modelData.nombre + "  →  " + fila.modelData.nuevo : fila.modelData.nombre
                    color: Colours.palette.m3onSurface
                    font.pixelSize: 13
                    elide: Text.ElideMiddle
                }
                StyledText {
                    id: tamTxt

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.tam(fila.modelData.tamano)
                    color: Colours.palette.m3onSurfaceVariant
                    font.pixelSize: 11
                }
            }
        }
        StyledText {
            visible: (root.payload.mas ?? 0) > 0
            height: visible ? 22 : 0
            text: "y " + root.payload.mas + " más…"
            color: Colours.palette.m3onSurfaceVariant
            font.pixelSize: 12
        }
    }

    // Resumen
    StyledText {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.bottom: botones.top
        anchors.bottomMargin: 10
        text: root.tam(root.payload.total_bytes ?? 0) + (root.payload.destino ? "  ·  a " + root.payload.destino : "")
        color: Colours.palette.m3onSurfaceVariant
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    // Botones (también vale decir «sí» / «no»)
    Row {
        id: botones

        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        spacing: 8

        Rectangle {
            width: lblNo.implicitWidth + 36
            height: 34
            radius: 17
            color: Qt.alpha(Colours.palette.m3onSurface, maNo.containsMouse ? 0.14 : 0.06)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3onSurface, 0.3)

            StyledText {
                id: lblNo

                anchors.centerIn: parent
                text: "Cancelar"
                color: Colours.palette.m3onSurface
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: maNo

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: HoloState.cancelar(root.payload.plan)
            }
        }
        Rectangle {
            width: lblSi.implicitWidth + 36
            height: 34
            radius: 17
            color: Qt.alpha(root.acento, maSi.containsMouse ? 1 : 0.88)

            StyledText {
                id: lblSi

                anchors.centerIn: parent
                text: root.borrar ? "Borrar" : "Confirmar"
                color: root.borrar ? Colours.palette.m3onError : Colours.palette.m3onPrimary
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: maSi

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: HoloState.confirmar(root.payload.plan)
            }
        }
    }

    // Cuenta atrás hasta que el plan caduca
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: 3
        width: parent.width * root.restante
        color: Qt.alpha(root.acento, 0.7)
    }
}
````

Guarda el parche como `/tmp/p_qml.py` y ejecútalo desde `configs/quickshell/caelestia/modules/` (comprueba cada ancla con `assert`; si alguna falla, otro agente ha tocado el archivo: léelo y adapta el ancla):

````python
"""Parche QML de la confirmación de archivos. Ejecutar desde configs/quickshell/caelestia/modules/."""
from pathlib import Path


def parchear(ruta: str, cambios: list[tuple[str, str]]) -> None:
    p = Path(ruta)
    s = p.read_text()
    for viejo, nuevo in cambios:
        assert s.count(viejo) == 1, f"ancla no encontrada o repetida en {ruta}: {viejo!r}"
        s = s.replace(viejo, nuevo)
    p.write_text(s)


# ------------------------------------------------------------------ HoloState.qml
parchear("assistant/HoloState.qml", [
    ('''    signal cleared()
''', '''    signal cleared()
    signal fx(var ev)
'''),
    ('''        case "clear":
            root.cleared();
            break;''', '''        case "fx":
            root.fx(ev);
            break;
        case "clear":
            root.cleared();
            break;'''),
    ('''    function externo(n: int): void {
        Laura.ctrl("holo-ext " + n);
    }
''', '''    function externo(n: int): void {
        Laura.ctrl("holo-ext " + n);
    }

    // Confirmación de un plan de archivos (borrar, mover…): el daemon ejecuta una sola vez
    function confirmar(plan: string): void {
        if (plan === "demo") {
            root._demoResolver(true);
            return;
        }
        Laura.ctrl("holo-confirm " + plan);
    }

    function cancelar(plan: string): void {
        if (plan === "demo") {
            root._demoResolver(false);
            return;
        }
        Laura.ctrl("holo-cancel " + plan);
    }
'''),
    ('''    IpcHandler {
        target: "holo"
''', '''    // Demo del panel de confirmación (sin daemon): `ipc call holo demoConfirm borrar|mover`
    function demoConfirm(accion: string): void {
        root.demo();
        demoTimer.stop();
        const ac = accion === "mover" ? "mover" : "borrar";
        const panel = {
            id: "confirmar",
            kind: "confirmar",
            titulo: ac === "borrar" ? "Borrar tres archivos" : "Mover tres archivos",
            item_n: null,
            payload: {
                plan: "demo",
                accion: ac,
                titulo: ac === "borrar" ? "Borrar tres archivos" : "Mover tres archivos",
                items: [
                    { nombre: "WhatsApp 21.04.jpg", tamano: 412000, es_dir: false, nuevo: null },
                    { nombre: "backup_config.tar.gz", tamano: 3200000, es_dir: false, nuevo: null },
                    { nombre: "dataset_v1.csv", tamano: 95000, es_dir: false, nuevo: null }
                ],
                mas: 0,
                total_bytes: 3707000,
                destino: ac === "mover" ? "Universidad" : null,
                segundos: 60,
                expira: Date.now() / 1000 + 60
            }
        };
        root.handle({
            type: "holo",
            op: "confirm",
            items: root.items,
            paneles: root.paneles.concat([panel]),
            seleccionado: null,
            panel: panel,
            ids: null
        });
    }

    function _demoResolver(si: bool): void {
        const sin = root.paneles.filter(p => p.id !== "confirmar");
        root.handle({
            type: "holo",
            op: "close",
            items: root.items,
            paneles: sin,
            seleccionado: null,
            panel: null,
            ids: ["confirmar"]
        });
        if (si)
            root.fx({ fx: "borrar", filas: [6, 7, 8], ids: [] });
    }

    IpcHandler {
        target: "holo"

        function demoConfirm(accion: string): void {
            root.demoConfirm(accion);
        }

        function demoResolver(si: bool): void {
            root._demoResolver(si);
        }
'''),
])

# ------------------------------------------------------------------ HoloPlacer.js
parchear("holo/HoloPlacer.js", [
    ('''    const tipo = (panel.payload && panel.payload.tipo) || panel.tipo || "otro";
''', '''    if (panel.kind === "confirmar") {
        const n = (panel.payload && Array.isArray(panel.payload.items)) ? Math.max(1, panel.payload.items.length) : 1;
        const mas = (panel.payload && panel.payload.mas > 0) ? 22 : 0;
        return { w: 400, h: 46 + 74 + 26 * n + mas + 64 };
    }

    const tipo = (panel.payload && panel.payload.tipo) || panel.tipo || "otro";
'''),
])

parchear("holo/test_placer.mjs", [
    ('''if (total === 0) {''', '''const sc = size({ kind: "confirmar", payload: { items: [1, 2, 3], mas: 0 } }, W, H);
if (sc.w !== 400 || sc.h !== 46 + 74 + 78 + 64) {
    console.error("ERROR: tamaño del panel de confirmación", sc);
    total++;
}
if (total === 0) {'''),
])

# ------------------------------------------------------------------ HoloLayer.qml
parchear("holo/HoloLayer.qml", [
    ('''            if (p.kind !== "visor" || np[p.id])
                continue;''', '''            if ((p.kind !== "visor" && p.kind !== "confirmar") || np[p.id])
                continue;'''),
    ('''        function onSent(pid: string): void {
            if (root.reg[pid])
                root.reg[pid].enviar();
        }
''', '''        function onSent(pid: string): void {
            if (root.reg[pid])
                root.reg[pid].enviar();
        }
        // Un plan de archivos se ha ejecutado: los visores afectados se van (borrar → papelera)
        function onFx(ev: var): void {
            if (!root.enfocada)
                return;
            for (const id of (ev.ids || [])) {
                const p = root.reg[id];
                if (!p)
                    continue;
                if (ev.fx === "borrar")
                    p.desintegrar();
                else
                    p.salir(0);
            }
            if (ev.fx === "borrar")
                papelera.pulsar();
        }
'''),
    ('''        // ------------------------------------------------------------ paneles
        Repeater {''', '''        // Papelera: aparece un instante en la esquina cuando se borra algo (one-shot)
        Item {
            id: papelera

            property real p: 0

            function pulsar(): void {
                pulso.restart();
            }

            x: root.width - 90
            y: root.height - 90
            width: 44
            height: 44
            z: 1
            opacity: p
            visible: p > 0.001
            scale: 0.8 + 0.4 * p

            Rectangle {
                anchors.fill: parent
                radius: 22
                color: Qt.alpha(Colours.palette.m3error, 0.18)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3error, 0.7)
            }
            MaterialIcon {
                anchors.centerIn: parent
                text: "delete"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3error
            }
            SequentialAnimation {
                id: pulso

                NumberAnimation {
                    target: papelera
                    property: "p"
                    to: 1
                    duration: 160
                    easing.type: Easing.OutCubic
                }
                PauseAnimation {
                    duration: 520
                }
                NumberAnimation {
                    target: papelera
                    property: "p"
                    to: 0
                    duration: 260
                    easing.type: Easing.InQuad
                }
            }
        }

        // ------------------------------------------------------------ paneles
        Repeater {'''),
])

# ------------------------------------------------------------------ HoloPanel.qml
parchear("holo/HoloPanel.qml", [
    ('''    readonly property bool esLista: panel?.kind === "lista"
''', '''    readonly property bool esLista: panel?.kind === "lista"
    readonly property bool esConfirmar: panel?.kind === "confirmar"
'''),
    ('''    readonly property color prim: cercaArriba ? Colours.palette.m3tertiary : Colours.palette.m3primary
''', '''    readonly property color prim: cercaArriba ? Colours.palette.m3tertiary : (esConfirmar && payload.accion === "borrar") ? Colours.palette.m3error : Colours.palette.m3primary
    readonly property string iconoConfirmar: ({
            borrar: "delete",
            mover: "drive_file_move",
            renombrar: "edit",
            crear_carpeta: "create_new_folder"
        })[payload.accion] ?? "help"
'''),
    ('''    property real sube: 0
''', '''    property real sube: 0
    // 0 = en su sitio, 1 = tragado por la papelera (esquina inferior derecha)
    property real cae: 0
'''),
    ('''    transform: Scale {
        origin.x: root.width / 2
        origin.y: 0
        xScale: 1 - 0.72 * root.sube
        yScale: 1 + 0.4 * root.sube
    }
''', '''    transform: [
        Scale {
            origin.x: root.width / 2
            origin.y: 0
            xScale: 1 - 0.72 * root.sube
            yScale: 1 + 0.4 * root.sube
        },
        Translate {
            x: (root.capa.width - 68 - (root.x + root.width / 2)) * root.cae
            y: (root.capa.height - 68 - (root.y + root.height / 2)) * root.cae
        }
    ]
'''),
    ('''    function enviar(): void {
        if (enviando || saliendo)
            return;''', '''    function desintegrar(): void {
        if (saliendo)
            return;
        saliendo = true;
        llegado = false;
        nacer.stop();
        desint.start();
    }
    // Cerrar con la ✕ o clic derecho: en una confirmación equivale a cancelar el plan
    function cerrarPanel(): void {
        if (esConfirmar)
            HoloState.cancelar(payload.plan);
        else
            HoloState.cerrar(pid);
    }
    function enviar(): void {
        if (enviando || saliendo)
            return;'''),
    ('''    SequentialAnimation {
        id: envio
''', '''    SequentialAnimation {
        id: desint

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "cae"
                to: 1
                duration: 460
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: root
                property: "escala"
                to: 0.05
                duration: 460
                easing.type: Easing.InCubic
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 200
                }
                NumberAnimation {
                    target: root
                    property: "opacity"
                    to: 0
                    duration: 260
                }
            }
        }
        ScriptAction {
            script: root.capa.quitar(root.pid)
        }
    }

    SequentialAnimation {
        id: envio
'''),
    ('''                    text: (root.panel?.titulo ?? "").startsWith("«") ? "search" : "folder_open"''',
     '''                    text: root.esConfirmar ? root.iconoConfirmar : ((root.panel?.titulo ?? "").startsWith("«") ? "search" : "folder_open")'''),
    ('''                text: {
                    if (root.enviado)''', '''                text: {
                    if (root.esConfirmar)
                        return "¿confirmas?";
                    if (root.enviado)'''),
    ('''                    onClicked: HoloState.cerrar(root.pid)''', '''                    onClicked: root.cerrarPanel()'''),
    ('''            readonly property string fichero: {
                if (root.esLista)''', '''            readonly property string fichero: {
                if (root.esConfirmar)
                    return "HoloConfirm.qml";
                if (root.esLista)'''),
    ('''        acceptedButtons: Qt.RightButton
        onTapped: HoloState.cerrar(root.pid)''', '''        acceptedButtons: Qt.RightButton
        onTapped: root.cerrarPanel()'''),
])

# ------------------------------------------------------------------ HoloList.qml
parchear("holo/HoloList.qml", [
    ('''            readonly property bool enviado: !!(fila.modelData && fila.modelData.enviado)
''', '''            readonly property bool enviado: !!(fila.modelData && fila.modelData.enviado)

            // Acción ejecutada sobre esta fila (borrada, movida…): se va deslizando y se apaga
            property real fuera: 0

            opacity: 1 - fuera
            transform: Translate {
                x: fila.fuera * 70
            }

            Connections {
                function onFx(ev: var): void {
                    if ((ev.filas || []).indexOf(fila.modelData.n) >= 0)
                        desaparece.start();
                }

                target: HoloState
            }
            NumberAnimation {
                id: desaparece

                target: fila
                property: "fuera"
                to: 1
                duration: 420
                easing.type: Easing.InCubic
            }
'''),
])
print("parche QML aplicado")
````

- [ ] **Step 4: Verificaciones estáticas**

```bash
cd configs/quickshell/caelestia/modules
node holo/test_placer.mjs | tail -2          # OK: sin solapes ni colisión…
for f in holo/HoloConfirm.qml holo/HoloPanel.qml holo/HoloLayer.qml holo/HoloList.qml assistant/HoloState.qml; do
  qmllint "$f" 2>&1 | grep -i -E 'syntax|unexpected|expected' ; done     # sin salida
```

- [ ] **Step 5: Sincronizar, reiniciar el shell y comprobar el log**

```bash
cd /home/alberviz/proyectos/LinuxRicing
R=configs/quickshell/caelestia/modules; D=~/.config/quickshell/caelestia/modules
cp -r $R/holo/. $D/holo/ && cp $R/assistant/HoloState.qml $D/assistant/ && diff -rq $R/holo $D/holo
(caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true); sleep 1; caelestia shell -d >/dev/null 2>&1; sleep 6
qs -c caelestia log 2>&1 | grep -E 'Configuration Loaded|ReferenceError|TypeError|HoloConfirm|HoloPanel|HoloLayer' | tail
```
Expected: `INFO: Configuration Loaded` y ninguna línea de `ReferenceError`/`TypeError`.

- [ ] **Step 6: Verificación visual con la demo (sin clics reales)**

```bash
S=/tmp/claude-1000/-home-alberviz-proyectos-LinuxRicing/7afdb9d3-41a2-453d-afcc-7930bfddf798/scratchpad
qs -c caelestia ipc call holo demoConfirm borrar; sleep 3; grim -o eDP-2 $S/confirm-borrar.png
qs -c caelestia ipc call holo demoResolver true; sleep 0.35; grim -o eDP-2 $S/confirm-fx.png   # fila yéndose + papelera
sleep 1.5; qs -c caelestia ipc call holo clear
qs -c caelestia ipc call holo demoConfirm mover; sleep 3; grim -o eDP-2 $S/confirm-mover.png
qs -c caelestia ipc call holo demoResolver false; sleep 1; qs -c caelestia ipc call holo clear
```
Lee las capturas con `Read` y comprueba: el panel de confirmación aparece sin solaparse con la lista ni los visores; «Borrar tres archivos» en rojo con 3 filas, tamaño total (`3,5 MB`-ish) y botones **Cancelar / Borrar**; barra inferior que se vacía; icono de papelera en la esquina al borrar y las filas 6–8 deslizándose; en «mover» sale «a Universidad» y el botón dice **Confirmar**; **la ✕ de la cabecera es un icono, no texto**.

- [ ] **Step 7: Commit**

```bash
git add configs/quickshell/caelestia/modules/holo configs/quickshell/caelestia/modules/assistant/HoloState.qml
git commit -m "feat(laura-archivos): panel holográfico de confirmación, desintegrar a la papelera y demo"
```

---

### Task 7: Configuración, evaluación, documentación y prueba real

**Files:**
- Modify: `assistant/config.toml` (sección `[archivos]`), `assistant/eval/frases.toml`, `docs/LAURA-HOLO.md`, `docs/superpowers/specs/2026-11-09-laura-archivos-design.md`
- Backlog: `vault/Backlog/` vía `tasks-index`; bitácora en `vault/🎯 Hoy.md`

- [ ] **Step 1: Sección `[archivos]` en `config.toml`**

Inserta justo antes de la línea `[vigia]`:

```bash
cd /home/alberviz/proyectos/LinuxRicing/assistant
python3 - <<'EOF'
p = "config.toml"
s = open(p).read()
assert s.count("\n[vigia]") == 1
bloque = """
[archivos]
# Gestión de archivos por voz (borrar a la papelera, mover, renombrar; con confirmación y «deshaz»).
# raices = carpetas donde Laura puede actuar. Vacío = Descargas, Documentos, Escritorio, Imágenes,
# Vídeos y Música (xdg-user-dirs) más ~/proyectos. Nunca toca ocultos, .git ni vault.
# raices = ["~/Descargas", "~/Documentos"]
max_ops = 50           # operaciones máximas por plan
ttl = 60               # segundos que un plan espera confirmación
"""
s = s.replace("\n[vigia]", bloque + "\n[vigia]", 1)
open(p, "w").write(s)
EOF
python3 -c "import tomllib; print(tomllib.load(open('config.toml','rb'))['archivos'])"
```
Expected: `{'max_ops': 50, 'ttl': 60}`.

> No se añade nada al `system_prompt`: las descripciones de las tools ya llevan los ejemplos y cada token cuenta (ver Global Constraints).

- [ ] **Step 2: Frases de evaluación**

Añade al final de `assistant/eval/frases.toml`:

````toml

# ---------- archivos ----------
[[frase]]
texto = "borra la dos"
espera = ["borrar_archivos"]
grupo = "archivos"

[[frase]]
texto = "elimina esas tres capturas"
espera = ["borrar_archivos"]
grupo = "archivos"

[[frase]]
texto = "mueve la tres a universidad"
espera = ["mover_archivos"]
args = [{destino = "universidad"}]
grupo = "archivos"

[[frase]]
texto = "renombra la uno a factura punto pdf"
espera = ["renombrar_archivo"]
grupo = "archivos"

[[frase]]
texto = "crea una carpeta que se llame facturas"
espera = ["crear_carpeta"]
args = [{nombre = "facturas"}]
grupo = "archivos"

[[frase]]
texto = "deshaz lo último"
espera = ["deshacer_archivos"]
grupo = "archivos"
````

Run: `cd assistant && python3 -c "import tomllib; d=tomllib.load(open('eval/frases.toml','rb')); print(sum(f.get('grupo')=='archivos' for f in d['frase']))"`
Expected: `6`. (El examen contra Ollama, `python3 eval/run.py`, es opcional y lento; no bloquea.)

- [ ] **Step 3: Documentación y spec**

Añade a `docs/LAURA-HOLO.md`, antes de la sección «Pruebas y Diagnóstico», una sección «Gestión de archivos» con: las 5 frases de ejemplo (borra la 2 / mueve la 3 a Universidad / renombra la 1 a X / crea una carpeta X / deshaz), el flujo plan → confirmación (voz o clic, caduca a los 60 s) → ejecución → relistado, la papelera y el diario `~/.local/state/laura/archivos.jsonl`, el alcance de carpetas, y los IPC `holo demoConfirm|demoResolver`.

Actualiza el spec con las decisiones tomadas al implementar:
- Donde dice «`borrar` → `gio trash` por origen» y «Tras `gio trash` se localiza…»: papelera freedesktop **propia** (`files/` + `info/`), que devuelve la ruta exacta.
- En «2. Herramientas»: sin parámetro `rutas` (solo números de la lista) y tools **contextuales** (`activas()`), por el presupuesto de contexto; `num_ctx` 10240.
- En «4. Hologramas»: «desintegrar» = el panel se encoge hacia una papelera en la esquina (sin partículas).

- [ ] **Step 4: Tareas del backlog y bitácora**

```bash
cd /home/alberviz/proyectos/LinuxRicing
tasks-index add LinuxRicing "Laura Archivos fase 2 — orden inteligente (ordenar carpetas, renombrado en lote)" -p 3 -a laura
tasks-index add LinuxRicing "Laura Archivos fase 3 — duplicados, grandes/viejos y reglas" -p 4 -a laura
tasks-index add LinuxRicing "Laura Archivos fase 4 — comprimir, buscar por contenido, resumir" -p 4 -a laura
tasks-index add LinuxRicing "Laura — correo y calendario con hologramas y delegación (Gemini 3.8 Flash medium / Haiku 5.5 medium)" -p 2 -a laura
```
Añade UNA línea arriba del todo de «📓 Bitácora de sesiones» en `vault/🎯 Hoy.md`: `- **2026-11-09 · Claude** — Laura Archivos fase 1: borrar/mover/renombrar/crear carpeta con confirmación por voz o clic, papelera con diario y «deshaz», panel holográfico y tools contextuales.`

- [ ] **Step 5: Reiniciar Laura y prueba real (cuidado: habla en voz alta)**

```bash
systemctl --user restart laura && sleep 25 && journalctl --user -u laura --since '-1min' --no-pager | tail -5
mkdir -p ~/Descargas/prueba-laura && printf 'a' > ~/Descargas/prueba-laura/uno.txt && printf 'b' > ~/Descargas/prueba-laura/dos.txt
python3 - <<'EOF'
import os, socket
def ask(frase):
    s = socket.socket(socket.AF_UNIX); s.connect(os.path.expandvars("$XDG_RUNTIME_DIR/laura.sock"))
    s.sendall(f"ask {frase}\n".encode()); print(s.recv(200)); s.close()
ask("enséñame la carpeta prueba-laura de descargas")
EOF
```
Después, **por voz o con `ask`**: «borra la 1» → debe aparecer el panel rojo y Laura preguntar; confirma con «sí» (y repite otra vez confirmando con el clic del panel). Comprueba que `uno.txt` está en `~/.local/share/Trash/files/`, que «deshaz» lo devuelve, y que el diario `~/.local/state/laura/archivos.jsonl` tiene las líneas. Limpia: `rm -r ~/Descargas/prueba-laura` (es tu carpeta de prueba, no un archivo del usuario).

> Si algo falla en el ciclo de voz (no testeable en unitario), revisa `journalctl --user -u laura -n 50` antes de tocar código: el motor y la confirmación ya están cubiertos por tests.

- [ ] **Step 6: Suite completa y commit**

Run: `cd assistant && python3 -m pytest -q -p no:cacheprovider tests && cd ../widgets && python3 -m pytest -q -p no:cacheprovider tests && node ../configs/quickshell/caelestia/modules/holo/test_placer.mjs | tail -1`
Expected: todo en verde.

```bash
cd /home/alberviz/proyectos/LinuxRicing
git add assistant/config.toml assistant/eval/frases.toml docs/LAURA-HOLO.md docs/superpowers/specs/2026-11-09-laura-archivos-design.md "vault/🎯 Hoy.md" vault/Backlog
git commit -m "docs(laura-archivos): configuración, frases de evaluación, documentación y backlog de la fase 1"
```

- [ ] **Step 7: Cierre de la rama**

Invoca `superpowers:finishing-a-development-branch` (la rama `feat/laura-archivos` salió de `feat/laura-holo`: el merge de vuelta lo decide Alberto).

---

## Self-Review

**Spec coverage**
- Motor (validador, plan, planificar, confirmación requerida, ejecutar, diario, deshacer): Task 1.
- Herramientas y `effect="confirm:archivos"`: Task 4. Confirmación en el ciclo (voz+panel, silencio+TTL, respuesta tardía): Tasks 3 y 5.
- Panel `confirmar`, animaciones (desintegrar, fila, papelera), relistado, demo: Tasks 2 y 6.
- Errores (ruta no permitida, origen desaparecido, colisión, fallo a medias, >50, plan caducado): cubiertos por los tests de Task 1 y los mensajes de `archivos.py`.
- Tests del spec (motor, tools, confirmación, visual con demo): Tasks 1–4 y 6.
- Config `[archivos]`, evaluación, docs, backlog: Task 7. Desviaciones respecto al spec (papelera propia, tools sin `rutas`, contextuales, `num_ctx`, sin partículas) documentadas en Global Constraints y actualizadas en el spec (Task 7 Step 3).

**Placeholder scan:** sin «TBD»/«TODO»; cada paso de código lleva el código o un parche con anclas verificadas (`assert`).

**Type consistency:** `Plan`, `resolver(plan_id, si)`, `Escena.resolver_plan/tras_plan/refrescar/mostrar_confirmacion`, `confirmar_archivos.confirmar/responder_pendiente/interpretar`, `tools.activas`, `HoloState.confirmar/cancelar/fx` y `HoloPanel.desintegrar/cerrarPanel` se usan con los mismos nombres y firmas en todas las tareas.
