---
tags: [rice, rgb, proyecto]
estado: diseño
actualizado: 2026-08-27
---

# Centro de Iluminación RGB

Proyecto para sustituir el desplegable actual de ajustes de la base MCHOSE (una tarjeta que se expande al clicar el ratón en el widget de periféricos) por **una ventana única** que controle la iluminación de **todos** los periféricos.

## Problema

- Los ajustes de luz están repartidos: tarjeta inline en `Background.qml`, widget de tira LED aparte, y varios CLIs ocultos (`mchose-config`, `mchose-lighting`, `sync-rgb.py`).
- El color de reposo **no se puede elegir**: siempre es el `primary` del tema. Poner un color fijo obliga a editar Python.
- No hay control por dispositivo ni efectos reactivos.

Detalle de cómo funciona hoy: [[Iluminación - Estado actual]].

## Decisiones (firmes)

1. **Forma:** panel superpuesto centrado en capa Wayland (patrón `AreaPicker`), fondo oscurecido, cierra al clicar fuera. **No** ventana flotante XDG.
2. **Alcance:** global — base MCHOSE (anillo + logo), teclado Akko (retro + tira lateral), placa/RAM/ventiladores (OpenRGB), tira MagicHome. Con **interruptor on/off por dispositivo**.
3. **Selector de color:** paleta de presets (colores del tema actual + fijos comunes) + campo hex editable. Sin rueda/Canvas.
4. **Reposo:** selector "seguir tema (Material You) / color fijo".
5. **Efectos de la base:** se mantienen "efecto al cargar" y "alerta de batería baja" + umbral (solo la base, es lo único con batería).
6. **v1 incluye** el motor de "efecto temporal → restaurar" y el **flash al recibir notificación** (rojo / acento / complementario del color actual). El resto de efectos reactivos van al [[Backlog - Efectos de iluminación|backlog]].

## Diseño de implementación

> Pendiente de consolidar con el plan detallado. Se rellenará aquí cuando esté aprobado.

Piezas previstas:

- **Módulo QML nuevo** `configs/quickshell/caelestia/modules/rgbcontrol/` con `IpcHandler` (`target: "rgb"`, `open()`), montado en `shell.qml`.
- **Config unificada** `~/.config/caelestia/rgb-config.json` (semilla en el repo). Relación con `mchose-config.json` por decidir (fusionar vs separado).
- **`sync-rgb.py`**: leer `rgb-config.json` (source theme/fixed, color fijo, toggles por dispositivo); aceptar color por argumento para previsualizar; retrocompatible sin config.
- **Motor de flash**: escucha `services/Notifs.qml`, calcula complementario (HSV hue+180), guarda y restaura estado, con debounce.
- **Retirar** la tarjeta inline de **las dos** copias de `Background.qml` (`configs/.../background/` y `widgets/`).
- **`install.sh`**: desplegar `mchose-config`, `mchose-lighting`, el flash y la config semilla.

## Riesgos

- Bus SMBus/I2C de las RAMs: nada de pulsos rápidos sobre OpenRGB. El flash probablemente solo toca base + teclado + tira.
- `Background.qml` duplicado: mantener las dos copias iguales.
- Divergencias de `target 0x06`/`0x07` ya existentes en el código.
- Keyboard focus exclusivo del overlay: no bloquear el resto del shell.

## Registro

- **2026-08-27** — Brainstorming inicial. Decisiones 1-6 tomadas con Alberto. Creada esta bóveda y el [[Backlog - Efectos de iluminación|backlog]].
