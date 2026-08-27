---
tags: [tarea-agente, gemini, rgb, bateria, fix, integracion]
para: Gemini
de: Claude
creado: 2026-08-27
estado: completado
depende_de: "[[Gemini · Validación de hardware — INFORME]]", "[[Gemini · Panel QML — INFORME]]"
---

# Gemini · Arreglos post-validación + re-integración del panel

> **Eres el agente `fixes`.** Los 3 agentes anteriores terminaron. Quedan **dos cosas**:
> (1) la integración del panel QML está incompleta, y (2) la validación de hardware
> encontró 3 arreglos necesarios en `rgb/battery-lighting`. Haz ambas y deja la rama
> `feat/battery-lighting-engine` lista para el merge final a `main`.

> [!warning] No toques `configs/quickshell/caelestia/services/BatteryLightingConfig.qml`
> Es el contrato de esquema. Si de verdad crees que hay que cambiarlo, para y avisa a Alberto para que lo revise Claude.

## 0. Contexto

- Rama del motor: `feat/battery-lighting-engine` (`origin`, HEAD `1c89c0b`).
- Rama del panel QML: `feat/battery-panel-ui` (`origin`, HEAD `79eca00`) — tiene 2 commits que **NO están** en la del motor: `339ba56` (un fix real de delegados) y `79eca00` (el informe).
- Informe de hardware: [[Gemini · Validación de hardware — INFORME]] (léelo entero, sección 5).

Trabaja en tu propio worktree:
```
git fetch origin
git worktree add .worktrees/fixes -b feat/battery-fixes feat/battery-lighting-engine
cd .worktrees/fixes
```

---

## 1. Re-integrar el panel QML

```
git merge origin/feat/battery-panel-ui
```
Debe ser **limpio** (ya comprobado con `merge-tree`, 0 conflictos). Trae el fix `339ba56`
(`BatteryActionRow` pasa a `required property var modelData` + `property var action: modelData`,
y el `Repeater` en `BatteryRuleCard` deja de re-declarar `index`/`modelData`). Sin este fix
el panel lanza *warnings* de "required property not set".

Verifica tras el merge:
```
grep -n "required property var modelData" configs/quickshell/caelestia/modules/rgbcontrol/BatteryActionRow.qml   # debe aparecer
qmllint configs/quickshell/caelestia/modules/rgbcontrol/*.qml configs/quickshell/caelestia/services/*.qml
```

---

## 2. Arreglos en `rgb/battery-lighting` (del informe de hardware, sección 5)

### 2a. `[Alta]` — Teclas del Akko: `battery_meter` → `breathing_battery` por defecto

El modo lienzo por-tecla (`LightUserPicture` / `AKKO_KEY_ROWS`) **no funcionó** en el firmware
ROYUAN del 5075B (el teclado no conmutó de modo). `breathing_battery` sí está 100% probado.
Cambia el **valor por defecto**, pero deja `battery_meter` como opción seleccionable (backlog):

1. En `DEFAULTS` (~línea 44), la regla `akko-charging`, acción de zona `keys`:
   ```python
   {"target": "akko_keyboard", "zone": "keys", "effect": "breathing_battery"},   # era "battery_meter"
   ```
2. En `LEGACY_AKKO_BACKLIGHT` (~línea 150):
   ```python
   LEGACY_AKKO_BACKLIGHT = {"theme": "theme", "fill": "breathing_battery",   # era "battery_meter"
                            "breathing": "breathing_battery", "stream": "stream"}
   ```
3. **NO** quites `"battery_meter"` de `EFFECTS["akko_keyboard:keys"]` — sigue siendo válido para
   quien lo elija a mano. Añade un comentario `# battery_meter: experimental, el firmware 5075B no conmuta a modo lienzo (ver informe hw 2026-08)`.
4. **Tests afectados** en `rgb/tests/test_config.py`:
   - `test_seed_migrates_akko_config`: cambia `assert acts["keys"] == "battery_meter"` → `== "breathing_battery"`.
   - Revisa `test_seed_uses_defaults_without_legacy` y cualquier assert sobre `DEFAULTS` que mencione `battery_meter` en la zona `keys`.

