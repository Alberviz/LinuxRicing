# Motor unificado de iluminación reactiva a la batería — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un daemon único que enruta eventos de batería (cargando / baja / crítica) de cualquier periférico a efectos de iluminación en cualquier zona RGB, configurable con reglas, sustituyendo la lógica escrita a fuego que hoy vive repartida en `mchose-battery` y `sync-rgb.py`.

**Architecture:** `rgb/battery-lighting` (Python, sin dependencias, hidraw crudo por `fcntl.ioctl` como `mchose-battery`) corre como servicio systemd `--user`. En cada tick lee la telemetría de las tres baterías, la cachea, resuelve las reglas de `~/.config/caelestia/battery-lighting.json` con un orden de prioridad por zona, aplica el efecto ganador a cada zona y publica el estado en `~/.cache/battery_alerts.json` para que `sync-rgb.py` y `rgb-notify-flash` no lo pisen. Cadencia adaptativa: 60 s en reposo, ~3 s mientras algo carga. La UI (Fase 2) es una sección nueva en la pestaña Notificaciones del Centro de Iluminación con un singleton `BatteryLightingConfig.qml`.

**Tech Stack:** Python 3.14 (stdlib only: `fcntl`, `os`, `glob`, `select`, `json`, `time`, `subprocess`, `colorsys`), pytest 9 para tests unitarios, systemd `--user`, Quickshell/QML (Caelestia), OpenRGB SDK Python (`openrgb`, ya instalado) sólo para el destino `openrgb`.

**Spec:** `docs/superpowers/specs/2026-08-27-battery-lighting-engine-design.md`

## Global Constraints

- **Sin dependencias nuevas de Python.** `battery-lighting` usa sólo stdlib + `openrgb` (ya presente). Nada de `hid`/`hidapi` (no está instalado; el patrón del repo es hidraw crudo con `fcntl.ioctl`, ver `rgb/mchose-battery`).
- **Estilo del repo: un archivo por herramienta, sin módulos compartidos entre scripts.** Los helpers HID se copian, no se importan (cabecera de `rgb/rgb-notify-flash`). Los tests cargan `rgb/battery-lighting` con `importlib` (no tiene extensión `.py`).
- **`rgb/mchose-battery` ⇔ `widgets/mchose-battery` deben quedar byte a byte idénticos.** Toda edición a uno se replica al otro y se verifica con `diff -q rgb/mchose-battery widgets/mchose-battery` (sin salida). Igual que `widgets/Background.qml ⇔ configs/quickshell/caelestia/modules/background/Background.qml`.
- **Textos de usuario en español con tildes** (`qsTr("Reacciones de batería")`, etc.). Nunca ASCII-plano por acentos.
- **La radio 2.4 GHz del Akko se corrompe con escrituras muy seguidas.** Nunca por debajo de 2 s entre escrituras al Akko; sólo escribir cuando el estado calculado (nivel apreciable / trigger / efecto) cambia. Ver `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md`.
- **Checksum del Akko (opcodes `0x07`/`0x08`/`0x0C`):** `byte[8] = 0xFF - (sum(byte[0..8]) & 0xFF)` para paquetes de 64 bytes tras `Report ID 0x00`. Payload MCHOSE base: XOR `0xFF` en `byte[1..20]` tras `Report ID 0x11`.
- **Rama:** `feat/battery-lighting-engine` (ya creada desde `main`). Commits frecuentes, uno por paso "Commit".
- **Fin de cada mensaje de commit:** `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

---

## Estructura de archivos

### Fase 1 — motor (independientemente entregable: se configura editando el JSON a mano)

| Archivo | Responsabilidad |
| --- | --- |
| `rgb/battery-lighting` (nuevo) | Daemon + CLI. Todo: telemetría, resolución de reglas, aplicación de efectos, estado compartido, notificaciones de escritorio. |
| `rgb/tests/conftest.py` (nuevo) | Carga `rgb/battery-lighting` como módulo (`bl`) vía `importlib`; fixtures de `tmp_path` para configs y cachés. |
| `rgb/tests/test_config.py` (nuevo) | Parseo y validación del esquema; sembrado; migración de `akko-config.json` / `mchose-config.json`. |
| `rgb/tests/test_resolver.py` (nuevo) | Resolución de prioridad por zona (crítica > baja > cargando; empate por orden; `both` → 2 zonas). |
| `rgb/tests/test_effects.py` (nuevo) | Cálculo de color por nivel; fracción de relleno del medidor → filas/LEDs; construcción de los 7 chunks del lienzo Akko. |
| `systemd/battery-lighting.service` (nuevo) | `--user`, `ExecStart=… battery-lighting --daemon`, `Restart=always`. |
| `rgb/sync-rgb.py` (modificar) | Quitar reglas de batería de `sync_akko_keyboard`; cada `sync_*` consulta `battery_alerts.json` y salta su zona si está reclamada. |
| `rgb/mchose-battery` (modificar) + `widgets/mchose-battery` (espejo) | Quitar toda la lógica de iluminación (`apply_charging_lighting`, `apply_low_battery_lighting`, `apply_akko_battery_lighting`, `handle_charging_lighting_transition`, `check_and_notify`, flags `--*-lighting`, `--notify`, `--daemon`, `--akko-mode`). Dejar telemetría + `--json`/`--waybar-*` sirviendo de caché con fallback a lectura directa. |
| `rgb/rgb-notify-flash` (modificar) | `restore()`: si la zona está en `battery_alerts.json`, re-disparar `battery-lighting --tick` en vez de pintar tema. |
| `install.sh` (modificar) | Instalar `battery-lighting` + servicio; `disable --now mchose-battery.timer`; dejar de instalar el `.timer`. |
| `systemd/mchose-battery.service`, `systemd/mchose-battery.timer` (borrar) | Sustituidos por el daemon. |
| `rgb/mchose-config` (borrar) | Sustituido por la UI del motor (Fase 2). `rgb/mchose-lighting` se queda. |
| `docs/HARDWARE_PROTOCOLS.md`, `docs/AKKO_BATTERY_LIGHTING_FRONTEND.md` (modificar) | Documentar el motor. |
| `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md` (modificar) | Registrar hallazgos de validación del lienzo Akko. |
| `CLAUDE.md` (modificar) | Añadir `rgb/mchose-battery ⇔ widgets/mchose-battery` a "Copias que deben ir idénticas". |

### Fase 2 — UI

| Archivo | Responsabilidad |
| --- | --- |
| `configs/quickshell/caelestia/services/BatteryLightingConfig.qml` (nuevo) | Singleton que refleja `battery-lighting.json`; setters con debounce 250 ms; tras guardar dispara `battery-lighting --tick`. |
| `configs/quickshell/caelestia/modules/rgbcontrol/BatteryRuleCard.qml` (nuevo) | Tarjeta de regla plegable: origen + disparador + umbral + lista de acciones + Probar + borrar. |
| `configs/quickshell/caelestia/modules/rgbcontrol/BatteryActionRow.qml` (nuevo) | Una acción: destino → zona (si Akko) → efecto. |
| `configs/quickshell/caelestia/modules/rgbcontrol/NotificacionesView.qml` (modificar) | Nueva sección "Reacciones de batería" + botón "Añadir regla". |
| `configs/quickshell/caelestia/modules/rgbcontrol/AkkoCard.qml` (modificar) | Quitar sección de batería (queda aspecto normal / color global). |
| `configs/quickshell/caelestia/modules/rgbcontrol/DispositivosView.qml` (modificar) | Quitar bloque "Eventos de batería" de la ficha de la Base. |
| `configs/quickshell/caelestia/services/AkkoConfig.qml`, `MchoseConfig.qml` (borrar) | Sustituidos por `BatteryLightingConfig.qml`. |
| `configs/quickshell/caelestia/modules/rgbcontrol/KeyboardPreview.qml` (reutilizar) | Preview dentro de `BatteryActionRow` cuando el destino es el Akko. |

---

## Contrato de datos (define Fase 1, consume Fase 2)

### `~/.config/caelestia/battery-lighting.json`

```json
{
  "poll": { "idle_seconds": 60, "charging_seconds": 3 },
  "critical_threshold": 10,
  "rules": [
    {
      "id": "akko-charging",
      "source": "akko_keyboard",
      "trigger": "charging",
      "threshold": null,
      "actions": [
        { "target": "akko_keyboard", "zone": "keys",      "effect": "battery_meter" },
        { "target": "akko_keyboard", "zone": "sidestrip",  "effect": "stream_battery" }
      ]
    }
  ]
}
```

- `source ∈ {"akko_keyboard","mchose_mouse","v9_headset"}`
- `trigger ∈ {"charging","low","critical"}`; `threshold` entero 5..40 sólo si `trigger=="low"`, si no `null`.
- `action.target ∈ {"akko_keyboard","mchose_base","magichome","openrgb"}`
- `action.zone ∈ {"keys","sidestrip","both"}` sólo si `target=="akko_keyboard"`, si no ausente/`null`.
- `action.effect`: uno de la tabla del spec §3 según destino/zona.

### `~/.cache/battery_alerts.json` (lo escribe el daemon; lo leen `sync-rgb.py` y `rgb-notify-flash`)

```json
{
  "akko_keyboard:sidestrip": { "effect": "red_breathing", "trigger": "low", "source": "akko_keyboard", "level": 18 },
  "mchose_base:_":           { "effect": "battery_color", "trigger": "charging", "source": "mchose_mouse", "level": 64 }
}
```

Clave = `"<target>:<zone>"`; para destinos sin zonas, `zone` es `"_"`. Zonas del Akko siempre expandidas (`keys` / `sidestrip`, nunca `both`). Fichero vacío `{}` = sin alertas.

### `~/.cache/mchose_battery.json` (telemetría; formato ya existente, se conserva)

Claves ya en uso: `v9_battery`, `v9_status`, `k7_battery`, `k7_status`, `akko_battery`, `akko_status`, `notified_levels`. El daemon es el único escritor cuando corre.

---

# FASE 1 — Motor

## Task 1: Esqueleto de `battery-lighting` + infraestructura de tests

**Files:**
- Create: `rgb/battery-lighting`
- Create: `rgb/tests/conftest.py`
- Create: `rgb/tests/test_config.py`

**Interfaces:**
- Produces:
  - módulo cargable como `bl` con: `CONFIG_PATH: str`, `ALERTS_CACHE: str`, `BATTERY_CACHE: str`, `STATE_CACHE: str` (rutas, todas bajo `~`).
  - `DEFAULTS: dict` — config sembrada por defecto (spec §5).
  - `main(argv: list[str]) -> int`.

- [ ] **Step 1: Escribir el test que falla**

`rgb/tests/conftest.py`:
```python
import importlib.util
import os
from pathlib import Path
import pytest

_SRC = Path(__file__).resolve().parents[1] / "battery-lighting"


def _load():
    spec = importlib.util.spec_from_file_location("battery_lighting", _SRC)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def bl(monkeypatch, tmp_path):
    mod = _load()
    monkeypatch.setattr(mod, "CONFIG_PATH", str(tmp_path / "battery-lighting.json"))
    monkeypatch.setattr(mod, "ALERTS_CACHE", str(tmp_path / "battery_alerts.json"))
    monkeypatch.setattr(mod, "BATTERY_CACHE", str(tmp_path / "mchose_battery.json"))
    monkeypatch.setattr(mod, "STATE_CACHE", str(tmp_path / "battery_lighting_state.json"))
    monkeypatch.setattr(mod, "AKKO_CONFIG_LEGACY", str(tmp_path / "akko-config.json"))
    monkeypatch.setattr(mod, "MCHOSE_CONFIG_LEGACY", str(tmp_path / "mchose-config.json"))
    return mod
