"""Convierte los .raw de gen_lut_edge.c (uint16 N*N) a PNG RGBA8: R=hi, G=lo, B=0, A=255.
Sin numpy. N=2048, RHO_MAX=12, R_OUTER=10, THETA0=acos(0.06)."""
from PIL import Image
import struct
N = 2048
for k in ("o0_r", "o0_az", "o1_r", "o1_az"):
    raw = open(f"lut_edge_{k}.raw", "rb").read()
    v = struct.unpack(f"<{N*N}H", raw)
    buf = bytearray(N*N*4)
    buf[0::4] = bytes(x >> 8 for x in v)
    buf[1::4] = bytes(x & 255 for x in v)
    buf[3::4] = b"\xff" * (N*N)
    Image.frombytes("RGBA", (N, N), bytes(buf)).save(f"lut_edge_{k}.png")
    print(k, sum(1 for x in v if x))
