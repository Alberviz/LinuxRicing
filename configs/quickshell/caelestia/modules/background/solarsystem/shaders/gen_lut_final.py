"""
Genera las dos texturas LUT de producción (lens_lut_order0.png / order1.png,
RGBA8) con la geodésica real de Schwarzschild para el agujero negro de
solarfield.frag. Regenerar tras cualquier cambio de bhTilt/FLAT (inclinación)
o de rHorizon/rISCO/rOuter — están hardcodeadas en la cabecera de blackHole().

Una textura por orden de imagen (0=directa, 1=envolvente). Codificación
(sentinel EXACTO r=0.0 = "sin cruce en este píxel para este orden"):
  R = radio real del disco en el cruce, normalizado [0,1] sobre [rHorizon,rOuter]
  G,B = azimut del cruce en 16 bits (hi,lo) — 8 bits solos se ven como
        "escalones" tras la cizalla ~15x de sampleDisk() (ver commit de esta
        sesión: primero se generó con azimut de 8 bits, se veía aliasing)
  A = SIEMPRE 255 — Qt aplica alfa premultiplicado al subir la imagen como
      textura; con A=0 en todo el PNG, R/G/B llegan a la GPU puestos a cero
      pese a tener datos válidos en disco (bug real de esta sesión, costó un
      diagnóstico completo con debug shader antes de encontrarlo)

Dominio: (pr.x/R, pr.y/R) en [-RHO_MAX, RHO_MAX]^2, la MISMA convención que
el shader ya usa (pr.y = eje menor/comprimido, pr.x = eje mayor/ecuatorial).
xi = atan2(pr.x, pr.y) (xi=0 a lo largo de +pr.y).

Física validada en geodesic_lut.py (límite de campo débil, esfera de fotones)
y visualmente contra Interstellar/Luminet 1979 (sombra real = 3*sqrt(3)*M).
Cachea el resultado crudo (sin cuantizar) en lut_raw_cache.npz — permite
tocar SOLO la codificación (p.ej. subir de 8 a 16 bits) sin repetir la
integración completa (~10-15 min a 896x896).
"""
import numpy as np
from PIL import Image

M = 0.5
THETA0 = np.arccos(0.20)
B_CRIT = 1.5*np.sqrt(3)
R_HORIZON, R_ISCO, R_OUTER = 1.0, 1.18, 3.60

N = 896
RHO_MAX = 5.6
xs = np.linspace(-RHO_MAX, RHO_MAX, N)
ys = np.linspace(-RHO_MAX, RHO_MAX, N)
PRX, PRY = np.meshgrid(xs, ys)

RHO = np.sqrt(PRX**2 + PRY**2)
XI = np.arctan2(PRX, PRY)

A = np.cos(THETA0)
Bc = np.cos(XI) * np.sin(THETA0)
phi0 = np.arctan2(-A, Bc)
phi0 = np.where(phi0 <= 1e-9, phi0 + np.pi, phi0)
PHI_TARGETS = [phi0, phi0 + np.pi]

def disk_xy_angle(phi, xi):
    cphi, sphi = np.cos(phi), np.sin(phi)
    cxi, sxi = np.cos(xi), np.sin(xi)
    s0, c0 = np.sin(THETA0), np.cos(THETA0)
    pos_x = cphi*s0 + sphi*(-cxi*c0)
    pos_y = sphi*(-sxi)
    return np.arctan2(pos_y, pos_x)

b = np.maximum(RHO, 1e-6)
u = np.zeros_like(b)
up = 1.0/b
phi = np.zeros_like(b)
dphi = 0.0008
phi_max = 3.4*np.pi
n_steps = int(phi_max/dphi)

started = np.zeros_like(b, dtype=bool)
horizon = np.zeros_like(b, dtype=bool)
escaped = np.zeros_like(b, dtype=bool)

r_result = [np.full_like(b, np.nan), np.full_like(b, np.nan)]
th_result = [np.full_like(b, np.nan), np.full_like(b, np.nan)]
recorded = [np.zeros_like(b, dtype=bool), np.zeros_like(b, dtype=bool)]

def f(u, up):
    return -u + 3.0*M*u*u

prev_u, prev_phi = u.copy(), phi.copy()
print(f"Integrando {N}x{N}={N*N} rayos, {n_steps} pasos...")

