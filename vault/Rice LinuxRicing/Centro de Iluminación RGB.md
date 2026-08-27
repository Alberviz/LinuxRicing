---
tags: [rice, rgb, proyecto]
estado: en-implementación (fases 0-3 hechas; faltan 4-5)
actualizado: 2026-08-27
---

# Centro de Iluminación RGB

Proyecto para sustituir el desplegable actual de ajustes de la base MCHOSE (una tarjeta que se expande al clicar el ratón en el widget de periféricos) por **una ventana única** que controle la iluminación de **todos** los periféricos.

## ▶ PARA RETOMAR EN UNA SESIÓN NUEVA

Rama: **`feat/obsidian-vault-and-rgb-control`**. Documento de traspaso completo y detallado:
**`docs/CENTRO_ILUMINACION_RGB_HANDOFF.md`** (en el repo) — lo tiene todo: estado exacto,
mapa de archivos, cómo desplegar/probar, y **Fase 4 (motor de flash) y Fase 5 (instalador)
paso a paso con esqueletos de código**.

Al decir *"empieza con las fases 4 y 5"*: leer ese handoff + `docs/CENTRO_ILUMINACION_RGB_PLAN.md`,
`git fetch`, y ejecutar Fase 4 y luego Fase 5 tal como están descritas.

Hecho y desplegado: Fases 0 (config + `sync-rgb.py`), 1 (esqueleto del panel), 2 (las 3
pestañas funcionales), 3 (el ratón abre el panel; retirada la tarjeta inline).

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

Plan detallado y vivo en `docs/CENTRO_ILUMINACION_RGB_PLAN.md` (repo). Resumen:

- **Estructura:** 3 pestañas — `Inicio` (estado en reposo) · `Dispositivos` (acordeón,
  una ficha por dispositivo; la base MCHOSE contiene los eventos de batería; OpenRGB elige
  `RGB estático` / `ARGB ola animada`) · `Notificaciones` (flash + qué dispositivos flashean).
- **Módulo QML** `configs/quickshell/caelestia/modules/rgbcontrol/` (`RgbControl.qml`,
  `Content.qml`, `InicioView`, `DispositivosView`, `NotificacionesView`, `DeviceCard`,
  `ColourPicker`, `Chip`) con `IpcHandler` target `"rgb"` (`open`, `openTab`, `close`,
  `toggle`), montado en `shell.qml`, expuesto en `ShellState.rgbControl`.
- **Singletons** `services/RgbConfig.qml` (mirror de `rgb-config.json` + re-lanza
  `sync-rgb.py`) y `services/MchoseConfig.qml` (mirror de `mchose-config.json`, escribe vía
  el CLI `mchose-config`). Configs **separadas** a propósito.
- **`sync-rgb.py`** ya lee `rgb-config.json` (source theme/fijo, toggles por dispositivo),
  acepta color por argumento y `--only`/`--skip-config` para preview. Retrocompatible.
- **Motor de flash** (pendiente): `rgb/rgb-notify-flash` + `Connections { target: Notifs }`
  en el `Scope` de `RgbControl.qml`. Complementario = tono +180° HSV. No toca OpenRGB.
- **Retirada** la tarjeta inline de las dos copias de `Background.qml`; el ratón abre el
  panel; botón `tune` en el widget de tira LED.
- **`install.sh`** (pendiente): desplegar `mchose-config`, `mchose-lighting`, el flash y la
  semilla `rgb-config.json`.

## Riesgos

- Bus SMBus/I2C de las RAMs: nada de pulsos rápidos sobre OpenRGB. El flash probablemente solo toca base + teclado + tira.
- `Background.qml` duplicado: mantener las dos copias iguales.
- Divergencias de `target 0x06`/`0x07` ya existentes en el código.
- Keyboard focus exclusivo del overlay: no bloquear el resto del shell.

## Registro

- **2026-08-27** — Brainstorming inicial. Decisiones 1-6 tomadas con Alberto. Creada esta bóveda y el [[Backlog - Efectos de iluminación|backlog]].
- **2026-08-27** — Mockup en Claude Design (3 pantallas). Reestructurado a 3 pestañas.
- **2026-08-27** — Implementado: Fase 0 (`rgb-config.json` + `sync-rgb.py` config-aware),
  Fase 1 (esqueleto del panel), Fase 2 (las 3 pestañas funcionales), Fase 3 (el widget del
  ratón abre el panel; retirada la tarjeta inline). Pendiente: Fase 4 (flash) y Fase 5
  (`install.sh`, docs).
- **2026-08-27** — Feedback de Alberto: bugs (acordeón no colapsaba, pestañas poco
  redondeadas) — arreglados `DeviceCard.qml` y `Content.qml`. Falta pase de diseño fino y
  verificar clics. Escrito `docs/CENTRO_ILUMINACION_RGB_HANDOFF.md` para reiniciar la
  conversación. **Siguiente sesión: fases 4 y 5.**
