#!/usr/bin/env python3
import os
import fcntl
import time
import sys

def HIDIOCSFEATURE(size):
    return (3 << 30) | (size << 16) | (ord("H") << 8) | 0x06

node = "/dev/hidraw7"

def send_mode(mode_id, color_mode=0x00, speed=0x01, direction=0x00):
    payload = [
        0x2B, 0x01, 0x02, 0x00,
        100, speed, mode_id, color_mode, direction,
        255, 0, 0,
        0, 255, 255,
        0x00, 0x00, 0x00, 0x00, 0x00
    ]
    raw = bytearray([0x11] + [x ^ 0xFF for x in payload])
    fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
    fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw)), raw)
    os.close(fd)

if len(sys.argv) > 1:
    m = int(sys.argv[1])
    cm = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    send_mode(m, cm)
    print(f"✔ Modo {m} (ColorMode {cm}) enviado!")
else:
    print("=== Probando Modos 1 al 10 con modo Rainbow (ColorMode=0) ===")
    for m in range(1, 11):
        send_mode(m, color_mode=0x00, speed=0x02)
        print(f"👉 Probando MODO {m}... (Observa la base durante 4 segundos)")
        time.sleep(4)
