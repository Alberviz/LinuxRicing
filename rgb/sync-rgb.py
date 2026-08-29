#!/usr/bin/env python3
"""
Sync Caelestia dynamic colors to:
1. PC RGB devices (Motherboard, RAM) via OpenRGB SDK
2. Akko 5075B Plus Keyboard (Backlight + Side-Strip) via direct HID (3151:4015)
3. MCHOSE Dongle / Charging Base via direct HID (3837:1001)
4. External Magic Home LED strip via Wi-Fi (flux_led)
With intelligent color saturation boosting for physical RGB LEDs.
"""

import colorsys
import fcntl
import glob
import json
import os
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

# --- CONFIGURATION ---
MAGIC_HOME_IP = "192.168.0.136"
COLOR_KEY = "primary"  # Primary extracted color from wallpaper
LOG_FILE = "/tmp/sync-rgb.log"

RGB_CONFIG_PATH = os.path.expanduser("~/.config/caelestia/rgb-config.json")

# Written by rgb/battery-lighting: {"<target>:<zone>": {effect, trigger, source, level}}.
# Zones we must not stomp while a battery alert owns them.
ALERTS_CACHE = os.path.expanduser("~/.cache/battery_alerts.json")

# Default = the historical behaviour: follow the theme, every device on, no flash.
# Absence of the config file must not change anything.
DEFAULT_RGB_CONFIG = {
    "source": "theme",          # "theme" | "fixed"
    "fixed_color": "d8bde7",
    "devices": {
        "openrgb": True,
        "magichome": True,
        "mchose_base": True,
        "akko_keyboard": True,
        "spicetify": True,
    },
    "device_profiles": {
        "akko_keyboard": {
            "keys": {"animation": "solid", "colour": {"source": "theme", "hex": "d8bde7"},
                     "speed": 3, "direction": "right"},
            "sidestrip": {"animation": "snake", "colour": {"source": "battery", "hex": "d8bde7"},
                          "speed": 1, "direction": "right"},
        },
        "mchose_base": {
            "ring": {"animation": "solid", "colour": {"source": "theme", "hex": "d8bde7"},
                     "speed": 3, "direction": "right"},
        },
        "openrgb": {
            "mode": "theme",
            "fixed_color": "d8bde7",
        },
        "magichome": {
            "mode": "theme",
            "fixed_color": "d8bde7",
        },
    },
    "devices_extra": {"openrgb": {"argb_zones": False}},
    "notification_flash": {"enabled": False, "mode": "accent", "pulses": 2},
}

# Written every run so argb-wave.py can react to wallpaper *preview* (before
# Enter is pressed), not just to a confirmed theme change.
LIVE_PALETTE_CACHE = Path("/tmp/caelestia-rgb-live-palette.json")

# Maps the internal device key -> the sync function it drives.
DEVICE_KEYS = ["openrgb", "magichome", "mchose_base", "akko_keyboard", "spicetify"]


