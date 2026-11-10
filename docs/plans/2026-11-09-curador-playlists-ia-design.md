# Diseño Técnico: Curador de Playlists con IA y Sincronización YouTube ↔ Spotify

**Fecha:** 2026-11-09  
**Autor:** Antigravity  
**Estado:** Propuesto (Pendiente de aprobación de Alberto)  
**Área:** `multimedia` / `asistente` / `agentes`

---

## 1. Contexto y Objetivos

### El problema
1. **Descontinuación de BitChord Desktop:** BitChord ha abandonado el soporte para Linux/PC y su versión PWA carece de soporte para enviar a la tele (Cast) y de APIs para ser controlada por IAs locales.
2. **Limitaciones de Spotify Free:** Alberto utiliza Spotify con cuenta gratuita en PC y tele. La API oficial para desarrolladores de Spotify (`developer.spotify.com`) está bloqueada para cuentas gratuitas:
   - Exige una suscripción **Spotify Premium** activa para el dueño de la app en modo desarrollo (`403 Forbidden: Active premium subscription required for the owner of the app`).
   - Los endpoints de control de reproducción y dispositivos exigen `PREMIUM_REQUIRED`.
3. **Fragmentación de listas:** En el móvil se utiliza YouTube/YouTube Music (por versatilidad y ausencia de restricciones móviles de reproducción), mientras que en el salón/PC se usa Spotify y Chromecast. Mantener las listas sincronizadas manualmente es una molestia.
4. **La visión de Alberto:** Poder pedirle a **cualquier agente (Laura, Antigravity, Claude)** con lenguaje natural:  
   *«Hazme una playlist cogiendo canciones de aquí y de allá, mezcla tal género con este otro y ponlo en mi cuenta»* o *«sincroniza mi lista de YouTube con Spotify»*, y que la playlist se materialice de verdad en su cuenta.

---

## 2. Descubrimiento Clave en el Sistema Actual

El repositorio ya cuenta con una herramienta excepcional: **`widgets/spotify-tele`** (desarrollada para Laura y el escritorio):
- Controla el cliente oficial de Spotify en Linux mediante **Chrome DevTools Protocol (CDP)** en el puerto `127.0.0.1:9222` (habilitado en `~/.config/spotify-flags.conf`).
- Tiene acceso a las APIs internas de la sesión activa de Spicetify (`Spicetify.Platform`).
- **Verificación en vivo:** Hemos inspeccionado en tiempo real la instancia de Spotify en ejecución y se ha confirmado que las APIs internas de listas están disponibles:
  - `Spicetify.Platform.PlaylistAPI`: métodos `add`, `remove`, `getContents`, `getPlaylist`, `updateDetails`.
  - `Spicetify.Platform.RootlistAPI`: método `createPlaylist`.
  - `Spicetify.GraphQL`: búsqueda interna de canciones, álbumes y artistas con el cliente de escritorio.
  - `Spicetify.CosmosAsync`: mutaciones de red con el token de sesión de la app de escritorio.
- **Resultado:** **NO se necesita Spotify Premium ni API keys de desarrollador**. Al ejecutarse a través de la sesión de escritorio ya iniciada, se pueden crear, leer y modificar playlists de forma totalmente gratuita y local.
- **`yt-dlp`** ya está instalado en el sistema (`~/.local/bin/yt-dlp`) y permite extraer metadatos de cualquier playlist de YouTube en JSON al instante.

---

## 3. Arquitectura de la Solución

```
                ┌────────────────────────────────────────────────────────┐
                │             Entrada de Usuario / Lenguaje Natural       │
                └───────────────────────────┬────────────────────────────┘
                                            │
                     ┌──────────────────────┴──────────────────────┐
                     ▼                                             ▼
        ┌──────────────────────────┐                  ┌──────────────────────────┐
        │  Asistente Laura (Voz)   │                  │  Agentes (Antigravity,   │
        │  assistant/laura/tools/  │                  │  Claude, CLI terminal)   │
        └────────────┬─────────────┘                  └────────────┬─────────────┘
                     │                                             │
                     └──────────────────────┬──────────────────────┘
                                            │ Invoca CLI
                                            ▼
                    ┌──────────────────────────────────────────────┐
                    │      widgets/spotify-tele (Subcomando)       │
                    │               `playlist`                     │
                    └───────┬──────────────────────────────┬───────┘
                            │                              │
                            ▼ CDP (puerto 9222)            ▼ Subproceso local
               ┌──────────────────────────┐  ┌──────────────────────────┐
               │    Spotify Desktop       │  │          yt-dlp          │
               │ (Spicetify.Platform)     │  │ (Lectura de listas YT    │
               │ - PlaylistAPI.add        │  │  públicas / no listadas) │
               │ - PlaylistAPI.remove     │  └──────────────────────────┘
               │ - RootlistAPI.create     │
               └────────────┬─────────────┘
                            │
                            ▼
               ┌──────────────────────────┐
               │   Playlist en Spotify    │
               │ (Lista para PC o Tele)   │
               └──────────────────────────┘
```

