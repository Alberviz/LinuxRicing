# Chromecast — enviar vídeo desde el escritorio

Enviar vídeos locales o URLs al Chromecast de casa sin terminal: tarjeta en el panel lateral
rápido de Caelestia + reproductor MPRIS que aparece en el panel de música (dashboard).

- **Dispositivo:** «Гостиная», Chromecast Ultra, `192.168.1.5`.
- **Rama de origen:** `feat/chromecast-panel` (2026-11-08).

## Piezas

| Pieza | Dónde | Qué hace |
|---|---|---|
| `cast-helper` | `widgets/cast-helper` → `~/.local/bin/` | Daemon Python: descubre Chromecasts (pychromecast), sirve archivos por HTTP, transcodifica audio al vuelo, publica MPRIS `org.mpris.MediaPlayer2.casthelper`. |
| Servicio | `systemd/cast-helper.service` (usuario) | Mantiene el daemon vivo. `systemctl --user status cast-helper`. |
| `Cast.qml` | `configs/quickshell/caelestia/services/` | Singleton: lee `$XDG_RUNTIME_DIR/cast-helper/state.json` y lanza órdenes `cast-helper <cmd>`. |
| Tarjeta | `.../modules/utilities/cards/Chromecast.qml` | Encima de los quick toggles: dispositivo, zona para soltar archivos/URLs, «Elegir archivo», controles. |
| Dashboard | (sin código propio) | El panel de música de Caelestia muestra cualquier MPRIS; el helper aparece como «Chromecast · Гостиная». |

Dependencias: `catt` (instalado con `uv tool`, aporta pychromecast/zeroconf/yt-dlp; el helper añade su
`site-packages` a `sys.path`), `ffmpeg`/`ffprobe`, `python-gobject` para MPRIS.

## Uso desde terminal

```
cast-helper devices
cast-helper probe <archivo>            # códecs, pistas, modo direct/transcode
cast-helper cast Гостиная <archivo|url> [--audio N] [--sub N|--sub-file F|--no-subs] [--start S]
cast-helper toggle | stop | seek 3600 | volume 50 | mute
playerctl -p casthelper play-pause     # también vale MPRIS / teclas multimedia
```

## Cómo decide qué hacer con un archivo

- **direct** — mp4/m4v/webm con vídeo h264/hevc/vp9 y audio aac/mp3/opus/vorbis: se sirve tal cual
  con Range (seek nativo).
- **transcode** — lo demás (MKV, audio AC3/E-AC3/DTS/TrueHD…): `ffmpeg` copia el vídeo y pasa el audio a
  AAC estéreo 256k en MP4 fragmentado, en vivo. No ocupa disco. El seek reinicia ffmpeg con `-ss`
  (cae en el keyframe anterior, desvío de hasta un GOP).
- Vídeo que no sea h264/hevc/vp9 → error; no se recodifica vídeo.
- **URLs** http(s) → `catt`/yt-dlp (YouTube y similares).
- Audio por defecto: primera pista en español. Subtítulos por defecto: la pista *forzada* en español si
  existe; también detecta `.srt/.vtt` junto al vídeo. PGS (imagen) no soportado.

## Red y cortafuegos

El Chromecast descarga el vídeo **desde el PC**: el helper sirve en el puerto **45114/tcp**
(regla UFW ya existente para `192.168.1.0/24` en `wlan0`). Si otro `catt cast` está sirviendo, el puerto
está ocupado y el helper lo dice en la tarjeta. Si el PC se suspende o se cierra el servicio, la tele se corta.

## Por qué no VLC

VLC 3 con Chromecast se congela con MKV de alto bitrate y audio Dolby (`httpd buffer full: dropping packets`,
`non monotonically increasing dts`). Antes del helper, el apaño fue convertir con
`ffmpeg -map 0:v:0 -map 0:2 -c:v copy -c:a aac -ac 2 -b:a 256k` (3 min para 2h40, ~53x) y `catt cast`.

## Diagnóstico

- `journalctl --user -u cast-helper -f` — logs del daemon.
- `jq . $XDG_RUNTIME_DIR/cast-helper/state.json` — estado que lee la tarjeta (`error` se muestra en ella).
- No aparece el dispositivo: `catt scan`; mDNS (5353/udp) está permitido en UFW; hay caché en
  `~/.cache/cast-helper/devices.json`.