def log(msg: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")


def load_rgb_config() -> dict:
    """Read ~/.config/caelestia/rgb-config.json, falling back to legacy behaviour."""
    cfg = json.loads(json.dumps(DEFAULT_RGB_CONFIG))  # deep copy
    try:
        with open(RGB_CONFIG_PATH) as f:
            user = json.load(f)
        if isinstance(user, dict):
            if user.get("source") in ("theme", "fixed"):
                cfg["source"] = user["source"]
            if isinstance(user.get("fixed_color"), str):
                cfg["fixed_color"] = user["fixed_color"].lstrip("#") or cfg["fixed_color"]
            if isinstance(user.get("devices"), dict):
                for k, v in user["devices"].items():
                    if k in cfg["devices"]:
                        cfg["devices"][k] = bool(v)
            if isinstance(user.get("device_profiles"), dict):
                for dev, prof in user["device_profiles"].items():
                    if dev in cfg["device_profiles"] and isinstance(prof, dict):
                        cfg["device_profiles"][dev].update(prof)
            if isinstance(user.get("notification_flash"), dict):
                cfg["notification_flash"].update(user["notification_flash"])
            extra = user.get("devices_extra")
            if isinstance(extra, dict) and isinstance(extra.get("openrgb"), dict):
                cfg["devices_extra"]["openrgb"]["argb_zones"] = bool(
                    extra["openrgb"].get("argb_zones", False)
                )
    except FileNotFoundError:
        pass
    except Exception as e:
        log(f"rgb-config.json unreadable ({e}), using defaults")
    return cfg


def battery_alert_zones() -> set:
    """Set of "<target>:<zone>" keys currently claimed by an active battery alert.

    Reads ~/.cache/battery_alerts.json (written by rgb/battery-lighting). Returns
    an empty set if the file is missing or unreadable, so absence changes nothing.
    """
    try:
        with open(ALERTS_CACHE) as f:
            data = json.load(f)
        if isinstance(data, dict):
            return set(data.keys())
    except FileNotFoundError:
        pass
    except Exception as e:
        log(f"battery_alerts.json unreadable ({e}), ignoring")
    return set()


def HIDIOCSFEATURE(size: int) -> int:
    return (3 << 30) | (size << 16) | (ord("H") << 8) | 0x06


def get_hex_color(config: dict | None = None, cli_hex: str | None = None) -> tuple[str, bool]:
    """Resolve the colour to apply.

    Priority:
      1. explicit CLI hex (panel preview / scripting)
      2. SCHEME_COLOURS env (wallpaper preview - keep winning so Wallpapers.qml works)
      3. config source == "fixed" -> fixed_color
      4. scheme.json primary
      5. hard fallback

    Returns (hex_without_hash, from_theme). ``from_theme`` is False for CLI/fixed
    colours so the caller can skip the saturation boost and send them verbatim.
    """
    if cli_hex:
        c = cli_hex.lstrip("#")
        log(f"Using CLI colour #{c}")
        return c, False

    raw_colours = os.environ.get("SCHEME_COLOURS")
    if raw_colours:
        try:
            colours = json.loads(raw_colours)
            if COLOR_KEY in colours:
                c = colours[COLOR_KEY].lstrip("#")
                log(f"Extracted #{c} from SCHEME_COLOURS env")
                return c, True
        except Exception as e:
            log(f"Error parsing SCHEME_COLOURS: {e}")

    if config and config.get("source") == "fixed":
        c = str(config.get("fixed_color", "d8bde7")).lstrip("#")
        log(f"Using fixed colour #{c} from rgb-config.json")
        return c, False

    state_file = Path.home() / ".local/state/caelestia/scheme.json"
    if state_file.exists():
        try:
            data = json.loads(state_file.read_text())
            colours = data.get("colours", {})
            if COLOR_KEY in colours:
                c = colours[COLOR_KEY].lstrip("#")
                log(f"Extracted #{c} from scheme.json state")
                return c, True
        except Exception as e:
            log(f"Error reading scheme.json: {e}")

    return "d8bde7", True


def enhance_color_for_leds(hex_color: str) -> tuple[int, int, int]:
    """Preserve wallpaper Hue while boosting saturation for rich LED colors."""
    hex_clean = hex_color.lstrip("#")
    r = int(hex_clean[0:2], 16) / 255.0
    g = int(hex_clean[2:4], 16) / 255.0
    b = int(hex_clean[4:6], 16) / 255.0

    h, s, v = colorsys.rgb_to_hsv(r, g, b)

    if s > 0.05:
        boosted_s = min(1.0, max(0.80, s * 3.5))
        boosted_v = 1.0
        new_r, new_g, new_b = colorsys.hsv_to_rgb(h, boosted_s, boosted_v)
        res = (int(new_r * 255), int(new_g * 255), int(new_b * 255))
        log(f"Color enhancement: #{hex_clean} (Sat {s*100:.0f}%) -> RGB{res} (Sat {boosted_s*100:.0f}%)")
        return res
    else:
        return (int(r * 255), int(g * 255), int(b * 255))


def get_palette() -> dict:
    """Full colour palette dict from the wallpaper-preview env or Caelestia state."""
    raw_colours = os.environ.get("SCHEME_COLOURS")
    if raw_colours:
        try:
            return json.loads(raw_colours)
        except Exception as e:
            log(f"Error parsing SCHEME_COLOURS for palette: {e}")
    state_file = Path.home() / ".local/state/caelestia/scheme.json"
    if state_file.exists():
        try:
            return json.loads(state_file.read_text()).get("colours", {})
        except Exception as e:
            log(f"Error reading scheme.json for palette: {e}")
    return {}


def cache_live_palette():
    """Publish the current palette so argb-wave.py reacts every frame."""
    try:
        palette = get_palette()
        if palette:
            LIVE_PALETTE_CACHE.write_text(json.dumps(palette))
    except Exception as e:
        log(f"Error caching live palette: {e}")


def hex_to_rgb(hex_c: str) -> tuple[int, int, int]:
    h = str(hex_c).lstrip("#")
    if len(h) < 6:
        h = h.ljust(6, "0")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)



