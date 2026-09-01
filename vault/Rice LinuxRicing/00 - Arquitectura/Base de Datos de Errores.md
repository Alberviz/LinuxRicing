---
tags: [rice, errores, referencia]
actualizado: 2026-09-01
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
  - ~~Añadido `_akko_rf_wake(fd)`: 2× keepalive `0xF7` antes de la escritura~~ — **revertido**. Alberto: minimizar al máximo las señales al teclado, nada periódico ni "para que no se duerma" (congela el teclado igual que el lienzo). Las escrituras de color en frío llegan sin wake; si alguna se pierde se busca otra vía. Ver entrada más abajo (la tira lateral y la batería baja).
  - `battery-lighting` reaplica los efectos de color de batería mientras carga cuando el nivel cruza un escalón de 10 % (1 paquete de firmware, sin congelar).
  - Flash de notificación limitado a 2 pulsos en el Akko por 2.4 GHz.
  - Documentado en `hardware/akko-5075b-plus/{PROTOCOL,README,BATTERY_LIGHTING_FRONTEND}.md`; tests en `rgb/tests/test_effects.py`.

### La "píldora persistente" de agente rompía el cajón de notificaciones de Caelestia
- **Síntoma:** al encoger la notificación de agente a un circulito de 48 px, el fondo oscuro (`PanelBg`) seguía ocupando ~360 px y los `ClippingRectangle` cortaban la burbuja y los números.
- **Causa:** en Caelestia los paneles del cajón comparten un `BlobGroup` (metabola SDF), cada delegado va envuelto en `ClippingRectangle`, y `sidebar` está anclada a `notifications.bottom` — meter un elemento persistente y pequeño ahí choca con las cuatro cosas a la vez. Revertido en `e6569fc`.
- **Arreglo:** rediseño completo (rama `feat/agent-notifications`). El estado persistente vive en el **pip del workspace** en la barra (halo estilo `OccupiedBg` + puntito de "sin ver"), el detalle en un popout de barra (`AgentsPopout.qml`), y el clic lo resuelve Caelestia de forma nativa. Nada nuevo se inyecta en el cajón de notificaciones, respetando el ciclo de vida efímero de los toasts. Spec: `docs/superpowers/specs/2026-08-29-agent-notifications-workspace-pip-design.md`.

### La tira lateral del Akko "no funcionaba" — era ahorro de batería del firmware
- **Síntoma:** durante el desarrollo del modelo unificado de efectos, la tira
  lateral (SLED, opcode `0x08`) del teclado dejó de responder a mitad de sesión:
  cualquier modo que se le mandara (sólido, respiración, flujo…) no hacía nada,
  se quedaba apagada. Las **teclas** (`0x07`) seguían funcionando con normalidad.
  Horas persiguiendo un byte mal en la construcción del paquete `0x08`.
- **Causa:** **no había ningún byte mal.** El firmware del Akko 5075B **apaga la
  tira lateral cuando la batería está baja y descargando**, para ahorrar — las
  teclas se mantienen, la tira se corta. Al principio de la sesión (batería
  ~49 %, 2.4 GHz) el barrido de modos de la tira funcionó perfecto; más tarde
  (~35 %, descargando) la tira ya no encendía; al enchufar el cable a cargar
  (27 %) volvió sola. Verificado mandando `08 01 04 04 08 00 00 ff` (azul sólido)
  por `akko-poke` mientras cargaba → la tira se puso azul sin problema.
- **Arreglo:** ninguno en código — es comportamiento del hardware. Lección: antes
  de sospechar del protocolo de una zona LED secundaria, comprobar el **nivel de
  batería y si está cargando**. Documentado en
  `hardware/akko-5075b-plus/README.md` / `PROTOCOL.md`.
- **De paso** (esto sí eran bugs del refactor, ya arreglados):
  - `snake` es el modo de firmware **5** en la tira (`0x08`, flujo) pero el **7**
    en las teclas (`0x07`). El mapa unificado usaba 7 para las dos → la tira
    recibía un modo inexistente. Añadido override por zona.
  - El slider de velocidad mapeaba velocidad 1 → `byte[2] = 0`, y `byte[2] = 0`
    deja inertes la respiración y el sólido (el código viejo usaba siempre
    `byte[2] = 0x04` para sólido, `0x02` para respiración). Ahora el `byte[2]`
    por defecto depende de la animación y el slider solo lo mueve ±2, sin llegar
    a 0 salvo en `snake`.
  - La base MCHOSE: `byte[3]` del payload `0x2B` (velocidad) también se rompía
    con el valor crudo del slider; los modos estáticos van a `byte[3] = 0`
    (idéntico a lo que manda `rgb-notify-flash`, que sí funcionaba — esa fue la
    pista que dio Alberto).