- Sin sonido: `cast-helper probe <archivo>` y comprobar que `mode` es `transcode` si el audio es Dolby/DTS.
- La tarjeta no se actualiza: reinicio completo del shell (ver CLAUDE.md, nunca hot-reload).

## Pendiente

- Drawer Proyectar (rediseño 2026-11-09, sin chips): fuente en 4 tarjetas, escritorios como mini-tarjetas numeradas con un punto
  por ventana, monitores dibujados a escala, Calidad/Codificador en botones segmentados dentro de una tarjeta «Ajustes» plegable
  con resumen. Falta probar con una proyección real las fuentes Ventana/Extender y el cambio de fuente desde la tarjeta.
- Tarjeta del panel rápido al proyectar la pantalla (≠ mini-reproductor): miniatura «EN VIVO», qué se ve y en qué tele, grupo de
  fuentes (cambiar reconecta con los mismos ajustes), escritorios, Calidad/Codificador/Audio en caliente, volumen y Detener.
  Prueba sin tele: `cast-helper serve-test --fake-mirror [workspace:2]`.
- 1080p (medido 2026-11-09): VP8 por CPU 29,8 fps, 123 ms, 6 % tardíos (~470 % CPU en modo ahorro); NVENC 28 fps pero >90 %
  tardíos (entrecorta). Por eso el codificador «auto» usa CPU a 1080p. Arreglados: `hypr_wake` hacía `dpms on` aunque la pantalla
  estuviera encendida y gpu-screen-recorder no encontraba `eDP-2` (~2 de cada 3 arranques); un cambio en caliente durante el
  arranque dejaba el emisor sin captura y la sesión «PLAYING» sin imagen (ahora vigilante de la captura + reintentos).
  stderr de la captura en `$XDG_RUNTIME_DIR/cast-helper/capture.log`.

- Espejo: medir la latencia real con audio (`cast-helper mirror test-latency`); desfase audio/vídeo ~40 ms sin ajustar; 1080p
  (`CAST_STREAM_SIZE=1920x1080`, ~230 % CPU) y NVENC (`CAST_STREAM_CODEC=h264 CAST_ENCODER=h264_nvenc`, ~48 % CPU pero despierta la RTX) son opcionales.
- Guardar en el repo el bind `Super+K` (`kbCastPanel`, y `showall` → `Super+Shift+K`): está aplicado en `~/.config/hypr` pero
  `configs/hypr/{variables,hyprland/keybinds}.lua` tienen cambios sin commitear de otro agente; parche en el scratchpad de la sesión
  2026-11-08 (`superk-hypr.patch`).
- Arrastrar la tarjeta de una llegada a otra app (`Drag.Automatic`) sin probar con un arrastre real.
- Textos de la tarjeta sin `Tr.tr`.
- Si hay varios reproductores MPRIS, el dashboard muestra el `defaultPlayer`/primero; quizá priorizar casthelper.

## Portales de arrastre (agujeros negros en los bordes)

Al arrastrar un archivo desde el gestor de archivos o el navegador aparecen dos mini agujeros negros
(estilo Gargantua del escritorio) en los bordes de la pantalla; crecen al acercar el cursor y se abren
al entrar en la banda del borde:

- **Borde derecho -> tele:** `cast-helper cast <dispositivo elegido> <ruta|url>` (vía `Cast.run`).
- **Borde superior -> móvil:** `olimpo enviar --json --progreso <ruta>` (CLI de Olimpo instalada en `~/.local/bin/olimpo`;
  se exige fichero ejecutable: `~/proyectos/olimpo/cli/olimpo` es un *directorio* y antes colgaba el envío en «Enviando…»).
  Llega a la bandeja «Desde el PC» de Olimpo (Pi) y el móvil muestra la tarjeta «Llegó del PC».

Diseño elegido: **variante B «clavado en el borde»** del mockup (artefacto «Portales Gargantua»): el centro del agujero queda
sobre el borde, medio fuera de pantalla, y succiona en espiral; el borde de la pantalla se curva a su alrededor. Render por GPU
(`modules/portals/shaders/portal.frag` → `.qsb` con `/usr/lib/qt6/bin/qsb`): sombra, anillo de fotones, disco a −17° con Doppler,
halo lensado, corrientes de succión. Mientras se arrastra, estela y fragmentos («espaguetización») en la posición del cursor
(el icono del arrastre lo pinta el compositor y no se puede deformar).