def get_cached_battery(device_pref: str) -> tuple[int, str]:
    """Returns (level, status)."""
    pref_map = {
        "akko_keyboard": "akko",
        "akko": "akko",
        "mchose_mouse": "k7",
        "mchose_base": "k7",
        "k7": "k7",
        "v9_headset": "v9",
        "v9": "v9",
    }
    pref = pref_map.get(device_pref, device_pref)
    try:
        cache_p = Path.home() / ".cache/mchose_battery.json"
        if cache_p.exists():
            with open(cache_p) as f:
                data = json.load(f)
            lvl = data.get(f"{pref}_battery", 100)
            st = data.get(f"{pref}_status", "Descargando")
            return (lvl if lvl is not None else 100, st)
    except Exception:
        pass
    return (100, "Descargando")


def _akko_checksum8(buf: bytearray) -> int:
    """
    ROYUAN 'Bit8' checksum used by SET_LEDPARAM/SET_SLEDPARAM: one's-complement
    sum of bytes 0..7, stored at byte 8 - NOT a plain sum stored at the end of
    the 64-byte buffer. Confirmed against the hardware-verified open-source
    reimplementation at https://github.com/dniminenn/sharkfin (protocol.rs);
    writing the checksum in the wrong place makes the firmware silently
    discard the packet, which is why colors never visibly changed.
    """
    return 0xFF - (sum(buf[:8]) & 0xFF)


def get_akko_battery_level_color(bat_level: int | None) -> tuple[int, int, int]:
    """Calculate progressive color from Red (<=15%) -> Amber -> Yellow -> Lime -> Emerald Green (100%)."""
    if bat_level is None:
        bat_level = 100
    bat_level = max(0, min(100, bat_level))
    if bat_level <= 15:
        return (255, 0, 0)
    hue = ((bat_level - 15) / 85.0) * (120.0 / 360.0)
    nr, ng, nb = colorsys.hsv_to_rgb(hue, 1.0, 1.0)
    return (int(nr * 255), int(ng * 255), int(nb * 255))


# --- Modelo de efecto Akko (duplicado a propósito de rgb/battery-lighting;
#     ver docs/AKKO_EFFECTS_MODEL_HANDOFF.md) --------------------------------
_AKKO_ANIM_BYTE = {
    "off": 0, "solid": 1, "breathing": 2, "neon": 3, "wave": 4, "ripple": 5,
    "raindrop": 6, "snake": 7, "press_action": 8, "converge": 9, "sine_wave": 10,
    "kaleidoscope": 11, "line_wave": 12, "laser": 14, "circle_wave": 15,
    "dazzing": 16, "meteor": 18, "train": 23, "fireworks": 24,
}
_AKKO_SIDESTRIP_ANIMS = {"off", "solid", "breathing", "neon", "wave", "snake"}
# La tira lateral (0x08) numera algunos modos distinto que las teclas (0x07):
# "snake" es el modo 5 en la tira (flujo) pero el 7 en las teclas.
_AKKO_SIDESTRIP_ANIM_BYTE = {"snake": 5}
_AKKO_DIRECTIONAL = {"wave"}
_AKKO_DIR_IDX = {"right": 0, "left": 1, "down": 2, "up": 3}
_AKKO_EFFECT_ALIASES = {
    "theme": {"animation": "solid", "colour": {"source": "theme"}},
    "fixed": {"animation": "solid", "colour": {"source": "fixed"}},
    "battery_color": {"animation": "solid", "colour": {"source": "battery"}},
    "breathing": {"animation": "breathing", "colour": {"source": "theme"}},
    "breathing_battery": {"animation": "breathing", "colour": {"source": "battery"}},
    "theme_breathing": {"animation": "breathing", "colour": {"source": "theme"}},
    "battery_breathing": {"animation": "breathing", "colour": {"source": "battery"}},
    "hardware_battery": {"animation": "hardware_battery", "colour": {"source": "battery"}},
    "wave": {"animation": "wave", "colour": {"source": "theme"}},
    "wave_battery": {"animation": "wave", "colour": {"source": "battery"}},
    "stream": {"animation": "snake", "colour": {"source": "battery"}},
    "stream_battery": {"animation": "snake", "colour": {"source": "battery"}},
    "reactive_press": {"animation": "press_action", "colour": {"source": "theme"}},
    "press_action": {"animation": "press_action", "colour": {"source": "theme"}},
    "red_static": {"animation": "solid", "colour": {"source": "fixed", "hex": "ff0000"}},
    "red_breathing": {"animation": "breathing", "colour": {"source": "fixed", "hex": "ff0000"}},
    "off": {"animation": "off", "colour": {"source": "theme"}},
    "none": {"animation": "off", "colour": {"source": "theme"}},
}


