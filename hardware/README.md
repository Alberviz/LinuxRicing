# 🔬 Base de conocimiento de hardware

Ingeniería inversa de cada periférico y componente del setup: identificadores USB,
protocolos decodificados, qué se ha conseguido y qué no, y qué script del repo lo
maneja. Esta carpeta es la **fuente canónica** de la parte técnica; el vault de
Obsidian (`vault/`) guarda la narrativa y el diario de cómo se llegó a cada cosa y
enlaza aquí.

## Dispositivos

| Dispositivo | IDs (VID:PID) | Lo maneja | Iluminación | Batería | Ficha |
|---|---|---|---|---|---|
| **Teclado Akko 5075B Plus** | `3151:4015` cable · `3151:4011` 2.4 GHz | `rgb/akko-rgb`, `rgb/sync-rgb.py`, `rgb/battery-lighting` | ✅ teclas + tira lateral (sólido); 🚧 per-key solo estático | ✅ opcode `0x83` | [akko-5075b-plus/](akko-5075b-plus/) |
| **Ratón MCHOSE K7 Ultra + Base 8K** | `3837:1001` base/2.4 GHz · `3837:4150` cable | `rgb/mchose-lighting`, `rgb/mchose-battery`, `rgb/sync-rgb.py` | ✅ anillo LED de la base (cmd `0x2B`) | ✅ cmd `0x06` | [mchose-k7-ultra/](mchose-k7-ultra/) |
| **Auriculares MCHOSE V9 Pro** | `291D:385D` (dongle 2.4 GHz) | `rgb/mchose-battery`, `rgb/battery-lighting` | ❌ sin RGB direccionable | ✅ cmd `0x55 0x65` (2.4 GHz); 🚧 Bluetooth por documentar | [mchose-v9-pro/](mchose-v9-pro/) |
| **Placa ASUS TUF B560M-PLUS + RAM A-DATA** | OpenRGB SDK `localhost:6742` | `rgb/sync-rgb.py`, `rgb/argb-wave.py` | ✅ Aura + ARGB + ENE DRAM (modo Direct) | — | [asus-tuf-b560m/](asus-tuf-b560m/) |
| **Tira LED Magic Home Wi-Fi** | TCP `:5577` (`flux_led`) | `rgb/magichome-control`, `rgb/sync-rgb.py` | ✅ color sólido | — | [magic-home-strip/](magic-home-strip/) |

Leyenda: ✅ resuelto y verificado · 🚧 parcial / con límites · ❌ no viable.

## Cómo se hace ingeniería inversa aquí

- **Windows** — captura USB con **USBPcap** + Wireshark mientras corre el driver
  propietario. Procedimiento verificado y fallo conocido de USBPcap en esta build:
  [`../docs/WINDOWS_USB_CAPTURE_RUNBOOK.md`](../docs/WINDOWS_USB_CAPTURE_RUNBOOK.md).
  Las capturas `.pcapng` se guardan junto a la ficha del dispositivo
  (p. ej. [`akko-5075b-plus/captures/`](akko-5075b-plus/captures/)).
- **Linux** — `usbmon` / `tshark` sobre `/dev/hidraw*`, y comunicación directa por
  `ioctl(HIDIOCSFEATURE)` sin dependencias.
- **Análisis** — `rgb/mchose-pcap-analyzer.py` decodifica trazas USB y desglosa los
  campos de cada Feature Report (incluye des-ofuscación `XOR 0xFF` de MCHOSE).
- **Contexto de la comunidad** — cómo resuelve esto el mundo open source (OpenRGB,
  OpenRazer, HID-BPF, `akko-bpf-battery`): vault →
  `00 - Arquitectura/Estado del Arte e Ingeniería Inversa en la Comunidad.md`.

## Convención de cada ficha

- `README.md` — identidad, IDs por modo, tabla de estado, qué script lo usa, y la
  historia corta de cómo se sacó.
- `PROTOCOL.md` — la especificación decodificada (opcodes, payloads, checksums).
- `captures/` — los `.pcapng` y su índice, cuando los hay.
