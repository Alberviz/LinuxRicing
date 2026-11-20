# Elysium × Spotify

Integración de Spotify dentro del modo consola de Elysium: control por mando y teclado, carátulas integradas en el menú, biblioteca de playlists a pantalla completa, mini-reproductor flotante encima de los juegos, píldoras de cambio de canción, tarjeta en la pantalla de apoyo del portátil y limbo del planeta reactivo al audio.

## Cómo se usa

### 1. En el menú principal de Elysium (`ElysiumConsole.qml`)

La tarjeta **Spotify** aparece en la fila principal justo después de los juegos y antes de las tarjetas de sistema:

- Con música cargada: muestra la carátula del disco a sangre con un velo oscuro sutil y un ecualizador animado de 3 barras en la esquina inferior derecha (se detiene al pausar).
- Sin reproducción activa: muestra el glifo `album`.
- Al seleccionarla, el fondo difuminado (`heroArt`) muestra la carátula actual y el héroe presenta la etiqueta `AHORA SUENA · <dispositivo>` (`PC`, `Comedor`, etc.), título, artista · álbum, barra de progreso y pistas de mando:

| Botón | Acción |
|---|---|
| **A** / **Start** | Play / Pausa (si no suena nada, abre la Biblioteca) |
| **LB** / **RB** | Canción anterior / siguiente |
| **X** | Me gusta / quitar Me gusta (`♥`) |
| **Y** | Abrir la **Biblioteca** de playlists |

En teclado (consola abierta): `Espacio`/`Intro` (A), `Retroceso` (B), `X` (Me gusta), `Y` (Biblioteca), `[` / `]` (LB / RB), `←` / `→` (navegar).

### 2. Biblioteca de playlists (`SpotifyLibrary.qml`)

Vista a pantalla completa sobre un velo oscuro:

- Lista las playlists personales obtenidas de `spotify-tele playlist listar` como tarjetas cuadradas en fila horizontal (portada si el CLI la aporta o degradado del acento con la inicial cuando no la hay).
- Si Spotify no está abierto al abrir la Biblioteca, muestra un aviso legible con **A** para abrir Spotify y cargar las playlists sin bloquear la interfaz.

| Botón | Acción |
|---|---|
| **←** / **→** | Moverse por las playlists |
| **A** / **Start** | Poner la playlist seleccionada (`spotify-tele poner "<uri>" --tipo playlist --donde actual`) o abrir Spotify |
| **B** / **Y** / **Home** | Volver al menú |

### 3. Mini-reproductor durante el juego (`MusicHud.qml`)

Ventana flotante en la esquina superior derecha de la pantalla activa (`elysium.consoleScreen`, margen 40 px) sin foco de teclado (`WlrKeyboardFocus.None`) y con máscara `Region` restringida a la tarjeta para no interceptar clics fuera:

- Se abre y se cierra en cualquier momento (jugando o desde cualquier sitio) con el acorde **LB + ↓**.
- Mientras está visible, toma el mando en exclusiva (`padGrab` → `grab` en `gamepad-watch`) para que los botones no lleguen al juego.
- Se cierra automáticamente a los **6 s** sin actividad, mostrando un aro en el borde que se vacía y se recarga al pulsar cualquier botón.

| Botón | Acción |
|---|---|
| **A** / **Start** | Play / Pausa |
| **LB** / **RB** | Anterior / Siguiente |
| **↑** / **↓** | Subir / bajar volumen de Spotify (`spotify-tele control subir/bajar`) |
| **X** | Me gusta |
| **B** o **LB + ↓** | Cerrar y soltar el mando |

### 4. Píldora de cambio de canción (`TrackToast.qml`)

Aparece abajo a la izquierda de la pantalla del juego durante **4 s** (entrando desde la izquierda, click-through) cuando cambia la canción mientras hay un juego en marcha (`playing && !consoleShown && !musicHudVisible`) y la preferencia `trackToasts` está activa (activada por defecto en `~/.local/state/caelestia/elysium.json`).

### 5. Pantalla de apoyo en el portátil (`ElysiumCompanion.qml`)

Incluye una tarjeta compacta **Ahora suena** (`NowPlaying.qml`) encima de **Avisos** con carátula (o disco concéntrico si no hay carátula), dispositivo, barra de progreso y botones táctiles/ratón clicables (**⏮**, **⏯**, **⏭**).

