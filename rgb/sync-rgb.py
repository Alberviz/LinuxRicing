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
    "notification_flash": {"enabled": False, "mode": "accent", "pulses": 2},
}

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
            if isinstance(user.get("notification_flash"), dict):
                cfg["notification_flash"].update(user["notification_flash"])
    except FileNotFoundError:
        pass
    except Exception as e:
        log(f"rgb-config.json unreadable ({e}), using defaults")
    return cfg


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


def sync_openrgb(r: int, g: int, b: int):
    """Set PC components (Motherboard, RAM, Fans) in OpenRGB via SDK Server, skipping Akko to avoid USB collisions."""
    try:
        from openrgb import OpenRGBClient
        from openrgb.utils import RGBColor

        client = OpenRGBClient()
        col = RGBColor(r, g, b)
        synced = []
        for dev in client.devices:
            # Skip Akko/ROYUAN keyboards in OpenRGB - handled by dedicated sync_akko_keyboard
            if "akko" in dev.name.lower() or "royuan" in dev.name.lower():
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
                zone.set_color(col)
            synced.append(dev.name)
        log(f"OpenRGB (SDK): Synced RGB({r},{g},{b}) to {synced}")
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


def sync_akko_keyboard(r: int, g: int, b: int, brightness: int = 4):
    """
    Set Akko 5075B Plus Keyboard Backlight (Opcode 0x07) and Side-Strip (Opcode 0x08)
    via direct USB HID Feature Reports on Interface 2.
    Backlight follows the system palette in solid color.
    Side-strip applies reactive rules:
      - Charging / USB: Steady stream (0x05) at slowest speed with progressive battery level color.
      - Low Battery (<=20%): Breathing Red (0x02).
      - Normal (>20%): Solid system color (0x01).
    """
    nodes = []
    for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        uevent = f"{h}/device/uevent"
        if os.path.exists(uevent):
            try:
                with open(uevent) as f:
                    content = f.read()
                if "3151" in content and ("4015" in content or "4011" in content):
                    link = os.path.realpath(f"{h}/device")
                    if ":1.2" in link:
                        nodes.append("/dev/" + os.path.basename(h))
            except Exception:
                pass

    if not nodes:
        log("Akko Keyboard: No HID node found")
        return

    AKKO_FLAGS_CUSTOM_RGB = 0x08

    # Read cached battery/charging state from mchose-battery cache to avoid IOCTL collisions
    cache_file = Path.home() / ".cache/mchose_battery.json"
    bat_pct = 100
    is_charging = False
    if cache_file.exists():
        try:
            cdata = json.loads(cache_file.read_text())
            bat_pct = cdata.get("akko_battery", 100)
            is_charging = (cdata.get("akko_status") == "Cargando")
        except Exception:
            pass

    # 1. Main Backlight (LED = Opcode 0x07) -> Solid Theme Color
    led = bytearray(64)
    led[0] = 0x07
    led[1] = 0x01  # Mode: Static
    led[2] = 0x04  # Speed
    led[3] = brightness
    led[4] = AKKO_FLAGS_CUSTOM_RGB
    led[5], led[6], led[7] = r, g, b
    led[8] = _akko_checksum8(led)
    raw_led = bytearray([0x00]) + led

    # 2. Side-Strip (SLED = Opcode 0x08) -> Reactive Battery & Charging Rules
    sled = bytearray(64)
    sled[0] = 0x08
    sled[3] = brightness
    sled[4] = AKKO_FLAGS_CUSTOM_RGB

    if is_charging:
        br, bg, bb = get_akko_battery_level_color(bat_pct)
        sled[1] = 0x05  # Steady Stream / Snake
        sled[2] = 0x00  # Velocidad mínima = 0 (ultracalmada)
        sled[5], sled[6], sled[7] = br, bg, bb
        status_log = f"Cargando ({bat_pct}% -> Steady Stream RGB({br},{bg},{bb}))"
    elif bat_pct <= 20:
        sled[1] = 0x02  # Breathing / Respiración
        sled[2] = 0x02  # Velocidad media
        sled[5], sled[6], sled[7] = 255, 0, 0  # Rojo
        status_log = f"Batería Baja ({bat_pct}% -> Breathing Rojo)"
    else:
        sled[1] = 0x01  # Static
        sled[2] = 0x04
        sled[5], sled[6], sled[7] = r, g, b
        status_log = f"Normal ({bat_pct}% -> Static RGB({r},{g},{b}))"

    sled[8] = _akko_checksum8(sled)
    raw_sled = bytearray([0x00]) + sled

    lock_fd = None
    try:
        lock_fd = os.open("/tmp/akko_sync.lock", os.O_CREAT | os.O_RDWR)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
    except Exception:
        lock_fd = None

    try:
        for node in nodes:
            try:
                fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
                # 1. Send Side-strip first (also acts as RF link wake)
                fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_sled)), raw_sled)
                time.sleep(0.03)

                # 2. Send Backlight packet
                fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_led)), raw_led)
                time.sleep(0.03)

                # 3. Confirmation retransmission for Backlight
                fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_led)), raw_led)
                os.close(fd)
                log(f"Akko Keyboard ({node}): Synced Backlight RGB({r},{g},{b}) + Side-Strip ({status_log})")
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


def sync_mchose_base(r: int, g: int, b: int):
    """Set MCHOSE 8K Dongle / Charging Base RGB via reverse-engineered Command 0x2B protocol."""
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

    payload = [
        0x2B, 0x01, 0x06, 0x00,
        100, 0x00, 0x01, 0x01, 0x00,
        r, g, b,
        r, g, b,
        0x00, 0x00, 0x00, 0x00, 0x00
    ]
    raw = bytearray([0x11] + [x ^ 0xFF for x in payload])

    for node in nodes:
        try:
            fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
            fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw)), raw)
            os.close(fd)
            log(f"MCHOSE Base: Synced RGB({r},{g},{b}) to {node} via Cmd 0x2B")
        except Exception as e:
            log(f"MCHOSE Base error on {node}: {e}")


def sync_magichome(r: int, g: int, b: int):
    """Set Magic Home LED strip color and power on."""
    if not MAGIC_HOME_IP:
        return

    try:
        from flux_led import WifiLedBulb

        bulb = WifiLedBulb(MAGIC_HOME_IP, timeout=2)
        bulb.turnOn()
        bulb.setRgb(r, g, b)
        bulb.close()
        log(f"MagicHome (flux_led): Set RGB ({r}, {g}, {b}) successfully")
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

    config = DEFAULT_RGB_CONFIG if opts["skip_config"] else load_rgb_config()

    raw_hex, from_theme = get_hex_color(config, opts["hex"])
    if from_theme:
        r, g, b = enhance_color_for_leds(raw_hex)
    else:
        hc = raw_hex.lstrip("#")
        r, g, b = int(hc[0:2], 16), int(hc[2:4], 16), int(hc[4:6], 16)
        log(f"Colour #{hc} sent verbatim (no saturation boost)")

    # A device runs only if enabled in config AND (no --only filter OR listed in it).
    enabled = config.get("devices", DEFAULT_RGB_CONFIG["devices"])
    only = opts["only"]

    def wants(key: str) -> bool:
        return enabled.get(key, True) and (only is None or key in only)

    targets = {
        "openrgb": lambda: sync_openrgb(r, g, b),
        "magichome": lambda: sync_magichome(r, g, b),
        "mchose_base": lambda: sync_mchose_base(r, g, b),
        "akko_keyboard": lambda: sync_akko_keyboard(r, g, b),
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
