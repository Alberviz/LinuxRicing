# Migración del conocimiento de hardware a `hardware/` — nota para Gemini

**Rama:** `feat/repo-reorg-hardware-kb` (Claude, 2026-08-29).

## Qué cambió

El conocimiento de ingeniería inversa estaba repartido en tres sitios. Ahora la
**fuente canónica** es `hardware/<dispositivo>/`:

- `hardware/README.md` — índice + matriz de estado.
- `hardware/akko-5075b-plus/` — `README.md`, `PROTOCOL.md`, `USB_FINDINGS_2.4G.md`,
  `BATTERY_LIGHTING_FRONTEND.md`, `captures/*.pcapng` (movido de `docs/pcap/`).
- `hardware/mchose-k7-ultra/` — `README.md`, `PROTOCOL.md`.
- `hardware/mchose-v9-pro/` — `README.md`, `PROTOCOL.md` (antes **solo** existía como
  comentario en `rgb/mchose-battery`).
- `hardware/magic-home-strip/`, `hardware/asus-tuf-b560m/` — `README.md`.

`docs/HARDWARE_PROTOCOLS.md` es ahora un stub de redirección. `docs/` se queda con
runbooks, traspasos (`docs/ARCHIVE/`) y planes.

## Lo que pido a Gemini (área `vault/`)

El vault y `hardware/` **duplican** opcodes/payloads y en algún punto se **contradicen**.
Convertir las notas del vault en narrativa + enlaces a `hardware/`, sin spec duplicada:

| Nota del vault | Acción |
|---|---|
| `01 - Linux/RGB/Protocolo USB HID Akko 5075B Plus.md` | ⚠️ **Desactualizada**: aún dice que el "commit `0x88`" es obligatorio para 2.4 GHz. Las capturas USB lo **refutaron** (`hardware/akko-5075b-plus/USB_FINDINGS_2.4G.md`). Reducir a: contexto + errores típicos + enlace a `hardware/akko-5075b-plus/PROTOCOL.md`. |
| `01 - Linux/RGB/Protocolo USB HID MCHOSE 8K.md` | Dejar la parte de "por qué no hay ARGB per-LED" y el diario; mover la tabla de bytes a un enlace a `hardware/mchose-k7-ultra/PROTOCOL.md`. |
| `01 - Linux/RGB/Iluminación - Estado actual.md` | Actualizar la fila del V9 Pro para apuntar a `hardware/mchose-v9-pro/`. |
| `02 - Windows/RGB y Hardware/Windows - Estado del Hardware, Luces y Batería.md` | Quitar el "commit `0x88`" de la fila del Akko; enlazar a `hardware/`. |
| `00 - Arquitectura/Tareas de Agentes/*` que citan `docs/HARDWARE_PROTOCOLS.md §X` | Reapuntar a `hardware/<dispositivo>/PROTOCOL.md`. |

## Pendiente de datos (Alberto)

`hardware/mchose-v9-pro/` tiene un TODO: el sniff de batería por **Bluetooth** del V9
Pro se hizo pero no está en el repo. Cuando aparezca, va a
`hardware/mchose-v9-pro/PROTOCOL.md` §Bluetooth.
