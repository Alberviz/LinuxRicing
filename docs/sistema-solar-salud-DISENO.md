# Sistema solar · salud del reloj (Amazfit GTS 2) — diseño

**Estado:** propuesta, pendiente del OK de Alberto (Fase 1). Rama `feat/solar-salud`
(worktree `.worktrees/solar-salud`, sale de `main` @ `c93a0bc`).
**Fecha:** 2026-10-26.
**Mockup:** `docs/sistema-solar-v3-mockup/salud-variantes.html` → captura `salud-variantes.png`.
**Relacionado:** `docs/sistema-solar-v3-DISENO.md` (spec de la escena),
`docs/sistema-solar-v3-ESTADO-Y-SIGUIENTE.md` (estado y gotchas de la máquina),
`docs/sistema-solar-cometa-rediseno.md` (precedente «dato real → cuerpo celeste»).
**Vault:** `vault/Rice LinuxRicing/01 - Linux/Widgets/Sistema Solar — salud del reloj.md`
y, en el vault del reloj, `~/proyectos/GTS2/04 - Capacidades Ocultas y Proyectos
Avanzados/04.4 Salud del reloj en el escritorio (LinuxRicing).md`.

---

## 1. Objetivo

Llevar los datos de salud del reloj (**pasos sobre todo**, más sueño, FC, entrenos y
hábitos) al sistema solar del escritorio **como un cuerpo celeste más**, con la misma
metáfora que el resto de la escena (música = agujero negro, Laura = sol, agentes =
planetas, dispositivos = satélites, tareas = cometa). No es un widget pegado. Tiene que verse
bien con datos ausentes o atrasados, y el fondo tiene que seguir siendo ligero.

## 2. Los datos reales (no supuestos)

Fuente: API JSON de solo lectura del gym-hub en la Raspberry Pi,
`GET https://vizcapon-pi.tail76abc5.ts.net:8443/v1/summary?from=AAAA-MM-DD&to=AAAA-MM-DD`
(HTTP Basic; `/health` sin auth → `{"status": "ok", "schema_version": "1.0"}`). Código:
`vizcapon@100.82.69.90:~/proyectos/gym-hub/src/gym_hub/readonly.py`, función
`build_summary`. Corre en el contenedor `gym-hub-readonly-1` (BD montada `:ro`).

La forma se verificó el 2026-10-26 ejecutando `build_summary` **dentro del contenedor**
(`docker exec gym-hub-readonly-1 python -c …`) para los últimos 14 días, porque el escritorio
aún no tiene credenciales (la API da 401 sin ellas). Campos que usa este diseño:

| Campo | Qué es | Estado real (13–26 oct) |
|---|---|---|
| `daily[].date`, `daily[].steps` | pasos del día | **13 de 14 días con dato**; falta el 16. Hoy (26) da 330 a las 16:00: va con horas de retraso |
| `daily[].sleep_h`, `daily[].sleep_stages_min` | sueño asignado a ese día (se infiere que es la noche que **termina** ese día: el 26 ya trae 4,97 h a las 16:00), y sus fases (`light`/`deep`/`awake`) | 10 de 14 noches; **fragmentado**: 0,55 h, 1,43 h, 1,73 h… y noches sin `deep` |
| `daily[].resting_hr` | FC en reposo | **siempre `null`** |
| `daily[].spo2`, `daily[].watch_workout_kcal` | SpO₂, kcal de entreno del reloj | **siempre `null`** |
| `daily[].workouts` | nombres de las sesiones de openGym de ese día | 2 sesiones (13 y 14 oct), ninguna en la última semana |
| `daily[].habits` | ids de hábitos hechos ese día | solo `creatina` (4 días) |
| `goals` | `steps_per_day: 10000`, `sleep_h: 7.5`, `sessions_per_week: 4`, … | config de la Pi |
| `last_sync.watch_google_health` | `cursor` (último sync con Google Health) y `last_day_with_data` | cursor al día (16:00); el retraso viene **antes**, de Zepp → Health Connect |

`activity.watch_sessions` (19 sesiones del reloj, 0 kcal) existen pero son de Health
Connect (paseos incluidos): no cuentan como entreno aquí.

