#!/usr/bin/env python3
"""Mando virtual (uinput, sin dependencias) para probar Elysium de punta a punta:
el sistema lo ve como un mando más (handler jsN), así que pasa por gamepad-watch
igual que el real.

    fake-gamepad.py "<guion>"
guion: pasos separados por espacios:
    wait:<s>      esperar
    tap:<botón>   pulsar y soltar   (a b x y start select home up down left right)
    hold:<botón>:<s>  mantener
Botones por código Linux (como los manda xpadneo): south=304 east=305 north=307
west=308 select=314 start=315 mode=316. Se llama «GuliKit Controller XW (test)»,
así que gamepad-watch aplica la disposición Nintendo (abajo=B, derecha=A).
"""
import fcntl, os, struct, sys, time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
CODES = {"b": 304, "a": 305, "x": 307, "y": 308, "select": 314, "start": 315, "home": 316,  # disposición Nintendo
         "up": 544, "down": 545, "left": 546, "right": 547}

fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
for ev in (EV_KEY, EV_ABS):
    fcntl.ioctl(fd, UI_SET_EVBIT, ev)
for c in list(range(304, 319)) + [544, 545, 546, 547]:
    fcntl.ioctl(fd, UI_SET_KEYBIT, c)
for a in (0, 1, 16, 17):
    fcntl.ioctl(fd, UI_SET_ABSBIT, a)
name = b"GuliKit Controller XW (test)"
absmax = [0] * 64; absmin = [0] * 64
for a in (0, 1):
    absmin[a], absmax[a] = -32768, 32767
for a in (16, 17):
    absmin[a], absmax[a] = -1, 1
# struct uinput_user_dev: name[80], input_id(4xu16), ff_effects_max(u32), absmax/min/fuzz/flat[64] i32
dev = struct.pack("80sHHHHI", name, 3, 0x045E, 0x02E0, 1, 0)
dev += struct.pack("64i", *absmax) + struct.pack("64i", *absmin) + struct.pack("64i", *[0] * 64) + struct.pack("64i", *[0] * 64)
os.write(fd, dev)
fcntl.ioctl(fd, UI_DEV_CREATE)


def ev(t, c, v):
    os.write(fd, struct.pack("llHHi", 0, 0, t, c, v))


def key(c, v):
    ev(EV_KEY, c, v)
    ev(EV_SYN, 0, 0)


try:
    for step in " ".join(sys.argv[1:]).split():
        kind, *args = step.split(":")
        if kind == "wait":
            time.sleep(float(args[0]))
        elif kind == "tap":
            key(CODES[args[0]], 1); time.sleep(0.08); key(CODES[args[0]], 0)
        elif kind == "hold":
            key(CODES[args[0]], 1); time.sleep(float(args[1])); key(CODES[args[0]], 0)
        print("ok", step, flush=True)
finally:
    fcntl.ioctl(fd, UI_DEV_DESTROY)
    os.close(fd)
