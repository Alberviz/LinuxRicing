# Elysium × Spotify — diseño y plan de implementación

Autor del diseño: Claude (Opus). Implementa: agente Gemini. Fecha: 2026-11-20.
Rama: `feat/elysium-spotify` (worktree aparte). Módulo: `configs/quickshell/caelestia/modules/elysium/`.

## 1. Idea

En Elysium, la música de Spotify es parte de la consola: se ve, se controla con el mando y se integra con el
«planeta». Hay **cuatro superficies**, de más a menos presencia:

1. **Menú (tele):** una tarjeta **«Spotify»** en la fila, con la carátula del disco que suena como cara de la
   tarjeta. Al seleccionarla, el héroe se convierte en «Ahora suena» y hay una **Biblioteca** para elegir qué poner.
2. **Durante el juego:** el **mini-reproductor** que se abre con **LB + ↓** (como el menú de música de la Switch
   modificada de Alberto), encima del juego, controlable con el mando y que se oculta solo.
3. **Avisos de canción:** cuando cambia la canción mientras juegas (también si se la pide a Laura: «Laura, pon…»,
   «para la música»), una **píldora pequeña** con carátula y título durante 4 s, sin robar el mando.
4. **Pantalla de apoyo (portátil):** tarjeta «Ahora suena» con carátula, progreso y botones táctiles/ratón.

Y un toque de ambiente: **el planeta escucha la música**. En el menú, con Spotify sonando, el resplandor del limbo
del planeta respira con los graves (cava). Y el **ambiente espacial propio de Elysium se apaga solo** (fundido)
mientras suena Spotify, y vuelve cuando se pausa.

Laura ya controla Spotify (tools `spotify` y `control_musica`, CLI `spotify-tele`): no hay que tocar Laura. Todo lo
que haga Laura se ve aquí porque la información sale de MPRIS.

## 2. Fuentes de datos y control

- **Qué suena:** servicio `Players` (`configs/quickshell/caelestia/services/Players.qml`, MPRIS).
  `Players.active` → `trackTitle`, `trackArtist`, `trackAlbum`, `isPlaying`, `position`, `length`, arte con
  `Players.getArtUrl(player)`, y `playPause()`, `next()`, `previous()`. Usar el reproductor cuya identidad sea
  Spotify si existe (`Players.list.find(p => Players.getIdentity(p).toLowerCase().includes("spotify"))`), si no
  `Players.active`. La posición de MPRIS no avanza sola: refrescarla con un Timer (1 s) solo mientras se ve
  (`player.positionChanged()` o leer `position` periódicamente), gateado a visible.
- **Lo demás:** CLI `~/.local/bin/spotify-tele` (también en `widgets/spotify-tele`):
  - `spotify-tele control {alternar|siguiente|anterior|subir|bajar|volumen N|me_gusta|no_me_gusta|aleatorio si/no}`
  - `spotify-tele playlist listar` (comprueba su salida real: JSON o texto, y adáptate)
  - `spotify-tele poner "<nombre o spotify:uri>" --tipo playlist --donde actual`
  - `spotify-tele estado` (JSON; `{"ok": true, "abierto": false}` si el cliente no está abierto)
  - `spotify-tele pasar tele|pc` (cambiar dónde suena: «Comedor» es el Chromecast de la tele)
  Ejecuta siempre con `Process` (nunca bloquear la UI) y muestra estado de carga/errores.
- **Espectro:** `Audio.cava.values` (activar con `ServiceRef { service: Audio.cava }` SOLO mientras se usa).

## 3. Mando

`widgets/gamepad-watch` emite `btn <a|b|x|y|start|select|home|up|down|left|right|lb|rb>` y `hold <select|home>`.
Añadir **acordes**: llevar la cuenta de LB (código 310) pulsado; si llega ↓ (544 o el eje Y de la cruceta/stick)
con LB pulsado → emitir `chord lb+down` y NO emitir el `btn down` suelto. (Otros acordes no hacen falta.)
En `Elysium.qml`, `kind === "chord"` → `handleChord(arg)`.

