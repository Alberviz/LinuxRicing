# LinuxRicing — notas para agentes

## Flujo de trabajo con ramas

- **Hotfixes y arreglos sueltos:** se pueden commitear directamente en la rama activa, sin ceremonia.
- **Features o trabajo sustancial** (por ejemplo: el menú de configuración de carga y los efectos
  de LED del teclado al cargar): **crear una rama dedicada**, hacer el trabajo ahí, y
  **mergearla de vuelta** a la rama de la que salió cuando esté terminada.
- Por defecto: para una petición de tamaño "feature", primero rama (tras brainstorming/plan),
  luego integrar. No asumir que todo va en la rama que esté checked out.

## Coordinación multi-agente

Alberto usa Claude y Gemini a la vez en este repo, misma identidad git. Reparto habitual:
**Gemini = `vault/`**; **Claude = `rgb/`, `configs/quickshell/`, `widgets/`, `docs/`, `install.sh`,
`systemd/`**. `git fetch` a menudo; commitear pronto (un `git add -A` del otro agente puede
barrer tu working tree a medias).

## Copias que deben ir idénticas

- `widgets/Background.qml` ⇔ `configs/quickshell/caelestia/modules/background/Background.qml`
  (verificar con `diff -q`, sin salida).
- `rgb/mchose-battery` ⇔ `widgets/mchose-battery` (verificar con `diff -q`, sin salida).
