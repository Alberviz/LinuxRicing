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

- Prueba de punta a punta contra el Chromecast (cast, subtítulos en el receptor, seek en transcode, URL).
- Textos de la tarjeta sin `Tr.tr`.
- Si hay varios reproductores MPRIS, el dashboard muestra el `defaultPlayer`/primero; quizá priorizar casthelper.

## Portales de arrastre (agujeros negros en los bordes)

Al arrastrar un archivo desde el gestor de archivos o el navegador aparecen dos mini agujeros negros
(estilo Gargantua del escritorio) en los bordes de la pantalla; crecen al acercar el cursor y se abren
al entrar en la banda del borde:

- **Borde derecho -> tele:** `cast-helper cast <dispositivo elegido> <ruta|url>` (vía `Cast.run`).
- **Borde superior -> móvil:** `olimpo enviar <ruta>` (CLI en `~/proyectos/olimpo/cli/olimpo` o
  `~/.local/bin/olimpo`; responde JSON `{"ok":...}`). Si no existe: «Envío al móvil aún no disponible».

Al soltar, el archivo cae en espiral, se muestra «Enviando…» y luego el resultado, y todo se recoge.

| Pieza | Dónde | Qué hace |
|---|---|---|
| `drag-watch` | `widgets/drag-watch` -> `~/.local/bin/` + `systemd/drag-watch.service` | Daemon: detecta botón izquierdo mantenido + >40 px de desplazamiento + ventana activa de gestor de archivos/navegador (`DRAG_WATCH_CLASSES`, `DRAG_WATCH_THRESHOLD`). Publica `$XDG_RUNTIME_DIR/drag-watch.sock` (JSON por línea; posición ~30 Hz solo durante el arrastre). Duerme en `select()` en reposo. |
| `DragWatch.qml` | `services/` | Cliente del socket (`dragging`, `cx`, `cy`). |
| `Portals.qml`, `Portal.qml` | `modules/portals/` | Ventana layer-shell overlay a pantalla completa, **sin input** salvo las bandas de ~140 px mientras dura el arrastre (Wayland solo entrega el DnD a la superficie bajo el cursor). Sin shaders ni gradientes radiales. |

Requisitos y límites: usuario en el grupo `input` (lee `/dev/input/event*`); solo detecta pulsaciones
físicas de botón (el tap-to-drag del touchpad no genera BTN_LEFT en evdev); sin hotplug de ratones
(reiniciar el servicio). Prueba sin arrastrar: `drag-watch sim <x> <y>` / `drag-watch sim off`.

## Proyectar la pantalla (Super+K) — modo espejo

- **Atajo:** `Super+K` abre el panel «Proyectar» (abajo a la derecha): lista de Chromecasts, tocas uno y empieza a proyectar.
  Con 2 monitores hay un selector de pantalla (se recuerda en `~/.config/caelestia/cast-last-monitor`). Proyectando:
  «Proyectando en X», conmutador del audio del sistema y «Desconectar». Esc o clic fuera lo cierra.
  El antiguo `Super+K` (mostrar todos los paneles, `caelestia:showall`) pasa a `Super+Shift+K`.
  También: `qs -c caelestia ipc call castPanel toggle`. Mientras se emite hay un icono rojo `cast_connected` en la barra (privacidad).
- **Backend:** `cast-helper mirror start [--device D] [--monitor M] [--no-audio]`, `mirror stop`, `mirror audio on|off`,
  `mirror monitors`. Pipeline: `gpu-screen-recorder -w <salida> -k h264 -bm cbr -q 6000 -keyint 1 -c mpegts` (NVENC/VAAPI según GPU)
  -> `ffmpeg -c copy -bsf:a aac_adtstoasc -f mp4 -movflags frag_keyframe+empty_moov+default_base_moof` -> HTTP del helper (`:45114`,
  fMP4 sin Content-Length, `stream_type=LIVE`). 1080p30 (si la salida es mayor se escala a 1920x1080), vídeo 6 Mbps, audio AAC 128k
  del monitor por defecto de PipeWire. `state.json`: `active.mode = "mirror"`, `active.monitor`, `active.audio`; y `monitors: [{name,width,height}]`.
  Notas: gpu-screen-recorder necesita la pantalla encendida (con DPMS apagado no lista ni captura monitores); cambiar el audio reinicia el flujo.
- **Latencia:** formato fMP4 progresivo (el Default Media Receiver acepta LIVE con este contenedor). No se ha podido medir con
  reloj en pantalla desde el PC; hay que mirar un cronómetro en pantalla vs. la tele (se espera ~3–5 s por el búfer del receptor).

## Cambiar subtítulos y audio en reproducción

- Al hacer `cast` se cargan TODAS las pistas de texto (incrustadas -> VTT, externas `<base>*.srt|vtt`) como `MediaTrack`; solo se activa la elegida.
  `cast-helper subs <n|off>` cambia la pista sin recargar (EDIT_TRACKS_INFO). `cast-helper audio <n>` recarga en la posición actual
  (en transcode relanza ffmpeg con esa pista; en direct pasa a transcode si no es la primera).
- Contrato en `state.json`, dentro de `active`:
  `tracks: {subs:[{n,label,lang,forced}], audio:[{n,label,lang,codec,channels}], sub_active:n|null, audio_active:n}`
  (`n` de subtítulos = índice de stream, o `1000+i` para externos; `n` de audio = índice de stream). `tracks` es `null` en `url` y `mirror`.
- La tarjeta del panel rápido tiene un chip de subtítulos y otro de audio que abren un menú con las pistas + «Desactivados».

## Agujero blanco (llegadas desde el móvil)

El puente de Olimpo añade una línea JSON por archivo recibido a `$XDG_RUNTIME_DIR/olimpo-puente/llegadas.jsonl`
(`{"ruta","nombre","tamano","mime","ts"}`). `modules/whitehole/WhiteHole.qml` lo vigila con `tail -n 0 -F` (cero coste en reposo): un agujero
blanco aparece en el borde superior (shader `whitehole.frag`: núcleo incandescente, disco frío inclinado con Doppler, chorro relativista, onda),
expulsa el archivo en arco y lo posa como tarjeta (miniatura real si es imagen). Clic: abrir; botón derecho: mostrar en carpeta;
~8 s o hasta que el ratón se va. Ráfaga escalonada (máx. 5 tarjetas a la vez). Prueba: `qs -c caelestia ipc call whitehole demo <ruta>`.
