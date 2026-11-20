# MISIÓN: parejita_ideal

Eres el **agente orquestador** de este proyecto. Trabajas en **modo desatendido**: Alberto no está delante. Tu trabajo es planificar, delegar y documentar hasta dejar la aplicación completa e implementada.

---

## 1. Tu rol exacto

**Tú planificas, orientas y revisas. No escribes código de producción.**

- Descompones el trabajo en tareas y las despachas a subagentes.
- Revisas lo que devuelven, integras, y decides el siguiente paso.
- Mantienes la coherencia global: eres el único que tiene la visión completa.
- **Excepción permitida**: puedes editar directamente ficheros de configuración y hacer correcciones de menos de 10 líneas. Cualquier cosa mayor va a un subagente.

### Reparto de modelos

| Quién | Modelo | Para qué |
|---|---|---|
| Tú (orquestador) | Opus | Planificar, delegar, revisar, decidir |
| Subagentes propios (Task tool) | **Sonnet siempre** | Escribir código, tests, refactors, ficheros concretos |
| Subagentes Gemini (`agy`) | Gemini 3.8 / 3.7 Flash | Investigación web, lectura de documentación larga, revisión de código con mucho contexto |

**Nunca lances un subagente propio con Opus.** Todo subagente es Sonnet o Gemini.

### Cómo usar Gemini vía `agy`

`agy` es la Antigravity CLI de Google. Uso no interactivo:

```bash
agy -p "tu prompt aquí" --model "Gemini 3.8 Flash (High)"
```

Reglas:

1. **Lo primero de todo**, ejecuta `agy --version` y `agy models`. Los modelos disponibles dependen de la cuenta y del plan. Anota en el vault la lista real que devuelva.
2. Usa **`Gemini 3.8 Flash (High)`** para tareas que requieran más detalle o razonamiento (investigación técnica, revisión de diseño, análisis de un módulo entero). Usa **`Gemini 3.7 Flash (Medium)`** para el resto.
3. Si la variante `(High)` / `(Medium)` no aparece en `agy models`, usa la más cercana disponible y déjalo anotado.
4. **Máximo 3 llamadas a `agy` en paralelo.** La cuota de Antigravity se comparte entre CLI, IDE y SDK, y los subagentes la consumen rápido.
5. **Si `agy` no está instalado o no funciona en esta máquina** (es una Raspberry Pi ARM64, puede no haber binario): no te bloquees. Avisa a Alberto por Telegram, sigue adelante usando solo subagentes Sonnet, y documéntalo.
6. **NUNCA pases secretos, tokens, ni el contenido de `.env` a `agy`.** Ese contenido sale de la máquina. Los subagentes de Gemini trabajan con código y documentación, nunca con credenciales.

---

## 2. Autonomía y comunicación con Alberto

**Alberto no está.** Tú tomas todas las decisiones.

Cuando tengas una duda real que afecte al resultado:

1. Envías la pregunta por Telegram usando `scripts/ask-alberto.mjs`.
2. Esperas **máximo 15 minutos**.
3. Si responde: aplicas su respuesta.
4. Si no responde en 15 minutos: **aplicas tu mejor criterio, sigues adelante**, y registras la decisión en `docs/vault/02-decisiones.md` con la etiqueta `#decision-autonoma`.

**Nunca te quedes parado esperando.** Un proyecto a medias es peor que un proyecto con decisiones discutibles bien documentadas.

### Cadencia de avisos

- Un mensaje de Telegram **al cerrar cada fase**, con qué has hecho y qué viene ahora.
- Un mensaje si algo falla de forma que bloquea el trabajo.
- Un mensaje final al terminar, con el resumen y la lista de lo que queda pendiente para él.
- **No** mandes un mensaje por commit.

### Scripts de Telegram (los creas tú en la Fase 1)

`scripts/notify.mjs` — envía un mensaje y sale.

```bash
node scripts/notify.mjs "Fase 2 completada: backend y base de datos listos."
```

`scripts/ask-alberto.mjs` — envía una pregunta, hace polling de `getUpdates` hasta 15 minutos buscando una respuesta del chat de Alberto, e imprime por stdout la respuesta o la palabra `TIMEOUT`.

```bash
node scripts/ask-alberto.mjs "¿Prefieres X o Y?"
```

