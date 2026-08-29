---
tags: [rice, errores, referencia]
actualizado: 2026-08-29
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

### Desincronización y reversión al fondo anterior en Quickshell (Wallpapers.qml)
- **Síntoma:** al elegir un nuevo wallpaper, los LEDs y aplicaciones a veces se
  quedaban con el tema anterior o revertían bruscamente poco después.
- **Causa:** carrera de temporizadores en `Wallpapers.qml` (`rgbRestoreTimer` a
  los 400 ms y `previewIdleRestoreTimer` a los 15 s ejecutaban `sync-rgb.py` sin
  variables de entorno antes de que `caelestia wallpaper -f` terminase de escribir
  el nuevo `scheme.json`), sumado a cerrojo no bloqueante (`LOCK_NB`) en `theme.py`
  que abortaba si `sudo` de Chromium demoraba el proceso.
- **Arreglo:** en `Wallpapers.qml`, parada inmediata e incondicional de los
  temporizadores de marcha atrás al seleccionar fondo; guardián `if (root.justSelected) return;`
  en `getPreviewColoursProc`; `"enableChromium": false` en `cli.json`.

### OpenRGB (RAM y ventiladores) volvía al fondo anterior tras 2 s en Super+W
- **Síntoma:** al navegar con `Super + W` por la lista de fondos y quedarse parado
  en uno mirando la pantalla, a los ~2-3 segundos la RAM y los ventiladores ARGB
  volvían al color del wallpaper anterior.
- **Causa:** `argb-wave.py` tenía `LIVE_CACHE_TTL = 2.0`, lo que invalidaba la
  caché temporal `/tmp/caelestia-rgb-live-palette.json` a los 2 segundos de
  inactividad y volvía a leer el `scheme.json` anterior.
- **Arreglo:** eliminado el TTL de 2 segundos en `argb-wave.py` y eliminado
  `previewIdleRestoreTimer` de `Wallpapers.qml`. Ahora la animación ARGB mantiene
  el color del fondo previsualizado indefinidamente hasta que el usuario confirme
  o cierre explícitamente el menú con `Escape`.

### El efecto de carga en la base MCHOSE cambiaba a un color deslavado (theme_breathing)
- **Síntoma:** al colocar el ratón (M8 / K7 Ultra) en la base 8K para cargar con
  el modo `theme_breathing`, la luz parpadeaba en un color blanquecino/descolorido
  o ámbar en lugar del color vivo del tema.
- **Causa:** `get_theme_primary_rgb()` en `mchose-battery` leía el valor hexadecimal
  crudo de `scheme.json` sin potenciar la saturación para LEDs físicos
  (`enhance_color_for_leds`), mandando valores pastel al firmware que en hardware
  LED se aprecian apagados/blanquecinos.
- **Arreglo:** añadido el algoritmo de saturación inteligente `enhance_color_for_leds()`
  y lectura preferente de `rgb-config.json` en `mchose-battery`.

### Congelación del teclado Akko cada minuto por reescritura periódica de LEDs
- **Síntoma:** mientras se escribe con el teclado Akko 5075B, cada 1-2 minutos
  el teclado se quedaba bloqueado / "petado" durante ~2 segundos, perdiendo o
  retrasando pulsaciones de teclas.
- **Causa:** en el commit `b3b01d1`, la función `check_and_notify()` de
  `mchose-battery` ejecutaba incondicionalmente `apply_akko_battery_lighting()`
  en cada tick del timer de sistema (`mchose-battery.timer`). Al recibir paquetes
  de configuración LED (`SET_REPORT 0x07/0x08`), el microcontrolador ROYUAN del
  teclado pausa el procesamiento del escaneo de teclas mientras reinicia el PWM
  de los LEDs.
- **Arreglo:** eliminada la llamada a `apply_akko_battery_lighting()` dentro de
  `check_and_notify()`. La iluminación del teclado Akko es de disparo único
  (*One-Shot*) y solo debe escribirse al cambiar de tema/wallpaper vía `sync-rgb.py`.

---

## 2026-08-29

