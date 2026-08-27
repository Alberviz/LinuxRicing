---
tags: [rice, errores, referencia]
actualizado: 2026-08-27
---

# Base de Datos de Errores

Registro de fallos que han ocurrido en el rice y cómo se resolvieron. La idea
es que el histórico dé perspectiva al diagnosticar problemas nuevos: muchos
síntomas se repiten (colisiones de bus, procesos que se pisan, tokens QML mal
escritos…).

**Formato de cada entrada:** síntoma observado · causa raíz · arreglo (commit /
archivo / ajuste). Añadir según van pasando, no solo al cerrar sesión.
Ambos agentes (Claude y Gemini) escriben aquí — añadir, no reescribir.

---

## 2026-08-27

### La RAM se quedaba en arco iris tras un reinicio forzoso
- **Síntoma:** tras apagar el PC en forzoso, los LEDs de la caja (los módulos
  de RAM) arrancaban en multicolor/arco iris y no había forma de recuperarlos;
  ejecutar `sync-rgb.py` no arreglaba nada.
- **Causa:** dos cosas que solo coinciden en un reinicio sucio. (1) Los módulos
  ENE DRAM guardan su último modo hardware en su propio controlador; en un
  apagado limpio quedan neutros, en uno forzoso arrancan en el modo guardado
  (`Rainbow`). Mientras un modo hardware está activo, OpenRGB ignora en
  silencio cualquier `set_colors`. (2) El daemon `argb-wave.py` arrancaba a la
  vez que `openrgb.service`, que acepta conexiones SDK **antes** de terminar de
  enumerar el hardware SMBus/AURA. `argb-wave` se conectaba, recibía una lista
  de dispositivos vacía (`Synced ... to []` en el log de sync-rgb) y se quedaba
  girando eternamente sin tocar nada, porque nunca volvía a pedir la lista ni
  se reconectaba si no había excepción. Con `argb_zones: true`, `sync-rgb.py`
  cede la RAM y la placa a `argb-wave`, así que con el daemon K.O. nadie sacaba
  la RAM de `Rainbow`.
- **Arreglo:** `argb-wave.py` ahora tiene `connect()`, que bloquea con backoff
  hasta que OpenRGB ha enumerado de verdad la RAM y la placa antes de animar; y
  cada 20 s hace `client.update()` para detectar una enumeración tardía o un
  dispositivo que se ha caído a modo hardware, reafirmando `Direct`.
  `sync_openrgb()` reintenta hasta 10 s si `client.devices` viene vacío en vez
  de dar el sync por bueno. `install.sh` ahora despliega `argb-wave.py` y las
  units de systemd (antes no lo hacía). Remedio inmediato si vuelve a pasar
  antes de reiniciar: `systemctl --user restart argb-wave.service`.

### La placa y los ventiladores ARGB parpadeaban y ciclaban colores
- **Síntoma:** al activar la ola ARGB, la placa base y los ventiladores de la
  caja pasaban por varios colores a saltos en cada cambio de fondo/tema.
- **Causa:** dos clientes de OpenRGB escribían en el mismo dispositivo a la vez
  — el daemon `argb-wave.py` (anima cada ~60 ms) y `sync-rgb.py` (mandaba el
  color sólido a la zona `Aura Mainboard` en cada hook de tema).
- **Arreglo:** commit `761e74a`. Con `argb_zones` activo, `sync_openrgb()` se
  salta por completo los dispositivos DRAM y ASUS/AURA — son territorio
  exclusivo del daemon.

### El backlight del teclado Akko se quedaba en blanco
- **Síntoma:** al pasar wallpapers, el retroiluminado del teclado se corrompía
  a blanco fijo en vez de seguir el color del tema.
- **Causa:** el selector de wallpaper lanza `sync-rgb.py` cada ~150 ms mientras
  se hace scroll. La radio 2.4 GHz del Akko pierde paquetes que llegan tan
  seguidos y el firmware deja el backlight en un estado corrupto. (Mismo motivo
  por el que el intento de *fade* de Gemini rompió el teclado.)
