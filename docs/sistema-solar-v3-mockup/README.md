# Maqueta de composición — Sistema Solar v3

Referencia visual del brainstorming de colocación (2026-09-03). Autocontenida en
el repo para que cualquier sesión pueda verla sin depender de artifacts.

- **`variantes.html`** — maqueta interactiva (Canvas 2D). Cuatro posibilidades de
  dónde vive el agujero negro. Ábrela en un navegador, o para una captura:
  ```bash
  chromium --headless --no-sandbox --disable-gpu --hide-scrollbars \
    --window-size=1360,840 --virtual-time-budget=3000 \
    --screenshot=/tmp/mock.png "file://$PWD/variantes.html?p=D"
  ```
  El parámetro `?p=A|B|C|D` selecciona la variante directamente.
- **`variante-{A,B,C,D}.png`** — capturas de las cuatro.

**Elegida: la D** (agujero negro en la esquina superior derecha saliéndose de
cuadro, disco de acreción en diagonal; binario Laura↔Configuración anclado
abajo-izquierda). La calidad de render de la maqueta hay que **superarla** al
implementar — ver `docs/sistema-solar-v3-DISENO.md` §4.

**Reserva: la B**, guardada en
`vault/Rice LinuxRicing/01 - Linux/Widgets/Sistema Solar — visión B (reserva).md`.

La maqueta es HTML/Canvas; el motor de dibujo se porta a QML Canvas (API casi
idéntica) al implementar.

## `harness-v3.html` — el diseño de la v3 ya iterado (2026-09-03)

Harness de trabajo de la implementación de la variante D: la composición y el
render finales (agujero negro con todas las capas de la spec §4.1, soles
granulados, satélites, cinturón), con la paleta *tonalspot* cálida real simulada.
**Supera la calidad de `variante-D.png`.** Es el porte 1:1 del código que va a
`configs/quickshell/caelestia/modules/background/solarsystem/SolarSystem.qml`.

```bash
chromium --headless --no-sandbox --disable-gpu --hide-scrollbars \
  --window-size=1920,1080 --virtual-time-budget=2500 \
  --screenshot=/tmp/v3.png \
  "file://$PWD/harness-v3.html?t=52&agents=2&done=1&dev=mouse,keyboard&tasks=7&low=mouse"
```

Parámetros de la URL: `t` (segundos de animación), `agents` / `done` (nº de
agentes en curso / completados orbitando Laura), `dev` (`headset,mouse,keyboard`
conectados a Config), `low` (dispositivos con batería < 20 %), `tasks` (nº de
tareas pendientes → densidad del cinturón), `music` (0..1), `laura`
(`tertiary`|`secondary`), `live` (anima en vez de un frame fijo).

- **`v3-harness-reposo.png`** — sin agentes ni dispositivos (0 satélites).
- **`v3-harness-activo.png`** — 2 agentes + 1 completado, ratón+teclado, ratón con
  batería baja.

Se itera aquí y se re-porta a QML mientras la verificación en el escritorio real
siga bloqueada (ver `docs/sistema-solar-v3-DISENO.md` §13).