def _akko_norm_effect(eff):
    if isinstance(eff, str):
        eff = _AKKO_EFFECT_ALIASES.get(eff, {"animation": "off"})
    eff = eff if isinstance(eff, dict) else {}
    out = {"animation": eff.get("animation", "solid"),
           "speed": eff.get("speed", 3),
           "direction": eff.get("direction", "right")}
    c = eff.get("colour") or {}
    out["colour"] = {"source": c.get("source", "theme"),
                     "hex": (c.get("hex") or "d8bde7").lstrip("#").lower()}
    if out["colour"]["source"] not in ("theme", "fixed", "battery"):
        out["colour"]["source"] = "theme"
    try:
        out["speed"] = max(1, min(5, int(out["speed"])))
    except (TypeError, ValueError):
        out["speed"] = 3
    if out["direction"] not in _AKKO_DIR_IDX:
        out["direction"] = "right"
    if out["animation"] not in _AKKO_ANIM_BYTE and out["animation"] != "hardware_battery":
        out["animation"] = "off"
    return out


# animación -> byte[2] (velocidad) por defecto — valores verificados en hardware
# (color sólido y notify-flash usan 0x04; respiración/ola 0x02; el "flujo" snake 0x00).
_AKKO_SPEED_DEFAULT = {"solid": 0x04, "off": 0x04, "breathing": 0x02, "neon": 0x02,
                       "wave": 0x02, "snake": 0x00}


def _akko_speed_byte(anim: str, ui_speed: int, opcode: int) -> int:
    base = _AKKO_SPEED_DEFAULT.get(anim, 0x02)
    if anim in ("solid", "off"):
        return base
    ui = max(1, min(5, int(ui_speed)))
    # el slider mueve la velocidad ±2 alrededor del valor probado (ui 3 = por defecto)
    delta = (3 - ui) if opcode == 0x07 else (ui - 3)   # teclas invertido, tira directo
    lo = 0 if anim == "snake" else 1
    return max(lo, min(4, base + delta))


