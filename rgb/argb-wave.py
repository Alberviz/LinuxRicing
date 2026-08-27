#!/usr/bin/env python3
"""
Continuous ARGB wave animation for addressable zones (RAM, ARGB fan headers).

Runs as a background daemon (see argb-wave.service). Reads Caelestia's live
color palette every frame and scrolls a gradient across each addressable
zone's LEDs, so it stays in sync with wallpaper changes without needing to
be restarted.

Keyboard, motherboard non-addressable LEDs, MCHOSE base and the MagicHome
strip are never touched here - those stay on sync-rgb.py's solid-color path.
"""

import colorsys
import json
import sys
import time
from pathlib import Path

from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

EXPECTED_MARKERS = ("DRAM", "ASUS", "AURA")
# The OpenRGB SDK server accepts connections *before* it finishes probing the
# SMBus / AURA hardware, so a client that connects at boot can get an empty or
# partial device list and then spin forever driving nothing. We block on
# connect() until the RAM and the board are actually present.
CONNECT_MAX_WAIT = 120  # seconds to wait for enumeration before recycling state
REASSERT_SECONDS = 20.0  # re-poll hardware and re-assert Direct mode this often

STATE_FILE = Path.home() / ".local/state/caelestia/scheme.json"
# Written by sync-rgb.py on every run (including wallpaper *preview*, before
# Enter is pressed). If it's fresh we use it instead of STATE_FILE, so the
# wave reacts live while scrolling through wallpapers, not just on confirm.
LIVE_PALETTE_CACHE = Path("/tmp/caelestia-rgb-live-palette.json")
LIVE_CACHE_TTL = 2.0  # seconds before falling back to the confirmed state file
GRADIENT_KEYS = ["red", "peach", "yellow", "green", "sky", "sapphire", "lavender", "mauve"]
FALLBACK_ANCHORS = [(255, 60, 60), (60, 255, 120), (60, 140, 255)]

CYCLE_SECONDS = 4.0   # time for the wave to loop back to its start
FRAME_SECONDS = 0.06  # ~16 fps (SMBus is slow - do not push much higher)


def log(msg: str) -> None:
    """One line to stderr -> shows up in `journalctl --user -u argb-wave`."""
    print(f"argb-wave: {msg}", file=sys.stderr, flush=True)


def enhance(hex_color: str) -> tuple[int, int, int]:
    hex_clean = hex_color.lstrip("#")
    r = int(hex_clean[0:2], 16) / 255.0
    g = int(hex_clean[2:4], 16) / 255.0
    b = int(hex_clean[4:6], 16) / 255.0
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if s > 0.05:
        s = min(1.0, max(0.80, s * 3.5))
        v = 1.0
        r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return (int(r * 255), int(g * 255), int(b * 255))


def get_anchors() -> list[tuple[int, int, int]]:
    primary_hex = None
    try:
        if time.time() - LIVE_PALETTE_CACHE.stat().st_mtime < LIVE_CACHE_TTL:
            colours = json.loads(LIVE_PALETTE_CACHE.read_text())
            primary_hex = colours.get("primary")
    except Exception:
        pass
    if not primary_hex:
        try:
            colours = json.loads(STATE_FILE.read_text()).get("colours", {})
            primary_hex = colours.get("primary")
        except Exception:
            pass

    if not primary_hex:
        primary_hex = "abcaea"

    base_rgb = enhance(primary_hex)
    h, s, v = colorsys.rgb_to_hsv(base_rgb[0] / 255.0, base_rgb[1] / 255.0, base_rgb[2] / 255.0)

    # Harmonious wave oscillating smoothly around the primary hue
    anchors = []
    for shift in [-0.04, -0.02, 0.0, 0.02, 0.04, 0.0]:
        cur_h = (h + shift) % 1.0
        r, g, b = colorsys.hsv_to_rgb(cur_h, s, v)
        anchors.append((int(r * 255), int(g * 255), int(b * 255)))
    return anchors


def color_at(anchors: list[tuple[int, int, int]], pos: float) -> tuple[int, int, int]:
    """pos in [0,1). Cyclic interpolation so the wave loops with no seam."""
    n = len(anchors)
    scaled = (pos % 1.0) * n
    idx = int(scaled)
    frac = scaled - idx
    c1, c2 = anchors[idx % n], anchors[(idx + 1) % n]
    return tuple(int(c1[k] + (c2[k] - c1[k]) * frac) for k in range(3))


