# Plan de Implementación: Curador de Playlists con IA y Sincronización YouTube

**Fecha:** 2026-11-09  
**Diseño de referencia:** `docs/plans/2026-11-09-curador-playlists-ia-design.md`  
**Estado:** Listo para ejecución tras aprobación de Alberto  

---

## Tareas

### Tarea 1: Ampliar `widgets/spotify-tele` con soporte de Playlists vía CDP
- [ ] **1.1. Inyectar funciones JS para `PlaylistAPI` y `RootlistAPI`:**
  - `createPlaylist(name, description, isPublic)` utilizando `P.RootlistAPI.createPlaylist()`.
  - `addToPlaylist(playlistUri, trackUris)` utilizando `P.PlaylistAPI.add()`.
  - `removeFromPlaylist(playlistUri, trackUris)` utilizando `P.PlaylistAPI.remove()`.
  - `getPlaylistTracks(playlistUri)` utilizando `P.PlaylistAPI.getContents()`.
- [ ] **1.2. Añadir subcomando `playlist` al parser argparse:**
  - `spotify-tele playlist crear <nombre> [--descripcion <texto>]`
  - `spotify-tele playlist anadir <playlist> <canciones...>`
  - `spotify-tele playlist quitar <playlist> <canciones...>`
  - `spotify-tele playlist ver <playlist>`
  - `spotify-tele playlist listar` (listado de playlists del usuario en la biblioteca)
- [ ] **1.3. Pruebas manuales:**
  - Crear una playlist de prueba en Spotify Desktop y verificar que aparece al instante.
  - Añadir 2 o 3 canciones por nombre resolviéndolas con la búsqueda GraphQL.

### Tarea 2: Implementar la sincronización desde YouTube (`sync-youtube`)
- [ ] **2.1. Integrar extracción de canciones con `yt-dlp`:**
  - Ejecutar `yt-dlp --flat-playlist -J "<url>"` para parsear títulos y autores en streaming JSON.
- [ ] **2.2. Algoritmo de resolución y deduplicación:**
  - Comprobar los temas ya presentes en la playlist de Spotify para evitar duplicados.
  - Resolver cada tema nuevo en Spotify buscando por `f"{artista} {titulo}"` (filtrando sufijos como "(Official Music Video)", "HD", etc.).
  - Enviar las URIs encontradas a `P.PlaylistAPI.add()` en bloques.
- [ ] **2.3. Subcomando en el CLI:**
  - `spotify-tele playlist sync-youtube <playlist_spotify> <url_youtube>`

### Tarea 3: Integración en Laura (`assistant/laura/tools/`)
- [ ] **3.1. Crear o ampliar tool en `assistant/laura/tools/spotify.py`:**
  - Registrar acciones de lenguaje natural: `crear_playlist`, `anadir_a_playlist`, `sincronizar_youtube`.
  - Configurar esquemas de parámetros e iconos.
- [ ] **3.2. Probar con llamadas simuladas y evaluar respuestas en el asistente:**
  - Verificar que Laura procesa comandos como: *"Crea una lista llamada Chillout y mete 3 canciones"* o *"Sincroniza mi lista de YouTube con Spotify"*.

### Tarea 4: Documentar en Backlog y guía de uso para agentes
- [ ] **4.1. Registrar la tarea en `vault/Backlog/`** según las normas del repositorio.
- [ ] **4.2. Documentar ejemplos de invocación para agentes (Antigravity/Claude)** en `docs/PLAYLISTS_IA_Y_SYNC.md` o en la wiki interna.