```

`rgb/tests/test_config.py`:
```python
def test_module_exposes_paths_and_defaults(bl):
    assert bl.CONFIG_PATH.endswith("battery-lighting.json")
    assert isinstance(bl.DEFAULTS, dict)
    assert bl.DEFAULTS["poll"] == {"idle_seconds": 60, "charging_seconds": 3}
    assert bl.DEFAULTS["critical_threshold"] == 10
    assert any(r["id"] == "akko-low" for r in bl.DEFAULTS["rules"])


def test_main_help_returns_zero(bl, capsys):
    assert bl.main(["--help"]) == 0
    assert "battery-lighting" in capsys.readouterr().out
```

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `cd /home/alberviz/LinuxRicing && python3 -m pytest rgb/tests/test_config.py -q`
Expected: FAIL — `battery-lighting` no existe / `FileNotFoundError`.

- [ ] **Step 3: Implementación mínima**

`rgb/battery-lighting` (cabecera + rutas + DEFAULTS + `main` con parser a mano al estilo `sync-rgb.py`):
```python
#!/usr/bin/env python3
"""
battery-lighting — motor unificado de iluminación reactiva a la batería.

Un daemon systemd --user que enruta eventos de batería (cargando / baja /
crítica) de los periféricos a efectos de iluminación en cualquier zona RGB,
según las reglas de ~/.config/caelestia/battery-lighting.json.

Modos:
  battery-lighting --daemon          bucle principal (lo lanza el servicio)
  battery-lighting --tick            un ciclo (leer, resolver, aplicar) y salir
  battery-lighting --apply <rule-id> fuerza una regla (botón "Probar" de la UI)
  battery-lighting --clear           suelta todas las alertas y repinta al tema
  battery-lighting --dump            imprime el estado resuelto en JSON

El proyecto duplica a propósito los helpers HID entre scripts en vez de
compartir un módulo; este archivo sigue ese estilo.
"""
import glob
import json
import os
import select
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CONFIG_PATH = f"{HOME}/.config/caelestia/battery-lighting.json"
ALERTS_CACHE = f"{HOME}/.cache/battery_alerts.json"
BATTERY_CACHE = f"{HOME}/.cache/mchose_battery.json"
STATE_CACHE = f"{HOME}/.cache/battery_lighting_state.json"
AKKO_CONFIG_LEGACY = f"{HOME}/.config/caelestia/akko-config.json"
MCHOSE_CONFIG_LEGACY = f"{HOME}/.config/caelestia/mchose-config.json"
SYNC_RGB = f"{HOME}/.config/caelestia/sync-rgb.py"
LOG_FILE = f"{HOME}/.cache/battery_lighting.log"

DEFAULTS = {
    "poll": {"idle_seconds": 60, "charging_seconds": 3},
    "critical_threshold": 10,
    "rules": [
        {"id": "akko-charging", "source": "akko_keyboard", "trigger": "charging", "threshold": None,
         "actions": [
             {"target": "akko_keyboard", "zone": "keys", "effect": "battery_meter"},
             {"target": "akko_keyboard", "zone": "sidestrip", "effect": "stream_battery"}]},
        {"id": "akko-low", "source": "akko_keyboard", "trigger": "low", "threshold": 20,
         "actions": [{"target": "akko_keyboard", "zone": "both", "effect": "red_breathing"}]},
        {"id": "mouse-charging", "source": "mchose_mouse", "trigger": "charging", "threshold": None,
         "actions": [{"target": "mchose_base", "zone": None, "effect": "theme_breathing"}]},
        {"id": "mouse-low", "source": "mchose_mouse", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "zone": None, "effect": "red_breathing"}]},
    ],
}

USAGE = __doc__


def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except Exception:
        pass


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(USAGE)
        return 0
    # los modos reales se añaden en tareas posteriores
    print(USAGE)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Ejecutar y ver pasar**

Run: `cd /home/alberviz/LinuxRicing && python3 -m pytest rgb/tests/test_config.py -q`
Expected: PASS (2 passed)

- [ ] **Step 5: Permisos y commit**

```bash
chmod +x rgb/battery-lighting
git add rgb/battery-lighting rgb/tests/conftest.py rgb/tests/test_config.py
git commit -m "feat(battery-lighting): skeleton + test harness

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: Carga y validación del esquema de config

**Files:**
- Modify: `rgb/battery-lighting`
- Modify: `rgb/tests/test_config.py`

**Interfaces:**
- Consumes: `bl.DEFAULTS`, `bl.CONFIG_PATH`
- Produces:
  - `load_config() -> dict` — lee `CONFIG_PATH`; si no existe o es inválido, devuelve una copia profunda de `DEFAULTS` (o el resultado del sembrado de la Task 4 cuando exista). Nunca lanza.
  - `validate_config(raw: dict) -> tuple[dict, list[str]]` — devuelve `(config_saneada, errores)`. Descarta reglas/acciones inválidas, rellena `poll`/`critical_threshold` con defaults, normaliza tipos.
  - `VALID_SOURCES: set[str]`, `VALID_TRIGGERS: set[str]`, `VALID_TARGETS: set[str]`, `EFFECTS: dict[str, set[str]]` (clave `"akko_keyboard:keys"`, `"akko_keyboard:sidestrip"`, `"mchose_base"`, `"magichome"`, `"openrgb"`).

- [ ] **Step 1: Tests que fallan**

Añadir a `rgb/tests/test_config.py`:
```python
import json


def _write(bl, obj):
    with open(bl.CONFIG_PATH, "w") as f:
        json.dump(obj, f)


def test_missing_file_yields_defaults(bl):
    cfg = bl.load_config()
    assert cfg["rules"] == bl.DEFAULTS["rules"]


def test_garbage_file_yields_defaults(bl):
    with open(bl.CONFIG_PATH, "w") as f:
        f.write("{not json")
    assert bl.load_config()["rules"] == bl.DEFAULTS["rules"]


def test_validate_drops_unknown_source_keeps_rest(bl):
    raw = {"rules": [
        {"id": "bad", "source": "toaster", "trigger": "low", "threshold": 20, "actions": []},
        {"id": "ok", "source": "v9_headset", "trigger": "low", "threshold": 15,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]},
    ]}
    cfg, errors = bl.validate_config(raw)
    ids = [r["id"] for r in cfg["rules"]]
    assert ids == ["ok"]
    assert any("toaster" in e for e in errors)


def test_validate_drops_invalid_effect_for_target(bl):
    raw = {"rules": [{"id": "r", "source": "v9_headset", "trigger": "low", "threshold": 20,
                      "actions": [
                          {"target": "magichome", "effect": "battery_meter"},   # inválido en magichome
                          {"target": "magichome", "effect": "red"},
                      ]}]}
    cfg, errors = bl.validate_config(raw)
    effs = [a["effect"] for a in cfg["rules"][0]["actions"]]
    assert effs == ["red"]


def test_validate_low_threshold_clamped_5_40(bl):
    raw = {"rules": [{"id": "r", "source": "v9_headset", "trigger": "low", "threshold": 999,
                      "actions": [{"target": "mchose_base", "effect": "red_static"}]}]}
    cfg, _ = bl.validate_config(raw)
    assert cfg["rules"][0]["threshold"] == 40


def test_validate_both_zone_allowed_only_for_akko(bl):
    raw = {"rules": [{"id": "r", "source": "akko_keyboard", "trigger": "low", "threshold": 20,
                      "actions": [{"target": "mchose_base", "zone": "both", "effect": "red_static"}]}]}
    cfg, _ = bl.validate_config(raw)
    assert "zone" not in cfg["rules"][0]["actions"][0] or cfg["rules"][0]["actions"][0]["zone"] is None
```

- [ ] **Step 2: Ver fallar**

Run: `python3 -m pytest rgb/tests/test_config.py -q`
Expected: FAIL — `validate_config` / `load_config` no existen.

- [ ] **Step 3: Implementar**

En `rgb/battery-lighting`, antes de `main`:
```python
import copy

VALID_SOURCES = {"akko_keyboard", "mchose_mouse", "v9_headset"}
VALID_TRIGGERS = {"charging", "low", "critical"}
VALID_TARGETS = {"akko_keyboard", "mchose_base", "magichome", "openrgb"}
VALID_ZONES = {"keys", "sidestrip", "both"}

EFFECTS = {
    "akko_keyboard:keys": {"theme", "battery_meter", "breathing_battery", "stream",
                           "red_breathing", "red_static", "none"},
    "akko_keyboard:sidestrip": {"stream_battery", "breathing", "solid_theme",
                                "red_breathing", "red_static", "none"},
    "mchose_base": {"theme_breathing", "battery_color", "hardware_battery", "wave",
                    "red_breathing", "red_static", "none"},
    "magichome": {"battery_color", "solid_theme", "red", "none"},
    "openrgb": {"battery_meter", "solid_theme", "red", "none"},
}


def _effect_keys_for(target, zone):
    if target == "akko_keyboard":
        zones = ("keys", "sidestrip") if zone in (None, "both") else (zone,)
        return [f"akko_keyboard:{z}" for z in zones]
    return [target]


def validate_config(raw):
    errors = []
    out = copy.deepcopy(DEFAULTS)
    out["rules"] = []
    if not isinstance(raw, dict):
        return out, ["config no es un objeto JSON"]

    poll = raw.get("poll", {})
    if isinstance(poll, dict):
        for k, lo in (("idle_seconds", 10), ("charging_seconds", 2)):
            v = poll.get(k)
            if isinstance(v, (int, float)) and v >= lo:
                out["poll"][k] = int(v)
    ct = raw.get("critical_threshold")
    if isinstance(ct, (int, float)) and 3 <= ct <= 25:
        out["critical_threshold"] = int(ct)

    for i, rule in enumerate(raw.get("rules", []) or []):
        if not isinstance(rule, dict):
            errors.append(f"regla #{i} no es objeto"); continue
        src = rule.get("source")
        trig = rule.get("trigger")
        if src not in VALID_SOURCES:
            errors.append(f"regla #{i}: source inválido {src!r} (toaster?)"); continue
        if trig not in VALID_TRIGGERS:
            errors.append(f"regla #{i}: trigger inválido {trig!r}"); continue
        thr = None
        if trig == "low":
            t = rule.get("threshold", 20)
            t = t if isinstance(t, (int, float)) else 20
            thr = max(5, min(40, int(round(t / 5) * 5)))
        actions = []
        for j, act in enumerate(rule.get("actions", []) or []):
            if not isinstance(act, dict):
                errors.append(f"regla #{i} acción #{j} no es objeto"); continue
            tgt = act.get("target")
            if tgt not in VALID_TARGETS:
                errors.append(f"regla #{i} acción #{j}: target inválido {tgt!r}"); continue
            zone = act.get("zone")
            if tgt != "akko_keyboard":
                zone = None
            elif zone not in VALID_ZONES:
                zone = "both"
            eff = act.get("effect")
            allowed = set().union(*(EFFECTS[k] for k in _effect_keys_for(tgt, zone)))
            if eff not in allowed:
                errors.append(f"regla #{i} acción #{j}: effect {eff!r} no válido para {tgt}/{zone}")
                continue
            a = {"target": tgt, "effect": eff}
            if zone is not None:
                a["zone"] = zone
            actions.append(a)
        rid = rule.get("id") or f"rule-{i}"
        out["rules"].append({"id": str(rid), "source": src, "trigger": trig,
                             "threshold": thr, "actions": actions})
    return out, errors


def load_config():
    try:
        with open(CONFIG_PATH) as f:
            raw = json.load(f)
    except FileNotFoundError:
        return seed_config()          # definido en Task 4
    except Exception as e:
        log(f"config ilegible ({e}); usando sembrado")
        return seed_config()
    cfg, errors = validate_config(raw)
    for e in errors:
        log(f"config: {e}")
    return cfg
```

Para que esta tarea pase sin la Task 4, añadir un stub temporal:
```python
def seed_config():
    return copy.deepcopy(DEFAULTS)
