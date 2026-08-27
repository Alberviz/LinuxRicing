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

def sync_openrgb(primary_color):
    """Applies unified solid color to RAM sticks and Motherboard/Fans without I2C flicker."""
    try:
        client = OpenRGBClient()
        c_primary = primary_color if isinstance(primary_color, (list, tuple)) else primary_color[0]
        
        dram_devs = [d for d in client.devices if "DRAM" in d.name or d.type == 2]
        
        # 1. RAM Sticks
        for dev in dram_devs:
            try:
                dev.set_mode(0)  # Direct Mode
                dev.set_color(RGBColor(*c_primary))
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
                
        print(f"[OpenRGB] Synced RAM and Fans to unified color: {c_primary}")
    except Exception as e:
        print(f"[OpenRGB Error] {e}")

def sync_mchose_base(primary_color):
    try:
        import hid
        r, g, b = primary_color
        payload = [
            0x2B, 0x01, 0x06, 0x00,
            100, 0x00, 0x03, 0x01, 0x00,
            r, g, b,
            r, g, b,
            0x00, 0x00, 0x00, 0x00, 0x00
        ]
        raw = bytearray([0x11] + [x ^ 0xFF for x in payload])
        for d in hid.enumerate(0x3837, 0x1001):
            if d.get('interface_number') == 2 or '&mi_02' in str(d.get('path', '')).lower():
                dev = hid.device()
                dev.open_path(d['path'])
                dev.send_feature_report(raw)
                dev.close()
        print(f"[MCHOSE Base] Synced LED Ring to unified color: {primary_color}")
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

def get_akko_battery_level_color(bat_level):
    """Calculate progressive color from Red (<=15%) -> Amber -> Yellow -> Lime -> Emerald Green (100%)."""
    if bat_level is None:
        bat_level = 100
    bat_level = max(0, min(100, bat_level))
    if bat_level <= 15:
        return (255, 0, 0)
    hue = ((bat_level - 15) / 85.0) * (120.0 / 360.0)
    nr, ng, nb = colorsys.hsv_to_rgb(hue, 1.0, 1.0)
    return (int(nr * 255), int(ng * 255), int(nb * 255))