### 2b. `[Media]` — Realce de saturación del color del tema

Los pasteles de Material You se ven blanquecinos en los LEDs. En `theme_primary_rgb()`
(~línea 879), tras obtener `(r,g,b)` del `scheme.json`, aplica el mismo boost HSV que usa
`enhance_color_for_leds` en `rgb/sync-rgb.py:164` (copia, no importes — estilo del repo):

```python
import colorsys  # ya está importado en la cabecera

def _boost_for_leds(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    if s > 0.05:
        s2 = min(1.0, max(0.80, s * 3.5))
        nr, ng, nb = colorsys.hsv_to_rgb(h, s2, 1.0)
        return int(nr * 255), int(ng * 255), int(nb * 255)
    return r, g, b
```
Y que `theme_primary_rgb()` devuelva `_boost_for_leds(r, g, b)` en la ruta de éxito
(deja el fallback `return 255, 152, 0` igual, o pásalo también por el boost).
Los tests de `test_tick.py` monkeypatchean `theme_primary_rgb`, así que no deberían romperse;
verifica que no haya ningún test que asserte el valor crudo del scheme.

### 2c. `[Media]` — Observabilidad del daemon

En `_daemon_loop()` (~línea 1001), emite a `stdout` (con `print(..., flush=True)`) cuando:
- cambia la cadencia (60 s ↔ 3 s): `print(f"[battery-lighting] cadencia -> {secs}s (charging={charging})", flush=True)`
- `tick()` devuelve un mapa de alertas distinto al anterior: `print(f"[battery-lighting] alertas activas: {list(new)}", flush=True)`

Así `journalctl --user -u battery-lighting -f` muestra algo útil.

### 2d. `[Baja, opcional]` — Intento de arreglar `apply_akko_meter`

El informe identificó que el paquete de activación deja `activate[4] = 0x00`. Prueba a setear
el flag de color custom antes del checksum (en `apply_akko_meter`, ~línea 780):
```python
    activate[3] = 0x04
    activate[4] = 0x08          # flag color custom RGB (faltaba)
    activate[8] = (0xFF - (sum(activate[:8]) & 0xFF)) & 0xFF
```
Si con Alberto delante el `--apply` con una regla que use `battery_meter` en `keys` **ahora sí**
conmuta el teclado → genial, documéntalo. Si sigue sin funcionar → déjalo con el `0x08` puesto
igualmente (es correcto) y confirma que `breathing_battery` es el default (2a).

---

## 3. Verificación

```
python3 -m pytest rgb/tests/ -q                    # debe seguir en verde (48+; arregla los que rompa el 2a)
python3 -c "import ast; ast.parse(open('rgb/battery-lighting').read())"
python3 rgb/battery-lighting --dump                # JSON válido
diff -q rgb/mchose-battery widgets/mchose-battery  # sin salida
qmllint configs/quickshell/caelestia/modules/rgbcontrol/*.qml configs/quickshell/caelestia/services/*.qml
```

Con Alberto: recarga el shell y confirma que el panel de «Reacciones de batería» ya no
suelta *warnings*, y que `--apply akko-charging` ahora respira en color de batería en las
teclas (no medidor).

---

## 4. Commit + entrega

```
git commit ...   # si el merge dejó algo; los fixes en commits propios pequeños
git checkout feat/battery-lighting-engine
git merge --ff-only feat/battery-fixes    # o merge normal
git push origin feat/battery-lighting-engine
git worktree remove .worktrees/fixes
git branch -d feat/battery-fixes
```

Escribe el informe en
`vault/Rice LinuxRicing/00 - Arquitectura/Tareas de Agentes/Gemini · Arreglos — INFORME.md`
(qué mergeaste, qué arreglaste, resultado de los checks, si `battery_meter` funcionó o no).

Luego el **merge a `main`** lo hace el agente `integrador` siguiendo
[[Gemini · Integración y merge del motor de batería]] §6 — solo con «adelante» explícito de Alberto.