Mapa:
| Dónde | Botón | Acción |
|---|---|---|
| Jugando (Elysium no visible) | **LB + ↓** | abre/cierra el mini-reproductor |
| Mini-reproductor | A | play/pausa |
|  | LB / RB | anterior / siguiente |
|  | ↑ / ↓ | volumen de Spotify (`spotify-tele control subir/bajar`) |
|  | X | me gusta |
|  | B o LB+↓ | cerrar |
| Menú, tarjeta Spotify seleccionada | A | play/pausa (si no suena nada: abre la Biblioteca) |
|  | LB / RB | anterior / siguiente |
|  | X | me gusta · Y | abre la Biblioteca |
| Biblioteca | ←/→ | moverse por playlists · A | ponerla (`--donde actual`) · B | volver |
| Cualquier sitio en Elysium | LB + ↓ | también abre el mini-reproductor (atajo universal) |

Mientras el mini-reproductor está abierto encima de un juego, el mando es exclusivo de Elysium: reutilizar el
mecanismo de grab que ya existe (`padGrab` → `watcher.write("grab\n")`): ampliar `padGrab` para que también sea
verdadero con el mini-reproductor visible. Se oculta solo a los **6 s sin tocar nada** (y suelta el mando).

## 4. Diseño visual (mismo lenguaje que Elysium)

Reutiliza lo que ya hay: `PadGlyph.qml` (botones dibujados), `LauraStatus.qml` como ejemplo de componente de estado,
`UpdateView.qml`/`UpdateDialog.qml` como ejemplo de vista y diálogo, la paleta `Colours.palette.m3*`, el acento
`m3primary`, `StyledText`, `MaterialIcon`, `Tokens.font.*`, Shapes con `CurveRenderer`, fundidos con `Behavior`.
Nivel: estudio top, nada genérico. Animaciones siempre gateadas a visible (nunca `running: true` fijo).

- **`NowPlaying.qml` (componente reutilizable):** carátula con esquinas redondeadas (`ClippingRectangle` o
  `layer` con máscara), título (title.medium), artista · álbum (body), barra de progreso fina con tiempo
  transcurrido/total, y opcionalmente fila de pistas de mando. Propiedades `compact`, `showHints`. Si no hay
  carátula, un disco dibujado (círculos concéntricos) con el acento.
- **Tarjeta «Spotify» en la fila del menú:** cara = carátula a sangre (con un velo sutil y un ecualizador de 3
  barritas animado abajo a la derecha cuando suena, que se para si está en pausa). Sin música: glifo `album`.
  Ponerla justo después de los juegos y antes de las tarjetas de sistema.
- **Héroe con la tarjeta Spotify:** etiqueta «AHORA SUENA · <dispositivo>» (PC o Comedor), título grande,
  artista · álbum, barra de progreso ancha, y fila de pistas (A ⏯, LB/RB, X ♥, Y Biblioteca). Si no suena nada:
  «Spotify» + «Nada sonando · A para elegir música».
- **Arte gigante desenfocado de fondo** (el `heroArt` del menú) = la carátula cuando la tarjeta Spotify está
  seleccionada (igual que con los juegos).
- **Biblioteca (`SpotifyLibrary.qml`):** vista a pantalla completa como `UpdateView` (velo oscuro): título
  «Biblioteca», fila horizontal de playlists como tarjetas cuadradas (portada si el CLI la da; si no, degradado del
  acento con la inicial), la seleccionada más grande con el nombre debajo, cargando con un shimmer suave; error
  legible si Spotify no está abierto (con «A para abrir Spotify» si el CLI lo permite).
- **Mini-reproductor durante el juego (`MusicHud.qml`):** ventana `PanelWindow` capa `Overlay` en la pantalla del
  juego (`elysium.consoleScreen` o donde esté el juego), esquina superior derecha, margen 40 px, **sin foco de
  teclado** (`WlrKeyboardFocus.None`), `mask` solo de la tarjeta para no bloquear clics fuera. Tarjeta de cristal
  oscuro (m3surfaceContainer al 92 %, borde acento suave) de ~460×150: carátula 110 px, textos, progreso y una fila de
  pistas. Entrada: desliza 40 px desde arriba + fundido (OutExpo 380 ms); salida al revés. Un aro de 6 s se va
  vaciando en el borde (tiempo hasta ocultarse) y se recarga al pulsar.