def _akko_effect_buf(opcode: int, eff: dict, theme_rgb, bat_rgb, bright: int = 4) -> bytearray:
    anim = eff["animation"]
    if opcode == 0x08 and anim not in _AKKO_SIDESTRIP_ANIMS:
        anim = "solid"
    if opcode == 0x08 and anim in _AKKO_SIDESTRIP_ANIM_BYTE:
        mode = _AKKO_SIDESTRIP_ANIM_BYTE[anim]
    else:
        mode = _AKKO_ANIM_BYTE.get(anim, 1)
    src = eff["colour"]["source"]
    if src == "fixed":
        h = eff["colour"]["hex"] or "d8bde7"
        rgb = (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    elif src == "battery":
        rgb = bat_rgb
    else:
        rgb = theme_rgb
    speed_byte = _akko_speed_byte(anim, eff["speed"], opcode)
    flag = 0x08
    if anim in _AKKO_DIRECTIONAL:
        flag = 0x08 | (_AKKO_DIR_IDX.get(eff["direction"], 0) << 4)
    buf = bytearray(64)
    buf[0] = opcode
    buf[1] = mode
    buf[2] = speed_byte
    buf[3] = bright
    buf[4] = flag
    buf[5], buf[6], buf[7] = rgb
    buf[8] = _akko_checksum8(buf)
    return buf


def sync_openrgb(r: int, g: int, b: int, argb_zones: bool = False, profile: dict | None = None):
    """Set PC components (Motherboard, RAM, Fans) in OpenRGB via SDK Server, skipping Akko to avoid USB collisions.

    When ``argb_zones`` is True the animated wave daemon (argb-wave.py) owns the
    whole ASUS board and the RAM via its own OpenRGB client, so we skip DRAM and
    ASUS/AURA devices to prevent LED race conditions and strobing.
    """
    if "openrgb:_" in battery_alert_zones():
        log("OpenRGB: reclamado por una alerta de batería, se omite el sync de tema")
        return

    profile = profile or {}
    omode = profile.get("mode", "theme")
    if omode == "fixed":
        r, g, b = hex_to_rgb(profile.get("fixed_color", "d8bde7"))
    elif omode == "battery_color":
        k7_bat, _ = get_cached_battery("k7")
        r, g, b = get_akko_battery_level_color(k7_bat)
    elif omode == "argb_wave":
        argb_zones = True

    try:
        from openrgb import OpenRGBClient
        from openrgb.utils import RGBColor

        client = OpenRGBClient()
        # The SDK server answers before it has finished probing the SMBus / AURA
        # hardware, so right after boot client.devices can come back empty. Give
        # it a few seconds to enumerate rather than silently syncing nothing.
        for _ in range(10):
            if client.devices:
                break
            time.sleep(1)
            client.update()
        if not client.devices:
            raise RuntimeError("OpenRGB server has no devices yet")

        col = RGBColor(r, g, b)
        synced = []
        for dev in client.devices:
            dev_name_l = dev.name.lower()
            # Skip Akko/ROYUAN keyboards in OpenRGB - handled by dedicated sync_akko_keyboard
            if "akko" in dev_name_l or "royuan" in dev_name_l:
                continue

            # When the animated wave daemon (argb-wave.py) is running it owns
            # the whole ASUS board (mainboard + addressable headers) and the
            # RAM via its own OpenRGB client. A second client writing here at
            # the same time makes the LEDs race and strobe, so bail entirely.
            if argb_zones and ("dram" in dev_name_l or "asus" in dev_name_l or "aura" in dev_name_l):
                continue

            if dev.modes and dev.modes[dev.active_mode].name != "Direct":
                try:
                    direct_idx = next(
                        i for i, m in enumerate(dev.modes) if m.name == "Direct"
                    )
                    dev.set_mode(direct_idx)
                except StopIteration:
                    log(f"Device {dev.name} has no Direct mode, skipping mode switch")
                except Exception as em:
                    log(f"Mode set error on {dev.name}: {em}")

            for zone in dev.zones:
                if argb_zones and "addressable" in zone.name.lower():
                    continue
                zone.set_color(col)
            synced.append(dev.name)
        log(f"OpenRGB (SDK): Synced RGB({r},{g},{b}) to {synced} (argb_zones={argb_zones})")
        return
    except Exception as e:
        log(f"OpenRGB SDK error ({e}), attempting CLI fallback...")

    # Fallback to CLI
    try:
        hex_c = f"{r:02x}{g:02x}{b:02x}"
        cmd = ["openrgb", "--noautoconnect", "-c", hex_c]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
        log("OpenRGB (CLI fallback) executed")
    except Exception as e2:
        log(f"OpenRGB CLI error: {e2}")



def sync_akko_keyboard(r: int, g: int, b: int, brightness: int = 4, throttle: bool = False, profile: dict | None = None):
    """
    Set Akko 5075B Plus Keyboard Backlight (Opcode 0x07) and Side-Strip (Opcode 0x08)
    via direct USB HID Feature Reports on Interface 2. Sólo modos de firmware de
    una escritura (el lienzo per-key se retiró: congela el teclado por 2.4 GHz).
    El perfil trae `keys` y `sidestrip` como objetos de efecto
    {animation, colour:{source,hex}, speed, direction}; también acepta el perfil
    antiguo {keys_mode, keys_fixed_color, sidestrip_mode, sidestrip_fixed_color}.
    """
    usb_nodes, wl_nodes = [], []
    for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        uevent = f"{h}/device/uevent"
        if not os.path.exists(uevent):
            continue
        try:
            with open(uevent) as f:
                content = f.read()
        except Exception:
            continue
        if "3151" not in content:
            continue
        if ":1.2" not in os.path.realpath(f"{h}/device"):
            continue
        node = "/dev/" + os.path.basename(h)
        if "4015" in content:
            usb_nodes.append(node)
        elif "4011" in content:
            wl_nodes.append(node)
    nodes = usb_nodes or wl_nodes

    if not nodes:
        log("Akko Keyboard: No HID node found")
        return

    alert_zones = battery_alert_zones()
    skip_sidestrip = "akko_keyboard:sidestrip" in alert_zones
    skip_keys = "akko_keyboard:keys" in alert_zones
    if skip_sidestrip and skip_keys:
        log("Akko Keyboard: ambas zonas reclamadas por una alerta de batería, no se toca")
        return

    profile = profile or {}

    def _profile_effect(new_key, mode_key, fixed_key, default_mode):
        if new_key in profile:
            return profile[new_key]
        m = profile.get(mode_key, default_mode)
        if m == "fixed":
            return {"animation": "solid",
                    "colour": {"source": "fixed", "hex": profile.get(fixed_key, "d8bde7")}}
        return m

    keys_eff = _akko_norm_effect(_profile_effect("keys", "keys_mode", "keys_fixed_color", "theme"))
    side_eff = _akko_norm_effect(_profile_effect("sidestrip", "sidestrip_mode",
                                                 "sidestrip_fixed_color", "stream_battery"))

    akko_bat, akko_st = get_cached_battery("akko")
    bat_rgb = get_akko_battery_level_color(akko_bat)

    raw_led = bytearray([0x00]) + _akko_effect_buf(0x07, keys_eff, (r, g, b), bat_rgb, brightness)
    raw_sled = bytearray([0x00]) + _akko_effect_buf(0x08, side_eff, (r, g, b), bat_rgb, brightness)
    keys_mode = keys_eff["animation"]
    sidestrip_mode = side_eff["animation"]

    lock_fd = None
    try:
        lock_fd = os.open("/tmp/akko_sync.lock", os.O_CREAT | os.O_RDWR)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
    except Exception:
        lock_fd = None

    stamp = Path("/tmp/akko_last_write.txt")
    if throttle:
        try:
            if stamp.exists() and time.time() - float(stamp.read_text().strip()) < 0.25:
                log("Akko Keyboard: skipped (preview, last write < 250 ms ago)")
                if lock_fd is not None:
                    fcntl.flock(lock_fd, fcntl.LOCK_UN)
                    os.close(lock_fd)
                return
        except Exception:
            pass

    try:
        for node in nodes:
            try:
                fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
                if not skip_sidestrip:
                    fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_sled)), raw_sled)
                    time.sleep(0.03)
                if not skip_keys:
                    fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_led)), raw_led)
                    time.sleep(0.03)
                    fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_led)), raw_led)
                    time.sleep(0.02)

                os.close(fd)
                try:
                    stamp.write_text(str(time.time()))
                except Exception:
                    pass
                log(f"Akko Keyboard ({node}): Backlight ({keys_mode}) + Side-Strip ({sidestrip_mode})")
                return
            except Exception as e:
                log(f"Akko Keyboard error on {node}: {e}")
    finally:
        if lock_fd is not None:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
                os.close(lock_fd)
            except Exception:
                pass