```
(la Task 4 lo reemplaza por la lógica de migración real).

- [ ] **Step 4: Ver pasar**

Run: `python3 -m pytest rgb/tests/test_config.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rgb/battery-lighting rgb/tests/test_config.py
git commit -m "feat(battery-lighting): config schema load + validation

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: Resolutor de prioridad

**Files:**
- Modify: `rgb/battery-lighting`
- Create: `rgb/tests/test_resolver.py`

**Interfaces:**
- Consumes: config saneada de `validate_config`.
- Produces:
  - `evaluate_trigger(rule: dict, level: int|None, charging: bool, critical_threshold: int) -> bool`
  - `resolve(config: dict, telemetry: dict) -> dict` — `telemetry` es `{"akko_keyboard": {"level": int|None, "charging": bool, "connected": bool}, "mchose_mouse": {...}, "v9_headset": {...}}`. Devuelve `{"<target>:<zone>": {"effect","trigger","source","level"}}` con la acción ganadora por zona. `zone` `"_"` para destinos sin zonas; `both` expandido a `keys` y `sidestrip`.
  - `SEVERITY = {"critical": 3, "low": 2, "charging": 1}`

- [ ] **Step 1: Tests que fallan**

`rgb/tests/test_resolver.py`:
```python
def _tele(akko=None, mouse=None, v9=None):
    base = {"level": None, "charging": False, "connected": False}
    def m(d): return {**base, **(d or {})}
    return {"akko_keyboard": m(akko), "mchose_mouse": m(mouse), "v9_headset": m(v9)}


def test_low_rule_fires_below_threshold(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "mchose_mouse", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]}]}
    out = bl.resolve(cfg, _tele(mouse={"level": 18, "connected": True}))
    assert out["mchose_base:_"]["effect"] == "red_breathing"
    assert out["mchose_base:_"]["trigger"] == "low"


def test_low_rule_silent_above_threshold(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "mchose_mouse", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]}]}
    assert bl.resolve(cfg, _tele(mouse={"level": 55, "connected": True})) == {}


def test_charging_rule_fires_when_charging(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "mchose_mouse", "trigger": "charging", "threshold": None,
         "actions": [{"target": "mchose_base", "effect": "theme_breathing"}]}]}
    out = bl.resolve(cfg, _tele(mouse={"level": 40, "charging": True, "connected": True}))
    assert out["mchose_base:_"]["trigger"] == "charging"


def test_critical_beats_low_on_same_zone(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "low", "source": "mchose_mouse", "trigger": "low", "threshold": 30,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]},
        {"id": "crit", "source": "mchose_mouse", "trigger": "critical", "threshold": None,
         "actions": [{"target": "mchose_base", "effect": "red_static"}]}]}
    out = bl.resolve(cfg, _tele(mouse={"level": 8, "connected": True}))
    assert out["mchose_base:_"]["effect"] == "red_static"


def test_same_severity_first_rule_wins(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "a", "source": "mchose_mouse", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]},
        {"id": "b", "source": "v9_headset", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_static"}]}]}
    out = bl.resolve(cfg, _tele(mouse={"level": 10, "connected": True},
                                v9={"level": 10, "connected": True}))
    assert out["mchose_base:_"]["effect"] == "red_breathing"


def test_both_zone_expands(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "akko_keyboard", "trigger": "low", "threshold": 20,
         "actions": [{"target": "akko_keyboard", "zone": "both", "effect": "red_breathing"}]}]}
    out = bl.resolve(cfg, _tele(akko={"level": 12, "connected": True}))
    assert set(out) == {"akko_keyboard:keys", "akko_keyboard:sidestrip"}


def test_disconnected_source_never_fires(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "v9_headset", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_static"}]}]}
    assert bl.resolve(cfg, _tele(v9={"level": 5, "connected": False})) == {}


def test_charging_rule_not_active_when_also_low_and_discharging(bl):
    # descargando al 8%: la regla 'charging' no aplica aunque exista
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "c", "source": "akko_keyboard", "trigger": "charging", "threshold": None,
         "actions": [{"target": "akko_keyboard", "zone": "sidestrip", "effect": "stream_battery"}]}]}
    assert bl.resolve(cfg, _tele(akko={"level": 8, "charging": False, "connected": True})) == {}
```

- [ ] **Step 2: Ver fallar**

Run: `python3 -m pytest rgb/tests/test_resolver.py -q`
Expected: FAIL — `resolve` no existe.

- [ ] **Step 3: Implementar**

En `rgb/battery-lighting`:
```python
SEVERITY = {"critical": 3, "low": 2, "charging": 1}


def evaluate_trigger(rule, level, charging, critical_threshold):
    trig = rule["trigger"]
    if trig == "charging":
        return bool(charging)
    if level is None:
        return False
    if trig == "critical":
        return (not charging) and level <= critical_threshold
    if trig == "low":
        return (not charging) and level <= (rule.get("threshold") or 20)
    return False


def _zone_keys(action):
    tgt = action["target"]
    if tgt != "akko_keyboard":
        return [f"{tgt}:_"]
    z = action.get("zone") or "both"
    zs = ("keys", "sidestrip") if z == "both" else (z,)
    return [f"{tgt}:{zz}" for zz in zs]


def resolve(config, telemetry):
    ct = config.get("critical_threshold", 10)
    winners = {}   # zonekey -> (severity, rule_index, payload)
    for idx, rule in enumerate(config.get("rules", [])):
        src = telemetry.get(rule["source"], {})
        if not src.get("connected"):
            continue
        if not evaluate_trigger(rule, src.get("level"), src.get("charging", False), ct):
            continue
        sev = SEVERITY[rule["trigger"]]
        for action in rule.get("actions", []):
            payload = {"effect": action["effect"], "trigger": rule["trigger"],
                       "source": rule["source"], "level": src.get("level")}
            for zk in _zone_keys(action):
                cur = winners.get(zk)
                if cur is None or sev > cur[0] or (sev == cur[0] and idx < cur[1]):
                    winners[zk] = (sev, idx, payload)
    return {zk: p for zk, (_, _, p) in winners.items()}
```

- [ ] **Step 4: Ver pasar**

Run: `python3 -m pytest rgb/tests/test_resolver.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rgb/battery-lighting rgb/tests/test_resolver.py
git commit -m "feat(battery-lighting): per-zone priority resolver

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 4: Sembrado + migración de configs antiguas

**Files:**
- Modify: `rgb/battery-lighting`
- Modify: `rgb/tests/test_config.py`

**Interfaces:**
- Consumes: `bl.AKKO_CONFIG_LEGACY`, `bl.MCHOSE_CONFIG_LEGACY`, `bl.DEFAULTS`, `validate_config`.
- Produces:
  - `seed_config() -> dict` — reemplaza el stub de la Task 2. Si existe `battery-lighting.json` no se llama (lo maneja `load_config`). Construye reglas: migra `akko-config.json` → reglas `akko_keyboard/charging` + `akko_keyboard/low`; migra `mchose-config.json` → `mchose_mouse/charging` + `mchose_mouse/low` sobre `mchose_base`; para lo que falte, usa las de `DEFAULTS`. Devuelve config ya saneada por `validate_config`.
  - `LEGACY_AKKO_BACKLIGHT = {"theme": "theme", "fill": "battery_meter", "breathing": "breathing_battery", "stream": "stream"}`
  - `LEGACY_AKKO_SIDESTRIP = {"stream_battery": "stream_battery", "breathing": "breathing", "solid": "solid_theme", "none": "none"}`
  - `LEGACY_AKKO_LOW = {"red_breathing": "red_breathing", "red_static": "red_static", "none": "none"}`
  - `LEGACY_MCHOSE_CHARGE = {"theme_breathing": "theme_breathing", "battery_breathing": "battery_color", "hardware_battery": "hardware_battery", "wave": "wave"}`
  - `LEGACY_MCHOSE_LOW = {"red_breathing": "red_breathing", "red_static": "red_static", "wave": "wave", "none": "none"}`

- [ ] **Step 1: Tests que fallan**

Añadir a `rgb/tests/test_config.py`:
```python
def test_seed_uses_defaults_without_legacy(bl):
    cfg = bl.seed_config()
    assert [r["id"] for r in cfg["rules"]] == [r["id"] for r in bl.DEFAULTS["rules"]]


def test_seed_migrates_akko_config(bl):
    with open(bl.AKKO_CONFIG_LEGACY, "w") as f:
        json.dump({"reactive_enabled": True,
                   "charging": {"backlight": "fill", "sidestrip": "stream_battery"},
                   "low_battery": {"backlight": "red_breathing", "sidestrip": "red_static"},
                   "low_battery_threshold": 25}, f)
    cfg = bl.seed_config()
    charge = next(r for r in cfg["rules"] if r["source"] == "akko_keyboard" and r["trigger"] == "charging")
    acts = {a["zone"]: a["effect"] for a in charge["actions"]}
    assert acts["keys"] == "battery_meter"
    assert acts["sidestrip"] == "stream_battery"
    low = next(r for r in cfg["rules"] if r["source"] == "akko_keyboard" and r["trigger"] == "low")
    assert low["threshold"] == 25


def test_seed_migrates_mchose_config(bl):
    with open(bl.MCHOSE_CONFIG_LEGACY, "w") as f:
        json.dump({"charging_effect": "battery_breathing",
                   "low_battery_effect": "red_static",
                   "low_battery_threshold": 30}, f)
    cfg = bl.seed_config()
    low = next(r for r in cfg["rules"] if r["source"] == "mchose_mouse" and r["trigger"] == "low")
    assert low["threshold"] == 30
    assert low["actions"][0]["effect"] == "red_static"
    charge = next(r for r in cfg["rules"] if r["source"] == "mchose_mouse" and r["trigger"] == "charging")
    assert charge["actions"][0]["effect"] == "battery_color"


def test_seed_reactive_disabled_akko_yields_no_akko_rules(bl):
    with open(bl.AKKO_CONFIG_LEGACY, "w") as f:
        json.dump({"reactive_enabled": False,
                   "charging": {"backlight": "fill", "sidestrip": "stream_battery"},
                   "low_battery": {"backlight": "red_breathing", "sidestrip": "red_breathing"},
                   "low_battery_threshold": 20}, f)
    cfg = bl.seed_config()
    assert not any(r["source"] == "akko_keyboard" for r in cfg["rules"])
```

- [ ] **Step 2: Ver fallar**

Run: `python3 -m pytest rgb/tests/test_config.py -q`
Expected: FAIL — `seed_config` es el stub, no migra.

- [ ] **Step 3: Implementar**

Reemplazar el stub `seed_config` en `rgb/battery-lighting`:
```python
LEGACY_AKKO_BACKLIGHT = {"theme": "theme", "fill": "battery_meter",
                         "breathing": "breathing_battery", "stream": "stream"}
LEGACY_AKKO_SIDESTRIP = {"stream_battery": "stream_battery", "breathing": "breathing",
                         "solid": "solid_theme", "none": "none"}
LEGACY_AKKO_LOW = {"red_breathing": "red_breathing", "red_static": "red_static", "none": "none"}
LEGACY_MCHOSE_CHARGE = {"theme_breathing": "theme_breathing", "battery_breathing": "battery_color",
                        "hardware_battery": "hardware_battery", "wave": "wave"}
LEGACY_MCHOSE_LOW = {"red_breathing": "red_breathing", "red_static": "red_static",
                     "wave": "wave", "none": "none"}


