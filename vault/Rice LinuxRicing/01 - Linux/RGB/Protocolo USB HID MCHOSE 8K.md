---
tags: [rice, rgb, usb, protocolo, hardware, mchose]
actualizado: 2026-08-29
---

# Protocolo USB HID · MCHOSE 8K Base

Documentación histórica, notas de diseño y diario de integración de la base de carga y receptor 8K del ratón MCHOSE K7 Ultra (**VID: `0x3837`, PID: `0x1001`** inalámbrico / **`PID 0x4150`** cable).

> [!NOTE]
> **Especificación Canónica:** Para la especificación de bytes, ofuscación XOR, opcodes y estructura exacta de paquetes, consultar [`hardware/mchose-k7-ultra/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-k7-ultra/PROTOCOL.md) y [`hardware/mchose-k7-ultra/README.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-k7-ultra/README.md).

```mermaid
graph TD
    Host[PC Linux / Caelestia] -->|SET_REPORT 0x11 XOR 0xFF| Node[/dev/hidrawX :1.2]
    Node --> Target6[Target 0x06: Color Fijo Estático]
    Node --> Target2[Target 0x02: Respiración Monocolor]
    Node --> Target1[Target 0x01: Modo Batería Firmware]
    Node --> Target7[Target 0x07: Ola Arcoíris ARGB Hardware]
```

---

## 1. Contexto de Arquitectura y Limitaciones de Hardware

### ¿Por qué no hay control ARGB direccionable por LED individual?
Durante la ingeniería inversa inicial se buscaba direccionar cada uno de los LEDs del anillo exterior individualmente. Sin embargo, las capturas de tráfico USB y pruebas de firmware revelaron:
- La base **no expone un frame-buffer per-LED** direccionable vía USB.
- Las animaciones multicolor como el efecto *Wave* (`Target 0x07`) son algoritmos precodificados que corren autónomamente dentro de la ROM del microcontrolador.
- Para integración con el tema dinámico del sistema (**Material You** / `scheme.json`), se utiliza el modo estático sólido (`Target 0x06`) sincronizado en tiempo real, o modos reactivos de respiración monocolor (`Target 0x02`).

---

## 2. Targets de Iluminación Confirmados en Hardware

| Target ID | Efecto en la Base | Integración en el Rice |
|---|---|---|
| **`0x06`** | **Color Fijo Constante (*Static Solid*)** | Sincronizado en tiempo real con **Material You** (`scheme.json`). Cero parpadeo. |
| **`0x02`** | **Respiración Monocolor (*Breathing*)** | Respiración suave continua con el color `R,G,B` en el anillo. |
| **`0x01`** | **Modo Batería Oficial (*Hardware Battery*)** | Algoritmo nativo de fábrica del firmware (respiración verde/ámbar/rojo). |
| **`0x07`** | **Ola Arcoíris ARGB (*Full Moving Wave*)** | Algoritmo autónomo de ola multicolor giratoria en el anillo. |

---

## 3. Automatizaciones y Comandos

### Herramientas del Sistema:
- **`mchose-lighting <static|breathing|wave|battery|off> [#hex]`**: Aplicación manual inmediata.
- **`mchose-config <charge|lowbat|threshold>`**: Selector interactivo de efectos.
- **`mchose-pcap-analyzer <archivo.pcapng>`**: Decodificador automático de trazas USB con desglose de campos.

### Disparadores Automáticos:
1. **Al Acoplar el Ratón a la Base (Carga):** Activa el efecto configurado (`theme_breathing`, `battery_breathing`, `hardware_battery` o `wave`).
2. **Al Desacoplar el Ratón (Uso normal):** Restaura el color estático del wallpaper (`Target 0x06`).
3. **Batería Baja (`<= 20%`):** Si está fuera de la base, activa la alerta visual seleccionada (`red_breathing`, `wave`, `red_static` o `none`).

---

## 4. Telemetría de Batería y Conexión

- **Receptor / Base 8K (`PID 0x1001`):** Emite telemetría por pulsos de radiofrecuencia periódicos cada **`3.65 segundos`**. La lectura por script reintenta varias veces para sincronizar con este pulso.
- **Cable USB Directo (`PID 0x4150`):** Conexión permanente con respuesta instantánea.

---

## 📚 5. Especificación Canónica

Para el desglose de los 20 bytes del comando `0x2B`, solicitud de telemetría `0x06` y funciones de ofuscación `XOR 0xFF`, consultar:
- [`hardware/mchose-k7-ultra/PROTOCOL.md`](file:///C:/Users/Alberviz/LinuxRicing/hardware/mchose-k7-ultra/PROTOCOL.md)
