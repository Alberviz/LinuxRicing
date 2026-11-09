---
fileClass: Backlog
tipo: tarea
estado: hecha
prioridad: 2
area: multimedia
origen: Alberto
esfuerzo: M
creado: 2026-11-09
tags:
  - backlog
---

# Curador de playlists con IA y sincronización con YouTube

Permitir que **Laura y agentes de codificación (Antigravity, Claude)** puedan crear, modificar y
curar playlists en Spotify a partir de peticiones en lenguaje natural (*«hazme una playlist que
mezcle X con Y…»*), así como **sincronizar playlists entre YouTube (móvil) y Spotify (PC/Tele)**.

## Solución técnica diseñada

Dado que la API oficial de desarrolladores de Spotify (`developer.spotify.com`) exige una
suscripción de pago **Spotify Premium** para apps en modo desarrollo (`403 Forbidden`), la
solución aprovecha la infraestructura ya existente en el repositorio:

- **CLI `spotify-tele` (`widgets/spotify-tele`):** Ya controla Spotify Desktop mediante Chrome
  DevTools Protocol (CDP, puerto 9222) usando Spicetify.
- Se amplía con el subcomando `playlist` para interactuar con `Spicetify.Platform.PlaylistAPI`
  (`add`, `remove`, `getContents`) y `Spicetify.Platform.RootlistAPI` (`createPlaylist`).
  **Funciona con Spotify Free sin coste ni API keys.**
- **Sincronización con YouTube:** Utiliza `yt-dlp` (ya instalado en `~/.local/bin/yt-dlp`) para
  extraer canciones de listas de YouTube y mapearlas a URIs de Spotify mediante búsqueda GraphQL.
- **Integración con Laura:** Nueva tool o ampliación de `assistant/laura/tools/spotify.py`.
- **Integración con agentes:** Subcomando CLI con salida estándar en JSON.

Documentos de diseño y plan en `docs/plans/`:
- `docs/plans/2026-11-09-curador-playlists-ia-design.md`
- `docs/plans/2026-11-09-curador-playlists-ia.md`