def sync_mchose_base(r: int, g: int, b: int, profile: dict | None = None):
    """Set MCHOSE 8K Dongle / Charging Base RGB via reverse-engineered Command 0x2B protocol."""
    if "mchose_base:_" in battery_alert_zones():
        log("MCHOSE Base: reclamado por una alerta de batería, se omite el sync de tema")
        return
    nodes = []
    for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        uevent = f"{h}/device/uevent"
        if os.path.exists(uevent):
            try:
                with open(uevent) as f:
                    content = f.read()
                if "3837" in content and "1001" in content:
                    link = os.path.realpath(f"{h}/device")
                    if ":1.2" in link:
                        nodes.append("/dev/" + os.path.basename(h))
            except Exception:
                pass

    if not nodes:
        return

    profile = profile or {}

    k7_bat, _ = get_cached_battery("k7")
    bat_r, bat_g, bat_b = get_akko_battery_level_color(k7_bat)

    # perfil nuevo {ring: <efecto>} o antiguo {mode, fixed_color}
    _MCHOSE_ANIM_BYTE = {"solid": 0x06, "breathing": 0x02, "wave": 0x07,
                         "hardware_battery": 0x01}
    if "ring" in profile:
        eff = _akko_norm_effect(profile["ring"])
    else:
        m = profile.get("mode", "theme")
        if m == "fixed":
            eff = _akko_norm_effect({"animation": "solid",
                                     "colour": {"source": "fixed",
                                                "hex": profile.get("fixed_color", "d8bde7")}})
        else:
            eff = _akko_norm_effect(m)
    bmode = eff["animation"]
    mode_byte = _MCHOSE_ANIM_BYTE.get(bmode, 0x06)
    # byte[3] del payload 0x2B = velocidad; los modos estáticos van a 0 (valor
    # verificado con rgb-notify-flash), respiración a 1, ola a 3.
    speed_byte = {"breathing": 1, "wave": 3}.get(bmode, 0)
    src = eff["colour"]["source"]
    if src == "fixed":
        br, bg, bb = hex_to_rgb(eff["colour"]["hex"] or "d8bde7")
    elif src == "battery":
        br, bg, bb = bat_r, bat_g, bat_b
    else:
        br, bg, bb = r, g, b
    if bmode == "wave":
        br, bg, bb = 255, 59, 0

    payload = [
        0x2B, 0x01, mode_byte, speed_byte,
        100, 0x00, 0x01, 0x01, 0x00,
        br, bg, bb,
        br, bg, bb,
        0x00, 0x00, 0x00, 0x00, 0x00
    ]
    raw = bytearray([0x11] + [x ^ 0xFF for x in payload])

    for node in nodes:
        try:
            fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
            fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw)), raw)
            os.close(fd)
            log(f"MCHOSE Base: Synced RGB({br},{bg},{bb}) mode {bmode} to {node} via Cmd 0x2B")
        except Exception as e:
            log(f"MCHOSE Base error on {node}: {e}")


