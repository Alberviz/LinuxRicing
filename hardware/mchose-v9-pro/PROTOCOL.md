# MCHOSE V9 Pro — protocolo de telemetría de batería

Fuente: capturas del dongle 2.4 GHz + implementación en `rgb/mchose-battery`
(`get_v9_pro_battery`) y `rgb/mchose-battery-windows.py`.

## Transporte (modo 2.4 GHz, `291D:385D`)

- Report HID de 64 bytes, **sin `XOR`**.
- Windows: Interface 0, `UsagePage 0xFFA0`.
- Linux: primer nodo `/dev/hidraw*` que matchee VID/PID; escritura con `os.write`,
  lectura con `select` + `os.read` (no es Feature report, es I/O directo).

## Consulta

```
solicitud (64 bytes):  55 65 01 00 00 ... 00
respuesta (>= 4 bytes): 55 65 <nivel> <estado>
```

- `byte[0..1]` = `0x55 0x65` — cabecera de confirmación (validar antes de usar).
- `byte[2]` = **nivel de batería** `0..100`.
- `byte[3]` = **estado**:
  - `0x00` o `0x03` → cargando
  - `0x02` → descargando / en uso inalámbrico
  - (otros) → tratado como descargando

## Bluetooth

🚧 **Pendiente.** Alberto hizo sniffing del canal Bluetooth pero el volcado no está
en el repo todavía. Ver el TODO en [`README.md`](README.md).