def sync_akko_keyboard(primary_color, brightness=4):
    import urllib.request, struct, hid
    r, g, b = primary_color
    AKKO_FLAGS_CUSTOM_RGB = 0x08

    # 1. Query current battery and charging status from keyboard (Opcode 0x83)
    bat_pct = 100
    is_charging = False
    target_dev_path = None
    target_pid = 0x4015

    for pid in [0x4015, 0x4011]:
        for d in hid.enumerate(0x3151, pid):
            path_str = d['path'].decode('utf-8', errors='ignore') if isinstance(d['path'], bytes) else str(d['path'])
            if d.get('interface_number') == 2 or 'mi_02' in path_str.lower():
                target_dev_path = d['path']
                target_pid = pid
                try:
                    dev = hid.device()
                    dev.open_path(d['path'])
                    req = bytearray(64); req[0] = 0x83
                    req[8] = 0xFF - (sum(req[:8]) & 0xFF)
                    dev.send_feature_report(bytearray([0x00]) + req)
                    time.sleep(0.02)
                    resp = dev.get_feature_report(0x00, 65)
                    dev.close()
                    if len(resp) >= 4 and resp[1] == 0x83:
                        bat = resp[2]
                        st_code = resp[3]
                        is_charging = (st_code == 1 or pid == 0x4015)
                        if bat > 0:
                            bat_pct = bat
                except Exception:
                    pass
                break
        if target_dev_path:
            break

    # 2. Main Backlight (Teclas) -> Siempre color primario sólido de Material You
    led = bytearray(64)
    led[0] = 0x07; led[1] = 0x01; led[2] = 0x04; led[3] = brightness; led[4] = AKKO_FLAGS_CUSTOM_RGB
    led[5], led[6], led[7] = r, g, b

    # 3. Side-strip (Tira Lateral) -> Reglas reactivas de batería
    sled = bytearray(64)
    sled[0] = 0x08; sled[3] = brightness; sled[4] = AKKO_FLAGS_CUSTOM_RGB

    if is_charging:
        # Enchufado/Cargando: Flujo de luz (Steady Stream) a velocidad mínima (0) con el color del nivel de batería
        br, bg, bb = get_akko_battery_level_color(bat_pct)
        sled[1] = 0x05  # Steady Stream / Snake
        sled[2] = 0x00  # Velocidad mínima = 0 (ultracalmada)
        sled[5], sled[6], sled[7] = br, bg, bb
        status_log = f"Cargando (Steady Stream {bat_pct}% -> RGB({br},{bg},{bb}))"
    elif bat_pct <= 20:
        # Batería baja (<=20%): Rojo parpadeante/respiración de advertencia
        sled[1] = 0x02  # Breathing / Respiración
        sled[2] = 0x02  # Velocidad media
        sled[5], sled[6], sled[7] = 255, 0, 0
        status_log = f"Batería Baja ({bat_pct}% -> Rojo Respiración)"
    else:
        # Normal (>20%): Sincronizado en color sólido del tema
        sled[1] = 0x01  # Fijo
        sled[2] = 0x04
        sled[5], sled[6], sled[7] = r, g, b
        status_log = f"Normal ({bat_pct}% -> Sincronizado Sólido)"

    # Try direct HID write
    try:
        sled_hid = bytearray(sled); sled_hid[8] = 0xFF - (sum(sled_hid[:8]) & 0xFF)
        led_hid = bytearray(led); led_hid[8] = 0xFF - (sum(led_hid[:8]) & 0xFF)
        if target_dev_path:
            dev = hid.device()
            dev.open_path(target_dev_path)
            dev.send_feature_report(bytearray([0x00]) + led_hid)
            time.sleep(0.02)
            dev.send_feature_report(bytearray([0x00]) + sled_hid)
            dev.close()
            mode_label = "USB Wired" if target_pid == 0x4015 else "2.4G Wireless"
            print(f"[Akko Keyboard (HID {mode_label})] Synced ({status_log}) | Backlight: {primary_color}")
            return
    except Exception as e:
        print(f"[Akko HID Warning] {e}")

    # Fallback to gRPC bridge
    try:
        url = "http://127.0.0.1:3814/driver.DriverGrpc/sendMsg"
        for pid_str in ["PID_4015", "PID_4011"]:
            dev_path = rf"\\?\HID#VID_3151&{pid_str}&MI_02#7&26793fac&0&0000#{{4d1e55b2-f16f-11cf-88cb-001111000030}}"
            for msg in [led, sled]:
                pb = encode_sendmsg(dev_path, bytes(msg), checksum_type=1)
                frame = bytes([0x00]) + struct.pack(">I", len(pb)) + pb
                req = urllib.request.Request(url, data=frame, headers={"Content-Type": "application/grpc-web+proto", "x-grpc-web": "1"})
                with urllib.request.urlopen(req, timeout=1) as resp:
                    resp.read()
            print(f"[Akko Keyboard (gRPC)] Synced ({status_log}) | Backlight: {primary_color}")
            return
    except Exception:
        pass

def sync_magichome(primary_color):
    try:
        from flux_led import WifiLedBulb
        r, g, b = primary_color
        bulb = WifiLedBulb(MAGIC_HOME_IP, timeout=2)
        bulb.turnOn()
        bulb.setRgb(r, g, b)
        print(f"[MagicHome] Synced Room Ambient to unified color: {primary_color}")
    except Exception as e:
        print(f"[MagicHome Error] {e}")

def sync_all(palette=None):
    if not palette:
        palette = get_pure_wallpaper_palette(1)
        
    c_primary = palette[0]
    
    print("\n========================================================")
    print("--- Unified Wallpaper Primary Color ---")
    print(f"   * Primary Color (RGB): {c_primary}")
    print("========================================================")
    
    threads = [
        threading.Thread(target=sync_openrgb, args=(c_primary,)),
        threading.Thread(target=sync_mchose_base, args=(c_primary,)),
        threading.Thread(target=sync_akko_keyboard, args=(c_primary,)),
        threading.Thread(target=sync_magichome, args=(c_primary,)),
    ]
    for t in threads: t.start()
    for t in threads: t.join()

if __name__ == "__main__":
    sync_all()
