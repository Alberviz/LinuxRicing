#!/usr/bin/env python3
"""
Sync Caelestia dynamic colors to:
1. PC RGB devices (Motherboard, RAM) via OpenRGB SDK
2. Akko 5075B Plus Keyboard (Backlight + Side-Strip) via direct HID ioctl (3151:4015)
3. MCHOSE Dongle / Charging Base (Ring + Center) via direct HID ioctl (3837:1001)
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

# Set to False to go back to solid single-color everywhere.
RAINBOW_MODE = True
# Read by argb-wave.py on every frame: lets the wave react live to wallpaper
# *preview* (before Enter), not just to a confirmed change.
LIVE_PALETTE_CACHE = Path("/tmp/caelestia-rgb-live-palette.json")
# Palette keys (from Caelestia's scheme.json) used as gradient stops on
# addressable zones (RAM, ARGB fan headers). Keyboard is never touched.
GRADIENT_KEYS = ["red", "peach", "yellow", "green", "sky", "sapphire", "lavender", "mauve"]


def log(msg: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")


def HIDIOCSFEATURE(size: int) -> int:
    return (3 << 30) | (size << 16) | (ord("H") << 8) | 0x06


def get_hex_color() -> str:
    """Retrieve active color from environment or Caelestia state."""
    raw_colours = os.environ.get("SCHEME_COLOURS")
    if raw_colours:
        try:
            colours = json.loads(raw_colours)
            if COLOR_KEY in colours:
                c = colours[COLOR_KEY].lstrip("#")
                log(f"Extracted #{c} from SCHEME_COLOURS env")
                return c
        except Exception as e:
            log(f"Error parsing SCHEME_COLOURS: {e}")

    state_file = Path.home() / ".local/state/caelestia/scheme.json"
    if state_file.exists():
        try:
            data = json.loads(state_file.read_text())
            colours = data.get("colours", {})
            if COLOR_KEY in colours:
                c = colours[COLOR_KEY].lstrip("#")
                log(f"Extracted #{c} from scheme.json state")
                return c
        except Exception as e:
            log(f"Error reading scheme.json: {e}")

    return "d8bde7"


def get_palette() -> dict:
    """Retrieve the full color palette dict from environment or Caelestia state."""
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
        return res
    else:
        return (int(r * 255), int(g * 255), int(b * 255))


def get_device_colors():
    """Derive distinct harmonious colors for different hardware zones."""
    palette = get_palette()
    primary_hex = get_hex_color()
    c_primary = enhance_color_for_leds(primary_hex)

    sec_hex = palette.get("secondary", palette.get("mauve", primary_hex))
    c_secondary = enhance_color_for_leds(sec_hex)

    tert_hex = palette.get("tertiary", palette.get("pink", primary_hex))
    c_tertiary = enhance_color_for_leds(tert_hex)

    accent_hex = palette.get("peach", palette.get("pink", palette.get("lavender", sec_hex)))
    c_accent = enhance_color_for_leds(accent_hex)

    return {
        "primary": c_primary,
        "secondary": c_secondary,
        "tertiary": c_tertiary,
        "accent": c_accent,
    }


def build_gradient(count: int) -> list[tuple[int, int, int]]:
    """Build a smooth `count`-stop RGB gradient from the theme palette."""
    palette = get_palette()
    anchors = [
        enhance_color_for_leds(palette[key].lstrip("#"))
        for key in GRADIENT_KEYS
        if key in palette
    ]
    if not anchors:
        anchors = [enhance_color_for_leds(get_hex_color())]
    if count <= 1 or len(anchors) == 1:
        return [anchors[0]] * count

    stops = []
    for i in range(count):
        pos = i * (len(anchors) - 1) / (count - 1)
        idx = int(pos)
        frac = pos - idx
        c1, c2 = anchors[idx], anchors[min(idx + 1, len(anchors) - 1)]
        stops.append(tuple(int(c1[k] + (c2[k] - c1[k]) * frac) for k in range(3)))
    return stops


def sync_openrgb(r: int, g: int, b: int):
    """Set PC components (Motherboard / RAM) in OpenRGB via SDK Server."""
    try:
        from openrgb import OpenRGBClient
        from openrgb.utils import RGBColor

        client = OpenRGBClient()
        col = RGBColor(r, g, b)
        synced = []
        for dev in client.devices:
            # Skip Keyboard: Akko is controlled with high precision via direct HID
            if "Keyboard" in dev.name:
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
                is_addressable_zone = "DRAM" in dev.name or zone.name in (
                    "Aura Addressable 1",
                    "Aura Addressable 2",
                )
                if RAINBOW_MODE and is_addressable_zone and len(zone.leds) > 1:
                    gradient = build_gradient(len(zone.leds))
                    zone.set_colors([RGBColor(*c) for c in gradient])
                else:
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


def sync_akko_keyboard(backlight_rgb: tuple[int, int, int], sidelight_rgb: tuple[int, int, int], brightness: int = 4):
    """
    Set Akko 5075B Plus Keyboard Backlight (Opcode 0x07) and Side-Strip (Opcode 0x08)
    via direct USB HID Feature Reports on Interface 2.
    """
    nodes = []
    for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        uevent = f"{h}/device/uevent"
        if os.path.exists(uevent):
            try:
                with open(uevent) as f:
                    content = f.read()
                if "3151" in content and "4015" in content:
                    link = os.path.realpath(f"{h}/device")
                    if ":1.2" in link:  # Target ONLY Interface 2 (Vendor RGB Interface)
                        nodes.append("/dev/" + os.path.basename(h))
            except Exception:
                pass

    if not nodes:
        # Fallback search if interface string differs
        for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
            uevent = f"{h}/device/uevent"
            if os.path.exists(uevent):
                try:
                    with open(uevent) as f:
                        if "3151" in f.read() and "4015" in f.read():
                            nodes.append("/dev/" + os.path.basename(h))
                except Exception:
                    pass

    if not nodes:
        log("Akko Keyboard: No HID node found")
        return

    r_side, g_side, b_side = sidelight_rgb
    r_back, g_back, b_back = backlight_rgb

    # 1. Side-Strip (SLED = Opcode 0x08)
    sled = bytearray(64)
    sled[0] = 0x08
    sled[1] = 0x01  # Mode: Static
    sled[2] = 0x04  # Speed
    sled[3] = brightness
    sled[4] = 0x08  # Custom RGB
    sled[5] = r_side
    sled[6] = g_side
    sled[7] = b_side
    sled[63] = sum(sled[:63]) & 0xFF
    raw_sled = bytearray([0x00]) + sled

    # 2. Backlight (LED = Opcode 0x07)
    led = bytearray(64)
    led[0] = 0x07
    led[1] = 0x01  # Mode: Static
    led[2] = 0x04  # Speed
    led[3] = brightness
    led[4] = 0x08  # Custom RGB
    led[5] = r_back
    led[6] = g_back
    led[7] = b_back
    led[63] = sum(led[:63]) & 0xFF
    raw_led = bytearray([0x00]) + led

    for node in nodes:
        try:
            fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
            fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_sled)), raw_sled)
            time.sleep(0.02)
            fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_led)), raw_led)
            os.close(fd)
            log(f"Akko Keyboard: Synced Backlight {backlight_rgb}, Side-Strip {sidelight_rgb} to {node}")
            return
        except Exception as e:
            log(f"Akko Keyboard error on {node}: {e}")


def sync_mchose_base(c_ring: tuple[int, int, int], c_center: tuple[int, int, int]):
    """Set MCHOSE 8K Dongle / Charging Base RGB (Ring + Center) via reverse-engineered Command 0x2B protocol."""
    nodes = []
    for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        uevent = f"{h}/device/uevent"
        if os.path.exists(uevent):
            try:
                with open(uevent) as f:
                    content = f.read()
                if "3837" in content and "1001" in content:
                    link = os.path.realpath(f"{h}/device")
                    if ":1.2" in link:  # Target ONLY Interface 2 (Vendor RGB Interface)
                        nodes.append("/dev/" + os.path.basename(h))
            except Exception:
                pass

    if not nodes:
        log("MCHOSE Base: No Interface 2 HID node found")
        return

    r1, g1, b1 = c_ring
    r2, g2, b2 = c_center

    # Payload discovered from Wireshark capture (Frame 7499):
    # Byte 0: 0x2B (Base RGB Command)
    # Byte 1: 0x01 (Subcommand)
    # Byte 2: 0x06 (Lighting mode)
    # Byte 3: 0x00
    # Byte 4: Brightness (100 = 0x64)
    # Byte 5: 0x00
    # Byte 6: Speed (3)
    # Byte 7: Mode (1 = Static)
    # Byte 8: 0x00
    # Bytes 9..11: LED 1 Outer Ring RGB (r1, g1, b1)
    # Bytes 12..14: LED 2 Center Logo RGB (r2, g2, b2)
    payload = [
        0x2B, 0x01, 0x06, 0x00,
        100, 0x00, 0x03, 0x01, 0x00,
        r1, g1, b1,
        r2, g2, b2,
        0x00, 0x00, 0x00, 0x00, 0x00
    ]
    raw = bytearray([0x11] + [x ^ 0xFF for x in payload])

    for node in nodes:
        try:
            fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
            fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw)), raw)
            os.close(fd)
            log(f"MCHOSE Base: Synced Ring {c_ring}, Center {c_center} to {node} via Cmd 0x2B")
        except Exception as e:
            log(f"MCHOSE Base error on {node}: {e}")


def sync_magichome(ambient_rgb: tuple[int, int, int]):
    """Set Magic Home LED strip color and power on."""
    if not MAGIC_HOME_IP:
        return

    r, g, b = ambient_rgb
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


def cache_live_palette():
    try:
        palette = get_palette()
        if palette:
            LIVE_PALETTE_CACHE.write_text(json.dumps(palette))
    except Exception as e:
        log(f"Error caching live palette: {e}")


def main():
    log(f"--- sync-rgb started (PID {os.getpid()}) ---")
    cache_live_palette()
    
    colors = get_device_colors()
    c_primary = colors["primary"]
    c_secondary = colors["secondary"]
    c_tertiary = colors["tertiary"]
    c_accent = colors["accent"]

    log(f"Colors: Primary={c_primary}, Secondary={c_secondary}, Tertiary={c_tertiary}, Accent={c_accent}")

    t1 = threading.Thread(target=sync_openrgb, args=c_primary)
    t2 = threading.Thread(target=sync_akko_keyboard, args=(c_primary, c_accent))
    t3 = threading.Thread(target=sync_mchose_base, args=(c_accent, c_primary))
    t4 = threading.Thread(target=sync_magichome, args=(c_secondary,))

    t1.start()
    t2.start()
    t3.start()
    t4.start()

    t1.join(timeout=6)
    t2.join(timeout=6)
    t3.join(timeout=6)
    t4.join(timeout=6)
    log(f"--- sync-rgb finished ---")


if __name__ == "__main__":
    main()