**Detalle del servidor que condiciona el cliente:** `readonly.py` bloquea el login
**para todos** tras 10 fallos en 15 min (`FALLOS_MAX, FALLOS_VENTANA = 10, 15 * 60`). Un
fondo que reintentara con una contraseña mala dejaría sin acceso también a la vista web y al
asistente externo. Por eso el cliente **no reintenta nunca un 401** (§6.3).

## 3. Conceptos explorados

Zona libre de la escena (captura real del 2026-10-26): **abajo a la derecha**, x ≈ 1300–1850,
y ≈ 420–880 en 1920×1080. Encima queda el disco del agujero negro y a la izquierda la órbita
del cometa (que llega hasta x ≈ 0,70·w). Por debajo, la franja de ~200 px reservada al overlay
de voz de Laura (restricción dura de `Sim.js`).

### A · Planeta «Cuerpo» con su propio sistema (ELEGIDO)

Un planeta nuevo, fijo en el hueco de abajo a la derecha. Representa a Alberto/su cuerpo.

| Dato | Elemento |
|---|---|
| pasos de hoy / meta | **arco de órbita** que se cierra alrededor del planeta, con una «sonda» brillante en la punta; al llegar a la meta el arco se cierra y el planeta gana halo |
| últimos 7 días de pasos | **7 cuentas** bajo el planeta (hoy, la última, con aro): llena = meta cumplida; tenue ∝ pasos; hueca = sin dato → la racha se lee de un vistazo |
| sueño de anoche | **terminador** (fase día/noche) del planeta: fracción iluminada = horas / 7,5 h |
| entrenos (openGym) de la semana ISO | **lunas**: llenas = hechas; huecas = lo que falta hasta `sessions_per_week` (4) |
| hábitos | **marca** fina sobre la cuenta del día en que se hizo |
| FC en reposo | **solo en la etiqueta** cuando haya dato (hoy no hay ninguno) |

- **Sin datos:** el planeta queda como contorno tenue, con la órbita discontinua y la etiqueta
  «sin datos». Atrasado: el arco pasa a gris, muestra el último día bueno y dice «ayer» o
  «hace N h». Nada se pinta en rojo ni roto: no es un error del sistema.
- **Coste:** ~20 elementos `Shape`/`Rectangle` estáticos que se repintan cuando cambian los
  datos (cada 20 min). Las lunas se mueven con el ticker de `Sim.js`, que ya existe. Shader: 0.
- **Cometa:** no se tocan; ~150 px de margen con la órbita del cometa.
- **Modo Laura:** se atenúa y se congela como el resto de cuerpos.

### B · Constelación de la semana

Siete estrellas en el hueco, una por día: tamaño y brillo ∝ pasos, una línea viva entre días
seguidos que cumplen la meta (la racha es literalmente una constelación), una cruz de 4 puntas
para los entrenos, un aro para el sueño y un hueco cuando falta el día.

- **Sin datos:** estrellas que faltan y líneas rotas. Es honesto, pero con varios días vacíos
  ya no se lee como constelación.
- **Coste:** muy bajo, como A.
- **Contra:** lo que más importa, «¿cuánto llevo hoy?», queda en una estrella más. Además no es
  un cuerpo del sistema: es un adorno de fondo y rompe la metáfora «cada servicio orbita algo».

### C · Nebulosa en el shader

Una nebulosa en el hueco: densidad/brillo = pasos de hoy, «nacimiento de estrellas» = entrenos,
turbulencia = calidad del sueño.

- **Sin datos:** nebulosa apagada; queda bien.
- **Coste:** **alto**. Son fbm por píxel añadidos al `solarfield.frag` a pantalla completa (el
  fondo costó mucho dejarlo en ~4,7 % de un núcleo, ver estado §3.1). Haría falta una caja de
  corte temprano.
- **Contra:** no se puede leer un número. Bonito, pero no informa.

### D · Repartir los datos en cuerpos que ya existen

Pasos = tamaño de la corona de Laura, sueño = brillo del sol de Configuración, entrenos =
lunas de Laura…

- **Sin datos:** nada cambia, porque se queda el aspecto por defecto.
- **Coste:** el más bajo.
- **Contra:** **sobrecarga significados.** Laura activa ya cambia su aspecto, y Configuración
  es el ancla de los dispositivos. No se sabría si un sol brilla por el sueño o por otra cosa.
  Descartado.

### Decisión

