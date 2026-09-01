---
tipo: tarea
estado: pendiente
prioridad: 3
area: hardware
origen: Alberto
esfuerzo: L
creado: 2026-08-29
tags:
  - backlog
---

Hoy el porcentaje es un valor estático; descifrar el Feature Report de batería real por USB / 2.4G. Ver [[Roadmap Maestro de Innovaciones]] §6 y `hardware/akko-5075b-plus/`.

**Progreso 2026-09-01 (rama `fix/akko-kb-transport-and-battery`):**
- **Por cable el firmware NO expone porcentaje** — `0x83` devuelve `byte[bat] = 0x00` mientras carga (única situación por cable). Callejón sin salida salvo que un sniff en Windows encuentre otro opcode. El widget ya no inventa un número: muestra solo `⚡ Cargando · Cable USB`.
- **Por 2.4 GHz** sigue siendo un EMA suavizado del `0x83` por RF (frames rancios del dongle); es lo mejor disponible sin forzar un frame fresco.
- **Por Bluetooth** sí hay lectura real (UPower/GATT).
- Eliminado el valor estático/inventado (era `cache.get("akko_battery", 100)`). Ver [[Base de Datos de Errores]] §2026-09-01.

Queda pendiente lo "L": una lectura 2.4 GHz fiable sin EMA (requiere sniff Windows del handshake que fuerza frame fresco) y/o el opcode VBUS por cable.