### El widget mostraba "Cargando · 2.4GHz" con el teclado Akko conectado por cable
- **Síntoma:** con el dongle 2.4 GHz y el cable USB enchufados a la vez y la
  palanca del teclado en modo cable, el chip de estado del teclado en el widget
  de periféricos ponía "Cargando · 2.4G" en lugar de "Cable USB". El sistema no
  distinguía cuál de los dos transportes estaba activo.
- **Causa:** cadena de tres eslabones en `rgb/mchose-battery` y `rgb/battery-lighting`:
  1. La rama cableada de `get_akko_keyboard_battery()` (PID `0x4015`) devolvía el
     estado `"Cargando"` **sin marcador de transporte** cuando `resp83[3] == 1`
     (solo el caso "no carga" devolvía `"Conectado (USB)"`).
  2. `write_battery_cache()` normaliza el `status` a `"Cargando"`/`"Descargando"`
     y guarda el transporte solo en el campo aparte `akko_mode`. La ruta de caché
     fresco de `fresh_cache_reading()` devolvía el `status` pelado e ignoraba
     `akko_mode`.
  3. `mchose-battery --json` deriva el `mode` buscando la subcadena `"usb"` en el
     `status`. Sin ella → caía a `"2.4G Inalámbrico"`. Y el flag `charging` usaba
     `"cargando (usb)" in status`, que también matchea `"des-cargando (usb)"`.
- **Arreglo** (commit `17a133c`):
  - La rama cableada marca siempre el transporte: `"Cargando (USB)"`,
    `"Cargada (USB)"` (`resp83[3] == 2`, batería llena) o `"Conectado (USB)"`. El
    fallback sin respuesta `0x83` ya no afirma `"Cargando"`.
  - `fresh_cache_reading()` reinyecta el marcador `"(USB)"`/`"(Bluetooth)"` en el
    `status` a partir del campo `{prefix}_mode` del caché.
  - El `charging` del teclado en `--json` se calcula por la primera palabra del
    `status`, no por subcadena.
  - Gemelo `widgets/mchose-battery` sincronizado; ambos binarios desplegados y
    `battery-lighting.service` reiniciado.

### El teclado Akko en 2.4G cargando salía como "Cable USB" / "Descargando"
- **Síntoma:** con la palanca en 2.4G y el cable USB al PC para cargar, el widget
  mostraba mal el transporte y/o el estado de carga (unas veces "Cable USB",
  otras "Descargando" estándolo cargando).
- **Causa:**
  1. La rama cableada devolvía siempre "(USB)" en cuanto el PID `0x4015` estaba
     enumerado, sin comprobar que el nodo contestara a `0x83`.
  2. El parche anterior de la rama 2.4G (`is_chg = wired_present and resp83[3]==1`)
     forzaba `charging=False` si `0x4015` no estaba en el bus — y con la palanca
     en 2.4G **`0x4015` no enumera** (verificado en Linux: `lsusb` solo muestra
     `3151:4011`), así que mataba el caso legítimo de carga por 2.4G.
  3. Al reintentar con detección por nivel, se vio que `resp83[2]` (nivel) por RF
     **salta ±10 %** cuando el daemon y otra sonda leen el dongle a la vez: el
     `0xFC` (`GET_CACHED_RESPONSE`) de un lector recoge el frame del otro.
- **Arreglo** (commit pendiente):
  - **Discriminador de transporte:** presencia del PID `0x4015` en el bus hidraw.
    Enumerado → "Cable USB"; solo `0x4011` → "2.4G Inalámbrico". La enumeración de
    `0x4015` sigue la posición física de la palanca. Si `0x4015` enumera pero no
    contesta `0x83` y hay dongle, se trata como 2.4G.
  - **Carga en 2.4G:** flag `resp83[3]` como señal primaria, validado por la
    **tendencia de un EMA del nivel** sobre ~8-16 min (buffer `akko_ema_hist` en
    caché). Si el flag dice "cargando" pero el EMA baja ≥4 puntos → flag pegado
    tras desenchufar → `Descargando`. No depende de `0x4015`, así que cubre
    también el cargador de pared. El nivel nunca se muestra crudo, solo el EMA.
  - Retirado el parche `wired_present` y las claves `akko_chg_anchor`/`akko_chg_flag`.
