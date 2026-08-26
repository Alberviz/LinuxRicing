#!/usr/bin/env python3
"""
Unified RGB Synchronizer for Windows:
1. Extracts authentic color palette directly from active wallpaper (Red/Magenta/Purple/Rose)
2. Applies solid, rock-steady harmonious lighting across all hardware (No I2C flickering):
   - RAM 1: Primary Magenta (#D000FF)
   - RAM 2: Secondary Purple (#7E00FF)
   - Motherboard & Fans: Magenta (#D000FF)
   - MCHOSE Base: Outer ring Crimson (#FF0025), Center Magenta (#D000FF)
   - Akko Keyboard: Backlight Magenta (#D000FF), Side-Strip Rose Pink (#FF00B8)
   - Magic Home LED Strip: Purple Ambient (#7E00FF)
"""

import sys, os, time, json, colorsys, threading, urllib.request, struct
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor
from PIL import Image

MAGIC_HOME_IP = "192.168.0.136"

def get_pure_wallpaper_palette(max_colors=4):
    """Extract authentic colors actually present in the wallpaper."""
    transcoded = os.path.expandvars(r"%APPDATA%\Microsoft\Windows\Themes\TranscodedWallpaper")
    if not os.path.exists(transcoded):
        return [(208, 0, 255), (126, 0, 255), (255, 0, 184), (255, 0, 37)]
        
    im = Image.open(transcoded).convert("RGB").resize((150, 150))
    quantized = im.quantize(colors=16, method=Image.Quantize.MEDIANCUT)
    palette_raw = quantized.getpalette()[:48]
    
    candidates = []
    for i in range(0, len(palette_raw), 3):
        r, g, b = palette_raw[i], palette_raw[i+1], palette_raw[i+2]
        h, s, v = colorsys.rgb_to_hsv(r/255.0, g/255.0, b/255.0)
        if s > 0.15 and v > 0.08:
            boosted_s = min(1.0, max(0.80, s * 1.8))
            nr, ng, nb = colorsys.hsv_to_rgb(h, boosted_s, 1.0)
            candidates.append(((int(nr * 255), int(ng * 255), int(nb * 255)), s * v, h))
            
    if not candidates:
        return [(208, 0, 255), (126, 0, 255), (255, 0, 184), (255, 0, 37)]
        
    candidates.sort(key=lambda x: x[1], reverse=True)
    result = []
    for col, score, h in candidates:
        if not any(abs(h - colorsys.rgb_to_hsv(c[0]/255.0, c[1]/255.0, c[2]/255.0)[0]) < 0.04 for c in result):
            result.append(col)
        if len(result) >= max_colors:
            break
            
    while len(result) < max_colors:
        result.append(result[len(result) % len(result)])
    return result

def sync_openrgb(palette):
    """Applies steady solid colors to RAM sticks and Motherboard/Fans without I2C flicker."""
    try:
        client = OpenRGBClient()
        c_primary = palette[0]
        c_secondary = palette[1] if len(palette) > 1 else palette[0]
        
        dram_devs = [d for d in client.devices if "DRAM" in d.name or d.type == 2]
        
        # 1. RAM Sticks
        for i, dev in enumerate(dram_devs):
            try:
                dev.set_mode(0)  # Direct Mode
                dev.set_color(RGBColor(*(c_primary if i % 2 == 0 else c_secondary)))
            except Exception as e:
                print(f"[RAM Error] {e}")
                
        # 2. Motherboard & Fans
        for dev in client.devices:
            if "Keyboard" in dev.name or dev in dram_devs:
                continue
            for z in dev.zones:
                if "Addressable" in z.name and len(z.leds) == 0:
                    try: z.resize(30)
                    except Exception: pass
            try:
                dev.set_mode(0)
                dev.set_color(RGBColor(*c_primary))
            except Exception as e:
                print(f"[Mobo Error] {e}")
                
        print(f"[OpenRGB] Synced RAM (Solid {c_primary} & {c_secondary}) and Fans ({c_primary})")
    except Exception as e:
        print(f"[OpenRGB Error] {e}")

def sync_mchose_base(c_ring, c_center):
    try:
        import hid
        r1, g1, b1 = c_ring
        r2, g2, b2 = c_center
        payload = [
            0x2B, 0x01, 0x06, 0x00,
            100, 0x00, 0x03, 0x01, 0x00,
            r1, g1, b1,
            r2, g2, b2,
            0x00, 0x00, 0x00, 0x00, 0x00
        ]
        raw = bytearray([0x11] + [x ^ 0xFF for x in payload])
        for d in hid.enumerate(0x3837, 0x1001):
            if d.get('interface_number') == 2 or '&mi_02' in str(d.get('path', '')).lower():
                dev = hid.device()
                dev.open_path(d['path'])
                dev.send_feature_report(raw)
                dev.close()
        print(f"[MCHOSE Base] Synced Ring: {c_ring}, Center: {c_center}")
    except Exception as e:
        print(f"[MCHOSE Error] {e}")