### Regresión: Desincronización y RAM en arco iris tras apagado forzoso / regleta
- **Síntoma:** tras un corte brusco de corriente (apagar la regleta) o reinicio forzoso, al arrancar el equipo los módulos de RAM se quedaban en arco iris (modo hardware) y las luces no se sincronizaban correctamente con el fondo/tema.
- **Causa:** durante la implementación de los perfiles individuales de iluminación por dispositivo (commit `ce740fb`), se añadió una segunda definición de `def sync_openrgb()` en la línea 432 de `rgb/sync-rgb.py`. En Python, la segunda definición sobrescribió silenciosamente a la primera (línea 235), eliminando:
  1. El bucle de reintentos (`for _ in range(10): if client.devices: break; time.sleep(1); client.update()`) necesario porque el servidor OpenRGB SDK acepta conexiones de clientes antes de terminar el escaneo SMBus/AURA en el arranque en frío.
  2. La comprobación de zonas de alerta de batería (`if "openrgb:_" in battery_alert_zones(): return`).
  3. La exclusión completa de dispositivos DRAM y ASUS cuando `argb_zones` está activo (`if argb_zones and ("dram" in dev_name_l or "asus" in dev_name_l or "aura" in dev_name_l): continue`), provocando carreras con `argb-wave.py`.
  Al iniciar en frío con `sleep 2`, `OpenRGBClient()` recibía `client.devices = []`, no reintentaba, registraba falsamente sincronización con éxito a 0 dispositivos y salía sin sacar la RAM del modo Rainbow hardware.
- **Arreglo:**
  - Consolidada una única función `sync_openrgb()` en `rgb/sync-rgb.py` y desplegada en `~/.config/caelestia/sync-rgb.py` que integra soporte de perfiles (`fixed`, `battery_color`, `argb_wave`), retención de alertas activas, bucle de reintentos con backoff hasta enumeración efectiva de hardware y forzado de modo `Direct`.
  - Sincronizado `rgb/argb-wave.py` y `~/.config/caelestia/argb-wave.py` sin expiración de TTL para que la caché de paleta en `/tmp` mantenga la continuidad de color.
  - Añadidos tests unitarios en `rgb/tests/test_sync_rgb_alerts.py` (`test_sync_openrgb_skips_when_alert_active` y `test_sync_openrgb_retries_and_sets_direct_mode`) para blindar contra futuras regresiones.

### Los efectos "al cargar" del teclado Akko por 2.4 GHz no hacían nada
- **Síntoma:** en el Centro de Notificaciones, al elegir efectos de carga para el teclado Akko (medidor tecla a tecla, "flujo", etc.) no se veía nada, o el teclado se quedaba congelado, o el gradiente de color de batería no avanzaba mientras cargaba.
- **Causa:** varias, todas por 2.4 GHz:
  1. El lienzo per-key (`0x07` modo `0x0D` + 7×`0x0C`) se re-renderizaba cada tick de carga; cada pasada satura la radio y deja el teclado sin responder ~1 s, y el firmware del 5075B ni siquiera conmuta a modo lienzo de forma fiable.
  2. El efecto "flujo" (`stream`) se mandaba como modo `0x05` sobre el opcode de las teclas (`0x07`), donde el modo 5 es *Ripple* (reactivo), no un flujo — invisible sin pulsar teclas. El modo 5 solo es un flujo en la tira lateral (`0x08`).
  3. `battery-lighting` solo reaplicaba un efecto cuando cambiaba su **nombre**, no cuando subía la batería, así que el gradiente rojo→verde de `breathing_battery`/`stream_battery` se quedaba clavado en el nivel inicial durante toda la carga.
  4. Ninguna ruta de escritura de color (`sync-rgb.py`, `akko-rgb`, `rgb-notify-flash`, `battery-lighting`) despertaba el enlace RF antes de escribir; una escritura `0x07`/`0x08` sobre el dongle "frío" se pierde y deja el backlight congelado en blanco.
- **Arreglo:**
  - Retirado del stack de Linux todo efecto que no sea un modo de firmware de una sola escritura: fuera `battery_meter` / "Letra a letra" / "Fila a fila" y todo el andamiaje de lienzo (`akko_canvas_chunks`, `AKKO_KEY_ROWS`, `apply_akko_meter`) en `rgb/battery-lighting` y `rgb/sync-rgb.py`, y de la UI (`AkkoCard.qml`, `BatteryLightingConfig.qml`).
  - Añadido el efecto de firmware `wave` / `wave_battery` (opcode `0x07` modo `0x04`); `stream` retirado de las teclas, `stream_battery` conservado en la tira.
  - Añadido `_akko_rf_wake(fd)`: 2× keepalive `0xF7` antes de la escritura de color, solo sobre el dongle (`PID 0x4011`), en los cuatro scripts.
  - `battery-lighting` reaplica los efectos de color de batería mientras carga cuando el nivel cruza un escalón de 10 % (1 paquete de firmware, sin congelar).
  - Flash de notificación limitado a 2 pulsos en el Akko por 2.4 GHz.
  - Documentado en `hardware/akko-5075b-plus/{PROTOCOL,README,BATTERY_LIGHTING_FRONTEND}.md`; tests en `rgb/tests/test_effects.py`.