**A.** Es la única que mantiene la metáfora (un servicio = un cuerpo con su séquito), pone lo
más importante (los pasos de hoy) en el elemento más legible (un arco que se cierra hacia la
meta) y degrada con dignidad: lo que falta se ve hueco, no roto. De B toma la idea de la
racha (las 7 cuentas). Cuesta casi nada, porque no añade trabajo al shader ni ninguna
animación continua nueva.

## 4. Diseño visual del planeta «Cuerpo»

Mockup: `docs/sistema-solar-v3-mockup/salud-variantes.png` (paneles 1-3).

- **Posición:** ancla fija `health` en `defaultConfig` de `SolarSystemModel.qml`, con
  `motion: { kind: "fixed", fx: 0.81, fy: 0.58 }` y `rFrac: 0.020` (r ≈ 21 px a 1080p). Se
  puede afinar desde `~/.config/caelestia/solarsystem.json`, como las demás anclas. El planeta
  no se traslada (principio de la v3: posiciones estables y predecibles).
  - *Ajuste para la implementación:* en el mockup el planeta se ve pequeño al lado de los
    planetas de agente (r ≈ 25–30 px con halo). En la Fase 2 se calibra con la captura real
    (rango 0,020–0,026).
- **Esfera:** gradiente radial con roles de paleta, nunca un hex (regla del proyecto). Propuesta:
  `m3tertiary` (rol que hoy no usa ningún cuerpo fijo) con luz arriba a la izquierda.
- **Terminador (sueño):** `Shape` con dos arcos (semicírculo + arco elíptico) relleno de
  `colVoid` al 78 %. Fracción iluminada = `clamp(sleep_h / goals.sleep_h, 0, 1)`. Con meta
  cumplida, luna llena. **Sin dato de sueño → sin terminador** (esfera entera, sin juzgar).
  **Noche parcial** (< 3 h o sin fase `deep`): el terminador se pinta igual y la etiqueta dice
  «parcial». El reloj fragmenta noches, así que no se finge un dato que no es fiable.
- **Arco de pasos:** elipse (`ry = 0,42·rx`, la misma inclinación de perspectiva que las
  órbitas de la escena) de radio ≈ 3·r. Base al 13 % y arco `PathAngleArc` en `colPrimary`
  al 85 % desde las 12 en sentido horario, fracción = `steps_hoy / goals.steps_per_day`,
  con la sonda en la punta (gradiente radial, sin `shadowBlur`). Con ≥ 100 %, arco cerrado y
  halo radial del planeta.
- **Lunas (entrenos):** `goals.sessions_per_week` lunas (4) en una órbita a ≈ 1,7·r: llenas
  `colInk` = sesiones openGym de lunes a hoy; huecas `colOutline` al 35 % = las que faltan. Las
  lunas giran despacio (período ~240 s, en `Sim.js`, igual que los demás satélites).
- **Cuentas (racha):** 7 puntos bajo el planeta, espaciados 22 px; la última es hoy (aro).
  Meta cumplida = punto mayor y opaco; parcial = opacidad 0,15 + 0,45·fracción; sin dato =
  contorno. Hábito hecho ese día = marca de 1,6 px encima.
- **Etiqueta:** reutiliza `BodyLabel.qml`. En reposo: `CUERPO` + «6 919 / 10 000 pasos».
  Al pasar el ratón (como `zComet` en el cometa) añade «sueño 5,0 h · 0/4 entrenos»,
  «FC 58» si hay dato y «reloj: 16:00» o «hace 9 h».
- **Clic:** abre la vista web `https://vizcapon-pi.tail76abc5.ts.net:8443/resumen` (con su
  propio login) con `Qt.openUrlExternally`.

### 4.1 Estados

| Estado | Cuándo | Se ve |
|---|---|---|
| `ok` | respuesta buena y `daily[hoy].steps` existe | todo lo anterior |
| atrasado | `daily[hoy].steps` es `null` (p. ej. recién pasada la medianoche) | arco gris (`colOutline`) con el último día con pasos; etiqueta «ayer 6 919» o con fecha |
| `offline` | la red falla y hay caché | lo de la caché, arco gris; etiqueta «sin conexión · hace N h» |
| `auth` | 401 | planeta fantasma; etiqueta «credenciales rechazadas» |
| `nocreds` | falta el fichero de credenciales o es legible por otros | planeta fantasma; etiqueta «sin datos» |
| `error` | 5xx, JSON inválido o sin caché | planeta fantasma; etiqueta «sin datos» |

