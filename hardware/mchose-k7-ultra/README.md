# 🐭 Ratón MCHOSE K7 Ultra + Base / Dongle 8K

Ratón inalámbrico ligero con base de carga 8000 Hz. La base lleva un **anillo LED**
(tira direccionable por firmware) y es también el receptor RF.

- **Controlador:** RealTek SoC HID, Interface 2 (`UsagePage 0xFF01` / `Col02`).
- **Tipo de reporte:** Feature Report de 21 bytes (`Report ID 0x11` + 20 de payload);
  además Input Reports `0x13` en modo cable.
- **Ofuscación:** todo el payload (`byte[1..20]`) va invertido con **`XOR 0xFF`**.

## Identificadores

| Modo | VID | PID | Notas |
|---|---|---|---|
| Inalámbrico (Base 8K / dongle) | `0x3837` | `0x1001` | telemetría en pulsos RF cada **3.65 s** sin desconectar |
| Cable USB directo | `0x3837` | `0x4150` | respuesta instantánea, reportes push `0x13` |

## Estado

| Capacidad | Estado | Detalle |
|---|---|---|
| Anillo LED de la base — color sólido | ✅ | cmd `0x2B`, target `0x06`. [`PROTOCOL.md`](PROTOCOL.md). |
| Anillo LED — breathing / wave / modo batería firmware | ✅ | targets `0x02` / `0x07` / `0x01`. |
| Telemetría de batería del ratón | ✅ | cmd `0x06`, `dec[11]` nivel, `dec[12]` carga. |
| RGB per-LED del anillo desde el PC | ❌ | El firmware quema el efecto de ola en ROM para no saturar el MCU con el sondeo 8K. Ningún proyecto open source lo tiene para dongles 8K sin cambiar el firmware. |

## Cómo se usa en el rice

- `rgb/mchose-lighting <static|breathing|wave|battery|off> [#hex]` — aplicación manual.
- `rgb/mchose-battery` — telemetría (comparte binario con `widgets/mchose-battery`).
- `rgb/sync-rgb.py` — pinta el anillo con el color Material You (target `0x06`).
- `rgb/battery-lighting` — al acoplar a la base cambia el efecto; batería baja → alerta.
- `rgb/mchose-pcap-analyzer.py` — decodifica capturas (des-ofusca `XOR 0xFF`).

## Historia

Protocolo obtenido con `tshark` + `usbmon` sobre `/dev/hidraw*` de la base. La clave
fue descubrir la ofuscación `XOR 0xFF` de todo el payload y que la interfaz de
control es la `:1.2` (`Col02`). El "misterio del ARGB" (por qué no se puede pintar
LED a LED) está explicado en el vault →
`00 - Arquitectura/Estado del Arte e Ingeniería Inversa en la Comunidad.md` §2.
Diario: vault → `01 - Linux/RGB/Protocolo USB HID MCHOSE 8K.md`.