- **Limitaciones:** ~8-15 min de latencia para detectar el desenchufe con flag
  pegado; si se desenchufa al ~100 % el nivel baja tan lento que puede seguir
  diciendo "Cargando" un buen rato. Detalle en
  `hardware/akko-5075b-plus/USB_FINDINGS_2.4G.md`.
- **De paso:** el `mchose-battery.timer` de systemd llama a `mchose-battery
  --notify`, flag que ya no existe → el servicio falla cada 60 s. Debería
  retirarse (además, un segundo lector empeora el ruido del `0x83`).

### La tira lateral del Akko se quedaba clavada en el wave de carga
- **Síntoma:** con la palanca en 2.4G, el LED lateral (y a veces las teclas) se
  quedaba fijo en el efecto `wave` de "cargando" un buen rato aunque ya no
  estuviera cargando. El widget mostraba el estado bien; solo el RGB no cambiaba.
- **Causa:** tres cosas sumadas:
  1. **`tick()` escribía `battery_alerts.json` después de liberar zonas.** Al
     dejar de cargar, `tick()` llamaba a `apply_zone(zk, None)` para volver la
     zona a estático, pero eso delega en `sync-rgb.py`, que **se salta las zonas
     que `battery_alerts.json` todavía reclame**. Como `write_alerts(new)` se
     ejecutaba al final del `tick()`, sync-rgb veía el claim viejo (`charging`) y
     abortaba sin resetear → el firmware seguía corriendo el wave solo.
  2. **`resp83` por RF devuelve frames rancios:** el flag `resp83[3]` llegaba a
     `1` en el daemon mientras una sonda lo leía `0`. El daemon se quedaba
     "cargando" por frames viejos del búfer del dongle.
  3. El daemon sondeaba cada 60 s en reposo → hasta 1 min de lag al enchufar.
- **Arreglo** (commit pendiente):
  1. `write_alerts(new)` **antes** del bucle de liberación de zonas en `tick()`.
  2. `is_chg` en 2.4G exige las tres: flag actual `1`, ≥2 de las últimas 6
     lecturas `1` (`akko_chg_hist`, contra frames rancios), y EMA no caído >6 bajo
     un ancla que trepa con la carga (detecta fin de carga aunque el flag se
     quede pegado, ~pocos minutos).
  3. `poll.idle_seconds` 60 → 15 (daemon, `BatteryLightingConfig.qml`, config del
     usuario). Enchufar reacciona en ≤15 s; desenchufar en ≤3 s (cadencia de
     carga).
- **Limitación:** si el flag se queda pegado en `1` tras desenchufar, el wave
  tarda unos minutos en apagarse (hasta que el EMA baje ~6 bajo el pico).

---

## 2026-09-01

### El widget mostraba "2.4GHz" y batería inventada con el Akko SOLO por cable
- **Síntoma:** con la palanca en cable y **sin** dongle 2.4 GHz en el bus (solo
  `3151:4015`), el widget de periféricos seguía mostrando el teclado como "2.4G
  Inalámbrico" y un nivel de batería (p.ej. 54 %) que no venía de ningún sitio.
  Las entradas del 2026-08-29 arreglaron el caso "cable + dongle a la vez" pero
  no este.
- **Causa:** dos fallos independientes.
  1. **Caché rancia dada por fresca para siempre.** `fresh_cache_reading()` en
     `rgb/mchose-battery` devolvía `akko_status`/`akko_battery` de
     `~/.cache/mchose_battery.json` mientras el `mtime` estuviera a < 90 s — pero
     el fichero tenía el `mtime` **en el futuro** (salto de reloj NTP hacia
     atrás en esta máquina), así que la edad salía negativa y siempre pasaba el
     test. Su `akko_mode` rancio (`"2.4G Inalámbrico"`, de una sesión anterior)
     ganaba a la enumeración USB real. Y nadie mantenía la caché al día: el
     `mchose-battery.timer` disparaba `mchose-battery --notify` (flag ya
     inexistente → `mchose-battery.service` en fallo cada 60 s) y
     `battery-lighting.service` estaba **deshabilitado y parado**.
  2. **Batería 100 hardcodeada por cable.** El firmware del Akko no reporta
     porcentaje por cable (`0x83` byte[bat] = `0x00`, ver USB_FINDINGS fase C).
     El código lo tapaba con
     `bat = resp[2] if 0<resp[2]<=100 else cache.get("akko_battery", 100)` →
     `100` fijo, o el valor rancio de 2.4G.