def sync_magichome(r: int, g: int, b: int, profile: dict | None = None):
    """Set Magic Home LED strip color and power on."""
    if "magichome:_" in battery_alert_zones():
        log("MagicHome: reclamado por una alerta de batería, se omite el sync de tema")
        return
    if not MAGIC_HOME_IP:
        return

    profile = profile or {}
    mmode = profile.get("mode", "theme")
    if mmode == "fixed":
        r, g, b = hex_to_rgb(profile.get("fixed_color", "d8bde7"))
    elif mmode == "battery_color":
        akko_bat, _ = get_cached_battery("akko")
        r, g, b = get_akko_battery_level_color(akko_bat)

    try:
        from flux_led import WifiLedBulb

        bulb = WifiLedBulb(MAGIC_HOME_IP, timeout=2)
        bulb.turnOn()
        bulb.setRgb(r, g, b)
        bulb.close()
        log(f"MagicHome (flux_led): Set RGB ({r}, {g}, {b}) mode {mmode} successfully")
    except Exception as e:
        log(f"MagicHome error via python ({e}), attempting CLI fallback...")
        try:
            hex_c = f"{r:02x}{g:02x}{b:02x}"
            subprocess.run(
                ["/home/alberviz/.local/bin/magichome-control", "--color", f"#{hex_c}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=3,
            )
            log("MagicHome (CLI fallback) executed")
        except Exception as e2:
            log(f"MagicHome CLI error: {e2}")


def is_spotify_focused() -> bool:
    """Check if Spotify window is currently active/focused."""
    try:
        res = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True, timeout=1)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            wclass = str(data.get("class", "")).lower()
            return "spotify" in wclass
    except Exception:
        pass
    return False


