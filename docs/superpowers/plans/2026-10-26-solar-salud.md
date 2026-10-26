# Planeta «Cuerpo» (salud del reloj en el sistema solar) — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dibujar en el sistema solar del escritorio un planeta «Cuerpo» con los pasos, el sueño,
los entrenos y los hábitos del Amazfit GTS 2, leídos de la API de solo lectura del gym-hub.

**Architecture:** un helper Python sin dependencias (`widgets/gym-health`) consulta
`/v1/summary`, normaliza la respuesta y la cachea. El adaptador de `SolarSystemModel.qml` lo
ejecuta cada 20 min y expone `health`. `Sim.js` coloca el ancla `health` y calcula la fase de
las lunas. `HealthPlanet.qml` lo dibuja todo con `Shape`/`Rectangle`.

**Tech Stack:** Python 3 (stdlib: `urllib`, `netrc`, `json`, `zoneinfo`, `unittest`), QML/Qt 6.12
(QtQuick.Shapes), Quickshell.

**Spec:** `docs/sistema-solar-salud-DISENO.md`

## Global Constraints

- Credenciales solo en `~/.config/gym-hub-desktop/credentials` (netrc, 600). Nunca en el repo,
  en argv, en stdout/stderr ni en la caché.
- Un 401 **no se reintenta** hasta que cambie el `mtime` del fichero de credenciales (bloqueo
  global del servidor tras 10 fallos en 15 min).
- Sondeo cada 20 min. Caché fresca = menos de 15 min.
- Sin dependencias nuevas. Sin cambios en el shader, el cometa ni la Pi.
- Ningún color hex en la vista: todo desde los roles `col*` de `SolarSystem.qml`.
- Nada de `FrameAnimation`, ni `Canvas` nuevo, ni `shadowBlur`.
- Desplegar en `~/.config/quickshell/` o `~/.local/bin`, y mergear a `main`: **solo con el OK
  de Alberto**.
- Tras desplegar: restart limpio del shell (nunca hot-reload) y comprobar `INFO: Configuration Loaded`.

---

### Task 1: helper `gym-health` con tests

**Files:**
- Create: `widgets/gym-health`
- Create: `widgets/tests/test_gym_health.py`

**Interfaces:**
- Produces: `gym-health --json` imprime siempre un objeto JSON y sale con 0:
  `{status, reason, fetchedAt, today, goal:{steps,sleepH,sessionsPerWeek}, syncCursor,
  lastDayWithData, days:[{date,steps,sleepH,deepMin,restingHr,workouts,habits}] (7), weekWorkouts, webUrl}`.
  `status ∈ ok|offline|auth|nocreds|error`.
- Variables de entorno (solo para los tests): `GYM_HEALTH_URL`, `GYM_HEALTH_CREDENTIALS`,
  `GYM_HEALTH_CACHE_DIR`, `GYM_HEALTH_TODAY` (AAAA-MM-DD).

- [ ] **Step 1:** escribir `widgets/tests/test_gym_health.py`. Levanta un `http.server` local
  que responde 200 con un resumen de prueba, 401 o 500 según la ruta. Casos:
  `normalize` (7 días, `weekWorkouts` desde el lunes, `deepMin`), `nocreds` sin fichero,
  `nocreds` con permisos 644, `ok` y caché escrita, caché fresca sin red (el servidor cuenta las
  peticiones), `auth` y que la 2.ª llamada no toque la red, que el bloqueo se levante al tocar
  el fichero, `offline` con caché, `error` con 500, y que la contraseña no salga en stdout,
  stderr ni caché.
- [ ] **Step 2:** `python3 -m unittest widgets/tests/test_gym_health.py` → FALLA (no existe el helper).
- [ ] **Step 3:** implementar `widgets/gym-health`.
- [ ] **Step 4:** volver a ejecutar los tests → PASAN.
- [ ] **Step 5:** commit `feat(gym-health): helper de salud del reloj para el sistema solar`.

### Task 2: modelo + ancla

**Files:**
- Modify: `configs/quickshell/caelestia/services/SolarSystemModel.qml`: ancla `health` en
  `defaultConfig.anchors`; `property var health`; `Process` + `Timer` de 20 min.
- Modify: `configs/quickshell/caelestia/modules/background/solarsystem/Sim.js`: `layout.health`.

**Interfaces:**
- Consumes: la salida JSON de la Task 1.
- Produces: `SolarSystemModel.health` (el objeto JSON tal cual; al arrancar
  `{status:"loading", days:[]}`) y `layout.health = {x, y, r, moonR, moonPhase}` (px, rad), o
  `null` si no hay ancla.

