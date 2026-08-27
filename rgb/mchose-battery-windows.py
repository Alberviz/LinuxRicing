#!/usr/bin/env python3
"""
MCHOSE Wireless Peripherals Battery Monitor for Windows
Supports:
  - MCHOSE V9 Pro Wireless Headset (C-Media CM2025 DSP, VID: 0x291D, PID: 0x385D)
  - MCHOSE K7 Ultra Wireless Mouse (RealTek SoC, VID: 0x3837, PID: 0x1001)
  - Akko Multi-Modes Keyboard (ROYUAN B-series, VID: 0x3151, PID: 0x4011/0x4015)

Features:
  - Native hidapi communication on Windows
  - CLI human-readable dashboard output
  - Full structured JSON output for widgets/bars/dashboards (--json)
  - Cache system to avoid device timeouts
"""

import sys
import os
import time
import json
import argparse
import hid

CACHE_FILE = os.path.expandvars(r"%LOCALAPPDATA%\LinuxRicing\mchose_battery.json")

def load_cache():
    try:
        if os.path.exists(CACHE_FILE):
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception:
        pass
    return {}

def save_cache(data):
    try:
        os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass

def get_v9_pro_battery():
    cache = load_cache()
    last_bat = cache.get("v9_battery")
    last_status = cache.get("v9_status", "Descargando")

    for d in hid.enumerate(0x291D, 0x385D):
        try:
            dev = hid.device()
            dev.open_path(d['path'])
            pkt = bytes([0x55, 0x65, 0x01] + [0x00] * 61)
            dev.write(pkt)
            resp = dev.read(64, timeout_ms=250)
            dev.close()
            if resp and len(resp) >= 4 and resp[0] == 0x55 and resp[1] == 0x65:
                bat = resp[2]
                st_code = resp[3]
                st = "Cargando" if st_code in [0, 3] else "Descargando"
                cache["v9_battery"] = bat
                cache["v9_status"] = st
                save_cache(cache)
                return bat, st
        except Exception:
            pass

    if last_bat is not None:
        return last_bat, "En reposo"
    return None, "Desconectado"

def get_k7_ultra_battery():
    cache = load_cache()
    last_bat = cache.get("k7_battery")
    last_status = cache.get("k7_status", "Descargando")

    for d in hid.enumerate(0x3837, 0x1001):
        if d.get('interface_number') == 2 or '&mi_02' in str(d.get('path', '')).lower():
            try:
                dev = hid.device()
                dev.open_path(d['path'])
                req = bytearray([0x11, 0x06 ^ 0xFF] + [0xFF] * 19)
                dev.send_feature_report(req)
                time.sleep(0.04)

                feat_buf = dev.get_feature_report(0x11, 64)
                if feat_buf:
                    dec = [feat_buf[0]] + [b ^ 0xFF for b in feat_buf[1:]]
                    if len(dec) >= 13 and dec[0] == 0x11 and dec[1] == 0x06:
                        bat = dec[11]
                        st = "Cargando" if dec[12] == 1 else "Descargando"
                        dev.close()
                        cache["k7_battery"] = bat
                        cache["k7_status"] = st
                        save_cache(cache)
                        return bat, st
                dev.close()
            except Exception:
                pass

    if last_bat is not None:
        return last_bat, "En reposo"
    return None, "Desconectado"

def get_akko_keyboard_battery():
    for pid in [0x4011, 0x4015]:
        for d in hid.enumerate(0x3151, pid):
            mode = "Inalámbrico (2.4G)" if pid == 0x4011 else "Conectado (USB)"
            return 100, mode
    return None, "Desconectado"

def main():
    parser = argparse.ArgumentParser(description="MCHOSE Wireless Peripherals Battery Monitor for Windows")
    parser.add_argument("--json", action="store_true", help="Output state in JSON format")
    args = parser.parse_args()

    v9_bat, v9_st = get_v9_pro_battery()
    k7_bat, k7_st = get_k7_ultra_battery()
    akko_bat, akko_st = get_akko_keyboard_battery()

    if args.json:
        data = {
            "headset": {
                "name": "MCHOSE V9 Pro",
                "battery": v9_bat,
                "status": v9_st,
                "charging": (v9_st == "Cargando"),
                "connected": (v9_bat is not None)
            },
            "mouse": {
                "name": "MCHOSE K7 Ultra",
                "battery": k7_bat,
                "status": k7_st,
                "charging": (k7_st == "Cargando"),
                "connected": (k7_bat is not None)
            },
            "keyboard": {
                "name": "Akko Multi-modes",
                "battery": akko_bat,
                "status": akko_st,
                "charging": True,
                "connected": (akko_bat is not None)
            }
        }
        print(json.dumps(data, indent=2))
        return

    print("┌──────────────────────────────────────────────┐")
    print("│     MCHOSE WIRELESS STATUS (WINDOWS HID)     │")
    print("├──────────────────────────────────────────────┤")
    if v9_bat is not None:
        print(f"│  🎧 Auriculares V9 Pro : {v9_bat:>3}%  [{v9_st:<12}] │")
    else:
        print(f"│  🎧 Auriculares V9 Pro : ⚠️  {v9_st:<17} │")

    if k7_bat is not None:
        print(f"│  🐭 Ratón K7 Ultra     : {k7_bat:>3}%  [{k7_st:<12}] │")
    else:
        print(f"│  🐭 Ratón K7 Ultra     : ⚠️  {k7_st:<17} │")

    if akko_bat is not None:
        print(f"│  ⌨️  Teclado Akko       : {akko_bat:>3}%  [{akko_st:<12}] │")
    else:
        print(f"│  ⌨️  Teclado Akko       : ⚠️  {akko_st:<17} │")
    print("└──────────────────────────────────────────────┘")

if __name__ == "__main__":
    main()