**Feedback:**
- *Antes de soltar:* al entrar el arrastre en la banda se mide el archivo (`stat`) y el HUD muestra nombre · tamaño. Si no cabe
  en el móvil (`olimpo enviar --limites` → `archivo_max` 50 MiB, `libre`) o no es reproducible en la tele, el portal no se arma,
  se tiñe de rojo, el disco se frena y la píldora lo explica («Demasiado grande para el móvil · 13,9 GB / máx. 50 MB»); si se
  suelta igualmente, rebota y no se envía.
- *Durante:* tarjeta de transferencia con barra, %, velocidad, enviado/total, tiempo restante y cancelar (SIGTERM a la CLI; la
  Pi descarta el parcial). En la tele: «Preparando… / Cargando en <tele>… / Reproduciendo» siguiendo `Cast`.
- *Al terminar:* destello + resultado y `notify-send` (también si falla). Un watchdog cierra con error si la CLI no arranca.
- *Salida:* al dejar de arrastrar, el agujero se retrae deslizando hacia fuera (~380 ms, interrumpible: si vuelves a arrastrar
  regresa desde donde esté).
- Prueba sin arrastrar: `qs -c caelestia ipc call portals demo bad|good|progress|tele|ok|error`.

| Pieza | Dónde | Qué hace |
|---|---|---|
| `drag-watch` | `widgets/drag-watch` -> `~/.local/bin/` + `systemd/drag-watch.service` | Daemon: detecta botón izquierdo mantenido + >40 px de desplazamiento + ventana activa de gestor de archivos/navegador (`DRAG_WATCH_CLASSES`, `DRAG_WATCH_THRESHOLD`). Publica `$XDG_RUNTIME_DIR/drag-watch.sock` (JSON por línea; posición ~30 Hz solo durante el arrastre). Duerme en `select()` en reposo. |
| `DragWatch.qml` | `services/` | Cliente del socket (`dragging`, `cx`, `cy`). |
| `Portals.qml`, `Portal.qml`, `shaders/portal.frag(.qsb)` | `modules/portals/` | Ventana layer-shell overlay a pantalla completa, **sin input** salvo las bandas de ~140 px mientras dura el arrastre (Wayland solo entrega el DnD a la superficie bajo el cursor). Un `ShaderEffect` por portal; `FrameAnimation` solo mientras hay arrastre, transferencia o animación de salida. |

Requisitos y límites: usuario en el grupo `input` (lee `/dev/input/event*`); solo detecta pulsaciones
físicas de botón (el tap-to-drag del touchpad no genera BTN_LEFT en evdev); sin hotplug de ratones
(reiniciar el servicio). Prueba sin arrastrar: `drag-watch sim <x> <y>` / `drag-watch sim off`.

## Proyectar la pantalla (Super+K) — modo espejo

- **Atajo:** `Super+K` (global `caelestia:castPanel`) abre el drawer «Proyectar» (como Win+K): es un drawer más de Caelestia
  (`modules/cast/{Wrapper,Content}.qml`, `screenState.cast`), pegado al borde abajo a la derecha con el mismo marco y animación que
  utilities; comparte hueco con utilities y sidebar (abrir uno cierra el otro). Por IPC: `caelestia shell drawers toggle cast`.
  Lista de Chromecasts, tocas uno y empieza a proyectar.
  Con 2 monitores hay un selector de pantalla (se recuerda en `~/.config/caelestia/cast-last-monitor`). Proyectando:
  «Proyectando en X», conmutador del audio del sistema y «Desconectar». Esc o clic fuera lo cierra.
  El antiguo `Super+K` (mostrar todos los paneles, `caelestia:showall`) pasa a `Super+Shift+K`.
  Mientras se emite hay un icono rojo `cast_connected` en la barra (privacidad). Ojo: Gemini dejó en `~/.config/hypr` un segundo
  `SUPER + K` que abría utilities a la vez; se quitó el 2026-11-09 (si vuelven a salir dos paneles, buscar binds duplicados).