def _read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def seed_config():
    rules = []
    akko = _read_json(AKKO_CONFIG_LEGACY)
    if akko and akko.get("reactive_enabled", True):
        ch = akko.get("charging", {})
        bl_eff = LEGACY_AKKO_BACKLIGHT.get(ch.get("backlight"), "theme")
        ss_eff = LEGACY_AKKO_SIDESTRIP.get(ch.get("sidestrip"), "stream_battery")
        rules.append({"id": "akko-charging", "source": "akko_keyboard", "trigger": "charging",
                      "threshold": None, "actions": [
                          {"target": "akko_keyboard", "zone": "keys", "effect": bl_eff},
                          {"target": "akko_keyboard", "zone": "sidestrip", "effect": ss_eff}]})
        lb = akko.get("low_battery", {})
        lb_bl = LEGACY_AKKO_LOW.get(lb.get("backlight"), "red_breathing")
        lb_ss = LEGACY_AKKO_LOW.get(lb.get("sidestrip"), "red_breathing")
        acts = []
        if lb_bl != "none":
            acts.append({"target": "akko_keyboard", "zone": "keys", "effect": lb_bl})
        if lb_ss != "none":
            acts.append({"target": "akko_keyboard", "zone": "sidestrip", "effect": lb_ss})
        rules.append({"id": "akko-low", "source": "akko_keyboard", "trigger": "low",
                      "threshold": akko.get("low_battery_threshold", 20), "actions": acts})
    elif akko is None:
        rules += [r for r in DEFAULTS["rules"] if r["source"] == "akko_keyboard"]

    mchose = _read_json(MCHOSE_CONFIG_LEGACY)
    if mchose:
        ch_eff = LEGACY_MCHOSE_CHARGE.get(mchose.get("charging_effect"), "theme_breathing")
        rules.append({"id": "mouse-charging", "source": "mchose_mouse", "trigger": "charging",
                      "threshold": None,
                      "actions": [{"target": "mchose_base", "effect": ch_eff}]})
        lb_eff = LEGACY_MCHOSE_LOW.get(mchose.get("low_battery_effect"), "red_breathing")
        if lb_eff != "none":
            rules.append({"id": "mouse-low", "source": "mchose_mouse", "trigger": "low",
                          "threshold": mchose.get("low_battery_threshold", 20),
                          "actions": [{"target": "mchose_base", "effect": lb_eff}]})
    else:
        rules += [r for r in DEFAULTS["rules"] if r["source"] == "mchose_mouse"]

    cfg, _ = validate_config({"poll": DEFAULTS["poll"],
                              "critical_threshold": DEFAULTS["critical_threshold"],
                              "rules": rules})
    return cfg
```

- [ ] **Step 4: Ver pasar**

Run: `python3 -m pytest rgb/tests/ -q`
Expected: PASS (todos)

- [ ] **Step 5: Commit**

```bash
git add rgb/battery-lighting rgb/tests/test_config.py
git commit -m "feat(battery-lighting): seed + migrate legacy akko/mchose configs

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 5: Color por nivel + fracción del medidor + chunks del lienzo Akko

**Files:**
- Modify: `rgb/battery-lighting`
- Create: `rgb/tests/test_effects.py`

**Interfaces:**
- Produces:
  - `battery_level_color(level: int|None) -> tuple[int,int,int]` — idéntica a `get_akko_battery_level_color` de `rgb/sync-rgb.py:270` (≤15 rojo; luego HSV rojo→verde). Copiar, no importar.
  - `meter_rows(level: int|None, n_rows: int = 5) -> int` — nº de filas llenas de abajo arriba (`round(level/100*n_rows)`, mínimo 1 si level>0).
  - `akko_canvas_chunks(rgb_per_key: list[tuple[int,int,int]]) -> list[bytes]` — 130 teclas → 7 buffers de 64 bytes (`0x0C`, cabecera según `docs/HARDWARE_PROTOCOLS.md §1.G`).
  - `AKKO_KEY_ROWS: list[list[int]]` — mapa parcial de coordenadas de `docs/HARDWARE_PROTOCOLS.md §1.G` (5 filas; índice de tecla por columna).
  - `akko_meter_keys(level: int|None) -> list[tuple[int,int,int]]` — 130 tuplas; enciende las filas de abajo según `meter_rows`, resto apagado, color `battery_level_color`.

- [ ] **Step 1: Tests que fallan**

`rgb/tests/test_effects.py`:
```python
def test_battery_level_color_low_is_pure_red(bl):
    assert bl.battery_level_color(10) == (255, 0, 0)


def test_battery_level_color_full_is_greenish(bl):
    r, g, b = bl.battery_level_color(100)
    assert g > r and g > b


def test_meter_rows_scales(bl):
    assert bl.meter_rows(0, 5) == 0
    assert bl.meter_rows(1, 5) == 1
    assert bl.meter_rows(50, 5) == 3          # round(2.5)
    assert bl.meter_rows(100, 5) == 5


def test_akko_canvas_chunks_shape(bl):
    chunks = bl.akko_canvas_chunks([(1, 2, 3)] * 130)
    assert len(chunks) == 7
    assert all(len(c) == 64 for c in chunks)
    assert chunks[0][0] == 0x0C
    assert chunks[0][4] == 0        # chunk_index del primer chunk
    assert chunks[6][4] == 6


def test_akko_meter_keys_all_off_at_zero(bl):
    keys = bl.akko_meter_keys(0)
    assert len(keys) == 130
    assert set(keys) == {(0, 0, 0)}


def test_akko_meter_keys_full_lights_bottom_rows(bl):
    keys = bl.akko_meter_keys(100)
    # al menos las teclas mapeadas de la fila inferior están encendidas
    lit = [keys[i] for i in bl.AKKO_KEY_ROWS[-1]]
    assert all(px != (0, 0, 0) for px in lit)
```

- [ ] **Step 2: Ver fallar**

Run: `python3 -m pytest rgb/tests/test_effects.py -q`
Expected: FAIL.

- [ ] **Step 3: Implementar**

En `rgb/battery-lighting` (usar `colorsys`, ya importado en la cabecera de Task 1 — añadir `import colorsys` si falta):
```python
import colorsys


def battery_level_color(level):
    if level is None:
        level = 100
    level = max(0, min(100, level))
    if level <= 15:
        return (255, 0, 0)
    hue = ((level - 15) / 85.0) * (120.0 / 360.0)
    r, g, b = colorsys.hsv_to_rgb(hue, 1.0, 1.0)
    return (int(r * 255), int(g * 255), int(b * 255))


def meter_rows(level, n_rows=5):
    if not level or level <= 0:
        return 0
    return max(1, min(n_rows, round(level / 100 * n_rows)))


# docs/HARDWARE_PROTOCOLS.md §1.G — mapa PARCIAL, validar contra hardware (Task 12).
AKKO_KEY_ROWS = [
    [7, 13, 19, 25, 31, 37, 43, 49, 55, 61, 67, 73],   # números (arriba)
    [8, 14, 20, 26, 32, 38, 44, 50, 56, 62, 68],        # QWERTY
    [9, 15, 21, 27, 33, 39, 45, 51, 57, 63, 69],        # ASDF
    [10, 16, 22, 28, 34, 40, 46, 52, 58, 64],           # ZXCV
    [11, 17, 23, 29, 35, 41, 47, 53, 59],               # inferior (Ctrl/Alt/Espacio)
]


def akko_meter_keys(level):
    keys = [(0, 0, 0)] * 130
    rows_on = meter_rows(level, len(AKKO_KEY_ROWS))
    colour = battery_level_color(level)
    # AKKO_KEY_ROWS[0] es la fila de arriba; encendemos desde abajo.
    for row in AKKO_KEY_ROWS[len(AKKO_KEY_ROWS) - rows_on:]:
        for idx in row:
            if 0 <= idx < 130:
                keys[idx] = colour
    return keys


def akko_canvas_chunks(rgb_per_key):
    flat = bytearray()
    for (r, g, b) in rgb_per_key[:130]:
        flat += bytes((r, g, b))
    flat += bytes(392 - len(flat))
    chunks = []
    for ci in range(7):
        buf = bytearray(64)
        buf[0] = 0x0C
        buf[1] = 0x00
        buf[2] = 0x80
        buf[3] = 0x01
        buf[4] = ci
        payload = flat[ci * 56:(ci + 1) * 56]
        buf[8:8 + len(payload)] = payload
        chunks.append(bytes(buf))
    return chunks
```

- [ ] **Step 4: Ver pasar**

Run: `python3 -m pytest rgb/tests/ -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rgb/battery-lighting rgb/tests/test_effects.py
git commit -m "feat(battery-lighting): battery colour, meter fill, akko canvas chunks

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 6: Telemetría (portada de `mchose-battery`)

**Files:**
- Modify: `rgb/battery-lighting`
- Create: `rgb/tests/test_telemetry.py`

**Interfaces:**
- Produces:
  - `read_telemetry() -> dict` — `{"akko_keyboard": {"level","charging","connected"}, "mchose_mouse": {...}, "v9_headset": {...}}`. Portar `get_v9_pro_battery`, `get_k7_ultra_battery` (sin `handle_charging_lighting_transition`), `get_akko_keyboard_battery` de `rgb/mchose-battery` — copiar los helpers `glob_hidraw_nodes`, `HIDIOCSFEATURE`, `HIDIOCGFEATURE`. `charging` = `status == "Cargando"`.
  - `write_battery_cache(tele: dict) -> None` — vuelca al formato de `~/.cache/mchose_battery.json` (`v9_battery`, `v9_status`, `k7_battery`, `k7_status`, `akko_battery`, `akko_status`), preservando `notified_levels`.
  - `read_battery_cache() -> dict` — para el modo fallback de `mchose-battery`.

- [ ] **Step 1: Test que falla**

`rgb/tests/test_telemetry.py`:
```python
def test_write_then_shape_of_cache(bl, tmp_path):
    tele = {
        "akko_keyboard": {"level": 80, "charging": True, "connected": True},
        "mchose_mouse": {"level": 40, "charging": False, "connected": True},
        "v9_headset": {"level": None, "charging": False, "connected": False},
    }
    bl.write_battery_cache(tele)
    import json
    data = json.loads(open(bl.BATTERY_CACHE).read())
    assert data["akko_battery"] == 80
    assert data["akko_status"] == "Cargando"
    assert data["k7_status"] == "Descargando"


def test_write_battery_cache_preserves_notified_levels(bl):
    import json
    with open(bl.BATTERY_CACHE, "w") as f:
        json.dump({"notified_levels": {"k7": 20}}, f)
    bl.write_battery_cache({"akko_keyboard": {"level": 50, "charging": False, "connected": True},
                            "mchose_mouse": {"level": None, "charging": False, "connected": False},
                            "v9_headset": {"level": None, "charging": False, "connected": False}})
    assert json.loads(open(bl.BATTERY_CACHE).read())["notified_levels"] == {"k7": 20}


def test_read_telemetry_runs_without_hardware(bl):
    tele = bl.read_telemetry()
    assert set(tele) == {"akko_keyboard", "mchose_mouse", "v9_headset"}
    for v in tele.values():
        assert set(v) == {"level", "charging", "connected"}
```

- [ ] **Step 2: Ver fallar**

Run: `python3 -m pytest rgb/tests/test_telemetry.py -q`
Expected: FAIL.

- [ ] **Step 3: Implementar**

Portar desde `rgb/mchose-battery` (líneas: helpers `glob_hidraw_nodes` ~52, `load_cache`/`save_cache` ~35, `get_v9_pro_battery` ~93, `get_k7_ultra_battery` ~294 **omitiendo** las llamadas a `handle_charging_lighting_transition`, `get_akko_keyboard_battery` ~365). Al portar `load_cache`/`save_cache`, sustituir la constante `CACHE_FILE` por el módulo-var `BATTERY_CACHE` (para que el fixture de tests lo redirija). Envolver cada `get_*` en try/except que devuelva `(None, "Desconectado")`. Construir:
```python
def read_telemetry():
    def one(fn):
        try:
            lvl, st = fn()
        except Exception:
            lvl, st = None, "Desconectado"
        return {"level": lvl, "charging": (st == "Cargando"), "connected": lvl is not None}
    return {
        "akko_keyboard": one(get_akko_keyboard_battery),
        "mchose_mouse": one(get_k7_ultra_battery),
        "v9_headset": one(get_v9_pro_battery),
    }