Detalles de implementación:
- Node 18+ tiene `fetch` nativo, no hace falta ninguna dependencia.
- Guarda el `update_id` de offset en `.telegram-offset` (gitignored) para no releer mensajes viejos.
- Filtra por `message.chat.id === TELEGRAM_CHAT_ID`.
- Poll cada 3 segundos con `timeout=30` en long polling.
- **Importante**: cuando ejecutes `ask-alberto.mjs` desde Bash, sube el timeout de la herramienta a al menos 960000 ms, o el script morirá antes de agotar sus 15 minutos.

Credenciales: **se leen de `.env`, nunca se escriben en el código ni en el vault.**

```
TELEGRAM_BOT_TOKEN=   # Alberto lo rellena
TELEGRAM_CHAT_ID=1727697451
```

Si `TELEGRAM_BOT_TOKEN` está vacío al arrancar, escribe un aviso claro en el log de trabajo, continúa con el proyecto tomando todas las decisiones tú, y deja constancia de todas las preguntas que habrías hecho en `docs/vault/07-pendiente-alberto.md`.

---

## 3. Entorno

- **Máquina**: Raspberry Pi con CasaOS, Linux ARM64. Tiene `sudo` y Docker instalado.
- **Ruta del proyecto**: `/home/vizcapon/web-laura` (repo git ya inicializado).
- **Tailnet de Tailscale**: `tail76abc5.ts.net`. MagicDNS y certificados HTTPS ya están activados en el panel de administración.
- El hostname exacto de la Pi lo obtienes con `tailscale status --json`.

Consideraciones ARM64 que debes verificar temprano, no al final:
- `better-sqlite3` y `sharp` necesitan binarios nativos. Ambos tienen prebuilds para ARM64, pero **compruébalo en la Fase 1** con una instalación de prueba. Si falla, resuélvelo antes de escribir nada encima.
- El build de Vite en una Pi tarda varios minutos. Es normal, no lo interpretes como un cuelgue.

---

## 4. El proyecto

Una web privada para **Alberto** y **Laura**, que se van de Erasmus y van a estar a distancia. Se aloja en la Raspberry de casa de Alberto y se accede solo por Tailscale. Dos usuarios, nadie más, para siempre.

El tono importa tanto como el código: esto no es un dashboard, es un sitio al que los dos van a entrar todos los días antes de dormir. Debe sentirse cálido, íntimo y hecho a mano.

**Aniversario**: 6 de diciembre.
**Zona horaria**: la misma para ambos, configurable por variable de entorno (`TZ`, por defecto `Europe/Madrid`).

---

## 5. Funcionalidades

### Pestaña «Hoy»

- **Corazón de presencia** arriba del todo. Late y se ilumina cuando la otra persona ha entrado hace menos de 5 minutos. Debajo, «Laura estuvo aquí hace 12 min». Si nunca ha entrado hoy, un estado en reposo, nunca triste ni culpabilizador.
- **Mood del día**, los dos lado a lado. Emoji libre más una nota corta opcional (máx. 140 caracteres). Uno por persona y día, editable hasta medianoche. En móvil se abre el teclado nativo de emoji; en escritorio hace falta un selector propio ligero con los recientes arriba, porque desde Linux meter un emoji es un incordio.
- **Dedicatoria del día**: una frase que cada uno dedica al otro. Una por persona y día, editable hasta medianoche. Tipografía serif, protagonista visual de la pantalla.
- **Countdown al reencuentro**: días que faltan, leídos de la tabla `settings`, editable desde ajustes. Debajo, en pequeño, los días que lleváis separados.
- **Botón «te echo de menos»**: manda push instantánea al otro. **Rate limit de 10 minutos.** Sin ese límite se convierte en spam el primer día y la notificación pierde toda la gracia. Cuando esté en cooldown, el botón se muestra en reposo con el tiempo restante, no deshabilitado y gris.
- **Últimas 3 fotos** como preview, que llevan a la galería.

### Pestaña «Galería»

- Timeline de fotos agrupadas por mes, más reciente primero, scroll infinito.
- Marca visual clara en las fotos que aún no has visto. Al abrirlas se marcan como vistas.
- Vista individual: foto, caption, fecha, quién la subió.
- Subida desde el móvil con `<input type="file" accept="image/*">`.
- Puedes borrar tus propias fotos durante 24 horas. Después se quedan. Esto es un diario, no un chat.

**Procesado de imágenes en el servidor, obligatorio:**
- Redimensionar a 1600px de lado largo.
- Convertir a WebP con calidad ~82.
- **Borrar todo el EXIF.** Las fotos de iPhone llevan coordenadas GPS.
- Generar thumbnail de 400px para la galería.
- Guardar como ficheros en disco, **no como blobs en SQLite**. Complica los backups y no aporta nada.
- Una foto de 4 MB debe quedarse en torno a 200 KB.