- **Backend:** `cast-helper mirror start [--device D] [--monitor M] [--no-audio]`, `mirror stop`, `mirror audio on|off`,
  `mirror monitors`. Pipeline: `gpu-screen-recorder -w <salida> -k h264 -bm cbr -q 6000 -keyint 1 -c mpegts` (NVENC/VAAPI según GPU)
  -> `ffmpeg -c copy -bsf:a aac_adtstoasc -f mp4 -movflags frag_keyframe+empty_moov+default_base_moof` -> HTTP del helper (`:45114`,
  fMP4 sin Content-Length, `stream_type=LIVE`). 1080p30 (si la salida es mayor se escala a 1920x1080), vídeo 6 Mbps, audio AAC 128k
  del monitor por defecto de PipeWire. `state.json`: `active.mode = "mirror"`, `active.monitor`, `active.audio`; y `monitors: [{name,width,height}]`.
  Notas: gpu-screen-recorder necesita la pantalla encendida (con DPMS apagado no lista ni captura monitores); cambiar el audio reinicia el flujo.
- **Latencia (medida con el estimador del helper):** `active.latency` = (tiempo desde el primer dato servido) − (posición que reporta el
  receptor) + 1,0 s de calibración (Alberto midió 2,51 s con test-latency donde el estimador daba 1,52 s). Perfiles (`mirror start --profile P`,
  por defecto `hls`):

  | perfil | qué es | latencia |
  |---|---|---|
  | `base` | fMP4, keyframe 1 s, fragmento por keyframe | 3,7 s |
  | `ll` | keyframe 0,5 s, NVENC `tune=ull;zerolatency=1;rc-lookahead=0;bf=0`, `frag_every_frame` | 2,2 s |
  | `ll200` | igual con fragmentos de 200 ms | 2,15 s |
  | **`hls`** | HLS en tmpfs, segmentos de 0,5 s (lista de 3, `EXT-X-START:TIME-OFFSET=-0.5`), mismo encoder | **~2,3 s reales** (Alberto midió 2,5 s con el perfil sin START) |
  | `hls33` | segmentos de 0,33 s | 3,2 s (peor) |
  | `hls25` | segmentos de 0,25 s | 2,3 s (peor: el receptor necesita más segmentos y arranca peor) |

  Gana `hls`: el Default Media Receiver reproduce HLS en directo con búfer de ~3 segmentos de 0,5 s, menos que su búfer mínimo con
  MP4 progresivo. Por debajo de ~1,5 s no se baja con este receptor; para eso hace falta Cast Streaming (fase 2).
  Medida real a ojo: `cast-helper mirror test-latency` abre un cronómetro grande a pantalla completa; proyecta esa pantalla y
  fotografía monitor y tele juntos (diferencia de tiempos = latencia).

### Backend Cast Streaming (openscreen) — preferido

`cast-helper mirror start` usa por defecto **Cast Streaming** (el protocolo de «Transmitir pantalla» de Chrome: Mirroring App en la tele,
RTP/UDP cifrado, búfer de reproducción de 150 ms) si existe `~/.local/lib/linuxricing/cast_sender`; si no existe, o si falla 3 veces al
arrancar, cae solo a HLS. `--backend hls|cast-streaming|auto` (o `CAST_MIRROR_BACKEND`) lo fuerza. `state.json` → `active.backend`.

- **Latencia:** medida por el propio emisor (histograma end-to-end captura→reproducción): **~170-200 ms**, ~29 fps, ~5 % de fotogramas
  tardíos; a eso se suma captura+NVENC+pantalla de la tele (estimación pantalla a pantalla < 0,6 s; `active.latency` muestra el estimado
  0,3 s). Medición real pendiente con `cast-helper mirror test-latency`.
- **Pipeline:** `gpu-screen-recorder` (h264, GOP 0,5 s, 1280x720 por defecto, `CAST_STREAM_SIZE`) -> `ffmpeg -c copy -bsf:v dump_extra`
  (repite SPS/PPS en cada keyframe) -> `cast_sender` leyendo mpegts por stdin; el emisor decodifica y recodifica a **VP8 por software**
  (~1 núcleo de CPU) y lo manda por UDP. Variables: `CAST_STREAM_PLAYOUT_MS` (150), `CAST_STREAM_KBPS` (8000), `CAST_MIRROR_FPS` (30), `CAST_STREAM_CODEC`, `CAST_ENCODER`.