def read_battery_cache():
    try:
        with open(BATTERY_CACHE) as f:
            return json.load(f)
    except Exception:
        return {}


def write_battery_cache(tele):
    data = read_battery_cache()
    m = {"akko_keyboard": "akko", "mchose_mouse": "k7", "v9_headset": "v9"}
    for src, pref in m.items():
        t = tele[src]
        data[f"{pref}_battery"] = t["level"]
        data[f"{pref}_status"] = ("Cargando" if t["charging"]
                                  else ("Descargando" if t["connected"] else "Desconectado"))
    os.makedirs(os.path.dirname(BATTERY_CACHE), exist_ok=True)
    with open(BATTERY_CACHE, "w") as f:
        json.dump(data, f)
```

- [ ] **Step 4: Ver pasar**

Run: `python3 -m pytest rgb/tests/ -q`
Expected: PASS (`test_read_telemetry_runs_without_hardware` pasa porque no hay nodos hidraw → todo `None`).

- [ ] **Step 5: Commit**

```bash
git add rgb/battery-lighting rgb/tests/test_telemetry.py
git commit -m "feat(battery-lighting): port battery telemetry + cache writer

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 7: Aplicadores de efectos — MCHOSE base, MagicHome, Akko tira/teclas (no medidor)

**Files:**
- Modify: `rgb/battery-lighting`
- Modify: `rgb/tests/test_effects.py`

**Interfaces:**
- Produces:
  - `build_mchose_base_payload(effect: str, level: int|None, theme_rgb: tuple) -> bytes|None` — 21 bytes listos para `ioctl` (con `Report ID 0x11` + XOR). Portar payloads de `apply_charging_lighting` / `apply_low_battery_lighting` de `rgb/mchose-battery:162-255`.
  - `build_akko_packets(zone: str, effect: str, level: int|None, theme_rgb: tuple) -> list[bytes]` — lista de buffers de 65 bytes (`0x00` + 64) para `0x07` (teclas) y/o `0x08` (tira). Portar de `rgb/sync-rgb.py:sync_akko_keyboard` (estructura + `_akko_checksum8`). `battery_meter` en `keys` se maneja en Task 8; aquí para `keys` cubre `theme|breathing_battery|stream|red_breathing|red_static|none`.
  - `apply_zone(zonekey: str, action: dict|None, theme_rgb: tuple) -> None` — despacha al hardware. `action is None` → repinta la zona al tema (invoca `sync-rgb.py --only <device>`).
  - `_akko_checksum8(buf) -> int`, `_hidraw_nodes(vid, pids) -> list[str]`, `_write_feature(node, raw) -> None` copiados de `rgb/rgb-notify-flash:113-142`.
  - Placeholders forward que las Tasks 8-9 rellenan: `def _akko_nodes(): return []`, `def apply_akko_meter(level): pass`, `def apply_magichome(*a): pass`, `def apply_openrgb(*a): pass`. Los tests de esta tarea sólo ejercen los builders, no `apply_zone`.

- [ ] **Step 1: Tests que fallan**

Añadir a `rgb/tests/test_effects.py`:
```python
def test_mchose_payload_red_breathing_encodes_red(bl):
    raw = bl.build_mchose_base_payload("red_breathing", 15, (10, 20, 30))
    assert raw[0] == 0x11
    dec = [raw[0]] + [x ^ 0xFF for x in raw[1:]]
    assert dec[1] == 0x2B
    assert (dec[10], dec[11], dec[12]) == (255, 0, 0)   # bytes de color del anillo


def test_mchose_payload_none_returns_none(bl):
    assert bl.build_mchose_base_payload("none", 50, (1, 2, 3)) is None


def test_akko_sidestrip_red_static_packet(bl):
    pkts = bl.build_akko_packets("sidestrip", "red_static", 12, (9, 9, 9))
    assert len(pkts) == 1
    body = pkts[0][1:]                 # quita Report ID 0x00
    assert body[0] == 0x08            # opcode tira lateral
    assert body[1] == 0x01            # modo fijo
    assert (body[5], body[6], body[7]) == (255, 0, 0)
    assert body[8] == (0xFF - (sum(body[:8]) & 0xFF)) & 0xFF


def test_akko_keys_theme_uses_theme_rgb(bl):
    pkts = bl.build_akko_packets("keys", "theme", 90, (12, 34, 56))
    body = pkts[0][1:]
    assert body[0] == 0x07
    assert (body[5], body[6], body[7]) == (12, 34, 56)
```

- [ ] **Step 2: Ver fallar**

Run: `python3 -m pytest rgb/tests/test_effects.py -q`
Expected: FAIL.

- [ ] **Step 3: Implementar**

Portar los tres builders. Mapa efecto→(modo, velocidad, color) para la tira/teclas Akko:

| effect | modo `byte[1]` | vel `byte[2]` | color |
| --- | --- | --- | --- |
| `theme` / `solid_theme` | `0x01` | `0x04` | `theme_rgb` |
| `red_static` | `0x01` | `0x04` | `255,0,0` |
| `red_breathing` | `0x02` | `0x02` | `255,0,0` |
| `breathing` / `breathing_battery` | `0x02` | `0x02` | `theme_rgb` / `battery_level_color(level)` |
| `stream` / `stream_battery` | `0x05` | `0x00` | `battery_level_color(level)` |
| `none` | — | — | devuelve `[]` |

`byte[3]=0x04` (brillo), `byte[4]=0x08` (flags custom RGB), `byte[8]=_akko_checksum8`. Para MCHOSE base usar exactamente los `payload = [...]` de `rgb/mchose-battery:187-200` y `:232-245` según `effect` (`theme_breathing|battery_color|hardware_battery|wave|red_breathing|red_static`), con `bat_r/bat_g/bat_b` = `battery_level_color(level)` y `th_*` = `theme_rgb`.

`apply_zone`:
```python
_DEVICE_OF_ZONE = {"akko_keyboard": "akko_keyboard", "mchose_base": "mchose_base",
                   "magichome": "magichome", "openrgb": "openrgb"}


def apply_zone(zonekey, action, theme_rgb):
    target, zone = zonekey.split(":")
    if action is None:
        subprocess.run([sys.executable, SYNC_RGB, "--only", _DEVICE_OF_ZONE[target]],
                       timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    eff, level = action["effect"], action.get("level")
    if target == "mchose_base":
        raw = build_mchose_base_payload(eff, level, theme_rgb)
        if raw:
            for n in _hidraw_nodes("3837", ("1001",)):
                _write_feature(n, raw)
    elif target == "akko_keyboard":
        if zone == "keys" and eff == "battery_meter":
            apply_akko_meter(level); return            # Task 8
        for pkt in build_akko_packets(zone, eff, level, theme_rgb):
            for n in _akko_nodes():
                _write_feature(n, pkt)
    elif target == "magichome":
        apply_magichome(eff, level, theme_rgb)          # Task 9
    elif target == "openrgb":
        apply_openrgb(eff, level, theme_rgb)            # Task 9
```

- [ ] **Step 4: Ver pasar**

Run: `python3 -m pytest rgb/tests/ -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rgb/battery-lighting rgb/tests/test_effects.py
git commit -m "feat(battery-lighting): effect payload builders for base + akko zones

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 8: `battery_meter` sobre las teclas del Akko (con throttle y anti-corrupción RF)

**Files:**
- Modify: `rgb/battery-lighting`
- Modify: `rgb/tests/test_effects.py`

**Interfaces:**
- Consumes: `akko_meter_keys`, `akko_canvas_chunks`, `_akko_nodes`, `_write_feature`.
- Produces:
  - `apply_akko_meter(level: int|None) -> None` — activa modo lienzo (`0x07` con `byte[1]=0x0D`, checksum) y envía los 7 chunks `0x0C`, con `time.sleep(0.03)` entre escrituras. No-op si el nivel redondeado no cambió desde la última vez (`STATE_CACHE` clave `"akko_meter_level"`).
  - `_akko_nodes() -> list[str]` — nodos hidraw `3151:4015` (cable) preferidos, si no `3151:4011` (dongle), interfaz `:1.2`. Portar de `rgb/sync-rgb.py:297-315`.

- [ ] **Step 1: Tests que fallan**

```python
def test_apply_akko_meter_no_nodes_is_noop(bl, monkeypatch):
    monkeypatch.setattr(bl, "_akko_nodes", lambda: [])
    sent = []
    monkeypatch.setattr(bl, "_write_feature", lambda n, raw: sent.append(raw))
    bl.apply_akko_meter(50)
    assert sent == []                 # sin nodos no intenta escribir


def test_apply_akko_meter_dedupes_same_level(bl, monkeypatch):
    monkeypatch.setattr(bl, "_akko_nodes", lambda: ["/dev/null-fake"])
    calls = []
    monkeypatch.setattr(bl, "_write_feature", lambda n, raw: calls.append(bytes(raw)))
    bl.apply_akko_meter(48)
    first = len(calls)
    assert first >= 8                 # 1 activación + 7 chunks
    bl.apply_akko_meter(49)           # mismo nivel redondeado a fila -> no reenvía
    assert len(calls) == first
```

- [ ] **Step 2: Ver fallar** — Run: `python3 -m pytest rgb/tests/test_effects.py -q` → FAIL.

- [ ] **Step 3: Implementar**

```python
def _load_state():
    try:
        with open(STATE_CACHE) as f:
            return json.load(f)
    except Exception:
        return {}


def _save_state(st):
    try:
        with open(STATE_CACHE, "w") as f:
            json.dump(st, f)
    except Exception:
        pass


def apply_akko_meter(level):
    nodes = _akko_nodes()
    if not nodes:
        return
    rows = meter_rows(level, len(AKKO_KEY_ROWS))
    st = _load_state()
    if st.get("akko_meter_level") == rows:
        return
    activate = bytearray(64)
    activate[0] = 0x07
    activate[1] = 0x0D
    activate[2] = 0x04
    activate[3] = 0x04
    activate[8] = (0xFF - (sum(activate[:8]) & 0xFF)) & 0xFF
    packets = [bytes([0x00]) + activate] + [bytes([0x00]) + c for c in
                                            akko_canvas_chunks(akko_meter_keys(level))]
    node = nodes[0]
    for pkt in packets:
        _write_feature(node, bytearray(pkt))
        time.sleep(0.03)
    st["akko_meter_level"] = rows
    _save_state(st)
```

- [ ] **Step 4: Ver pasar** — `python3 -m pytest rgb/tests/ -q` → PASS.

- [ ] **Step 5: Commit**

```bash
git add rgb/battery-lighting rgb/tests/test_effects.py
git commit -m "feat(battery-lighting): akko per-key battery meter with RF-safe throttle

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 9: Aplicadores MagicHome y OpenRGB

**Files:**
- Modify: `rgb/battery-lighting`
- Modify: `rgb/tests/test_effects.py`

**Interfaces:**
- Produces:
  - `apply_magichome(effect: str, level: int|None, theme_rgb: tuple) -> None` — `subprocess.run(["~/.local/bin/magichome-control", "--color", "<rrggbb>"])`. Color: `battery_color`→`battery_level_color(level)`, `solid_theme`→`theme_rgb`, `red`→`(255,0,0)`, `none`→no-op (no llama a subprocess).
  - `apply_openrgb(effect: str, level: int|None, theme_rgb: tuple) -> None` — vía SDK `openrgb` (import perezoso dentro de la función, try/except → log y salir). `solid_theme`/`red` → `set_color` en zonas no direccionables + direccionables. `battery_meter` en v1 → **degrada a color sólido** `battery_level_color(level)` en las zonas ARGB (relleno LED-a-LED animado queda para una v2 integrada con `argb-wave.py`; anotarlo con `log()` y un `# TODO v2`). `none` → no-op.

- [ ] **Step 1: Tests que fallan**