- **Arreglo** (rama `fix/akko-kb-transport-and-battery`):
  - `get_akko_keyboard_battery()` (en `rgb/mchose-battery`, gemelo
    `widgets/mchose-battery`, y la copia de `rgb/battery-lighting`) devuelve
    `(nivel|None, status, mode, connected)`. **El modo sale siempre de
    `akko_live_transport()`** — enumeración en vivo: `0x4015`→cable, si no
    `0x4011`→2.4G, si no UPower→BT — nunca de la caché.
  - **Cable USB → `nivel = None`.** El widget muestra solo `⚡ Cargando · Cable
    USB`, sin porcentaje ni relleno líquido (`DeviceItem.batteryKnown`). El
    estado de carga sí se lee (`0x83` byte[3], reintento 4×).
  - `fresh_cache_reading()` descarta edad negativa y exige que el transporte
    cacheado coincida con el vivo; solo se usa ya en la rama 2.4G.
  - `install.sh` retira `mchose-battery.{timer,service}` legacy;
    `battery-lighting.service` habilitado y arrancado como único escritor de la
    caché. En la máquina: `systemctl --user` disable/rm + enable --now.
- **Verificado:** `mchose-battery --json` y `battery-lighting --dump` → teclado
  `mode: "Cable USB"`, `battery: null`, `charging: true`, aun con la caché
  rancia (`akko_mode: "2.4G Inalámbrico"`) todavía en disco. Shell recargado sin
  errores QML. Detalle en `hardware/akko-5075b-plus/USB_FINDINGS_2.4G.md`
  (§"Solución aplicada (2026-09-01)").

### El halo «en curso» de agentes parpadeaba sin ningún agente trabajando
- **Síntoma:** el contorno neón blanco parpadeante (*running pulse*) del pip de un
  workspace se quedaba encendido aunque no hubiera ningún agente procesando nada.
- **Causa:** la función `claude` de `~/.config/fish/config.fish` lanza Claude Code
  vía `agent-notify run --name "Claude Code" …`. `run_wrapped_command()` llamaba a
  `start_agent()` al arrancar y a `finish_agent()` **solo al salir el proceso**. Como
  Claude Code es un REPL interactivo que pasa horas ocioso esperando input, el agente
  quedaba en `runningAgents` toda la sesión → halo parpadeando. Encima, al cerrar el
  terminal, `finish_agent()` ya no resolvía la ventana → mandaba `complete` con
  `address` vacío, y el filtro de `Agents.qml`
  (`na === "" || _normAddr(a.address) !== na`) trataba el address vacío como
  «no quitar nada» → la entrada fantasma no se limpiaba nunca (hasta reiniciar el
  shell). Se veían 3–4 ficheros de estado huérfanos en `$XDG_RUNTIME_DIR/agent-notify/`.
- **Arreglo** (rama `fix/akko-kb-transport-and-battery`):
  - `rgb/agent-notify`: `run` detecta los procesos gestionados por hooks per-turno
    (`_is_hook_managed`: basename `claude` o nombre con «claude») y **no** marca
    `running` durante toda la vida del proceso — de eso se encargan los hooks
    `UserPromptSubmit` (→ `start`) y `Stop` (→ `finish`). Al salir, `run` barre con
    `ipc call agents clearRunning {address}` (address resuelto al arrancar, con el
    terminal vivo). Para `make -j` / `agy` / builds se mantiene el ciclo vida =
    tarea.
  - `services/Agents.qml`: (a) `complete` con address vacío ya no es un no-op que
    acumula fantasmas — limpia por nombre solo si hay una única sesión con ese
    nombre; (b) nuevo `clearRunningByAddress()` + IPC `clearRunning`; (c) TTL
    `runningTtlMs` (20 min): un pulso sin refrescar caduca solo (filtro en
    `runningWsMap` + `Timer` de poda).
- **Verificado:** simulado start/complete/clearRunning por IPC; con 2 sesiones Claude
  un `complete` ambiguo no apaga el pulso de la otra; con 1, sí. Shell recargado sin
  errores QML.