- **Audio** (monitor del sink por defecto de PipeWire, `ffmpeg -f pulse` -> FIFO WAV -> segundo capturador del emisor): activo por defecto;
  `mirror audio on|off` reconecta (~3 s) sin pasar a HLS. Medido con audio: e2e vídeo ~120 ms, 29,9 fps, <1 % tardíos; audio ~160 ms.
  Claves del parche: lecturas no bloqueantes con E/S propia (ffmpeg dormía esperando datos y el audio dejaba sin fotogramas al vídeo,
  que comparte hilo) y descarte del audio atrasado de PulseAudio (si no, el reloj de muestras de Opus se adelanta y todo se retrasa).
- **Resolución y CPU:** 720p por defecto (VP8 por software, ~130 % de CPU = 1,3 núcleos). `CAST_STREAM_SIZE=1920x1080`: ~230 % de CPU,
  mismos 30 fps y ~120 ms. Por hardware: `CAST_STREAM_CODEC=h264 CAST_ENCODER=h264_nvenc` (720p: ~48 % de CPU, 124 ms, 4 % tardíos;
  en 1080p salió peor: 26 fps y muchos tardíos), pero despierta la RTX 4050 (en reposo D3cold), por eso no es el valor por defecto.
  `h264_vaapi` no funciona (el emisor entrega fotogramas de sistema, no superficies VAAPI); VP9/AV1 no se probaron.
- **Cortafuegos:** no hace falta regla en UFW. El emisor inicia el flujo UDP y el RTCP de vuelta entra por el seguimiento de conexión
  (comprobado: paquetes del receptor recibidos con UFW activo). Los `[UFW BLOCK]` de 192.168.1.5 que se ven son RST TCP del 8009.
- **Instalación:** `tools/build-openscreen.sh` descarga openscreen (commit fijado), le aplica `tools/openscreen-live.patch` (modo en vivo:
  entrada por pipe sin bloqueo, reloj recuperado, audio por FIFO, `CAST_PLAYOUT_MS`, `CAST_INFLIGHT_MS`, `CAST_NO_AUDIO`, `CAST_ENCODER`) y lo compila (clang+ninja,
  ~2000 objetivos, ~20 min) a `~/.local/lib/linuxricing/cast_sender`. El código de openscreen no se guarda en el repo.
- **Notas:** el puerto de la tele es el 8009 explícito (sin puerto el emisor usa otro y falla con `ConnectionFailed`). A veces el primer
  arranque falla («Invalid data» al sondear): el helper reintenta hasta 3 veces antes de caer a HLS.

## Cambiar subtítulos y audio en reproducción

- Al hacer `cast` se cargan TODAS las pistas de texto (incrustadas -> VTT, externas `<base>*.srt|vtt`) como `MediaTrack`; solo se activa la elegida.
  `cast-helper subs <n|off>` cambia la pista sin recargar (EDIT_TRACKS_INFO). `cast-helper audio <n>` recarga en la posición actual
  (en transcode relanza ffmpeg con esa pista; en direct pasa a transcode si no es la primera).
- Contrato en `state.json`, dentro de `active`:
  `tracks: {subs:[{n,label,lang,forced}], audio:[{n,label,lang,codec,channels}], sub_active:n|null, audio_active:n}`
  (`n` de subtítulos = índice de stream, o `1000+i` para externos; `n` de audio = índice de stream). `tracks` es `null` en `url` y `mirror`.
- La tarjeta del panel rápido tiene un chip de subtítulos y otro de audio que abren un menú con las pistas + «Desactivados».

## Llegadas desde el móvil (agujero negro del borde)