```qml
// SolarSystemModel.qml — ancla
{ id: "health", label: "Cuerpo", kind: "health",
  motion: { kind: "fixed", fx: 0.81, fy: 0.58 }, rFrac: 0.022 }

// adaptador
property var health: ({ status: "loading", days: [] })
Process {
    id: healthProbe
    command: ["sh", "-c", "\"$HOME/.local/bin/gym-health\" --json 2>/dev/null"]
    stdout: StdioCollector {
        onStreamFinished: {
            try { const d = JSON.parse(text); if (d && d.status) root.health = d; } catch (e) {}
        }
    }
}
Timer {
    interval: 20 * 60 * 1000; running: root.enabled; repeat: true; triggeredOnStart: true
    onTriggered: healthProbe.running = true
}
```

```js
// Sim.js — dentro de computeLayout, antes del return
var hCfg = anchorById(cfg, "health");
var health = null;
if (hCfg) {
    var hm = hCfg.motion || {};
    var hr = (hCfg.rFrac != null ? hCfg.rFrac : 0.022) * h;
    health = {
        x: (hm.fx != null ? hm.fx : 0.81) * w,
        y: Math.min((hm.fy != null ? hm.fy : 0.58) * h, yFloor - hr * 3.4),
        r: hr, moonR: hr * 1.75,
        moonPhase: (2 * Math.PI / 240) * t
    };
}
// return { …, health: health }
```

- [ ] **Step 1:** editar los dos ficheros.
- [ ] **Step 2:** `node -e` que cargue `Sim.js` (quitando `.pragma library`) y compruebe que
  `computeLayout` devuelve `health` con la `x` y la `y` esperadas en 1920×1080 → `x≈1555`, `y≈626`.
- [ ] **Step 3:** `qmllint` del modelo sin errores nuevos.
- [ ] **Step 4:** commit `feat(solar-salud): ancla y adaptador de salud en el modelo`.

### Task 3: vista `HealthPlanet.qml` + integración

**Files:**
- Create: `configs/quickshell/caelestia/modules/background/solarsystem/HealthPlanet.qml`
- Modify: `SolarSystem.qml`: `property var health`; `zHealth`; hit-test `"health"` en
  `_updateZone`; instanciar `HealthPlanet` después del `cometLayer`.
- Modify: `SolarSystemLayer.qml`: `health: SolarSystemModel.health`.

**Interfaces:**
- Consumes: `layout.health` y `SolarSystemModel.health`.
- `HealthPlanet` props: `geo` (`layout.health`), `health`, `scale`, `zoom` (0..1 hover),
  `labelFont` y los colores `colPrimary`, `colPrimaryC`, `colInk`, `colOutline`, `colVoid`.

Reglas de la vista (spec §4):
- `ghost = !(status ∈ {ok, offline}) || days.length === 0` → esfera al 28 %, órbita
  discontinua, sin arco, sin terminador, lunas y cuentas huecas, subtítulo según el estado.
- `todayDay = days.find(d => d.date === today)`. Si `todayDay.steps` es `null`, se usa el
  último día con pasos (`stale`). Con `offline` también es `stale`. En `stale` el arco va en `colOutline`.
- `frac = clamp(steps / goal.steps, 0, 1)`. Con `frac ≥ 1`, halo.
- Terminador solo si `todayDay.sleepH != null`: `lit = clamp(sleepH / goal.sleepH)`.
  «parcial» si `sleepH < 3 || !deepMin`.
- Lunas: `n = clamp(goal.sessionsPerWeek, 1, 7)`, llenas `weekWorkouts`.
- Esfera: luz `_lit(colPrimary, .55)` → `colPrimaryC` → `_dk(colPrimaryC, .6)`. La spec decía
  m3tertiary, pero ese rol es el sol de Laura (`colLaura`), así que se cambia.

- [ ] **Step 1:** crear `HealthPlanet.qml` y editar `SolarSystem.qml` y `SolarSystemLayer.qml`.
- [ ] **Step 2:** `qmllint -I configs/quickshell/caelestia` sobre los tres ficheros.
- [ ] **Step 3:** vista previa aislada con `qs -p` y datos de prueba de los 4 estados
  (scratchpad, no va al repo), capturada en el workspace 8.
- [ ] **Step 4:** commit `feat(solar-salud): planeta «Cuerpo» en el sistema solar`.

### Task 4: install.sh, despliegue (con OK) y verificación

- [ ] **Step 1:** `install.sh`: copiar `widgets/gym-health` a `~/.local/bin` (patrón `tasks-index`).
- [ ] **Step 2:** **preguntar a Alberto** antes de desplegar.
- [ ] **Step 3:** CPU base (gotcha 6) → copiar los ficheros a `~/.config/quickshell/caelestia/` y el
  helper a `~/.local/bin` → restart limpio (gotcha 2/9) → `Configuration Loaded` sin warnings →
  captura del workspace 8 → CPU después.
- [ ] **Step 4:** calibrar `rFrac`/`fx`/`fy` con la captura si hace falta.
- [ ] **Step 5:** docs: §9 de la spec, nota del vault, nota 04.4 de GTS2, tabla de versiones
  de `docs/sistema-solar-binario.md` y bitácora de `vault/🎯 Hoy.md`. Commit.
- [ ] **Step 6:** **preguntar a Alberto** antes de mergear a `main`.