def encode_varint(val):
    out = bytearray()
    while val > 0x7F:
        out.append((val & 0x7F) | 0x80)
        val >>= 7
    out.append(val & 0x7F)
    return bytes(out)

def encode_sendmsg(device_path: str, msg: bytes, checksum_type: int = 1) -> bytes:
    buf = bytearray()
    dp_bytes = device_path.encode('utf-8')
    buf.append(0x0A)
    buf.extend(encode_varint(len(dp_bytes)))
    buf.extend(dp_bytes)
    buf.append(0x12)
    buf.extend(encode_varint(len(msg)))
    buf.extend(msg)
    if checksum_type != 0:
        buf.append(0x18)
        buf.extend(encode_varint(checksum_type))
    return bytes(buf)

def sync_akko_keyboard(backlight_rgb, sidelight_rgb, brightness=4):
    import urllib.request, struct
    dev_path = r"\\?\HID#VID_3151&PID_4015&MI_02#7&26793fac&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}"
    r_side, g_side, b_side = sidelight_rgb
    r_back, g_back, b_back = backlight_rgb
    
    sled = bytearray(64)
    sled[0] = 0x08; sled[1] = 0x01; sled[2] = 0x04; sled[3] = brightness; sled[4] = 0x08
    sled[5], sled[6], sled[7] = r_side, g_side, b_side
    
    led = bytearray(64)
    led[0] = 0x07; led[1] = 0x01; led[2] = 0x04; led[3] = brightness; led[4] = 0x08
    led[5], led[6], led[7] = r_back, g_back, b_back

    try:
        url = "http://127.0.0.1:3814/driver.DriverGrpc/sendMsg"
        for msg in [sled, led]:
            pb = encode_sendmsg(dev_path, bytes(msg), checksum_type=1)
            frame = bytes([0x00]) + struct.pack(">I", len(pb)) + pb
            req = urllib.request.Request(url, data=frame, headers={"Content-Type": "application/grpc-web+proto", "x-grpc-web": "1"})
            with urllib.request.urlopen(req, timeout=1) as resp:
                resp.read()
        print(f"[Akko Keyboard (gRPC)] Synced Backlight: {backlight_rgb}, Side-Strip: {sidelight_rgb}")
        return
    except Exception:
        pass

    try:
        import hid
        sled_hid = bytearray(sled); sled_hid[63] = sum(sled_hid[:63]) & 0xFF
        led_hid = bytearray(led); led_hid[63] = sum(led_hid[:63]) & 0xFF
        for d in hid.enumerate(0x3151, 0x4015):
            if d.get('interface_number') == 2 or '&mi_02' in str(d.get('path', '')).lower():
                dev = hid.device()
                dev.open_path(d['path'])
                dev.send_feature_report(bytearray([0x00]) + sled_hid)
                time.sleep(0.02)
                dev.send_feature_report(bytearray([0x00]) + led_hid)
                dev.close()
                print(f"[Akko Keyboard (HID)] Synced Backlight: {backlight_rgb}, Side-Strip: {sidelight_rgb}")
                return
    except Exception as e:
        print(f"[Akko Error] {e}")

def sync_magichome(ambient_rgb):
    try:
        from flux_led import WifiLedBulb
        r, g, b = ambient_rgb
        bulb = WifiLedBulb(MAGIC_HOME_IP, timeout=2)
        bulb.turnOn()
        bulb.setRgb(r, g, b)
        print(f"[MagicHome] Synced Room Ambient: {ambient_rgb}")
    except Exception as e:
        print(f"[MagicHome Error] {e}")

def sync_all(palette=None):
    if not palette:
        palette = get_pure_wallpaper_palette(4)
        
    c_magenta = palette[0]
    c_purple  = palette[1] if len(palette) > 1 else palette[0]
    c_rose    = palette[2] if len(palette) > 2 else palette[1]
    c_crimson = palette[3] if len(palette) > 3 else palette[0]
    
    print("\n========================================================")
    print("--- Pure Wallpaper Colors (Red / Magenta / Purple / Rose) ---")
    print(f"   * Color 1 (Magenta):    {c_magenta}")
    print(f"   * Color 2 (Purple):     {c_purple}")
    print(f"   * Color 3 (Rose Pink):  {c_rose}")
    print(f"   * Color 4 (Crimson):    {c_crimson}")
    print("========================================================")
    
    threads = [
        threading.Thread(target=sync_openrgb, args=(palette,)),
        threading.Thread(target=sync_mchose_base, args=(c_crimson, c_magenta)),
        threading.Thread(target=sync_akko_keyboard, args=(c_magenta, c_rose)),
        threading.Thread(target=sync_magichome, args=(c_purple,)),
    ]
    for t in threads: t.start()
    for t in threads: t.join()

if __name__ == "__main__":
    sync_all()