- **Arreglo:** commit `7348543`. El teclado se salta las llamadas de *preview*
  (`SCHEME_COLOURS` en el entorno) y solo se actualiza al confirmar el tema;
  además un suelo de 250 ms entre escrituras HID como red de seguridad.
- **Recuperación manual:** enviar un color limpio a los opcodes `0x07` y `0x08`
  tras una pausa de ~1 s.

### El acordeón del panel no respondía al clic
- **Síntoma:** clicar la cabecera de una ficha de dispositivo no la
  expandía/colapsaba.
- **Causa:** la cabecera era un `Item` sin `height` explícito; un `Item` no
  adopta `implicitHeight` como altura, así que el `StateLayer` que la rellenaba
  medía 0 px y no recibía clics.
- **Arreglo:** commit `a4f8a97`. Altura explícita en la cabecera; el `StateLayer`
  de hover pasó a ocupar todo el ancho de la tarjeta con sus mismas esquinas.

### Botones/chips del panel salían rectangulares
- **Síntoma:** los chips no eran píldoras, tenían esquinas casi rectas, y en
  hover aparecía un recuadro con forma que no encajaba.
- **Causa:** el código usaba `Tokens.rounding.normal`, que **no existe** en
  Caelestia (los tokens reales son `extraSmall / small / medium / large /
  largeIncreased / extraLarge / … / full`). Resolvía a 0.
- **Arreglo:** commit `a4f8a97` / `7ca0079`. Cambiado a `full` (píldora) y
  `large` según el caso. Lección: verificar los nombres de token contra
  `caelestia-config.qmltypes`, no inventarlos.

### El fade in/out de colores rompía el teclado (Gemini)
- **Síntoma:** parpadeos y backlight roto al intentar transiciones suaves de
  color al cambiar de tema.
- **Causa:** 5 frames con 25 ms entre ellos = escrituras demasiado rápidas para
  la radio 2.4 GHz del Akko y para el bus SMBus de OpenRGB.
- **Resolución:** revertido (commit `f1b7f94`). Decisión: no se implementa el
  fade — la ola ARGB ya da transiciones suaves en RAM/ventiladores, y en los
  demás dispositivos el coste (riesgo de romper hardware) no compensa.

### El teclado no seguía el color al cambiar de wallpaper/tema
- **Síntoma:** tras reiniciar, Caelestia cambiaba el tema pero el backlight del
  teclado no se actualizaba nunca al color nuevo.
- **Causa:** Caelestia exporta `SCHEME_COLOURS` en el entorno para **toda**
  llamada al `postHook` (`theme.py:469`, `wallpaper.py:200`), no solo en el
  preview. Un arreglo previo detectaba "preview" por esa variable y se saltaba
  el teclado → se lo saltaba también en cada cambio real.
- **Arreglo:** commit `d2e4a69`. La señal real de preview es el argumento
  `--only` (lo pasa `Wallpapers.qml`); el `postHook` confirmado va sin
  argumentos. El *throttle* de 250 ms del teclado ahora solo aplica en la ruta
  `--only`.

### Al cancelar el preview de wallpaper (Escape) las luces no volvían
- **Síntoma:** entras al selector de wallpapers, haces preview (las luces
  cambian), pulsas Escape → el fondo vuelve al original pero las luces se
  quedan con el color del preview.
- **Causa:** `Wallpapers.qml::stopPreview()` revertía los colores del shell
  (`Colours.showPreview = false`) pero **nunca re-lanzaba `sync-rgb.py`** para
  devolver los LEDs al esquema real.
- **Arreglo:** commit `d2e4a69`. `stopPreview()` para el write de preview
  pendiente y, salvo que se haya elegido un wallpaper (`justSelected`), re-lanza
  `sync-rgb.py` sin argumentos (lee `scheme.json`) tras 400 ms.
- **Nota de arquitectura:** este subsistema (preview de wallpaper → LEDs
  físicos) ha dado varios fallos encadenados. Está en evaluación si merece la
  pena o si los LEDs deberían seguir solo el wallpaper **confirmado**.