- **Píldora de cambio de canción (`TrackToast.qml`):** abajo a la izquierda de la pantalla del juego, carátula 48 px
  + título/artista, 4 s, entra deslizando desde la izquierda. Solo si hay un juego jugándose y el mini-reproductor
  no está abierto. Preferencia `trackToasts` (por defecto sí).
- **Pantalla de apoyo (`ElysiumCompanion.qml`):** tarjeta «Ahora suena» (NowPlaying compacto) encima de «Avisos»,
  con botones ⏮ ⏯ ⏭ clicables.
- **Planeta que escucha (`ElysiumConsole.qml`):** con Spotify sonando y el menú visible, la opacidad del resplandor
  del limbo (los `GlowArc` del planeta) se modula con la energía de las bandas graves de cava (media de las primeras
  barras, suavizada con un `Behavior` de 120 ms; rango sutil, ±35 % del valor base). Activar cava solo en ese caso.
- **Ambiente propio:** en `Elysium.qml`, `musicWanted` debe ser falso mientras el reproductor de Spotify esté sonando
  (fundido ya existente).
- **Sonidos:** usar `elysium.sfx(...)`: «dialog» al abrir mini-reproductor/biblioteca, «back» al cerrar,
  «select» al poner una playlist, «toggle_on» con me gusta, «move» al moverse. No añadir sonidos nuevos.

## 5. IPC (para probar sin mando)

En el `IpcHandler` de `Elysium.qml` (target `elysium`): `chord(c)` (simula `chord lb+down`), `musicHud()`
(alternar), `library()`. Ya existen `pad(b)`, `hold(b)`, `debug()`, `enter()`, `leave()`. Añade a `debug()` el estado
de Spotify (título, isPlaying, hud visible).

## 6. Pruebas obligatorias (en el sistema real)

- Arrancar/parar Spotify desde la UI (si no está abierto, el CLI lo abre) y ver título/carátula correctos.
- Menú: tarjeta Spotify con carátula y ecualizador; A pausa/reanuda; RB siguiente; Biblioteca lista playlists y A pone
  una; capturas con `grim -o HDMI-A-1` (la tele) y `grim -o eDP-2` (portátil).
- Mini-reproductor: con un juego abierto (o simulando `playing` con una ventana de prueba si no se puede lanzar el
  juego), `qs -c caelestia ipc call elysium chord lb+down` lo abre; A/LB/RB/↑/↓/X funcionan; se oculta solo a los 6 s y
  suelta el mando. Hay un mando virtual para pruebas: `python3 widgets/tests/fake-gamepad.py "<guion>"` (ver su
  cabecera; añade soporte de LB/RB y del acorde si hace falta).
- Píldora al cambiar de canción durante el juego.
- `qs -c caelestia log` sin errores de los archivos tocados.

## 7. Reglas (no negociables)

- Trabaja SOLO en el worktree `~/proyectos/LinuxRicing-spotify` (rama `feat/elysium-spotify`). Commits en español con
  `Co-Authored-By: Gemini <noreply@google.com>`. Sin merge ni push.
- **No interrumpas a Alberto si está jugando:** antes de desplegar en `~/.config/quickshell/caelestia/` o reiniciar el
  shell, comprueba `hyprctl clients -j | grep -q ProjectHookshot`; si hay juego abierto, ESPERA (reintenta cada 60 s).
  Tampoco llames a `elysium leave/enter` ni simules botones con un juego abierto.
- Tras cada cambio de QML: copia a `~/.config/quickshell/caelestia/modules/elysium/` y reinicia el shell con
  `caelestia shell -k 2>/dev/null; sleep 1; (caelestia shell -d >/dev/null 2>&1 &)`; nunca te fíes de la recarga en
  caliente. Revisa `qs -c caelestia log | tail -40`.
- No toques otros módulos salvo `widgets/gamepad-watch`, `widgets/tests/fake-gamepad.py` y lo necesario en
  `services/` si de verdad hace falta (explícalo). No toques Laura ni `spotify-tele` (si le falta algo, dilo en el
  resumen).
- No muevas el ratón ni hagas clic con ydotool (el cursor es compartido).
- Al final: `docs/ELYSIUM-SPOTIFY.md` (cómo se usa y cómo funciona) y un resumen con qué probaste y qué no.