def sync_spicetify(is_preview: bool = False):
    """Update Spicetify theme color.ini with current Material You palette.
    Only reload Spotify if Spotify is the currently focused window, avoiding background playback disruption.
    """
    try:
        state_file = Path.home() / ".local/state/caelestia/scheme.json"
        if not state_file.exists():
            return

        data = json.loads(state_file.read_text()).get("colours", {})
        if not data:
            return

        text = data.get("onSurface", "f9e0d9").lstrip("#")
        subtext = data.get("onSurfaceVariant", "bca6a0").lstrip("#")
        main = data.get("surfaceContainer", "221714").lstrip("#")
        primary = data.get("primary", "f9b7a3").lstrip("#")
        outline = data.get("outline", "84716c").lstrip("#")
        error = data.get("error", "fa746f").lstrip("#")
        card = data.get("surfaceContainerHigh", "291d19").lstrip("#")
        player = data.get("surfaceContainerLow", "1a110f").lstrip("#")
        sidebar = data.get("surface", "130d0a").lstrip("#")
        main_elevated = data.get("surfaceContainerHigh", "291d19").lstrip("#")
        highlight_elevated = data.get("surfaceContainerHighest", "30231e").lstrip("#")

        color_ini_content = f"""[caelestia]
text                = {text}
subtext             = {subtext}
main                = {main}
highlight           = {primary}
misc                = {primary}
notification        = {outline}
notification-error  = {error}
shadow              = 000000
card                = {card}
player              = {player}
sidebar             = {sidebar}
main-elevated       = {main_elevated}
highlight-elevated  = {highlight_elevated}
selected-row        = {text}
button              = {primary}
button-active       = {primary}
button-disabled     = {outline}
tab-active          = {card}
"""
        theme_dir = Path.home() / ".config/spicetify/Themes/caelestia"
        theme_dir.mkdir(parents=True, exist_ok=True)
        color_ini_file = theme_dir / "color.ini"

        old_content = ""
        if color_ini_file.exists():
            try:
                old_content = color_ini_file.read_text()
            except Exception:
                pass

        if old_content.strip() == color_ini_content.strip():
            log("Spicetify: Colors unchanged, skipping apply")
            return

        color_ini_file.write_text(color_ini_content)
        pending_flag = Path.home() / ".cache/spicetify_pending_reload"
        pending_flag.touch()

        # Never reload during preview
        if is_preview or os.environ.get("SCHEME_COLOURS"):
            log("Spicetify: Color.ini updated (preview mode, skipping apply)")
            return

        if is_spotify_focused():
            spicetify_bin = Path.home() / ".spicetify/spicetify"
            if spicetify_bin.exists():
                subprocess.run([str(spicetify_bin), "apply", "-q"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
                pending_flag.unlink(missing_ok=True)
                log("Spicetify: Applied Material You dynamic theme immediately (Spotify is focused)")
        else:
            log("Spicetify: Color.ini updated; apply queued for next Spotify focus (no playback disruption)")
    except Exception as e:
        log(f"Spicetify sync error: {e}")


def parse_argv(argv: list[str]) -> dict:
    """Tiny hand-rolled parser (the project deliberately avoids argparse).

    Usage:
      sync-rgb.py [#hex]              apply an explicit colour (no theme boost)
      sync-rgb.py --only a,b,c        restrict to these device keys
      sync-rgb.py --skip-config       ignore rgb-config.json (legacy behaviour)
    """
    opts = {"hex": None, "only": None, "skip_config": False}
    it = iter(argv)
    for tok in it:
        if tok == "--skip-config":
            opts["skip_config"] = True
        elif tok == "--only":
            opts["only"] = next(it, "")
        elif tok.startswith("--only="):
            opts["only"] = tok.split("=", 1)[1]
        elif tok in ("-h", "--help"):
            print(parse_argv.__doc__)
            sys.exit(0)
        elif not tok.startswith("-"):
            opts["hex"] = tok
    if opts["only"] is not None:
        opts["only"] = {k.strip() for k in opts["only"].split(",") if k.strip()}
    return opts


def main():
    log(f"--- sync-rgb started (PID {os.getpid()}) ---")
    opts = parse_argv(sys.argv[1:])
    cache_live_palette()

    config = DEFAULT_RGB_CONFIG if opts["skip_config"] else load_rgb_config()

    raw_hex, from_theme = get_hex_color(config, opts["hex"])
    if from_theme:
        r, g, b = enhance_color_for_leds(raw_hex)
    else:
        hc = raw_hex.lstrip("#")
        r, g, b = int(hc[0:2], 16), int(hc[2:4], 16), int(hc[4:6], 16)
        log(f"Colour #{hc} sent verbatim (no saturation boost)")

    # Prevent double-flashes when Caelestia fires multiple hooks (wallpaper + theme) simultaneously
    cache_color_file = Path("/tmp/sync_rgb_last_applied.txt")
    target_sig = f"{r},{g},{b}:{opts['only']}"
    now = time.time()
    if cache_color_file.exists() and not opts["hex"]:
        try:
            last_sig, last_time = cache_color_file.read_text().strip().split("@")
            if last_sig == target_sig and (now - float(last_time)) < 0.4:
                log(f"Skipping duplicate sync call (already applied {target_sig} < 0.4s ago)")
                return
        except Exception:
            pass
    try:
        cache_color_file.write_text(f"{target_sig}@{now}")
    except Exception:
        pass

    # A device runs only if enabled in config AND (no --only filter OR listed in it).
    enabled = config.get("devices", DEFAULT_RGB_CONFIG["devices"])
    profiles = config.get("device_profiles", DEFAULT_RGB_CONFIG.get("device_profiles", {}))
    only = opts["only"]

    # The wallpaper *preview* is the only caller that passes --only (see
    # Wallpapers.qml); the confirmed theme/wallpaper postHook runs with no
    # args (but WITH SCHEME_COLOURS in the env - that env var is NOT a
    # preview signal). Preview fires every ~150 ms while scrolling, and the
    # Akko 2.4 GHz radio garbles writes that close together, so throttle the
    # keyboard on the preview path only - never on a confirmed change.
    akko_throttle = only is not None

    def wants(key: str) -> bool:
        return enabled.get(key, True) and (only is None or key in only)

    argb_zones = config.get("devices_extra", {}).get("openrgb", {}).get("argb_zones", False)

    targets = {
        "openrgb": lambda: sync_openrgb(r, g, b, argb_zones, profile=profiles.get("openrgb")),
        "magichome": lambda: sync_magichome(r, g, b, profile=profiles.get("magichome")),
        "mchose_base": lambda: sync_mchose_base(r, g, b, profile=profiles.get("mchose_base")),
        "akko_keyboard": lambda: sync_akko_keyboard(r, g, b, throttle=akko_throttle, profile=profiles.get("akko_keyboard")),
        "spicetify": sync_spicetify,
    }

    threads = []
    for key, fn in targets.items():
        if wants(key):
            t = threading.Thread(target=fn)
            threads.append(t)
            t.start()
        else:
            log(f"Skipping {key} (disabled or filtered out)")

    for t in threads:
        t.join(timeout=6)
    log("--- sync-rgb finished ---")


if __name__ == "__main__":
    main()
