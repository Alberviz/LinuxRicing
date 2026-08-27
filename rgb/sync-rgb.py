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


def sync_openrgb(r: int, g: int, b: int, argb_zones: bool = False):
    """Set PC components (Motherboard, RAM, Fans) in OpenRGB via SDK Server, skipping Akko to avoid USB collisions.

    When ``argb_zones`` is True the animated wave daemon (argb-wave.py) owns the
    RAM and the ``Aura Addressable`` fan headers, so we only push the solid
    accent to the non-addressable motherboard LEDs and leave the rest alone.
    """
    if "openrgb:_" in battery_alert_zones():
        log("OpenRGB: reclamado por una alerta de batería, se omite el sync de tema")
        return
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
            name_l = dev.name.lower()
            # Skip Akko/ROYUAN keyboards in OpenRGB - handled by dedicated sync_akko_keyboard
            if "akko" in name_l or "royuan" in name_l:
                continue

            # When the animated wave daemon (argb-wave.py) is running it owns
            # the whole ASUS board (mainboard + addressable headers) and the
            # RAM via its own OpenRGB client. A second client writing here at
            # the same time makes the LEDs race and strobe, so bail entirely.
            if argb_zones and ("dram" in name_l or "asus" in name_l or "aura" in name_l):
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
    """Calculate progressive color from Red (<=15%) -> Orange -> Amber -> Lime -> Emerald Green (100%)."""
    if bat_level is None:
        bat_level = 100
    bat_level = max(0, min(100, bat_level))
    if bat_level <= 15:
        return (255, 0, 0)
    t = (bat_level - 15) / 85.0
    hue_deg = (t ** 1.3) * 125.0
    nr, ng, nb = colorsys.hsv_to_rgb(hue_deg / 360.0, 1.0, 1.0)
    return (int(nr * 255 + 0.5), int(ng * 255 + 0.5), int(nb * 255 + 0.5))


def sync_akko_keyboard(r: int, g: int, b: int, brightness: int = 4, throttle: bool = False):
    """
    Set Akko 5075B Plus Keyboard Backlight (Opcode 0x07) and Side-Strip (Opcode 0x08)
    via direct USB HID Feature Reports on Interface 2.
    Both the backlight and the side-strip follow the system palette in solid color.

    Battery-reactive behaviour now lives in rgb/battery-lighting: if it owns a
    zone (listed in ~/.cache/battery_alerts.json) we skip that packet so the
    theme sync does not stomp the active alert effect.
    """
    # Both the USB cable (PID 4015) and the 2.4 GHz dongle (PID 4011) can be
    # enumerated at once. The wireless link drops packets and the backlight
    # freezes white, so always drive the wired node when it exists and only
    # fall back to the dongle when USB is unplugged.
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

    AKKO_FLAGS_CUSTOM_RGB = 0x08

    # rgb/battery-lighting may own one or both Akko zones. Skip the packet for a
    # claimed zone; if both are claimed there is nothing left to do.
    alert_zones = battery_alert_zones()
    skip_sidestrip = "akko_keyboard:sidestrip" in alert_zones
    skip_keys = "akko_keyboard:keys" in alert_zones
    if skip_sidestrip and skip_keys:
        log("Akko Keyboard: ambas zonas reclamadas por una alerta de batería, no se toca")
        return

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

    # 2. Side-Strip (SLED = Opcode 0x08) -> Solid Theme Color
    sled = bytearray(64)
    sled[0] = 0x08
    sled[1] = 0x01  # Static
    sled[2] = 0x04  # Speed
    sled[3] = brightness
    sled[4] = AKKO_FLAGS_CUSTOM_RGB
    sled[5], sled[6], sled[7] = r, g, b
    sled[8] = _akko_checksum8(sled)
    raw_sled = bytearray([0x00]) + sled

    lock_fd = None
    try:
        lock_fd = os.open("/tmp/akko_sync.lock", os.O_CREAT | os.O_RDWR)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
    except Exception:
        lock_fd = None

    # On the preview path only: hard floor between writes. The 2.4 GHz radio
    # drops/garbles packets that arrive too close together (this is what
    # turns the backlight white when scrolling wallpapers fast). A confirmed
    # theme change (throttle=False) must always get through.
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
                # Exact send sequence from rgb/akko-rgb (the one that reliably
                # drives the 2.4 GHz keyboard): the side-strip packet goes
                # first and wakes the RF transceiver, then the backlight
                # packet lands, then a repeat confirms it - a single backlight
                # send gets dropped on the wireless link and the LEDs stay on
                # whatever they were (which reads as white/frozen).
                if not skip_sidestrip:
                    fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_sled)), raw_sled)
                    time.sleep(0.03)
                if not skip_keys:
                    fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_led)), raw_led)
                    time.sleep(0.03)
                    fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_led)), raw_led)
                os.close(fd)
                try:
                    stamp.write_text(str(time.time()))
                except Exception:
                    pass
                bl_txt = "omitido (alerta)" if skip_keys else f"RGB({r},{g},{b})"
                ss_txt = "omitido (alerta)" if skip_sidestrip else f"RGB({r},{g},{b})"
                log(f"Akko Keyboard ({node}): Backlight {bl_txt} + Side-Strip {ss_txt}")
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
    if "magichome:_" in battery_alert_zones():
        log("MagicHome: reclamado por una alerta de batería, se omite el sync de tema")
        return
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
        "openrgb": lambda: sync_openrgb(r, g, b, argb_zones),
        "magichome": lambda: sync_magichome(r, g, b),
        "mchose_base": lambda: sync_mchose_base(r, g, b),
        "akko_keyboard": lambda: sync_akko_keyboard(r, g, b, throttle=akko_throttle),
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