```python
def test_apply_magichome_none_does_not_call_subprocess(bl, monkeypatch):
    called = []
    monkeypatch.setattr(bl.subprocess, "run", lambda *a, **k: called.append(a))
    bl.apply_magichome("none", 10, (1, 2, 3))
    assert called == []


def test_apply_magichome_battery_color_calls_control_with_hex(bl, monkeypatch):
    calls = []
    monkeypatch.setattr(bl.subprocess, "run", lambda *a, **k: calls.append(list(a[0])))
    bl.apply_magichome("battery_color", 10, (1, 2, 3))
    flat = [tok for c in calls for tok in c]
    assert any("magichome-control" in tok for tok in flat)
    assert "ff0000" in flat            # rojo puro por nivel <= 15


def test_apply_openrgb_missing_sdk_is_swallowed(bl, monkeypatch):
    import builtins
    real = builtins.__import__
    def boom(name, *a, **k):
        if name == "openrgb":
            raise ImportError("no sdk")
        return real(name, *a, **k)
    monkeypatch.setattr(builtins, "__import__", boom)
    bl.apply_openrgb("solid_theme", 50, (1, 2, 3))   # no lanza
```

- [ ] **Step 2: Ver fallar** — FAIL.

- [ ] **Step 3: Implementar**

```python
MAGICHOME_CONTROL = f"{HOME}/.local/bin/magichome-control"


def _effect_rgb(effect, level, theme_rgb):
    if effect in ("battery_color",):
        return battery_level_color(level)
    if effect in ("solid_theme",):
        return tuple(theme_rgb)
    if effect == "red":
        return (255, 0, 0)
    return None


def apply_magichome(effect, level, theme_rgb):
    rgb = _effect_rgb(effect, level, theme_rgb)
    if rgb is None:
        return
    hexs = "%02x%02x%02x" % rgb
    try:
        subprocess.run([MAGICHOME_CONTROL, "--color", hexs], timeout=6,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        log(f"magichome: {e}")


def apply_openrgb(effect, level, theme_rgb):
    if effect == "none":
        return
    if effect == "battery_meter":
        log("openrgb battery_meter -> sólido por nivel (relleno animado es v2)")  # TODO v2: integrar con argb-wave.py
        rgb = battery_level_color(level)
    else:
        rgb = _effect_rgb(effect, level, theme_rgb) or tuple(theme_rgb)
    try:
        from openrgb import OpenRGBClient
        from openrgb.utils import RGBColor
        client = OpenRGBClient()
        for dev in client.devices:
            name_l = dev.name.lower()
            if "akko" in name_l or "royuan" in name_l:
                continue
            try:
                dev.set_mode(0)
                dev.set_color(RGBColor(*rgb))
            except Exception:
                pass
    except Exception as e:
        log(f"openrgb: {e}")
```

- [ ] **Step 4: Ver pasar** — `python3 -m pytest rgb/tests/ -q` → PASS.

- [ ] **Step 5: Commit**

```bash
git add rgb/battery-lighting rgb/tests/test_effects.py
git commit -m "feat(battery-lighting): magichome + openrgb appliers (meter degrades to solid v1)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 10: Ciclo `tick`, publicación de `battery_alerts.json`, notificaciones, y modos CLI

**Files:**
- Modify: `rgb/battery-lighting`
- Create: `rgb/tests/test_tick.py`

**Interfaces:**
- Consumes: `read_telemetry`, `write_battery_cache`, `load_config`, `resolve`, `apply_zone`, telemetría.
- Produces:
  - `theme_primary_rgb() -> tuple[int,int,int]` — de `~/.local/state/caelestia/scheme.json` (portar `get_theme_primary_rgb` de `rgb/mchose-battery:149`).
  - `read_alerts() -> dict`, `write_alerts(alerts: dict) -> None` (a `ALERTS_CACHE`).
  - `tick(config: dict|None = None, telemetry: dict|None = None) -> dict` — lee todo, resuelve, aplica sólo las zonas cuyo estado cambió respecto a `read_alerts()`, repinta al tema las zonas liberadas, escribe `battery_alerts.json` y la caché de batería, emite notificaciones de escritorio (misma lógica de umbrales que `check_and_notify` de `rgb/mchose-battery:497`), devuelve el mapa de alertas nuevo.
  - `main(argv)` completo: `--daemon` (bucle con cadencia adaptativa), `--tick`, `--apply <id>`, `--clear`, `--dump`.
  - `send_notification(title, message, icon, urgency)` copiado de `rgb/mchose-battery:544`.

- [ ] **Step 1: Tests que fallan**

`rgb/tests/test_tick.py`:
```python
import json


def _cfg_one_low():
    return {"poll": {"idle_seconds": 60, "charging_seconds": 3}, "critical_threshold": 10,
            "rules": [{"id": "r", "source": "mchose_mouse", "trigger": "low", "threshold": 20,
                       "actions": [{"target": "mchose_base", "effect": "red_breathing"}]}]}


def test_tick_writes_alerts_for_active_rule(bl, monkeypatch):
    monkeypatch.setattr(bl, "theme_primary_rgb", lambda: (1, 2, 3))
    applied = []
    monkeypatch.setattr(bl, "apply_zone", lambda zk, act, th: applied.append((zk, act and act["effect"])))
    monkeypatch.setattr(bl, "send_notification", lambda *a, **k: None)
    tele = {"akko_keyboard": {"level": None, "charging": False, "connected": False},
            "mchose_mouse": {"level": 15, "charging": False, "connected": True},
            "v9_headset": {"level": None, "charging": False, "connected": False}}
    out = bl.tick(_cfg_one_low(), tele)
    assert "mchose_base:_" in out
    assert json.loads(open(bl.ALERTS_CACHE).read())["mchose_base:_"]["effect"] == "red_breathing"
    assert ("mchose_base:_", "red_breathing") in applied


def test_tick_releases_zone_when_rule_clears(bl, monkeypatch):
    monkeypatch.setattr(bl, "theme_primary_rgb", lambda: (1, 2, 3))
    with open(bl.ALERTS_CACHE, "w") as f:
        json.dump({"mchose_base:_": {"effect": "red_breathing", "trigger": "low",
                                     "source": "mchose_mouse", "level": 15}}, f)
    released = []
    monkeypatch.setattr(bl, "apply_zone", lambda zk, act, th: released.append((zk, act)))
    monkeypatch.setattr(bl, "send_notification", lambda *a, **k: None)
    tele = {"akko_keyboard": {"level": None, "charging": False, "connected": False},
            "mchose_mouse": {"level": 80, "charging": False, "connected": True},
            "v9_headset": {"level": None, "charging": False, "connected": False}}
    out = bl.tick(_cfg_one_low(), tele)
    assert out == {}
    assert ("mchose_base:_", None) in released       # None -> repinta al tema
    assert json.loads(open(bl.ALERTS_CACHE).read()) == {}


def test_tick_only_applies_changed_zones(bl, monkeypatch):
    monkeypatch.setattr(bl, "theme_primary_rgb", lambda: (1, 2, 3))
    with open(bl.ALERTS_CACHE, "w") as f:
        json.dump({"mchose_base:_": {"effect": "red_breathing", "trigger": "low",
                                     "source": "mchose_mouse", "level": 15}}, f)
    applied = []
    monkeypatch.setattr(bl, "apply_zone", lambda zk, act, th: applied.append(zk))
    monkeypatch.setattr(bl, "send_notification", lambda *a, **k: None)
    tele = {"akko_keyboard": {"level": None, "charging": False, "connected": False},
            "mchose_mouse": {"level": 14, "charging": False, "connected": True},
            "v9_headset": {"level": None, "charging": False, "connected": False}}
    bl.tick(_cfg_one_low(), tele)
    assert applied == []              # misma effect/trigger -> no reescribe hardware


def test_main_dump_prints_json(bl, monkeypatch, capsys):
    monkeypatch.setattr(bl, "read_telemetry", lambda: {
        "akko_keyboard": {"level": None, "charging": False, "connected": False},
        "mchose_mouse": {"level": None, "charging": False, "connected": False},
        "v9_headset": {"level": None, "charging": False, "connected": False}})
    assert bl.main(["--dump"]) == 0
    json.loads(capsys.readouterr().out)   # salida es JSON válido
```

- [ ] **Step 2: Ver fallar** — FAIL.

- [ ] **Step 3: Implementar** `tick`, cachés de alertas, `theme_primary_rgb`, notificaciones y el `main` completo:
```python
def tick(config=None, telemetry=None):
    config = config or load_config()
    telemetry = telemetry or read_telemetry()
    write_battery_cache(telemetry)
    theme = theme_primary_rgb()
    new = resolve(config, telemetry)
    old = read_alerts()

    for zk, payload in new.items():
        prev = old.get(zk)
        if not prev or prev.get("effect") != payload["effect"] or prev.get("trigger") != payload["trigger"]:
            apply_zone(zk, payload, theme)
    for zk in old:
        if zk not in new:
            apply_zone(zk, None, theme)

    write_alerts(new)
    _notify(config, telemetry)
    return new


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(USAGE); return 0
    cmd = argv[0]
    if cmd == "--tick":
        tick(); return 0
    if cmd == "--clear":
        theme = theme_primary_rgb()
        for zk in read_alerts():
            apply_zone(zk, None, theme)
        write_alerts({}); return 0
    if cmd == "--dump":
        print(json.dumps({"telemetry": read_telemetry(),
                          "alerts": resolve(load_config(), read_telemetry())}, indent=2))
        return 0
    if cmd == "--apply" and len(argv) > 1:
        cfg = load_config()
        rule = next((r for r in cfg["rules"] if r["id"] == argv[1]), None)
        if not rule:
            print(f"regla desconocida: {argv[1]}"); return 1
        theme = theme_primary_rgb()
        for a in rule["actions"]:
            for zk in _zone_keys(a):
                apply_zone(zk, {"effect": a["effect"], "trigger": rule["trigger"],
                                "source": rule["source"], "level": 50}, theme)
        return 0
    if cmd == "--daemon":
        return _daemon_loop()
    print(USAGE); return 0


def _daemon_loop():
    while True:
        try:
            new = tick()
            charging = any(v.get("trigger") == "charging" for v in new.values())
        except Exception as e:
            log(f"tick error: {e}"); charging = False
        cfg = load_config()
        time.sleep(cfg["poll"]["charging_seconds"] if charging else cfg["poll"]["idle_seconds"])
```

`_notify(config, telemetry)` porta la lógica de `check_and_notify` (`rgb/mchose-battery:497-542`): dedupe por `notified_levels` en la caché de batería, crítico ≤ `critical_threshold`, bajo ≤ 20, `notify-send` vía `send_notification`.

- [ ] **Step 4: Ver pasar** — `python3 -m pytest rgb/tests/ -q` → PASS (todo).

- [ ] **Step 5: Commit**

```bash
git add rgb/battery-lighting rgb/tests/test_tick.py
git commit -m "feat(battery-lighting): tick cycle, alerts cache, notifications, CLI modes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 11: `sync-rgb.py` y `rgb-notify-flash` respetan `battery_alerts.json`

**Files:**
- Modify: `rgb/sync-rgb.py`
- Modify: `rgb/rgb-notify-flash`
- Create: `rgb/tests/test_sync_rgb_alerts.py`

**Interfaces:**
- Consumes: `~/.cache/battery_alerts.json` (formato de la Task 10).
- Produces (en `sync-rgb.py`):
  - `battery_alert_zones() -> set[str]` — lee el fichero; devuelve `{"akko_keyboard:keys", "mchose_base:_", ...}`; `{}` si no existe.
  - `sync_akko_keyboard`: quita el bloque reactivo de batería (`rgb/sync-rgb.py:322-367`); antes de construir cada paquete comprueba `f"akko_keyboard:{zone}"` en `battery_alert_zones()` y salta esa zona. Si ambas zonas están reclamadas, `return` sin tocar el teclado.
  - `sync_mchose_base` / `sync_magichome` / `sync_openrgb`: `if "<target>:_" in battery_alert_zones(): log(...); return`.