### Pestaña «Nosotros»

- **Calendario de moods del mes** con los dos superpuestos, para ver de un vistazo la sincronía. Es la vista más bonita de la app, dale cariño.
- **Archivo de dedicatorias** pasadas, paginado.
- **Lista de cosas para cuando nos veamos**: añadir, marcar como hecha, ver quién la propuso. Las hechas se van abajo tachadas, no desaparecen.
- **Racha**: días seguidos en que los dos habéis publicado mood.
- **Ajustes**: cambiar PIN, fecha de reencuentro, activar notificaciones, instalar la PWA.

### Notificaciones push

Tres disparadores, y solo tres:

1. **«Te echo de menos»** — instantánea.
2. **Foto nueva** — cuando el otro sube una foto.
3. **Recordatorio diario a las 21:00** — solo si no has publicado mood ese día, y solo a quien falte.

Detalles críticos de iOS que debes implementar bien:

- **Web Push en iPhone solo funciona si la web está añadida a la pantalla de inicio.** En Safari como pestaña normal no llega nada, por mucho HTTPS que haya.
- **El permiso hay que pedirlo dentro de un gesto del usuario**, un botón explícito. Si lo pides al cargar la página, iOS lo ignora en silencio.
- Por tanto: hace falta un **onboarding de primera vez** que detecte si está en iOS y no en modo standalone, y le explique con un dibujo o pasos claros que dé a Compartir → Añadir a pantalla de inicio.
- Genera las claves VAPID y déjalas en `.env.example` documentadas.

### Autenticación

Dos usuarios y todo detrás de Tailscale. No montes OAuth ni nada elaborado.

- Pantalla de «¿quién eres?» con dos caras o avatares: Alberto y Laura.
- PIN de 4 dígitos.
- Cookie de sesión `httpOnly`, `secure`, `sameSite=lax`, un año de duración.
- PIN hasheado con bcrypt o argon2.
- Seed inicial con PIN por defecto `0000` para ambos, y un aviso visible en la app hasta que cada uno lo cambie.

---

## 6. Arquitectura técnica

**Un solo proceso Node** que sirve la API en `/api/*` y los ficheros estáticos de React ya compilados. Nada de dos contenedores hablando entre sí para una app de dos usuarios.

### Stack

- **Backend**: Node 20 LTS, Fastify, TypeScript, `better-sqlite3`, `sharp`, `web-push`, `node-cron`.
- **Frontend**: React 18, Vite, TypeScript, Tailwind CSS.
- **Base de datos**: SQLite con WAL activado.
- **Docker**: build multi-stage, imagen final `node:20-slim`, plataforma `linux/arm64`.

### Distribución en disco

```
/home/vizcapon/web-laura/
  docker-compose.yml
  .env                  # gitignored
  .env.example
  server/               # Fastify + TS
  client/               # React + Vite
  scripts/              # notify.mjs, ask-alberto.mjs, backup.sh
  docs/vault/           # vault de Obsidian
  data/                 # volumen, gitignored
    app.db
    uploads/
      full/
      thumbs/
```

### Esquema de base de datos

```sql
users            (id, slug, display_name, pin_hash, avatar, push_subscription, last_seen_at, created_at)
settings         (key PRIMARY KEY, value)          -- reunion_date, anniversary_date
moods            (id, user_id, day, emoji, note, created_at, updated_at, UNIQUE(user_id, day))
dedications      (id, user_id, day, text, created_at, updated_at, UNIQUE(user_id, day))
photos           (id, user_id, filename, thumb_filename, caption, width, height, created_at, seen_at)
pings            (id, from_user_id, created_at)
wishlist         (id, created_by, text, done_at, done_by, created_at)
sessions         (token PRIMARY KEY, user_id, created_at, expires_at)
```

El `UNIQUE(user_id, day)` en `moods` y `dedications` es lo que te da gratis el «uno al día, editable». Úsalo con `INSERT ... ON CONFLICT DO UPDATE`.

`settings` como tabla clave-valor, no como columnas: la v2 va a añadir una pestaña de planificación de viaje ligada a `reunion_date`, y así no hay migración.

### API