«Fantasma» = esfera al 28 %, órbita discontinua, sin lunas llenas ni cuentas llenas. El
planeta **siempre existe**, a diferencia del cometa, que desaparece sin tareas: así su sitio en
el escritorio es estable y su ausencia también informa.

## 5. Arquitectura

```
Pi (gym-hub-readonly, /v1/summary)
   │  HTTPS + Basic (Tailscale Funnel)
   ▼
widgets/gym-health  (Python stdlib, → ~/.local/bin/gym-health)
   │  caché ~/.cache/gym-health/summary.json · estado de auth
   │  stdout: JSON compacto y normalizado (§6.2)
   ▼
SolarSystemModel.qml — adaptador «salud»: Process + Timer de 20 min
   │  root.health = { status, goal, days[7], weekWorkouts, … }
   ▼
Sim.js — ancla `health` → layout.health { x, y, r, moons[] }
   ▼
solarsystem/HealthPlanet.qml (nuevo) — dibujo (Shape/Rectangle), instanciado en SolarSystem.qml
```

### 5.1 Archivos que se tocan

| Archivo | Cambio |
|---|---|
| `widgets/gym-health` (**nuevo**) | helper de datos (§6) |
| `install.sh` | copiarlo a `~/.local/bin`, como `tasks-index` |
| `configs/quickshell/caelestia/services/SolarSystemModel.qml` | ancla `health` en `defaultConfig` + adaptador (`Process`, `Timer`, `property var health`) |
| `…/background/solarsystem/Sim.js` | posición del ancla `health` y fase de las lunas → `layout.health` |
| `…/background/solarsystem/HealthPlanet.qml` (**nuevo**) | el dibujo del planeta |
| `…/background/solarsystem/SolarSystem.qml` | instanciar `HealthPlanet` con `layout.health`, `health` del modelo y el factor de atenuación del modo Laura |

No se toca el shader, ni el cometa, ni nada en la Pi.

## 6. Servicio de datos — `widgets/gym-health`

### 6.1 Credenciales

- Fichero: **`~/.config/gym-hub-desktop/credentials`**, formato `netrc`, permisos **600**
  (directorio 700). Lo rellena Alberto:
  ```
  machine vizcapon-pi.tail76abc5.ts.net login <usuario> password <contraseña>
  ```
- El helper lo lee con el módulo `netrc` de Python y monta la cabecera `Authorization` en
  memoria. **Nunca va en la línea de comandos** (el `Process` de QML solo ejecuta
  `gym-health --json`, así que en `ps` no aparece nada), ni en la caché, ni en stdout/stderr.
- Si el fichero es legible por grupo u otros (`mode & 0o077`), el helper **no lo usa** y
  devuelve `nocreds` con motivo «permisos». No hay ninguna credencial en el repo.
- Son las mismas credenciales de la vista web `/resumen`. `readonly.py` admite **un único**
  usuario (`username` + `password_hash` scrypt en `~/.config/gym-readonly/config.json` de la
  Pi). La contraseña no se puede sacar del hash, así que la pone Alberto. Alternativa, sin
  hacer: añadir a `readonly.py` un segundo usuario para el escritorio, que se podría revocar por
  separado. Eso es tocar el gym-hub, así que solo se haría si Alberto lo pide.

### 6.2 Salida (contrato con QML)

`gym-health --json` imprime siempre **un** objeto JSON y sale con 0, aunque haya error:

```json
{
  "status": "ok | offline | auth | nocreds | error",
  "reason": "texto corto opcional",
  "fetchedAt": "2026-10-26T16:20:00+01:00",
  "today": "2026-10-26",
  "goal": { "steps": 10000, "sleepH": 7.5, "sessionsPerWeek": 4 },
  "syncCursor": "2026-10-26T16:00:38+01:00",
  "lastDayWithData": "2026-10-26",
  "days": [ { "date": "2026-10-20", "steps": 8161, "sleepH": 2.58, "deepMin": 24,
              "restingHr": null, "workouts": 0, "habits": [] }, "… 7 en total, el último = hoy" ],
  "weekWorkouts": 0
}
```

