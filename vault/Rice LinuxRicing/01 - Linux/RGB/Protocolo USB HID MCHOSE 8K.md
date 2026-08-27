---
tags: [rice, rgb, usb, protocolo, hardware]
actualizado: 2026-08-27
---

# Protocolo USB HID · MCHOSE 8K Base

Documentación exhaustiva del protocolo de ingeniería inversa obtenido mediante capturas de tráfico USB (`tshark` + `usbmon`) con el receptor / base 8K MCHOSE (**VID: `0x3837`, PID: `0x1001`**).

```mermaid
graph TD
    Host[PC Linux / Caelestia] -->|SET_REPORT 0x11 XOR 0xFF| Node[/dev/hidraw7 :1.2]
    Node --> Target6[Target 0x06: Color Fijo Estático]
    Node --> Target2[Target 0x02: Respiración Monocolor]
    Node --> Target1[Target 0x01: Modo Batería Firmware]
    Node --> Target7[Target 0x07: Ola Arcoíris ARGB Hardware]
```

---

## 1. Transporte y Endpoint

- **Interfaz:** `:1.2` (nodo `/dev/hidraw7` o detectado dinámicamente en `/sys/class/hidraw/`).
- **Tipo de Reporte:** Feature Report (`SET_REPORT`) con Report ID `0x11` (longitud total: 21 bytes).
- **Ofuscación:** Todos los bytes de payload (`byte[1..20]`) van invertidos a nivel de bit con **`XOR 0xFF`** (`byte ^ 0xFF`).

---

## 2. Estructura de 20 Bytes del Comando `0x2B`

```text
Byte 00: 0x2B           (Opcode de Iluminación)
Byte 01: 0x01           (Constante / Subcomando)
Byte 02: TARGET_ID      (0x06 = Fijo, 0x02 = Breathing, 0x01 = Batería, 0x07 = Wave)
Byte 03: 0x00           (Reservado)
Byte 04: BRIGHTNESS     (Brillo 0 a 100)
Byte 05: SPEED          (Velocidad de animación 0 a 4)
Byte 06: MODE_ID        (0x01 = Activo)
Byte 07: COLOR_MODE     (0x01 = Color personalizado, 0x00 = Auto)
Byte 08: 0x00           (Dirección / Reservado)
Byte 09: R1             (Rojo Anillo LED: 0-255)
Byte 10: G1             (Verde Anillo LED: 0-255)
Byte 11: B1             (Azul Anillo LED: 0-255)
Byte 12: R2             (Rojo duplicado / relleno: 0-255)
Byte 13: G2             (Verde duplicado / relleno: 0-255)
Byte 14: B2             (Azul duplicado / relleno: 0-255)
Byte 15..19: 0x00       (Padding de ceros)
```

---

## 3. Mapa de Target IDs Confirmados en Hardware

| Target ID | Efecto en la Base | Comportamiento en Linux |
|---|---|---|
| **`0x06`** | **Color Fijo Constante (*Static Solid*)** | Sincronizado en tiempo real con **Material You** (`scheme.json`). Cero parpadeo. |
| **`0x02`** | **Respiración Monocolor (*Breathing*)** | Respiración suave continua con el color `R1,G1,B1` en el anillo. |
| **`0x01`** | **Modo Batería Oficial (*Hardware Battery*)** | Algoritmo nativo de fábrica del firmware (respiración verde/ámbar/rojo). |
| **`0x07`** | **Ola Arcoíris ARGB (*Full Moving Wave*)** | Algoritmo autónomo de ola multicolor giratoria en el anillo. |

---

## 4. Automatizaciones y Comandos

### Herramientas del Sistema:
- **`mchose-lighting <static|breathing|wave|battery|off> [#hex]`**: Aplicación manual inmediata.
- **`mchose-config <charge|lowbat|threshold>`**: Selector interactivo de efectos.
- **`mchose-pcap-analyzer <archivo.pcapng>`**: Decodificador automático de trazas USB con desglose de campos.

### Disparadores Automáticos:
1. **Al Acoplar el Ratón a la Base (Carga):** Activa el efecto configurado (`theme_breathing`, `battery_breathing`, `hardware_battery` o `wave`).
2. **Al Desacoplar el Ratón (Uso normal):** Restaura el color estático del wallpaper (`Target 0x06`).
3. **Batería Baja (`<= 20%`):** Si está fuera de la base, activa la alerta visual seleccionada (`red_breathing`, `wave`, `red_static` o `none`).
