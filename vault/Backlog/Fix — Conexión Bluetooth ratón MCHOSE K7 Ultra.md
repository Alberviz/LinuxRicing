---
tipo: fix
estado: pendiente
prioridad: alta
componentes:
  - bluetooth
  - hardware
  - hyprland
creado: 2026-09-02
---

# 🖱️ Fix — Conexión Bluetooth ratón MCHOSE K7 Ultra

Ver la investigación y diagnóstico completo en [[Diagnóstico y Handoff Bluetooth - MCHOSE K7 Ultra]].

## Resumen
El ratón MCHOSE K7 Ultra negocia GATT pero el firmware aborta el enlace tras 2-3 segundos, regenerando su dirección MAC aleatoria antes de fijar las claves de cifrado.