def driven_devices(client: OpenRGBClient) -> list:
    """The devices this daemon owns: the RAM and the ASUS/AURA board (mainboard
    LEDs + addressable fan headers). Keyboards are never touched here."""
    return [
        dev
        for dev in client.devices
        if "Keyboard" not in dev.name
        and any(marker in dev.name for marker in EXPECTED_MARKERS)
    ]


def force_direct(dev) -> None:
    """Pull a device into Direct mode if it isn't already.

    The ENE DRAM modules (and the board) persist their last hardware effect
    mode in their own controller, so after a forced reboot the RAM can come up
    in 'Rainbow'. While a hardware mode is active every set_colors() we send is
    silently ignored, so the wave never shows until we switch back to Direct.
    """
    try:
        if dev.modes and dev.modes[dev.active_mode].name != "Direct":
            dev.set_mode("Direct")
    except Exception:
        pass


def setup_devices(client: OpenRGBClient) -> None:
    for dev in driven_devices(client):
        force_direct(dev)


def connect() -> tuple[OpenRGBClient, int]:
    """Connect to the OpenRGB server and wait until it has actually enumerated
    the devices we drive. Raises after CONNECT_MAX_WAIT so the caller recycles
    its state and tries again from scratch."""
    deadline = time.time() + CONNECT_MAX_WAIT
    delay = 1.0
    waited = False
    while True:
        try:
            client = OpenRGBClient(name="argb-wave")
            client.update()
            names = " ".join(dev.name for dev in client.devices)
            if "DRAM" in names and ("ASUS" in names or "AURA" in names):
                setup_devices(client)
                if waited:
                    log(f"connected, {len(client.devices)} devices enumerated")
                return client, len(client.devices)
        except Exception:
            pass
        if time.time() >= deadline:
            raise RuntimeError("OpenRGB devices not ready within CONNECT_MAX_WAIT")
        if not waited:
            log("waiting for OpenRGB to finish enumerating RAM / board...")
            waited = True
        time.sleep(delay)
        delay = min(delay * 1.5, 8.0)


def main():
    client = None
    device_count = 0
    last_reassert = 0.0
    phase = 0.0

    while True:
        try:
            if client is None:
                client, device_count = connect()
                last_reassert = time.time()

            now = time.time()
            if now - last_reassert >= REASSERT_SECONDS:
                # Re-poll the hardware: catches OpenRGB finishing a late device
                # probe after we connected, and catches a device that dropped
                # back to a hardware mode on its own.
                client.update()
                if len(client.devices) != device_count:
                    raise RuntimeError("OpenRGB device list changed, reconnecting")
                for dev in driven_devices(client):
                    force_direct(dev)
                last_reassert = now

            anchors = get_anchors()

            for dev in driven_devices(client):
                if "DRAM" in dev.name:
                    n = len(dev.leds)
                    cols = [
                        RGBColor(*color_at(anchors, phase + i / float(n)))
                        for i in range(n)
                    ]
                    dev.set_colors(cols, fast=True)

                elif "ASUS" in dev.name or "AURA" in dev.name:
                    cols = []
                    # 1. Mainboard non-addressable LEDs (4 LEDs): Solid accent
                    mainboard_col = RGBColor(*anchors[0])
                    cols.extend([mainboard_col] * 4)

                    # 2. Addressable headers 1 & 2 (60 LEDs each): Rich moving wave (12 LED cycle)
                    for i in range(60):
                        cols.append(RGBColor(*color_at(anchors, phase + (i / 12.0))))
                    for i in range(60):
                        cols.append(RGBColor(*color_at(anchors, phase + (i / 12.0))))

                    if len(cols) == len(dev.leds):
                        dev.set_colors(cols, fast=True)
                    else:
                        # Fallback for unexpected zone sizes
                        n = len(dev.leds)
                        cols = [
                            RGBColor(*color_at(anchors, phase + i / float(n)))
                            for i in range(n)
                        ]
                        dev.set_colors(cols, fast=True)

            phase = (phase + FRAME_SECONDS / CYCLE_SECONDS) % 1.0
            time.sleep(FRAME_SECONDS)
        except Exception as e:
            log(f"lost OpenRGB ({e!r}), reconnecting")
            client = None
            time.sleep(2)


if __name__ == "__main__":
    main()