El puente de Olimpo añade una línea JSON por archivo recibido a `$XDG_RUNTIME_DIR/olimpo-puente/llegadas.jsonl`
(`{"ruta","nombre","tamano","mime","ts"}`). `modules/whitehole/WhiteHole.qml` (nombre histórico) lo vigila con `tail -n 0 -F` (cero coste
en reposo). Se abre el MISMO agujero negro de los portales (shader `portals/shaders/portal.frag`, clavado en el borde superior, centrado: es el «agujero del móvil», el mismo del portal de arriba, y no se duplica durante un arrastre), el archivo emerge del horizonte (pequeño y estirado, con destello del anillo) y queda
aparcado en una tarjeta debajo (a la izquierda del eje, para no tapar el HUD del portal); varias se apilan (máx. 5). Clic: abrir (y cae de vuelta al agujero); botón derecho: mostrar en carpeta;
X: descartar; arrastrar la tarjeta: soltar en otra app (`Drag.Automatic`, `text/uri-list`); ~60 s sin interacción: se va sola. Cuando no queda
ninguna, el agujero se retrae con la animación de salida. Prueba: `qs -c caelestia ipc call whitehole demo <ruta>`.

## Móvil y otros agentes (Olimpo, Laura, Aurora)

Todo lo del móvil vive en Olimpo (`~/proyectos/olimpo`, desplegado en la Pi); ver sus diseños `docs/diseno-v2.11-tele-bandeja.md`,
`v2.12-ajustes-casa`, `v2.13-movil-al-pc` y la v2.14 (reproductor «Aurora»).

- **Topología:** el PC no abre puertos. `olimpo-puente.service` (usuario, en el PC) conecta **hacia** la Pi por Tailscale: sube el
  `state.json` de cast-helper y recoge órdenes de la tele para reenviarlas al socket del helper (`play|pause|toggle|stop|seek|volume|mute|subs|audio`).
  En la Pi, el contenedor `tele` escucha solo en la IP tailnet (`:8098`) con token propio y red aislada en `firewall.sh`.
- **Tele desde el móvil:** mini-reproductor «Aurora» sobre la barra de pestañas solo cuando hay sesión (color del fotograma, anillo de
  progreso); al tocarlo, hoja con seek, −10/+30, volumen y chips de subtítulos/audio (`active.tracks`).
- **PC → móvil:** portal de arriba / `olimpo enviar` → bandeja «Desde el PC» → tarjeta «Llegó del PC» en Inicio + aviso de Iris.
  Límites: 50 MiB por archivo, 1 GiB en total.
- **Móvil → PC:** Android «Compartir → Olimpo» (Web Share Target; hay que reinstalar la PWA tras actualizar) o «Enviar al PC» en
  Ajustes › Dispositivos → bandeja «Para el PC» → el puente lo descarga a `~/Descargas/Desde el móvil/` (sin pisar nombres),
  `notify-send` y una línea en `$XDG_RUNTIME_DIR/olimpo-puente/llegadas.jsonl` → animación del agujero de arriba (sección anterior).
- **Permisos:** tokens `olimpo-app`, `instinct`, `laura` y `aurora` con `tele:*` y `bandeja:*`; `olimpo-app` además
  `accesos:administrar` (Ajustes › Accesos de agentes, cambios con PIN en el móvil y auditoría). En la Pi también:
  `python -m horas.tokens permisos <id> --añadir … --quitar …`.
- **Laura:** tool `assistant/laura/tools/tele.py` (estado, pausar, reanudar, volumen, saltar, ir a minuto) sobre `cast-helper`, sin pasar
  por Olimpo. Su servicio apunta a `~/proyectos/LinuxRicing/assistant` (antes `~/LinuxRicing`, que no existe, y estaba en bucle 203/EXEC).
- **Aurora:** skill `tele` en su repo (instalada en `~/.hermes/skills/productivity/tele/`), llama a Horas local en la Pi con `aurora.token`.

## Historia (2026-11-08/09)

1. VLC 3 se congelaba con el MKV Dolby → conversión puntual a MP4/AAC y `catt cast`.
2. `cast-helper` (transcodifica solo el audio al vuelo, MPRIS) + tarjeta del panel rápido (reposo compacto / mini-reproductor).
3. Portales al arrastrar: zona en el borde → portales con `drag-watch` → rediseño con mockup interactivo (variantes A/B) → variante B
   en shader → feedback de tamaño/progreso/cancelar → animación de salida.
4. Olimpo v2.11–v2.14: tele en el móvil, bandejas en ambos sentidos, Ajustes, reproductor «Aurora».
5. Espejo: fMP4 (~4 s medidos) → HLS 0,5 s (2,5 s medidos) → Cast Streaming con openscreen (~0,12 s vídeo / ~0,16 s audio emisor→receptor, con audio desde `d3f0bea`).
