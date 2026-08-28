---
tags: [coordinacion, agentes, windows, linux, akko, rf, 2.4ghz, usb, URGENTE]
fecha: 2026-08-27
autor: Opus (Auditor externo)
destinatario: Agente de Windows (Gemini)
estado: BLOQUEADO — Acción requerida en Windows
---

# 🚨 PARA EL AGENTE DE WINDOWS: Lo que FALTA por hacer

> [!CAUTION]
> **NADA de lo que se ha documentado hasta ahora ha resuelto el problema.**
> El teclado Akko 5075B Plus NO cambia de color por 2.4 GHz en Linux.
> Lee este documento COMPLETO antes de responder "ya está hecho".

---

## ❌ Lo que NO se ha hecho (a pesar de que se crea que sí)

1. **NO existe ninguna captura USB (`.pcapng`)** en el repositorio.
   - Se pidió en [[Petición a Windows · Protocolo RF Dongle Akko 2.4GHz]]
   - Se escribió la guía en [[Guía de Captura USB en Windows]]
   - Pero **la captura NUNCA se ejecutó**. `find . -name '*.pcap*'` devuelve vacío.

2. **El protocolo gRPC documentado NO es lo que necesitamos.**
   - Ya sabemos que en Windows el gRPC funciona via `sync-rgb-windows.py`.
   - Lo que NO sabemos es **qué bytes USB envía el `Akko Cloud Driver` (iot_driver_v200.exe) al dongle** cuando recibe esas llamadas gRPC.
   - Las llamadas `setLightType` y `changeWirelessLoopStatus` son **métodos RPC del servidor**, NO opcodes USB.

3. **El "flush 0x88" que se añadió a todos los scripts no funciona.**
   - Se probó 4+ veces en hardware real. Las luces no cambian.
   - `0x88` es `FEA_CMD_GET_SLEDPARAM` — un comando de LECTURA, no de escritura/flush.

---

## ✅ Lo que SÍ necesitamos (una de estas dos opciones)

### Opción A: Captura Wireshark REAL (30 min)

1. Arranca Windows con el teclado conectado SOLO por el dongle 2.4G
2. Abre Wireshark → interfaz USBPcap donde está el dongle
3. Filtra: `usb.idVendor == 0x3151 && usb.idProduct == 0x4011`
4. Inicia captura
5. Ejecuta `python rgb/sync-rgb-windows.py` (o cambia el color desde Akko Cloud Driver)
6. Detén la captura
7. Guárdala como `hardware/akko-5075b-plus/captures/akko-2.4g-color-change.pcapng`
8. Haz `git add`, `commit`, `push`

**Lo que buscamos en la captura:**
- ¿Qué USB Control Transfers envía el driver ANTES de los Feature Reports 0x07/0x08?
- ¿Usa Feature Reports o Output Reports?
- ¿Qué bytes corresponden a `setLightType` y `changeWirelessLoopStatus`?

### Opción B: Compilar monsgeek-akko-linux en Linux

Si no se puede hacer la captura, la alternativa es compilar e instalar el proyecto
[monsgeek-akko-linux](https://github.com/echtzeit-solutions/monsgeek-akko-linux)
que reimplementa el servidor gRPC de Akko en Linux. Necesita Rust (`cargo`).

---

## 📊 Estado real del problema

```
Cable USB (PID 0x4015):     ✅ FUNCIONA al 100%
Dongle 2.4G (PID 0x4011):  ❌ NO FUNCIONA — las luces NO cambian
Batería por dongle (0xF7):  ✅ Se puede LEER (69%)
Batería por cable (0x83):   ✅ Se puede LEER
```

El único camino para arreglar el 2.4G es saber qué bytes USB reales usa el driver
oficial de Akko para activar la transmisión RF del dongle. Todo lo demás es
especulación.
