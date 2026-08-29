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
     pkill -9 -f "qs -c caelestia" 2>/dev/null; sleep 0.8; caelestia shell -d
     ```
  3. Comprobar que la salida confirme `INFO: Configuration Loaded` sin errores de sintaxis o propiedades QML.

