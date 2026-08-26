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
import time
from pathlib import Path

from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

STATE_FILE = Path.home() / ".local/state/caelestia/scheme.json"
# Written by sync-rgb.py on every run (including wallpaper *preview*, before
# Enter is pressed). If it's fresh we use it instead of STATE_FILE, so the
# wave reacts live while scrolling through wallpapers, not just on confirm.
LIVE_PALETTE_CACHE = Path("/tmp/caelestia-rgb-live-palette.json")
LIVE_CACHE_TTL = 2.0  # seconds before falling back to the confirmed state file
GRADIENT_KEYS = ["red", "peach", "yellow", "green", "sky", "sapphire", "lavender", "mauve"]
FALLBACK_ANCHORS = [(255, 60, 60), (60, 255, 120), (60, 140, 255)]

CYCLE_SECONDS = 7.0   # time for the wave to loop back to its start
FRAME_SECONDS = 0.08  # ~12.5 fps


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
    try:
        if time.time() - LIVE_PALETTE_CACHE.stat().st_mtime < LIVE_CACHE_TTL:
            colours = json.loads(LIVE_PALETTE_CACHE.read_text())
            anchors = [enhance(colours[k]) for k in GRADIENT_KEYS if k in colours]
            if anchors:
                return anchors
    except Exception:
        pass
    try:
        colours = json.loads(STATE_FILE.read_text()).get("colours", {})
        anchors = [enhance(colours[k]) for k in GRADIENT_KEYS if k in colours]
        if anchors:
            return anchors
    except Exception:
        pass
    return FALLBACK_ANCHORS


def color_at(anchors: list[tuple[int, int, int]], pos: float) -> tuple[int, int, int]:
    """pos in [0,1). Cyclic interpolation so the wave loops with no seam."""
    n = len(anchors)
    scaled = (pos % 1.0) * n
    idx = int(scaled)
    frac = scaled - idx
    c1, c2 = anchors[idx % n], anchors[(idx + 1) % n]
    return tuple(int(c1[k] + (c2[k] - c1[k]) * frac) for k in range(3))


def setup_devices(client: OpenRGBClient):
    for dev in client.devices:
        if "Keyboard" in dev.name:
            continue
        if dev.modes and dev.modes[dev.active_mode].name != "Direct":
            try:
                direct_idx = next(
                    i for i, m in enumerate(dev.modes) if m.name == "Direct"
                )
                dev.set_mode(direct_idx)
            except Exception:
                pass


def main():
    client = None
    phase = 0.0

    while True:
        try:
            if client is None:
                client = OpenRGBClient(name="argb-wave")
                setup_devices(client)

            anchors = get_anchors()
            
            for dev in client.devices:
                if "Keyboard" in dev.name:
                    continue

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
        except Exception:
            client = None
            time.sleep(2)


if __name__ == "__main__":
    main()

