"""Task 12: `mchose-battery` es ahora una herramienta de sólo telemetría.

Toda la lógica batería->iluminación y las notificaciones de escritorio viven
en `rgb/battery-lighting`. Aquí verificamos que:
  - los símbolos/flags de iluminación y notificación ya no existen en el fuente,
  - `--json` sigue devolviendo {"headset","mouse","keyboard"} y sale 0,
  - `rgb/mchose-battery` y `widgets/mchose-battery` son byte a byte idénticos.
"""

import json
import subprocess
import sys
from pathlib import Path

MB = Path(__file__).resolve().parents[1] / "mchose-battery"
WIDGET_MB = MB.parents[1] / "widgets" / "mchose-battery"

REMOVED_SYMBOLS = (
    "get_theme_primary_rgb",
    "set_base_mode",
    "apply_charging_lighting",
    "apply_low_battery_lighting",
    "handle_charging_lighting_transition",
    "apply_akko_battery_lighting",
    "get_akko_battery_level_color",
    "check_and_notify",
    "send_notification",
)

REMOVED_FLAGS = (
    "--notify",
    "--daemon",
    "--trigger-lighting",
    "--restore-lighting",
    "--akko-mode",
    "--akko-battery",
)


def test_no_lighting_or_notify_symbols_left():
    src = MB.read_text()
    for gone in REMOVED_SYMBOLS:
        assert gone not in src, gone


def test_no_lighting_or_notify_flags_left():
    src = MB.read_text()
    for gone in REMOVED_FLAGS:
        assert gone not in src, gone


def test_json_mode_still_runs():
    out = subprocess.run(
        [sys.executable, str(MB), "--json"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert out.returncode == 0, out.stderr
    d = json.loads(out.stdout)
    assert {"headset", "mouse", "keyboard"} <= set(d)


def test_mirror_identical():
    assert MB.read_bytes() == WIDGET_MB.read_bytes()