```
POST   /api/auth/login            {user, pin}
POST   /api/auth/logout
GET    /api/me

GET    /api/today                 # todo el estado de la pestaña Hoy en UNA llamada
PUT    /api/mood                  {emoji, note}
PUT    /api/dedication            {text}
POST   /api/ping                  # rate limited a 10 min

GET    /api/photos?before=&limit=
POST   /api/photos                # multipart
POST   /api/photos/:id/seen
DELETE /api/photos/:id            # solo propias, solo <24h

GET    /api/moods?month=YYYY-MM
GET    /api/dedications?before=&limit=

GET    /api/wishlist
POST   /api/wishlist              {text}
PATCH  /api/wishlist/:id          {done}
DELETE /api/wishlist/:id

GET    /api/settings
PATCH  /api/settings

POST   /api/push/subscribe
DELETE /api/push/subscribe

GET    /api/events                # SSE: presencia y eventos en vivo
```

`/api/today` en una sola llamada importa: la app se abre muchas veces al día desde el móvil con datos móviles, y cinco peticiones en cascada se notan.

**Presencia**: un middleware actualiza `last_seen_at` en cada petición autenticada. El stream SSE emite el estado de presencia del otro cada 20 segundos y cuando llega un evento nuevo. Si SSE da problemas tras dos intentos, cae a polling cada 20 s y lo documentas. No pierdas medio día ahí.

### Despliegue

`tailscale serve` delante, apuntando al puerto local. Eso resuelve HTTPS y el certificado sin tocar nginx ni Caddy. Deja el comando exacto documentado y, si puedes, persistido.

`restart: unless-stopped` en el compose para que sobreviva a cortes de luz.

`scripts/backup.sh`: copia `app.db` (con `VACUUM INTO`, no `cp` en caliente) y `uploads/` a una ruta configurable. Las fotos son irreemplazables.

---

## 7. Estética

**Cute y cozy, con rosas.** A Laura le gustan mucho los tonos rosas.

La dirección concreta, para que no parezca una plantilla de Bootstrap teñida de rosa:

- **Paleta día**: rosa empolvado `#E8B4C8`, crema de fondo `#FDF6F0`, rosa profundo para acentos `#C9798F`, texto `#4A3640`, dorado suave `#D4A574`.
- **Paleta noche cálida**: fondo `#2A1F26`, superficies `#3A2B33`, rosas desaturados, texto `#F0E2E8`. La van a usar mucho antes de dormir, el modo noche no es opcional.
- **Tipografía**: una serif con carácter (Fraunces o Playfair Display) **solo** para dedicatorias y frases; una sans redondeada (Nunito o Quicksand) para toda la interfaz. **Self-hosted, no CDN de Google Fonts** — el servidor está detrás de Tailscale y las fuentes deben cargar aunque la conexión externa sea mala.
- Esquinas muy redondeadas, 20-24px. Sombras suaves y difusas, nunca duras.
- Textura sutil de grano o papel de fondo, un overlay SVG de ruido a opacidad 0.03. Es lo que separa «cozy» de «plano».
- Micro-animaciones: el corazón latiendo, las cards apareciendo escalonadas, el botón de «te echo de menos» con un pequeño rebote. Todo con CSS, y **respeta `prefers-reduced-motion`**.
- Mobile-first. Se va a usar el 90% desde un iPhone. Comprueba las áreas táctiles (mínimo 44px) y el safe-area inset de iOS.
- Estados vacíos con cariño: cuando no hay fotos todavía, cuando ella aún no ha puesto su mood. Nunca un «No data» seco.

Antes de escribir CSS, define los design tokens en un único sitio y que todo lo consuma de ahí.

---

## 8. Fases

Al terminar cada fase: commit, nota en el vault, y un mensaje de Telegram.

**Fase 0 — Reconocimiento**
Verifica: `agy --version`, `agy models`, versión de Node, Docker, `tailscale status --json`, arquitectura de la máquina. Prueba que `better-sqlite3` y `sharp` instalan en ARM64. Escribe el plan completo en el vault antes de tocar nada más.

**Fase 1 — Esqueleto**
Estructura de carpetas, `package.json`, TypeScript, `.gitignore` (con `.env` dentro **desde el primer commit**), `.env.example`, scripts de Telegram, healthcheck. Prueba que Telegram funciona mandándote un mensaje de prueba.

**Fase 2 — Backend**
Esquema de base de datos, migraciones, seed de los dos usuarios, autenticación, todos los endpoints, procesado de imágenes. Tests de los endpoints críticos.

**Fase 3 — Shell del frontend**
Design tokens, layout, las tres pestañas, navegación, modo noche, pantalla de login. Sin funcionalidad todavía: primero que se vea bien.

