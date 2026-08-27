#!/usr/bin/env python3
"""
USB HID Packet Analyzer & Decoder for MCHOSE / RealTek Peripherals
Automates extraction of SET_REPORT / Feature Reports from Wireshark (.pcapng)
and decodes XOR 0xFF obfuscated payloads.
"""
import sys
import os
import subprocess

def analyze_pcapng(pcap_path):
    if not os.path.exists(pcap_path):
        print(f"Error: File '{pcap_path}' not found.")
        sys.exit(1)

    print(f"[*] Analizando captura: {pcap_path}")
    print("=" * 75)

    # 1. Usar tshark para extraer paquetes enviados desde el host
    cmd = [
        "tshark", "-r", pcap_path,
        "-Y", "usb.src == \"host\"",
        "-T", "fields",
        "-e", "frame.number",
        "-e", "usb.dst",
        "-e", "usb.capdata",
        "-e", "usb.data_fragment",
        "-e", "usbhid.data"
    ]

    try:
        res = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except Exception as e:
        print(f"Error ejecutando tshark: {e}")
        return

    found = 0
    for line in res.strip().split("\n"):
        if not line:
            continue
        parts = line.split("\t")
        frame = parts[0]
        dst = parts[1]
        data = "".join([p for p in parts[2:] if p])

        if data and len(data) >= 8:
            found += 1
            b = bytes.fromhex(data)
            inv = bytes([x ^ 0xFF for x in b])
            
            raw_hex = " ".join(f"{x:02X}" for x in b)
            inv_hex = " ".join(f"{x:02X}" for x in inv)

            print(f"[Frame #{frame}] Destino: {dst} ({len(b)} Bytes)")
            print(f"  ├─ RAW (Hex):       {raw_hex}")
            print(f"  └─ DECODIFICADO:    {inv_hex}")

            # Si es comando 0x2B (Control de Luces MCHOSE)
            if len(inv) >= 16 and (inv[0] == 0x2B or (len(inv) > 1 and inv[1] == 0x2B)):
                offset = 0 if inv[0] == 0x2B else 1
                cmd_code = inv[offset]
                sub = inv[offset+1]
                target = inv[offset+2]
                bright = inv[offset+4]
                speed = inv[offset+5]
                mode = inv[offset+6]
                color_mode = inv[offset+7]
                r1, g1, b1 = inv[offset+9], inv[offset+10], inv[offset+11]
                r2, g2, b2 = inv[offset+12], inv[offset+13], inv[offset+14]
                
                target_str = "Base 8K Ring" if target == 0x02 else "Ratón/Cuerpo" if target in [0x06, 0x07] else f"0x{target:02X}"
                mode_str = {0: "Apagado", 1: "Breathing (Respiración)", 2: "Wave (Ola/Arcoíris)", 3: "Static (Fijo)"}.get(mode, f"Modo {mode}")
                
                print(f"     ➤ [Estructura 0x2B Identificada]")
                print(f"        • Dispositivo:  {target_str} (Target 0x{target:02X})")
                print(f"        • Efecto:       {mode_str} (Mode ID: {mode})")
                print(f"        • Brillo:       {bright}% | Velocidad: {speed}")
                print(f"        • Color 1:      #{r1:02X}{g1:02X}{b1:02X} | Color 2: #{r2:02X}{g2:02X}{b2:02X}")
            print("-" * 75)

    if found == 0:
        print("[!] No se detectaron paquetes de datos salientes (host -> device) en la captura.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: mchose-pcap-analyzer <archivo.pcapng>")
        sys.exit(1)
    analyze_pcapng(sys.argv[1])
