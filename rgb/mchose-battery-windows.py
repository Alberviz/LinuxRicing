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

sys.stdout.reconfigure(encoding='utf-8')

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

    for pid in [0x4150, 0x1001]:
        for d in hid.enumerate(0x3837, pid):
            path_str = d['path'].decode('utf-8', errors='ignore') if isinstance(d['path'], bytes) else str(d['path'])
            # Target Col02 / Usage Page 0xFF01 (MCHOSE Base & Mouse Telemetry)
            if d.get('usage_page') == 0xFF01 or 'col02' in path_str.lower():
                try:
                    dev = hid.device()
                    dev.open_path(d['path'])
                    
                    # Retry across pulse window to catch heartbeat
                    for _ in range(6):
                        req = bytearray([0x11, 0x06 ^ 0xFF] + [0xFF] * 19)
                        dev.send_feature_report(req)
                        time.sleep(0.04)

                        feat_buf = dev.get_feature_report(0x11, 64)
                        if feat_buf:
                            dec = [feat_buf[0]] + [b ^ 0xFF for b in feat_buf[1:]]
                            if len(dec) >= 13 and dec[0] == 0x11 and dec[1] == 0x06 and dec[11] > 0:
                                bat = dec[11]
                                is_charging = (dec[12] == 1)
                                if is_charging:
                                    st = "Cargando (USB)" if pid == 0x4150 else "Cargando (En Base)"
                                else:
                                    st = "Descargando"
                                dev.close()
                                cache["k7_battery"] = bat
                                cache["k7_status"] = st
                                save_cache(cache)
                                return bat, st
                        time.sleep(0.05)
                    dev.close()
                except Exception:
                    pass

    if last_bat is not None:
        return last_bat, last_status
    return None, "Desconectado"

def resolve_akko_dongle_path():
    """Instance ID (8&xxxxxxxx) del nodo MI_02 del dongle 2.4G. Cambia entre
    máquinas y reconexiones, así que resolver en caliente."""
    try:
        for d in hid.enumerate(0x3151, 0x4011):
            p = d['path'].decode('utf-8', 'ignore') if isinstance(d['path'], bytes) else str(d['path'])
            if d.get('interface_number') == 2 or 'mi_02' in p.lower():
                return p
    except Exception:
        pass
    return None

def get_akko_keyboard_battery():
    cache = load_cache()
    last_bat = cache.get("akko_battery", 80)
    last_status = cache.get("akko_status", "Descargando")

    # 1. Query via direct USB HID if plugged in via cable (PID 0x4015)
    for d in hid.enumerate(0x3151, 0x4015):
        path_str = d['path'].decode('utf-8', errors='ignore') if isinstance(d['path'], bytes) else str(d['path'])
        if d.get('interface_number') == 2 or 'mi_02' in path_str.lower():
            try:
                dev = hid.device()
                dev.open_path(d['path'])
                req = bytearray(64); req[0] = 0x83; req[7] = 0x7C
                dev.send_feature_report(bytearray([0x00]) + req)
                time.sleep(0.04)
                feat = dev.get_feature_report(0x00, 65)
                dev.close()
                if feat and feat[1] == 0x83:
                    pct = feat[2] if feat[2] > 0 else last_bat
                    st_code = feat[3]
                    st = "Cargando (USB)" if st_code == 1 else ("Completa" if st_code == 2 else "Descargando")
                    cache["akko_battery"] = pct
                    cache["akko_status"] = st
                    save_cache(cache)
                    return pct, st
            except Exception:
                pass

    # 2. Query via gRPC bridge (PID 0x4011 / 2.4GHz Dongle)
    try:
        import urllib.request, struct
        grpc_dev_path = resolve_akko_dongle_path()
        if grpc_dev_path:
            def encode_varint(val):
                out = bytearray()
                while val > 0x7F:
                    out.append((val & 0x7F) | 0x80); val >>= 7
                out.append(val & 0x7F)
                return bytes(out)

            dp_bytes = grpc_dev_path.encode('utf-8')
            pb_send = bytearray([0x0A]) + encode_varint(len(dp_bytes)) + dp_bytes
            req_msg = bytearray(8); req_msg[0] = 0x83
            pb_send.append(0x12); pb_send.extend(encode_varint(len(req_msg))); pb_send.extend(req_msg)
            pb_send.append(0x20); pb_send.append(0x01) # DangleType KEYBOARD

            url = "http://127.0.0.1:3814/driver.DriverGrpc/sendMsg"
            frame = bytes([0x00]) + struct.pack(">I", len(pb_send)) + pb_send
            req = urllib.request.Request(url, data=frame, headers={"Content-Type": "application/grpc-web+proto", "x-grpc-web": "1"})
            with urllib.request.urlopen(req, timeout=1.5) as resp:
                resp.read()
            time.sleep(0.03)

            url_r = "http://127.0.0.1:3814/driver.DriverGrpc/readMsg"
            pb_read = bytearray([0x0A]) + encode_varint(len(dp_bytes)) + dp_bytes
            frame_r = bytes([0x00]) + struct.pack(">I", len(pb_read)) + pb_read
            req_r = urllib.request.Request(url_r, data=frame_r, headers={"Content-Type": "application/grpc-web+proto", "x-grpc-web": "1"})
            with urllib.request.urlopen(req_r, timeout=1.5) as resp:
                data = resp.read()
                if len(data) >= 5:
                    l = struct.unpack(">I", data[1:5])[0]
                    body = data[5:5+l]
                    if len(body) >= 3 and body[0] == 0x12:
                        p = body[2:]
                        if p[0] == 0x83 and p[1] > 0:
                            bat = p[1]
                            st = "Cargando (USB)" if p[2] == 1 else "Descargando"
                            cache["akko_battery"] = bat
                            cache["akko_status"] = st
                            save_cache(cache)
                            return bat, st
    except Exception:
        pass

    if last_bat is not None:
        return last_bat, last_status
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
                "charging": "Cargando" in (v9_st or ""),
                "connected": (v9_bat is not None)
            },
            "mouse": {
                "name": "MCHOSE K7 Ultra",
                "battery": k7_bat,
                "status": k7_st,
                "charging": "Cargando" in (k7_st or ""),
                "connected": (k7_bat is not None)
            },
            "keyboard": {
                "name": "Akko Multi-modes",
                "battery": akko_bat,
                "status": akko_st,
                "charging": "Cargando" in (akko_st or ""),
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
