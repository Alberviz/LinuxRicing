#!/usr/bin/env python3
"""
MCHOSE 8K Base Interactive Mode Explorer
Permite probar cualquier ID de modo, velocidad, target y color al instante.
"""
import sys
import os
import glob
import fcntl

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

def hex_to_rgb(hex_str):
    hex_str = hex_str.lstrip("#")
    if len(hex_str) == 6:
        return int(hex_str[0:2], 16), int(hex_str[2:4], 16), int(hex_str[4:6], 16)
    return 255, 0, 0

def send_packet(mode_id, color_mode=0, speed=0, target=2, brightness=100, color="#ff0000"):
    r, g, b = hex_to_rgb(color)
    payload = [
        0x2B, 0x01, target, 0x00,
        brightness, speed, mode_id, color_mode, 0x00,
        r, g, b,
        0, 255, 255,
        0x00, 0x00, 0x00, 0x00, 0x00
    ]
    raw = bytearray([0x11] + [x ^ 0xFF for x in payload])
    try:
        fd = os.open(NODE, os.O_RDWR | os.O_NONBLOCK)
        fcntl.ioctl(fd, HIDIOCSFEATURE(len(raw)), raw)
        os.close(fd)
        hex_preview = " ".join(f"{x:02X}" for x in payload)
        print(f"✔ ENVIADO A LA BASE:")
        print(f"  • Modo (Mode ID):       {mode_id}")
        print(f"  • ColorMode (0=Rainbow):{color_mode}")
        print(f"  • Velocidad (0-4):      {speed}")
        print(f"  • Target (2=Base):      0x{target:02X}")
        print(f"  • Payload (Decod):      {hex_preview}")
        return True
    except Exception as e:
        print(f"❌ Error al enviar a {NODE}: {e}")
        return False

def interactive_menu():
    print("=" * 60)
    print("      🧪 LABORATORIO DE MODOS MCHOSE 8K BASE")
    print("=" * 60)
    print("Comandos disponibles:")
    print("  • Escribe solo un número (ej. '1', '5', '8') para probar ese modo.")
    print("  • Escribe 'm c v' (ej. '5 0 0') -> Modo 5, ColorMode 0 (Rainbow), Vel 0 (Rápida).")
    print("  • Escribe 'target <num>' para cambiar el target (ej. 'target 7' para ratón).")
    print("  • Escribe 'q' o pulsa Ctrl+C para salir.\n")

    current_target = 2
    current_color_mode = 0
    current_speed = 0

    while True:
        try:
            line = input(f"[Target:0x{current_target:02X} | Rainbow:{current_color_mode==0}] Introduce Modo > ").strip()
            if not line:
                continue
            if line.lower() in ["q", "exit", "quit"]:
                print("Saliendo...")
                break
            
            parts = line.split()
            if parts[0].lower() == "target" and len(parts) > 1:
                current_target = int(parts[1], 0)
                print(f"Target cambiado a 0x{current_target:02X}")
                continue
            
            mode = int(parts[0], 0)
            cm = int(parts[1], 0) if len(parts) > 1 else current_color_mode
            spd = int(parts[2], 0) if len(parts) > 2 else current_speed

            send_packet(mode, color_mode=cm, speed=spd, target=current_target)
            print("-" * 60)
        except (ValueError, IndexError):
            print("Formato no válido. Escribe un número (ej. '5') o '5 0 0'")
        except (KeyboardInterrupt, EOFError):
            print("\nSaliendo...")
            break

if __name__ == "__main__":
    if len(sys.argv) > 1:
        m = int(sys.argv[1], 0)
        cm = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0
        spd = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0
        tgt = int(sys.argv[4], 0) if len(sys.argv) > 4 else 2
        send_packet(m, color_mode=cm, speed=spd, target=tgt)
    else:
        interactive_menu()