- Produces (en `rgb-notify-flash`): `restore()` — si `f"{dev}:_"` (o zonas Akko) está en las alertas activas, en vez de repintar al tema invoca `subprocess.run([sys.executable, BATTERY_LIGHTING, "--tick"])` (nuevo `BATTERY_LIGHTING = ~/.local/bin/battery-lighting`).

- [ ] **Step 1: Tests que fallan**

`rgb/tests/test_sync_rgb_alerts.py`:
```python
import importlib.util
from pathlib import Path

_SR = Path(__file__).resolve().parents[1] / "sync-rgb.py"


def _load_sync():
    spec = importlib.util.spec_from_file_location("sync_rgb", _SR)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def test_battery_alert_zones_empty_without_file(tmp_path, monkeypatch):
    m = _load_sync()
    monkeypatch.setattr(m, "ALERTS_CACHE", str(tmp_path / "nope.json"))
    assert m.battery_alert_zones() == set()


def test_battery_alert_zones_parses(tmp_path, monkeypatch):
    m = _load_sync()
    p = tmp_path / "a.json"
    p.write_text('{"mchose_base:_": {"effect":"red_breathing"}, "akko_keyboard:keys": {}}')
    monkeypatch.setattr(m, "ALERTS_CACHE", str(p))
    assert m.battery_alert_zones() == {"mchose_base:_", "akko_keyboard:keys"}
```

- [ ] **Step 2: Ver fallar** — Run: `python3 -m pytest rgb/tests/test_sync_rgb_alerts.py -q` → FAIL.

- [ ] **Step 3: Implementar** en `sync-rgb.py` (añadir `ALERTS_CACHE = os.path.expanduser("~/.cache/battery_alerts.json")` junto a las otras rutas ~28; añadir `battery_alert_zones`; editar los `sync_*`). En `sync_akko_keyboard` sustituir el bloque `if is_charging: … elif bat_pct <= 20: … else:` (que fija `sled`) por: la tira lateral sólo se pinta al color del tema si `"akko_keyboard:sidestrip"` **no** está reclamada; sino se omite el paquete `0x08`. Igual con `0x07` y `akko_keyboard:keys`.

- [ ] **Step 4: Ver pasar** — `python3 -m pytest rgb/tests/ -q` → PASS.

- [ ] **Step 5: Verificación manual (sin hardware obligatorio)**

Run: `python3 rgb/sync-rgb.py --help` → imprime uso sin error.
Run: `python3 -c "import ast; ast.parse(open('rgb/rgb-notify-flash').read())"` → sin error.

- [ ] **Step 6: Commit**

```bash
git add rgb/sync-rgb.py rgb/rgb-notify-flash rgb/tests/test_sync_rgb_alerts.py
git commit -m "feat(rgb): sync-rgb + notify-flash defer to active battery alerts

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 12: Adelgazar `mchose-battery` + espejo + `CLAUDE.md`

**Files:**
- Modify: `rgb/mchose-battery`
- Modify: `widgets/mchose-battery`
- Modify: `CLAUDE.md`
- Create: `rgb/tests/test_mchose_battery_slim.py`

**Interfaces:**
- Produces: `rgb/mchose-battery` con sólo: helpers HID, `get_v9_pro_battery`, `get_k7_ultra_battery` (sin `handle_charging_lighting_transition`), `get_akko_keyboard_battery`, y un `main` con `--json` / `--waybar-headset` / `--waybar-mouse`. Todos los `get_*` primero intentan `~/.cache/mchose_battery.json` si es fresco (< 90 s) y el daemon está activo (`~/.cache/battery_lighting.log` mtime < 120 s), si no leen directo.
- Se eliminan: `get_theme_primary_rgb`, `apply_charging_lighting`, `apply_low_battery_lighting`, `handle_charging_lighting_transition`, `apply_akko_battery_lighting`, `apply_akko_*`, `check_and_notify`, `send_notification`, y los flags `--notify`, `--daemon`, `--trigger-lighting`, `--restore-lighting`, `--akko-mode`, `--akko-battery`.

- [ ] **Step 1: Test que falla**

`rgb/tests/test_mchose_battery_slim.py`:
```python
import subprocess, sys
from pathlib import Path

MB = Path(__file__).resolve().parents[1] / "mchose-battery"


def test_no_lighting_symbols_left():
    src = MB.read_text()
    for gone in ("apply_charging_lighting", "apply_akko_battery_lighting",
                 "handle_charging_lighting_transition", "check_and_notify",
                 "--trigger-lighting", "--restore-lighting"):
        assert gone not in src, gone


def test_json_mode_still_runs():
    out = subprocess.run([sys.executable, str(MB), "--json"], capture_output=True, text=True, timeout=10)
    assert out.returncode == 0
    import json
    d = json.loads(out.stdout)
    assert {"headset", "mouse", "keyboard"} <= set(d)


def test_mirror_identical():
    w = MB.parent.parent / "widgets" / "mchose-battery"
    assert MB.read_bytes() == w.read_bytes()
```

- [ ] **Step 2: Ver fallar** — Run: `python3 -m pytest rgb/tests/test_mchose_battery_slim.py -q` → FAIL.

- [ ] **Step 3: Implementar** — recortar `rgb/mchose-battery`; `cp rgb/mchose-battery widgets/mchose-battery`; en `CLAUDE.md` sección "Copias que deben ir idénticas" añadir:
```markdown
- `rgb/mchose-battery` ⇔ `widgets/mchose-battery`
  (verificar con `diff -q`, sin salida).
```

- [ ] **Step 4: Ver pasar** — `python3 -m pytest rgb/tests/ -q` y `diff -q rgb/mchose-battery widgets/mchose-battery` (sin salida).

- [ ] **Step 5: Commit**

```bash
git add rgb/mchose-battery widgets/mchose-battery CLAUDE.md rgb/tests/test_mchose_battery_slim.py
git commit -m "refactor(mchose-battery): telemetry only; lighting moves to battery-lighting

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 13: systemd + install.sh + retirada del timer + validación de hardware

**Files:**
- Create: `systemd/battery-lighting.service`
- Delete: `systemd/mchose-battery.service`, `systemd/mchose-battery.timer`
- Delete: `rgb/mchose-config`
- Modify: `install.sh`
- Modify: `docs/HARDWARE_PROTOCOLS.md`, `docs/AKKO_BATTERY_LIGHTING_FRONTEND.md`
- Modify: `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md`

**Interfaces:**
- Consumes: `rgb/battery-lighting` instalado en `~/.local/bin/battery-lighting`.

- [ ] **Step 1: Crear `systemd/battery-lighting.service`**

```ini
[Unit]
Description=Motor de iluminación reactiva a la batería
After=graphical-session.target openrgb.service

[Service]
Type=simple
ExecStart=%h/.local/bin/battery-lighting --daemon
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
```

- [ ] **Step 2: `install.sh`** — en el bloque `SELECTED_RGB` (líneas ~156-183):
  - añadir copia de `rgb/battery-lighting` → `~/.local/bin/battery-lighting` + `chmod +x`.
  - en el `systemctl --user enable --now` cambiar `mchose-battery.timer` por `battery-lighting.service`.
  - añadir tras el `daemon-reload`: `systemctl --user disable --now mchose-battery.timer mchose-battery.service 2>/dev/null || true`.
  - el `cp -u "$BASE_DIR/systemd/"*.service "$BASE_DIR/systemd/"*.timer` seguirá funcionando (ya no habrá `.timer`; el glob `*.timer` dará error silenciado por el `|| true`; cambiarlo a sólo `*.service`).

- [ ] **Step 3: Borrar** `systemd/mchose-battery.service`, `systemd/mchose-battery.timer`, `rgb/mchose-config`.

Run: `git rm systemd/mchose-battery.service systemd/mchose-battery.timer rgb/mchose-config`

- [ ] **Step 4: Validación de hardware (manual — requiere los periféricos)**

Ejecutar y anotar resultados en la Base de Datos de Errores:
```bash
cp rgb/battery-lighting ~/.local/bin/battery-lighting && chmod +x ~/.local/bin/battery-lighting
~/.local/bin/battery-lighting --dump                     # telemetría real
~/.local/bin/battery-lighting --apply akko-charging      # ¿medidor en teclas? ¿flujo en tira?
~/.local/bin/battery-lighting --apply akko-low           # ¿rojo respiración ambas zonas?
~/.local/bin/battery-lighting --apply mouse-low          # ¿anillo base rojo?
~/.local/bin/battery-lighting --clear
```
- Si el medidor tecla-a-tecla **no** cuadra con `AKKO_KEY_ROWS`: ajustar el mapa contra el hardware; si sigue sin cuadrar, en `apply_zone` cambiar `battery_meter`→`keys` para que llame a `build_akko_packets("keys", "breathing_battery", ...)` y registrar el bloqueo en la Base de Datos de Errores y en `docs/AKKO_BATTERY_LIGHTING_FRONTEND.md`.

- [ ] **Step 5: Actualizar docs** — `docs/HARDWARE_PROTOCOLS.md` §1.D (reglas reactivas ahora las gestiona `battery-lighting.json`); `docs/AKKO_BATTERY_LIGHTING_FRONTEND.md` (marcar §"Qué falta" como hecho / apuntar al motor).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(systemd): battery-lighting.service; retire mchose-battery.timer + mchose-config

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 14: Checkpoint Fase 1 — smoke test integrado

**Files:** ninguno (validación).

- [ ] **Step 1: Suite completa**

Run: `cd /home/alberviz/LinuxRicing && python3 -m pytest rgb/tests/ -q`
Expected: PASS, sin skips inesperados.

- [ ] **Step 2: Lint sintáctico de todos los scripts tocados**

```bash
for f in rgb/battery-lighting rgb/mchose-battery rgb/sync-rgb.py rgb/rgb-notify-flash widgets/mchose-battery; do
  python3 -c "import ast,sys; ast.parse(open('$f').read()); print('ok', '$f')" || exit 1
done
diff -q rgb/mchose-battery widgets/mchose-battery
```

- [ ] **Step 3: Arranque real del daemon (con hardware)**

```bash
systemctl --user daemon-reload
systemctl --user enable --now battery-lighting.service
systemctl --user status battery-lighting.service --no-pager
journalctl --user -u battery-lighting -n 30 --no-pager
cat ~/.cache/battery_alerts.json
```
Enchufar/desenchufar el ratón y confirmar en el journal el cambio de cadencia (60 s ↔ 3 s) y de efecto. Cambiar el wallpaper con una alerta activa y confirmar que `sync-rgb` no pisa la zona.

- [ ] **Step 4: Registrar sesión en el vault** — `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md` y/o el doc de estado: qué efectos validaron, qué degradó.

- [ ] **Step 5: Commit** (si hubo ajustes)

