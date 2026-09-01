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
**Gemini = `vault/`**; **Claude = `rgb/`, `configs/quickshell/`, `widgets/`, `docs/`,
`hardware/`, `install.sh`, `systemd/`**. `git fetch` a menudo; commitear pronto (un
`git add -A` del otro agente puede barrer tu working tree a medias).

## Backlog de tareas y bitácora de sesiones

`vault/🎯 Hoy.md` (+ `vault/Backlog.base` + carpeta `vault/Backlog/`) es la lista viva y
priorizada de tareas que Alberto abre cada día. **Mantenerla es trabajo de los agentes,
no de Alberto:**

- **Cuando Alberto diga «añade una tarea», «esto para el futuro», «apunta que hay
  que…» o similar:** crea `vault/Backlog/<título>.md` con frontmatter `tipo: tarea`,
  `estado: pendiente`, `prioridad` (1 urgente … 5 algún día), `area`, `origen: Alberto`,
  `esfuerzo` (S/M/L) y `creado: <fecha ISO>`. Con eso aparece sola en las vistas.
- **Al ponerte a trabajar en una tarea del backlog:** cambia su nota a `estado:
  en-curso`. **Al terminar:** `estado: hecha` — nunca borres la nota, la vista «Hechas»
  es el registro de lo hecho.
- **Al cerrar la sesión:** añade UNA línea arriba del todo de la sección «📓 Bitácora de
  sesiones» de `vault/🎯 Hoy.md`: `- **<fecha> · <agente>** — <qué hiciste>`.
- Los proyectos grandes siguen viviendo en `Roadmap Maestro de Innovaciones.md`; el
  Backlog es la rodaja accionable y enlaza al roadmap.

## Conocimiento de hardware

`hardware/<dispositivo>/` es la **fuente canónica** de los protocolos de ingeniería
inversa (IDs USB, opcodes, payloads, checksums): un `README.md` (identidad + estado +
historia) y un `PROTOCOL.md` (spec) por dispositivo, más `captures/` con los `.pcapng`.
`docs/` ya **no** lleva specs de dispositivo — solo runbooks, traspasos y planes. El
vault enlaza a `hardware/` en vez de duplicar opcodes.

## Captura USB / ingeniería inversa de hardware en Windows

Si trabajas en la máquina Windows y el objetivo es capturar tráfico USB (protocolo del
dongle Akko, base MCHOSE, etc.), **lee primero `docs/WINDOWS_USB_CAPTURE_RUNBOOK.md`**.
Contiene el entorno verificado, el comando de captura que funciona, el fallo conocido de
USBPcap en esta build de Windows (que ya costó una sesión entera), y qué está resuelto
(`hardware/akko-5075b-plus/USB_FINDINGS_2.4G.md`) y qué no (per-key dinámico). Las
capturas `.pcapng` van en `hardware/<dispositivo>/captures/`.

## Copias que deben ir idénticas

- `widgets/Background.qml` ⇔ `configs/quickshell/caelestia/modules/background/Background.qml`
  (verificar con `diff -q`, sin salida).
- `rgb/mchose-battery` ⇔ `widgets/mchose-battery` (verificar con `diff -q`, sin salida).

## Reinicio obligatorio del Shell tras cambios en UI/Widgets

- **SIEMPRE que se modifique o implemente cualquier componente de UI, QML o widgets:**
  1. Sincronizar los archivos editados a `~/.config/quickshell/caelestia/` (y verificar que los pares de archivos gemelos queden idénticos).
  2. **Reiniciar el shell de Quickshell inmediatamente** para aplicar y verificar los cambios en vivo ejecutando:
     ```bash
     caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
     ```
  3. Comprobar que la salida confirme `INFO: Configuration Loaded` sin errores de sintaxis o propiedades QML.

- **NUNCA fiarse del hot-reload de Quickshell.** La recarga in-process que dispara
  cualquier cambio de archivo en `~/.config/quickshell/caelestia/` **fuga las
  animaciones de la generación anterior**: los `FrameAnimation` y los bucles de
  repintado de `Canvas` siguen vivos a 60fps como zombis. Tras ~10 recargas un
  núcleo se clava al 100% y no se recupera («el shell va petado»). Un restart
  limpio con la config completa vuelve a 0%. Por eso el paso 2 es **restart
  completo, siempre** — nunca dejar que el shell se recargue solo y seguir
  trabajando encima.

- **Gatear el `running:` de toda animación.** Prohibido `FrameAnimation { running:
  true }` incondicional. Atarlo a actividad real (visible, no en pausa, y algo
  que de verdad se mueva). En reposo, parar el bucle del todo y repintar una vez
  al cambiar los datos. Preferir un `Timer` con `interval` regulable a
  `FrameAnimation` para poder bajar los fps cuando no hacen falta.

- **`Canvas` 2D: nada de `shadowBlur` a ritmo de animación** — es un gaussian
  por-píxel en el hilo GUI. Para resplandores, gradiente radial; para algo más
  pesado, `ShaderEffect` / `Shape` en GPU.