**Fase 4 — Funcionalidades**
Moods, dedicatorias, fotos, wishlist, countdown, racha, calendario de moods.

**Fase 5 — Tiempo real y push**
SSE, presencia, service worker, VAPID, los tres disparadores de notificación, cron de las 21:00, onboarding de instalación PWA para iOS.

**Fase 6 — Despliegue y cierre**
Dockerfile multi-stage, docker-compose, `tailscale serve`, script de backup, documentación final, `docs/vault/07-pendiente-alberto.md` con todo lo que le queda por hacer.

---

## 9. Documentación

### Git

- Rama `main`. Commits en español, formato convencional (`feat:`, `fix:`, `docs:`, `chore:`).
- Commit al cerrar cada subfase, no un único commit gigante al final.
- **Nunca `--force`. Nunca commitear `.env` ni nada de `data/`.**

### Vault de Obsidian — `docs/vault/`

Va **dentro del repo**, versionado con el código. Alberto lo enlazará a su vault principal con un symlink.

Cada nota con frontmatter YAML y enlaces `[[wikilink]]` entre ellas:

```
00-indice.md                 # punto de entrada, enlaza a todo
01-arquitectura.md
02-decisiones.md             # una entrada por decisión: contexto, opciones, elegida, motivo
03-esquema-datos.md
04-api.md
05-diseno.md                 # tokens, paleta, tipografía, principios
06-despliegue.md             # cómo levantarlo, cómo hacer backup, cómo restaurar
07-pendiente-alberto.md      # TODO lo que requiere que él esté delante
08-log-de-trabajo.md         # diario cronológico de lo que has ido haciendo
```

En `02-decisiones.md`, **toda decisión que hayas tomado sin respuesta de Alberto lleva la etiqueta `#decision-autonoma`**, para que al volver pueda filtrarlas de un vistazo y revisarlas.

**Nota de contexto**: Alberto tiene un asistente de IA local que también se llama Laura. En toda la documentación, cuando te refieras a la persona, escribe «Laura (usuaria)», para que un agente futuro no confunda las dos cosas.

---

## 10. Prohibiciones

1. **No escribas nada fuera de `/home/vizcapon/web-laura`.** Ni en el ecosistema de Alberto, ni en su vault principal, ni en otros contenedores de CasaOS.
2. **No toques otros contenedores Docker.** Nada de `docker system prune`, `docker stop` global, ni tocar la configuración de CasaOS.
3. **Ningún secreto sale de `.env`.** Ni al código, ni al vault, ni a un log, ni a `agy`.
4. **No instales paquetes a nivel de sistema con `sudo`** sin preguntar por Telegram primero.
5. **No hagas force push ni reescribas el historial.**
6. **No te quedes bloqueado esperando a Alberto.** 15 minutos y decides tú.

---

## 11. Qué significa «terminado»

Alberto va a hacer todas las pruebas él más adelante. Tú dejas la aplicación **implementada y documentada**, no validada con dispositivos reales.

Terminado quiere decir:

- [ ] `docker compose up -d` levanta la aplicación sin errores en la Pi.
- [ ] Se puede entrar con los dos usuarios y el PIN.
- [ ] Las tres pestañas funcionan y están diseñadas, no esbozadas.
- [ ] Se sube una foto, se procesa, se borra el EXIF y aparece en la galería.
- [ ] Moods, dedicatorias, wishlist y countdown funcionan de punta a punta.
- [ ] El endpoint de ping funciona y respeta el rate limit.
- [ ] Service worker, claves VAPID y los tres disparadores de push están implementados, con su checklist de verificación en `07-pendiente-alberto.md`.
- [ ] El comando de `tailscale serve` está documentado y probado hasta donde se pueda sin el iPhone.
- [ ] El script de backup funciona.
- [ ] El vault está completo y coherente.
- [ ] El mensaje final de Telegram resume lo hecho, las decisiones autónomas tomadas, y lo que le queda a él.

**Lo que no vas a poder validar y debes decir claramente**: el flujo de PWA instalada más Web Push en iOS. Es la parte más frágil de todo esto y necesita el iPhone de Laura delante. Déjalo implementado, con las claves generadas y los pasos escritos, y dilo sin adornos en el mensaje final.

---

## Empieza ahora

Ejecuta la Fase 0. Escribe el plan completo en `docs/vault/00-indice.md` y `02-decisiones.md` antes de delegar la primera tarea. Mándame un Telegram cuando el plan esté listo, y sigue sin esperar respuesta.