- `days` sale de `daily[]` pidiendo `from = hoy − 6`, `to = hoy` (zona `Europe/Madrid`). Siempre
  incluye el lunes de la semana ISO, así que `weekWorkouts` = suma de `workouts` desde el lunes.
- Con `offline` o `auth` devuelve también los últimos `days` buenos de la caché (con su
  `fetchedAt`), para que la vista pinte el estado atrasado en vez del fantasma.

### 6.3 Red, caché y errores

- **Caché:** `~/.cache/gym-health/summary.json` (respuesta normalizada + `fetchedAt`). Si tiene
  menos de 15 min, el helper la devuelve **sin ir a la red**, así que reiniciar el shell no
  multiplica peticiones.
- **Sondeo:** `Timer` de **20 min** en el modelo (en el rango pedido de 15-30), con
  `triggeredOnStart`, y solo con `root.enabled`. Los datos llegan con horas de retraso: sondear
  más a menudo no aporta nada.
- **Petición:** `urllib.request`, timeout de 10 s, TLS verificado (el certificado de Tailscale
  es válido).
- **401:** guarda `~/.cache/gym-health/auth-blocked` con el `mtime` del fichero de credenciales
  y devuelve `auth`. **Mientras ese `mtime` no cambie, no vuelve a llamar a la API**: cero
  reintentos, para no provocar el bloqueo global del servidor (§2). Cuando Alberto corrige el
  fichero, el `mtime` cambia y la siguiente pasada lo prueba una vez.
- **Sin red / timeout / DNS:** `offline` + caché. Lo vuelve a intentar en la pasada siguiente
  (20 min), sin bucles.
- **5xx / JSON inválido / `schema_version` ≠ `1.x`:** `error` + caché, y una línea corta en
  stderr. Nunca la URL con credenciales ni las cabeceras.
- **Dependencias:** solo la biblioteca estándar de Python 3 (`urllib`, `netrc`, `json`,
  `zoneinfo`). No añade ningún paquete.

## 7. Rendimiento

- **Shader:** sin cambios. **Animaciones nuevas:** ninguna continua. Las lunas usan las
  posiciones de `Sim.js`, que ya calcula el ticker actual. El pulso de la sonda, si se añade, va
  en un `Timer` gateado por `visible && !lauraFocus && status === "ok"`, nunca en un
  `FrameAnimation` incondicional (CLAUDE.md).
- **Datos:** un proceso Python corto cada 20 min, que casi siempre lee la caché.
- **Objetivo:** ninguna diferencia medible en la CPU del shell. Se mide antes y después con el
  método del gotcha 6 de `sistema-solar-v3-ESTADO-Y-SIGUIENTE.md` (`/proc/<pid>/stat`, 15 s,
  máquina tranquila).

## 8. Plan de implementación (Fase 2, tras el OK)

1. `widgets/gym-health` + pruebas sin red: sin fichero → `nocreds`; permisos 644 → `nocreds`;
   URL inválida → `offline`; 401 simulado → `auth` y segunda llamada sin red. Después, una
   llamada real cuando exista el fichero.
2. `install.sh`: instalar el helper.
3. `SolarSystemModel.qml`: ancla + adaptador. Comprobar `health` con datos de prueba.
4. `Sim.js`: `layout.health` (posición, r, lunas).
5. `HealthPlanet.qml` + instanciarlo en `SolarSystem.qml`. `qmllint`.
6. **Antes de desplegar en `~/.config/quickshell/`: preguntar a Alberto** (límite del encargo).
   Después: copiar, restart limpio (nunca hot-reload), `INFO: Configuration Loaded` sin
   warnings, captura del escritorio real en el workspace 8 y CPU antes/después.
7. Calibrar tamaño y posición con la captura; revisar los estados degradados forzándolos
   (renombrar temporalmente el fichero de credenciales, cortar la red del helper con una URL
   mala).
8. Documentación: este documento (§9 con lo hecho), la nota del vault, la nota del vault GTS2,
   la tabla de versiones de `docs/sistema-solar-binario.md` y la bitácora de `vault/🎯 Hoy.md`.
9. **Merge a `main`: preguntar a Alberto** antes de hacerlo.

## 9. Registro

- 2026-10-26 · Fase 1: datos verificados en la Pi, 4 conceptos, mockup, elegido A. Pendiente
  del OK.