---

## 4. Diseño del CLI (`spotify-tele playlist`)

Ampliación del script existente `widgets/spotify-tele` para añadir el subcomando `playlist`:

### Comandos propuestos

1. **Crear playlist:**
   ```bash
   spotify-tele playlist crear "Nombre de la Lista" [--descripcion "Creada por IA"] [--publica/--privada]
   ```
   *Salida JSON:* `{"ok": true, "uri": "spotify:playlist:...", "nombre": "..."}`

2. **Añadir canciones a playlist:**
   ```bash
   spotify-tele playlist anadir "Nombre o URI de playlist" "Canción 1 - Artista" "Canción 2 - Artista" ...
   ```
   *Comportamiento:* Resuelve cada canción mediante la búsqueda GraphQL de Spicetify, obtiene sus URIs y ejecuta `P.PlaylistAPI.add(playlistUri, trackUris)`.

3. **Quitar canciones de playlist:**
   ```bash
   spotify-tele playlist quitar "Nombre o URI de playlist" "Canción a borrar"
   ```

4. **Ver contenido de playlist:**
   ```bash
   spotify-tele playlist ver "Nombre o URI de playlist" [--limite 50]
   ```
   *Salida JSON:* lista de temas con título, artista, duración y URI.

5. **Sincronizar desde YouTube:**
   ```bash
   spotify-tele playlist sync-youtube "Nombre de Playlist en Spotify" "https://www.youtube.com/playlist?list=..."
   ```
   *Comportamiento:*
   - Lanza `yt-dlp --flat-playlist -J "<url>"` para obtener títulos y autores.
   - Lee los temas actuales de la playlist de Spotify para no duplicar.
   - Resuelve en Spotify las canciones nuevas que falten y las añade en bloque.

---

## 5. Integración con Agentes y con Laura

### A. Para Agentes de Codificación / IA (Antigravity, Claude, terminal)
Cualquier agente con acceso a la shell puede:
1. Recibir la orden creativa del usuario: *«Crea una playlist llamada "Cyberpunk Focus" con 15 canciones que mezclen synthwave oscuro y ambient industrial»*.
2. El agente genera el listado de 15 títulos y artistas.
3. El agente ejecuta:
   ```bash
   spotify-tele playlist crear "Cyberpunk Focus" --descripcion "Mix curado por IA"
   spotify-tele playlist anadir "Cyberpunk Focus" "Perturbator - Future Club" "Carpenter Brut - Turbo Killer" ...
   ```
4. El agente devuelve el enlace o confirmación a Alberto.

### B. Para Laura (`assistant/laura/tools/`)
Se amplía la herramienta `spotify.py` (o se añade `playlists.py`) con las acciones:
- `crear_playlist`: `{"accion": "crear_playlist", "nombre": "...", "canciones": [...]}`
- `anadir_a_playlist`: `{"accion": "anadir_a_playlist", "playlist": "...", "cancion": "..."}`
- `sincronizar_youtube`: `{"accion": "sincronizar_youtube", "playlist_spotify": "...", "url_youtube": "..."}`

Cuando Alberto hable con Laura por voz:
*«Laura, añade la canción que está sonando a mi playlist de Favoritos»* o *«Laura, sincroniza mi lista del móvil de YouTube con la de Spotify»*, Laura ejecuta la tool directamente.

---

## 6. Ventajas de esta Arquitectura

1. **Coste 0€ y sin restricciones:** Funciona íntegramente con Spotify Free porque aprovecha la sesión del cliente de escritorio ya logueado.
2. **Sin dependencias frágiles:** Reutiliza el socket CDP que ya funciona perfectamente para mandar música a la tele y pausar/reproducir.
3. **Universal:** La misma herramienta sirve para Laura (asistente de voz), para agentes LLM en terminal y para el propio Alberto desde la línea de comandos.
4. **Resuelve el problema de las dos playlists:** Permite que YouTube siga siendo el reproductor en el móvil mientras que Spotify se mantiene al día en el ordenador y en la tele.
