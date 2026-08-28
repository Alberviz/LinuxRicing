# ⌨️ Teclado Akko 5075B Plus

Teclado mecánico 75 % multi-modo (cable / 2.4 GHz / Bluetooth) con retroiluminación
RGB por tecla **y** una tira LED lateral independiente ("side-strip" / SLED).

- **Controlador / firmware:** ROYUAN B-series USB HID (mismo OEM que MonsGeek,
  Epomaker, Yunzii, Attack Shark…).
- **Interfaz de control:** Interface 2 (`MI_02` en Windows, symlink `:1.2` en Linux).
  Las otras dos interfaces son teclas normales (`:1.0`) y multimedia (`:1.1`).
- **Tipo de reporte:** Feature Report de 65 bytes (`Report ID 0x00` + 64 de payload).

## Identificadores

| Modo | VID | PID | Qué se conecta al puerto |
|---|---|---|---|
| Cable USB directo | `0x3151` | `0x4015` | la placa del teclado |
| Inalámbrico 2.4 GHz | `0x3151` | `0x4011` | el dongle transceptor de radio |
| Bluetooth | — | — | (no ingenierizado; el RGB por BT no se usa en el rice) |

## Estado

| Capacidad | Estado | Detalle |
|---|---|---|
| Color sólido en teclas (`0x07`) | ✅ | Cable y 2.4 GHz. Ver [`PROTOCOL.md` §A](PROTOCOL.md). |
| Color sólido en tira lateral (`0x08`) | ✅ | Idéntico a `0x07`. |
| Telemetría de batería (`0x83`) | ✅ | Nivel + estado de carga. [`PROTOCOL.md` §B](PROTOCOL.md). |
| Estado de la palanca Win/Mac, WinLock (`0x86`) | ✅ | [`PROTOCOL.md` §E](PROTOCOL.md). |
| Per-key / lienzo (`0x07` modo `0x0D` + `0x0C`) | 🚧 | Funciona, pero **solo como estado estático**. Per-key animado por 2.4 GHz **no es viable** (satura la radio). Ver [`USB_FINDINGS_2.4G.md`](USB_FINDINGS_2.4G.md). |
| Reglas de iluminación reactivas a batería | ✅ | Daemon `rgb/battery-lighting` + perfil `~/.config/caelestia/battery-lighting.json`. Frontend: [`BATTERY_LIGHTING_FRONTEND.md`](BATTERY_LIGHTING_FRONTEND.md). |

## Cómo se usa en el rice

- `rgb/akko-rgb` — CLI de un disparo para fijar color.
- `rgb/sync-rgb.py` (Linux) / `rgb/sync-rgb-windows.py` (Windows) — aplican el color
  Material You del wallpaper a las dos zonas cuando cambia el tema de Caelestia.
- `rgb/battery-lighting` — daemon que cambia la iluminación según la batería
  (cargando → flujo con gradiente; batería baja → rojo).
- `rgb/rgb-notify-flash` — parpadeo de notificación.

## Historia

El protocolo del modo cable salió del controlador ROYUAN B-series y de capturas
`hidraw` en Linux. El **modo 2.4 GHz** costó una sesión entera: el driver de Windows
(`iot_driver_v200.exe`) habla con el dongle por un puente gRPC en `127.0.0.1:3814`,
y durante mucho tiempo se creyó que hacía falta un "commit `0x88`" y un bloqueo del
bucle RF. Las capturas USBPcap del 2026-08-27/28
([`captures/`](captures/)) demostraron que **el dongle acepta exactamente el mismo
paquete que el modo cable** como `SET_REPORT` a la interfaz 2 — sin handshake, sin
`0x88`. El bug real era un `device_path` del dongle hardcodeado en
`sync-rgb-windows.py` (el sufijo `8&xxxxxxxx` es el instance ID de Windows y cambia
entre máquinas). Análisis completo: [`USB_FINDINGS_2.4G.md`](USB_FINDINGS_2.4G.md).

Diario y contexto de comunidad (HID-BPF, `akko-bpf-battery`): vault →
`01 - Linux/RGB/Protocolo USB HID Akko 5075B Plus.md`.