for step in range(n_steps):
    active = ~(horizon | escaped)
    if not np.any(active):
        print(f"todos resueltos en step {step}")
        break
    started |= (u > 1e-6) & active
    horizon |= active & (u >= 1.0)
    escaped |= active & started & (u <= 0.0) & (up < 0.0)
    active = ~(horizon | escaped)

    for order in range(2):
        target = PHI_TARGETS[order]
        just_crossed = active & (~recorded[order]) & (phi >= target) & (prev_phi < target)
        if np.any(just_crossed):
            denom = np.where(phi > prev_phi, phi - prev_phi, 1.0)
            t = (target - prev_phi) / denom
            u_at = prev_u + t*(u - prev_u)
            r_at = np.where(u_at > 1e-9, 1.0/np.maximum(u_at, 1e-9), np.nan)
            th_at = disk_xy_angle(target, XI)
            r_result[order] = np.where(just_crossed, r_at, r_result[order])
            th_result[order] = np.where(just_crossed, th_at, th_result[order])
            recorded[order] = recorded[order] | just_crossed

    prev_u, prev_phi = u.copy(), phi.copy()
    k1u, k1up = up, f(u, up)
    k2u, k2up = up + 0.5*dphi*k1up, f(u + 0.5*dphi*k1u, up + 0.5*dphi*k1up)
    k3u, k3up = up + 0.5*dphi*k2up, f(u + 0.5*dphi*k2u, up + 0.5*dphi*k2up)
    k4u, k4up = up + dphi*k3up, f(u + dphi*k3u, up + dphi*k3up)
    u_new = u + (dphi/6.0)*(k1u + 2*k2u + 2*k3u + k4u)
    up_new = up + (dphi/6.0)*(k1up + 2*k2up + 2*k3up + k4up)
    u = np.where(active, u_new, u)
    up = np.where(active, up_new, up)
    phi = np.where(active, phi + dphi, phi)

    if step % 800 == 0:
        print(f"  step {step}/{n_steps}  activos={active.sum()}")

print("Integración terminada.")

# cache de los resultados crudos (sin cuantizar) — permite re-codificar la
# textura (p.ej. cambiar de 8 a 16 bits) sin repetir la integración completa.
np.savez("lut_raw_cache.npz",
         r0=r_result[0], th0=th_result[0], rec0=recorded[0],
         r1=r_result[1], th1=th_result[1], rec1=recorded[1],
         N=N, RHO_MAX=RHO_MAX, R_HORIZON=R_HORIZON, R_ISCO=R_ISCO, R_OUTER=R_OUTER)
print("cache crudo guardado en lut_raw_cache.npz")

# ---------------------------------------------------------------- codificación
# El azimut se amplifica ~15x por la cizalla de sampleDisk() antes de entrar en
# el ruido de turbulencia — con solo 8 bits (256 niveles = ~1.4°/paso) eso se ve
# como un "escalonado" visible tras la amplificación. Se codifica en 16 bits
# (hi+lo en dos canales de 8 bits) para que ese escalón sea invisible.
# Textura A (orden 0): R=radio(8b) G=azimut_hi(8b) B=azimut_lo(8b) A=255 fijo
# Textura B (orden 1): igual pero para el orden 1
def encode_order(r, th, valid):
    r_norm = np.clip((r - R_HORIZON) / (R_OUTER - R_HORIZON), 1.0/255.0, 1.0)
    th_norm = np.clip((th + np.pi) / (2*np.pi), 0.0, 1.0)
    r_ch = np.where(valid, r_norm, 0.0)
    th16 = np.where(valid, np.round(th_norm * 65535.0), 0).astype(np.uint32)
    th_hi = (th16 >> 8) & 0xFF
    th_lo = th16 & 0xFF
    r8 = np.clip(np.round(r_ch * 255.0), 0, 255).astype(np.uint8)
    return r8, th_hi.astype(np.uint8), th_lo.astype(np.uint8)

for order, name in [(0, "lens_lut_order0.png"), (1, "lens_lut_order1.png")]:
    r = r_result[order]
    th = th_result[order]
    valid = recorded[order] & (r >= R_ISCO*0.98) & (r <= R_OUTER)
    r8, th_hi, th_lo = encode_order(r, th, valid)
    # Alfa SIEMPRE 255 (opaco): Qt aplica alfa premultiplicado al subir la
    # imagen como textura — con alfa=0 en todo el PNG, R/G/B se ponen a cero
    # al llegar a la GPU sea cual sea su valor real (así se detectó el bug:
    # los canales de datos leían 0.0 en todo el shader pese a tener datos
    # válidos en el PNG en disco).
    alpha = np.full_like(r8, 255)
    rgba8 = np.stack([r8, th_hi, th_lo, alpha], axis=-1)
    out_path = f"{name}"
    Image.fromarray(rgba8, mode="RGBA").save(out_path)
    print(f"guardado {out_path}  validos={valid.sum()}/{N*N} ({100*valid.sum()/(N*N):.1f}%)")

print(f"({N}x{N}, RHO_MAX={RHO_MAX})")

# metadatos para el shader (constantes a incrustar)
print(f"RHO_MAX={RHO_MAX}  R_HORIZON={R_HORIZON}  R_ISCO={R_ISCO}  R_OUTER={R_OUTER}  B_CRIT={B_CRIT:.6f}")
