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
    """Set PC components AND Akko Keyboard Backlight in OpenRGB via SDK Server."""
    try:
        from openrgb import OpenRGBClient
        from openrgb.utils import RGBColor

        client = OpenRGBClient()
        col = RGBColor(r, g, b)
        synced = []
        for dev in client.devices:
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


def sync_akko_keyboard(r: int, g: int, b: int, brightness: int = 4):
    """
    Set Akko 5075B Plus Keyboard Backlight (Opcode 0x07) and Side-Strip (Opcode 0x08)
    via direct USB HID Feature Reports on Interface 2. OpenRGB does not support this
    keyboard's proprietary protocol, so both zones must be driven by raw HID here.
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
                    if ":1.2" in link:
                        nodes.append("/dev/" + os.path.basename(h))
            except Exception:
                pass

    if not nodes:
        log("Akko Keyboard: No HID node found")
        return

    # 1. Side-Strip (SLED = Opcode 0x08)
    sled = bytearray(64)
    sled[0] = 0x08
    sled[1] = 0x01  # Mode: Static
    sled[2] = 0x04  # Speed
    sled[3] = brightness
    sled[4] = 0x07  # Custom RGB (0x07 = custom color, 0x08 = preset pink)
    sled[5] = r
    sled[6] = g
    sled[7] = b
    sled[63] = sum(sled[:63]) & 0xFF
    raw_sled = bytearray([0x00]) + sled

    # 2. Backlight (LED = Opcode 0x07)
    led = bytearray(64)
    led[0] = 0x07
    led[1] = 0x01  # Mode: Static
    led[2] = 0x04  # Speed
    led[3] = brightness
    led[4] = 0x07  # Custom RGB
    led[5] = r
    led[6] = g
    led[7] = b
    led[63] = sum(led[:63]) & 0xFF
    raw_led = bytearray([0x00]) + led

    for node in nodes:
        try:
            fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
            fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_sled)), raw_sled)
            time.sleep(0.02)
            fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw_led)), raw_led)
            os.close(fd)
            log(f"Akko Keyboard: Synced Backlight+Side-Strip RGB({r},{g},{b}) to {node}")
            return
        except Exception as e:
            log(f"Akko Keyboard error on {node}: {e}")


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
        100, 0x00, 0x03, 0x01, 0x00,
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


def main():
    log(f"--- sync-rgb started (PID {os.getpid()}) ---")
    raw_hex = get_hex_color()
    r, g, b = enhance_color_for_leds(raw_hex)

    t1 = threading.Thread(target=sync_openrgb, args=(r, g, b))
    t2 = threading.Thread(target=sync_magichome, args=(r, g, b))
    t3 = threading.Thread(target=sync_mchose_base, args=(r, g, b))
    t4 = threading.Thread(target=sync_akko_keyboard, args=(r, g, b))

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
