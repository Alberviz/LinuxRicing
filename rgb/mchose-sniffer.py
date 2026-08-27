#!/usr/bin/env python3
import os
import sys
import select
import time
from datetime import datetime

nodes = ["/dev/hidraw5", "/dev/hidraw6", "/dev/hidraw7"]
fds = {}
for n in nodes:
    try:
        fd = os.open(n, os.O_RDWR | os.O_NONBLOCK)
        fds[fd] = n
        print(f"[*] Escuchando en {n}...", flush=True)
    except Exception as e:
        print(f"[!] No se pudo abrir {n}: {e}", flush=True)

if not fds:
    print("Error: No hidraw nodes opened.")
    sys.exit(1)

print("\n🚀 SNIFFER ACTIVO: Cambia a 'Breathing' en la web ahora...\n", flush=True)

while True:
    r, _, _ = select.select(list(fds.keys()), [], [], 0.1)
    for fd in r:
        try:
            data = os.read(fd, 64)
            if data:
                node = fds[fd]
                hex_str = " ".join(f"{b:02X}" for b in data)
                dec_inv = " ".join(f"{b ^ 0xFF:02X}" for b in data[1:]) if len(data) > 1 else ""
                now = datetime.now().strftime("%H:%M:%S.%f")[:-3]
                print(f"[{now}] [{node}] RAW ({len(data)}B): {hex_str}", flush=True)
                if dec_inv:
                    print(f"                 INVERTIDO (XOR 0xFF): {dec_inv}", flush=True)
        except Exception:
            pass