### 6. Ambiente espacial y planeta reactivo

- **Planeta que escucha (`ElysiumConsole.qml`):** cuando el menú es visible y suena Spotify, activa `Audio.cava` mediante `ServiceRef` (dentro de un `Loader` gateado) y modula la opacidad de los `GlowArc` del limbo con la media de las primeras 4 bandas graves (±35 % suavizado a 120 ms).
- **Ambiente propio (`Elysium.qml`):** `musicWanted` pasa a `false` mientras suena Spotify, fundiendo suavemente el ambiente espacial de Elysium y reanudándolo cuando Spotify se pausa.

## Cómo funciona por dentro

### Fuentes de datos y control

- **MPRIS (`services/Players.qml`):** busca el reproductor cuya identidad contenga `spotify` (`Players.list.find(...)`), o `Players.active` como respaldo. Lee título, artista, álbum, estado, duración, posición y carátula (`Players.getArtUrl`). Un `Timer` de 1 s llama a `positionChanged()` solo cuando el reproductor está sonando y alguna superficie de música está visible.
- **CLI (`~/.local/bin/spotify-tele`):** todas las operaciones que MPRIS no cubre se lanzan de forma asíncrona mediante `Process`:
  - `spotify-tele estado` (sin arrancar Spotify): consulta dispositivo activo (`PC` si coincide con `/etc/hostname`, o nombre remoto como `Comedor`) y estado de `me_gusta`.
  - `spotify-tele control <alternar|siguiente|anterior|subir|bajar|me_gusta|no_me_gusta>` (encolado secuencial de 1 ranura para evitar colisiones CDP al pulsar rápido).
  - `spotify-tele playlist listar` y `spotify-tele poner "<uri>" --tipo playlist --donde actual`.

### Acordes en `widgets/gamepad-watch` y pruebas

- `widgets/gamepad-watch` registra el estado de `LB` (código `310`). Si llega `↓` (código `545` o eje Y en `EV_ABS`) con `LB` pulsado, emite `chord lb+down` y suprime tanto `btn down` como el `btn lb` al soltar. Si `LB` se suelta sin haberse usado en acorde, emite `btn lb` normalmente.
- `widgets/tests/fake-gamepad.py` incorpora `lb` (`310`), `rb` (`311`) y pasos `chord:<b1>+<b2>` (por ejemplo `chord:lb+down`) para pruebas de punta a punta con `/dev/uinput`.

### IPC de depuración (`target: "elysium"`)

Además de `enter`, `leave`, `pad(b)` y `hold(b)`:

- `qs -c caelestia ipc call elysium chord lb+down` — dispara el acorde.
- `qs -c caelestia ipc call elysium musicHud` — alterna el mini-reproductor.
- `qs -c caelestia ipc call elysium library` — entra en Elysium si hace falta y abre la Biblioteca.
- `qs -c caelestia ipc call elysium trackToast` — muestra la píldora de canción actual durante 4 s (para prueba visual).
- `qs -c caelestia ipc call elysium trackToasts true|false` — activa/desactiva las píldoras automáticas.
- `qs -c caelestia ipc call elysium debug` — incluye `spotifyTitle`, `spotifyArtist`, `spotifyPlaying`, `spotifyDevice`, `musicHudVisible`, `spotifyLibraryOpen` y `trackToastVisible`.

## Archivos implicados

- `widgets/gamepad-watch`
- `widgets/tests/fake-gamepad.py`
- `configs/quickshell/caelestia/modules/elysium/Elysium.qml`
- `configs/quickshell/caelestia/modules/elysium/ElysiumConsole.qml`
- `configs/quickshell/caelestia/modules/elysium/ElysiumCompanion.qml`
- `configs/quickshell/caelestia/modules/elysium/PadGlyph.qml`
- `configs/quickshell/caelestia/modules/elysium/NowPlaying.qml`
- `configs/quickshell/caelestia/modules/elysium/SpotifyLibrary.qml`
- `configs/quickshell/caelestia/modules/elysium/MusicHud.qml`
- `configs/quickshell/caelestia/modules/elysium/TrackToast.qml`
