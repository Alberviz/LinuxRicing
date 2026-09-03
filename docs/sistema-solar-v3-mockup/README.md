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