```bash
git add -A && git commit -m "test(battery-lighting): phase 1 integration checkpoint + notes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

# FASE 2 — UI (Centro de Iluminación)

> Se construye contra el contrato de `battery-lighting.json` congelado en Fase 1.
> Patrón de referencia: `services/RgbConfig.qml`, `services/MchoseConfig.qml`,
> `modules/rgbcontrol/AkkoCard.qml`, `modules/rgbcontrol/DispositivosView.qml`.
> No hay tests automáticos de QML en este repo; la verificación es `caelestia shell -k && caelestia shell -d` + inspección visual.

## Task 15: `BatteryLightingConfig.qml` — singleton de config

**Files:**
- Create: `configs/quickshell/caelestia/services/BatteryLightingConfig.qml`

**Interfaces:**
- Produces: singleton con `property var rules` (lista de objetos `{id, source, trigger, threshold, actions}`), `property int criticalThreshold`, `property bool loaded`; métodos `addRule(source, trigger)`, `removeRule(id)`, `setRuleThreshold(id, n)`, `addAction(ruleId, target, zone, effect)`, `updateAction(ruleId, index, {...})`, `removeAction(ruleId, index)`, `probe(ruleId)` (→ `Quickshell.execDetached([binPath, "--apply", ruleId])`). `toJson()` serializa al esquema exacto de Fase 1. `save()` con `Timer` debounce 250 ms → `view.setText(toJson())`; tras guardar, `Quickshell.execDetached([binPath, "--tick"])`.
- `readonly property var sources`, `triggers`, `targets`, `effectsFor(target, zone)` — espejo de las tablas `VALID_*` / `EFFECTS` de `rgb/battery-lighting` (copiadas, con etiquetas en español).

- [ ] **Step 1: Escribir el singleton** siguiendo `MchoseConfig.qml` (FileView + watchChanges + onLoaded/onLoadFailed + Timer). `path: ${home}/.config/caelestia/battery-lighting.json`. `binPath: ${home}/.local/bin/battery-lighting`.

- [ ] **Step 2: Verificar carga**

```bash
caelestia shell -k && sleep 1 && caelestia shell -d
journalctl --user -t quickshell -n 40 --no-pager | grep -i battery || true
```
Expected: sin errores `BatteryLightingConfig:` en el log; el singleton resuelve.

- [ ] **Step 3: Commit**

```bash
git add configs/quickshell/caelestia/services/BatteryLightingConfig.qml
git commit -m "feat(shell): BatteryLightingConfig singleton mirrors battery-lighting.json

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 16: `BatteryActionRow.qml` — editor de una acción

**Files:**
- Create: `configs/quickshell/caelestia/modules/rgbcontrol/BatteryActionRow.qml`
- Modify: `configs/quickshell/caelestia/modules/rgbcontrol/KeyboardPreview.qml` (caso `breathing` para la tira lateral)

**Interfaces:**
- Consumes: `BatteryLightingConfig.targets`, `.effectsFor(...)`, `KeyboardPreview.qml`, componentes `Chip.qml`, `StyledText`, `Tokens`.
- Produces: fila con `required property string ruleId`, `required property int index`, `required property var action`. Menús: destino (chips), zona (chips `Teclas/Tira lateral/Ambas`, sólo visible si `action.target === "akko_keyboard"`), efecto (chips de `effectsFor`). Botón ✕ → `BatteryLightingConfig.removeAction(ruleId, index)`. Cuando `target==="akko_keyboard"`, incrustar `KeyboardPreview { mode: ...; sidestripMode: ... }`.

**Mapa efecto del motor → propiedad de `KeyboardPreview`** (su `mode` acepta `theme|fill|breathing|stream|red_breathing|red_static|none`; su `sidestripMode` acepta `stream_battery|solid|red_breathing|red_static|none`):

| effect (motor) zona `keys` | `KeyboardPreview.mode` |
| --- | --- |
| `theme` | `theme` |
| `battery_meter` | `fill` |
| `breathing_battery` | `breathing` |
| `stream` | `stream` |
| `red_breathing` / `red_static` / `none` | igual |

| effect (motor) zona `sidestrip` | `KeyboardPreview.sidestripMode` |
| --- | --- |
| `stream_battery` | `stream_battery` |
| `solid_theme` | `solid` |
| `breathing` | `solid` (con `visible` activo — ver nota) |
| `red_breathing` / `red_static` / `none` | igual |

Nota: `KeyboardPreview` no distingue hoy `breathing` en la tira lateral (su switch sólo mira `solid`/`red_static`/`stream_battery`/`none`). Añadir un caso `breathing` a `KeyboardPreview.qml` (pulso con color de acento) en el Step 1 de esta tarea — es un cambio de ~4 líneas junto a la línea 145.

- [ ] **Step 1: Escribir el componente** (patrón `ChipGroup` de `AkkoCard.qml:44-72`) + el caso `breathing` en `KeyboardPreview.qml`.
- [ ] **Step 2: Verificación visual** — se hace en la Task 18.
- [ ] **Step 3: Commit**

```bash
git add configs/quickshell/caelestia/modules/rgbcontrol/BatteryActionRow.qml
git commit -m "feat(shell): BatteryActionRow — target/zone/effect editor for one action

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 17: `BatteryRuleCard.qml` — tarjeta de regla

**Files:**
- Create: `configs/quickshell/caelestia/modules/rgbcontrol/BatteryRuleCard.qml`

**Interfaces:**
- Consumes: `BatteryActionRow.qml`, `BatteryLightingConfig`, `DeviceCard`-style layout, `StyledSlider`, `Chip`.
- Produces: `required property var rule`. Cabecera: icono según `rule.source` (`keyboard`/`mouse`/`headphones`) + texto disparador (`Al cargar` / `Batería baja` / `Batería crítica`) + resumen de acciones + botón borrar (`BatteryLightingConfig.removeRule(rule.id)`). Cuerpo plegable: si `rule.trigger === "low"`, `StyledSlider` de umbral 5–40 paso 5 (misma fórmula que `AkkoCard.qml:212-219`); `Repeater` sobre `rule.actions` → `BatteryActionRow`; botón "+ Añadir acción" (`BatteryLightingConfig.addAction(rule.id, "mchose_base", null, "red_breathing")`); botón "Probar" (`BatteryLightingConfig.probe(rule.id)`).

- [ ] **Step 1: Escribir el componente**.
- [ ] **Step 2: Verificación visual** — Task 18.
- [ ] **Step 3: Commit**

```bash
git add configs/quickshell/caelestia/modules/rgbcontrol/BatteryRuleCard.qml
git commit -m "feat(shell): BatteryRuleCard — one battery reaction rule

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 18: Sección "Reacciones de batería" en `NotificacionesView.qml` + quitar secciones viejas

**Files:**
- Modify: `configs/quickshell/caelestia/modules/rgbcontrol/NotificacionesView.qml`
- Modify: `configs/quickshell/caelestia/modules/rgbcontrol/AkkoCard.qml`
- Modify: `configs/quickshell/caelestia/modules/rgbcontrol/DispositivosView.qml`
- Delete: `configs/quickshell/caelestia/services/AkkoConfig.qml`
- Delete: `configs/quickshell/caelestia/services/MchoseConfig.qml`

**Interfaces:**
- Consumes: `BatteryLightingConfig`, `BatteryRuleCard`.

- [ ] **Step 1: `NotificacionesView.qml`** — añadir tras la `Card` de dispositivos que flashean una sección nueva:
  - Título "Reacciones de batería".
  - `Repeater { model: BatteryLightingConfig.rules; BatteryRuleCard { rule: modelData } }`.
  - Botón "+ Añadir regla" → diálogo mínimo (menú de `BatteryLightingConfig.sources` conectados + `triggers`) → `BatteryLightingConfig.addRule(source, trigger)`.
  - Quitar del bloque "Más adelante" la línea sobre "Aviso de batería baja propio de cada dispositivo" (ya implementado).

- [ ] **Step 2: `AkkoCard.qml`** — eliminar: `property bool showLow`, `KeyboardPreview` de evento, selector "Al cargar/Batería baja", master toggle "Reaccionar a la batería", ambos `ZoneTitle` + `ChipGroup` de carga/baja, el `ColumnLayout` del umbral, y la nota de estado. Dejar sólo icono/nombre/subtítulo (la tarjeta queda como placeholder de "aspecto normal"; si queda vacía de contenido útil, reducirla a una nota "El color del teclado sigue el tema global. Sus reacciones de batería están en Notificaciones → Reacciones de batería."). Quitar `import` y usos de `AkkoConfig`.

- [ ] **Step 3: `DispositivosView.qml`** — en la `DeviceCard` de la Base MCHOSE (líneas ~32-159) eliminar todo el bloque de "Eventos de batería" (los dos `ChipRow`, el slider de umbral, el botón "Probar"). Quitar `import`/usos de `MchoseConfig`. Dejar la ficha con su subtítulo; añadir la misma nota de reenvío a Notificaciones.

- [ ] **Step 4: Borrar singletons**

```bash
git rm configs/quickshell/caelestia/services/AkkoConfig.qml configs/quickshell/caelestia/services/MchoseConfig.qml
```

- [ ] **Step 5: Verificación visual completa**

```bash
grep -rn "AkkoConfig\|MchoseConfig" configs/quickshell/   # esperado: sin resultados
caelestia shell -k && sleep 1 && caelestia shell -d
caelestia shell ipc call rgb openTab 2                    # abre pestaña Notificaciones
```
Comprobar: la sección aparece con las reglas sembradas; añadir una regla V9 → batería baja → acción "Base MCHOSE / rojo respiración"; el JSON `~/.config/caelestia/battery-lighting.json` se actualiza; "Probar" dispara el efecto (con hardware). El log de quickshell sin errores. La ficha del Akko y de la Base ya no muestran secciones de batería.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(shell): battery reactions section in Notificaciones; drop per-card battery UI

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 19: Cierre — docs, base de datos de errores, revisión final

**Files:**
- Modify: `docs/AKKO_BATTERY_LIGHTING_FRONTEND.md` (o renombrar a `docs/BATTERY_LIGHTING_ENGINE.md`)
- Modify: `docs/CENTRO_ILUMINACION_RGB_PLAN.md` / handoff si procede
- Modify: `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md`
- Modify: `README.md` si lista servicios systemd

- [ ] **Step 1:** Documentar el motor: esquema `battery-lighting.json`, tabla de efectos, `battery_alerts.json`, cómo probar (`--apply`, `--dump`), el servicio. Marcar el frontend-only del Akko como superado.
- [ ] **Step 2:** En la Base de Datos de Errores: entrada nueva con lo aprendido (validación del lienzo Akko, colisiones evitadas con el fichero de alertas, cadencia RF).
- [ ] **Step 3:** Suite final `python3 -m pytest rgb/tests/ -q` + `diff -q rgb/mchose-battery widgets/mchose-battery`.
- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: battery-lighting engine — schema, effects, testing, error DB

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Merge de la rama** — seguir `superpowers:finishing-a-development-branch` (merge a `main`, push, borrar rama).

---

## Self-review (cobertura del spec)

| Requisito del spec | Task |
| --- | --- |
| Daemon único, dueño de la telemetría | 6, 10, 13 |
| `battery-lighting.json` esquema + validación | 2 |
| trigger `charging`/`low`/`critical` | 3 |
| Prioridad crítica>baja>cargando>tema; empate por orden; `both`→2 zonas | 3 |
| Cadencia adaptativa 60/3 s | 10 (`_daemon_loop`) |
| Efectos por destino (tabla spec §3) | 7, 8, 9 |
| `battery_meter` real en teclas Akko; degradación | 5, 8, 13 |
| `battery_meter` en OpenRGB (v1 degrada a sólido; v2 pendiente) | 9 |
| Color por nivel HSV | 5 |
| `battery_alerts.json` + coordinación `sync-rgb.py` / `rgb-notify-flash` | 10, 11 |
| Sembrado + migración `akko-config.json`/`mchose-config.json` | 4 |
| Notificaciones de escritorio | 10 |
| systemd + install.sh + retiro del timer y `mchose-config` | 13 |
| `mchose-battery` adelgazado + espejo idéntico + CLAUDE.md | 12 |
| UI: singleton + RuleCard + ActionRow + sección Notificaciones | 15-18 |
| Quitar secciones de batería de AkkoCard / ficha Base; borrar AkkoConfig/MchoseConfig | 18 |
| `KeyboardPreview` reutilizado | 16 |
| Docs + base de datos de errores | 13, 19 |
| Pruebas unitarias (resolver, migración, validación, medidor) | 2-10 |

**Decisión de alcance registrada:** `battery_meter` sobre OpenRGB se entrega en v1 como color sólido por nivel (no relleno animado LED-a-LED); la integración con `argb-wave.py` para el relleno animado es v2 y está marcada con `# TODO v2` en `apply_openrgb`. El spec ya contempla degradación de `battery_meter`; esto la hace explícita para OpenRGB.
