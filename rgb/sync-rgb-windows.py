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

def encode_sendmsg(device_path: str, msg: bytes, checksum_type: int = 0, dangle_type: int = 1) -> bytes:
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
    if dangle_type != 0:
        buf.append(0x20)
        buf.extend(encode_varint(dangle_type))
    return bytes(buf)

def resolve_akko_dongle_path():
    """Instance ID (8&xxxxxxxx) del nodo MI_02 del dongle 2.4G. Cambia entre
    máquinas y reconexiones, así que NUNCA hardcodear: resolver en caliente."""
    try:
        import hid
        for d in hid.enumerate(0x3151, 0x4011):
            p = d['path'].decode('utf-8', 'ignore') if isinstance(d['path'], bytes) else str(d['path'])
            if d.get('interface_number') == 2 or 'mi_02' in p.lower():
                return p
    except Exception:
        pass
    return None


def encode_readmsg(device_path: str) -> bytes:
    buf = bytearray()
    dp_bytes = device_path.encode('utf-8')
    buf.append(0x0A)
    buf.extend(encode_varint(len(dp_bytes)))
    buf.extend(dp_bytes)
    return bytes(buf)

def grpc_call(method: str, payload: bytes):
    url = f"http://127.0.0.1:3814/driver.DriverGrpc/{method}"
    frame = bytes([0x00]) + struct.pack(">I", len(payload)) + payload
    req = urllib.request.Request(url, data=frame, headers={"Content-Type": "application/grpc-web+proto", "x-grpc-web": "1"})
    with urllib.request.urlopen(req, timeout=1.5) as resp:
        data = resp.read()
        if len(data) >= 5:
            msg_len = struct.unpack(">I", data[1:5])[0]
            return data[5:5+msg_len]
        return data

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
    AKKO_FLAGS_CUSTOM_RGB = 0x08  # 0x08 = Custom RGB mode in firmware

    # 1. Query current battery and charging status from keyboard (Opcode 0x83)
    bat_pct = 80
    is_charging = False
    target_dev_path = None
    target_pid = 0x4011

    # 1a. Try direct USB HID first (wired mode, PID 0x4015)
    for d in hid.enumerate(0x3151, 0x4015):
        path_str = d['path'].decode('utf-8', errors='ignore') if isinstance(d['path'], bytes) else str(d['path'])
        if d.get('interface_number') == 2 or 'mi_02' in path_str.lower():
            try:
                dev = hid.device()
                dev.open_path(d['path'])
                req = bytearray(64); req[0] = 0x83; req[7] = 0x7C
                dev.send_feature_report(bytearray([0x00]) + req)
                time.sleep(0.03)
                resp = dev.get_feature_report(0x00, 65)
                dev.close()
                if resp and len(resp) >= 4 and resp[1] == 0x83:
                    if resp[2] > 0:
                        bat_pct = resp[2]
                    is_charging = (resp[3] == 1)
                    target_dev_path = d['path']
                    target_pid = 0x4015
            except Exception:
                pass
            break

    # 1b. Fall back to gRPC bridge / 2.4GHz dongle (PID 0x4011) if wired query failed
    grpc_dev_path = resolve_akko_dongle_path()
    if target_dev_path is None and grpc_dev_path:
        try:
            req_bat = bytearray(8); req_bat[0] = 0x83
            grpc_call("sendMsg", encode_sendmsg(grpc_dev_path, bytes(req_bat), checksum_type=0, dangle_type=1))
            time.sleep(0.03)
            resp = grpc_call("readMsg", encode_readmsg(grpc_dev_path))
            if resp and len(resp) >= 3 and resp[0] == 0x12:
                payload = resp[2:]
                if payload[0] == 0x83:
                    bat_pct = payload[1]
                    is_charging = (payload[2] == 1)
        except Exception:
            pass

    # 2. Backlight (teclas): opcode 0x07, color sólido custom. Layout confirmado por
    #    captura USB: 07 01 04 <brillo> 08 R G B <checksum>. checksum_type=1 => el
    #    bridge pone el checksum 0xFF-(sum[0..7]&0xFF) en byte[8].
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

    # Transmisión. Verificado por captura USBPcap (hardware/akko-5075b-plus/USB_FINDINGS_2.4G.md):
    # el dongle 2.4G acepta el MISMO paquete que el modo cable, como Feature report
    # a la interfaz 2. NO hacen falta setLightType, changeWirelessLoopStatus ni el
    # "flush 0x88" — eran cargo-cult y no generaban tráfico USB útil. El único fallo
    # real era el device_path obsoleto hardcodeado; ahora se resuelve en caliente.
    dev_path = target_dev_path or grpc_dev_path
    if not dev_path:
        print("[Akko Warning] no se encontró el nodo MI_02 del teclado (ni cable ni dongle)")
        return
    try:
        wire = "cable" if target_pid == 0x4015 else "gRPC 2.4G"
        grpc_call("sendMsg", encode_sendmsg(dev_path, bytes(led), checksum_type=1, dangle_type=1))
        time.sleep(0.15)
        grpc_call("sendMsg", encode_sendmsg(dev_path, bytes(sled), checksum_type=1, dangle_type=1))
        print(f"[Akko Keyboard ({wire})] Synced ({status_log}) | Backlight: {primary_color}")
        return
    except Exception as e:
        print(f"[Akko Warning] {e}")

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
