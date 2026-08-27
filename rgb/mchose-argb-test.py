#!/usr/bin/env python3
"""
MCHOSE 8K Base ARGB / Per-LED Investigation Tool
Tests individual LED addressing, zone splitting, and raw matrix commands.
"""
import sys
import os
import glob
import fcntl
import time

def HIDIOCSFEATURE(size):
    return (3 << 30) | (size << 16) | (ord("H") << 8) | 0x06

def find_mchose_node():
    for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        uevent = f"{h}/device/uevent"
        if os.path.exists(uevent):
            try:
                with open(uevent) as f:
                    c = f.read()
                if "3837" in c and "1001" in c:
                    link = os.path.realpath(f"{h}/device")
                    if ":1.2" in link:
                        return "/dev/" + os.path.basename(h)
            except Exception:
                pass
    return "/dev/hidraw7"

NODE = find_mchose_node()
print(f"[*] MCHOSE Base Node: {NODE}")

def send_raw_report(payload, report_id=0x11, invert=True):
    if invert:
        raw = bytearray([report_id] + [x ^ 0xFF for x in payload])
    else:
        raw = bytearray([report_id] + list(payload))
    try:
        fd = os.open(NODE, os.O_RDWR | os.O_NONBLOCK)
        fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw)), raw)
        os.close(fd)
        return True
    except Exception as e:
        print(f"[!] Error enviando a {NODE}: {e}")
        return False

def test_split_zones():
    print("\n--- TEST 1: Zona Dividida (Color 1: ROJO, Color 2: CYAN/AZUL) ---")
    # Color 1 = Rojo (255, 0, 0), Color 2 = Cyan (0, 255, 255)
    for color_mode in [0x00, 0x01, 0x02, 0x03, 0x04]:
        payload = [
            0x2B, 0x01, 0x06, 0x00,
            100, 0x00, 0x03, color_mode, 0x00,
            255, 0, 0,       # Color 1: Rojo
            0, 255, 255,     # Color 2: Cyan
            0x00, 0x00, 0x00, 0x00, 0x00
        ]
        send_raw_report(payload)
        print(f"Enviado Comando 0x2B con ColorMode={color_mode} (Rojo vs Cyan)... Observa la base (3 seg)")
        time.sleep(3)

def test_per_led_matrix():
    print("\n--- TEST 2: Array Direccionable ARGB (Alternando Rojo y Azul) ---")
    # Formato común RealTek/PixArt: 0x2C o 0x2B con buffer de 16-32 LEDs
    # Creamos un patrón alterno: LED par = Rojo, LED impar = Azul
    for cmd in [0x2C, 0x2D, 0x08, 0x07]:
        leds = []
        for i in range(16):
            if i % 2 == 0:
                leds.extend([255, 0, 0])      # Rojo
            else:
                leds.extend([0, 255, 255])    # Cyan
        
        payload = [cmd, 0x00, len(leds)] + leds
        # Pad to 64 bytes if needed
        if len(payload) < 63:
            payload.extend([0x00] * (63 - len(payload)))
        payload = payload[:63]
        
        send_raw_report(payload, report_id=0x11, invert=True)
        send_raw_report(payload, report_id=0x11, invert=False)
        print(f"Enviado buffer de LEDs con Opcode 0x{cmd:02X}... Observa si alterna colores (3 seg)")
        time.sleep(3)

def test_led_specific(index=5):
    print(f"\n--- TEST 3: Encender únicamente LED #{index} en VERDE y el resto en APAGADO ---")
    # Intentamos paquete indexado: [0x2B, MODE, LED_INDEX, R, G, B]
    for opcode in [0x2B, 0x2C]:
        payload = [
            opcode, 0x01, 0x06, index,
            100, 0x00, 0x03, 0x01, index,
            0, 255, 0,       # Verde puro
            0, 0, 0,         # Apagado
            0x00, 0x00, 0x00, 0x00, 0x00
        ]
        send_raw_report(payload, report_id=0x11, invert=True)
        print(f"Enviado comando indexado (LED #{index} Verde) con Opcode 0x{opcode:02X}... (3 seg)")
        time.sleep(3)

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    if mode == "split":
        test_split_zones()
    elif mode == "matrix":
        test_per_led_matrix()
    elif mode == "led":
        idx = int(sys.argv[2]) if len(sys.argv) > 2 else 5
        test_led_specific(idx)
    else:
        test_split_zones()
        test_per_led_matrix()
        test_led_specific(5)
