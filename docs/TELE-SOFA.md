# Tele en el sofá: pantalla de trabajo y escaparate

Sistema completo para usar la tele conectada por HDMI (`HDMI-A-1` o cualquier monitor externo que no empiece por `eDP`) como pantalla de trabajo o visualización desde el sofá en Hyprland (configuración Lua) y Quickshell / Caelestia.

## Las 3 piezas principales

### 1. «Mandar a la tele» (toggle por atajo)

Mueve la ventana activa al instante entre el portátil y la tele con un solo atajo.

- **Atajo:** `SUPER + SHIFT + T`
- **Helper:** `widgets/tele-window` → `~/.local/bin/tele-window`
- **Comportamiento:**
  - Si la ventana activa **no** está en la tele: la mueve a la tele, la enfoca y la pone a pantalla completa (`fullscreen`). Guarda el estado previo (monitor, workspace original, fullscreen) en `$XDG_RUNTIME_DIR/tele-window/<address>.json`. Notifica: *«En la tele: <título>»*.
  - Si la ventana activa **ya** está en la tele: quita la pantalla completa, la devuelve a su workspace/monitor original en el portátil y la enfoca. Notifica: *«De vuelta al portátil»*.
- **Detección dinámica:** No fija nombres estáticos. La tele se detecta como el primer monitor cuyo nombre no comience por `eDP`; el portátil es el monitor `eDP-*`. Si no hay tele HDMI conectada, lanza un aviso por `notify-send` y no interrumpe el entorno.

---

### 2. «Escaparate» (lo que quieres proyectar en la tele)

Permite proyectar contenidos dedicados en la tele en un workspace fijado (`name:tele`), a pantalla completa y sin robar el foco del monitor del portátil.

- **Configuración:** `~/.config/caelestia/escaparate.json` (ejemplo en `configs/caelestia/escaparate.example.json`).
  Lista de objetos:
  ```json
  [
    {
      "id": "video-demo",
      "name": "Efectos Visuales (Loop)",
      "icon": "movie",
      "kind": "video",
      "target": "/home/alberviz/Vídeos/effectcraft-smoketest.mp4"
    },
    {
      "id": "olimpo",
      "name": "Olimpo (Tareas)",
      "icon": "task_alt",
      "kind": "web",
      "target": "https://vizcapon-pi.tail76abc5.ts.net:8443"
    },
    {
      "id": "reloj-sala",
      "name": "Reloj de Sala (HTML)",
      "icon": "schedule",
      "kind": "web",
      "target": "/home/alberviz/.config/caelestia/escaparate-reloj.html"
    },
    {
      "id": "web-dev",
      "name": "Servidor Web Local",
      "icon": "language",
      "kind": "web",
      "target": "http://localhost:5173"
    }
  ]
  ```
- **Tipos de contenido (`kind`):**
  - `video`: reproductor `mpv` en bucle infinito (`--loop-file=inf`), pantalla completa, sin terminal, con socket de control IPC en `$XDG_RUNTIME_DIR/escaparate/mpv.sock` para pausar y salir sin dejar procesos zombies.
  - `web`: `chromium --app=<url>` con perfil de usuario independiente en `~/.cache/escaparate-chromium`. Si `target` es un archivo HTML local, arranca un vigilante en segundo plano (`inotifywait` o sondeo mtime) que envía la tecla `F5` a la ventana mediante `hl.dsp.send_shortcut` al guardar cambios.
  - `cmd`: ejecuta cualquier comando del sistema y acomoda su ventana en la tele.
- **Helper CLI:** `widgets/escaparate` → `~/.local/bin/escaparate`
  - `escaparate list`: devuelve en JSON la lista de elementos configurados.
  - `escaparate status`: devuelve el estado actual en JSON (`active`, `id`, `name`, `kind`, `pid`, etc.).
  - `escaparate show <id>`: lanza el elemento en la tele (`name:tele`), a pantalla completa, y devuelve inmediatamente el foco al monitor del portátil.
  - `escaparate open-target <ruta|url>`: abre cualquier archivo o URL al vuelo (vídeo, imagen, web) creando una sesión dinámica.
  - `escaparate off`: cierra el reproductor o ventana activa, desactiva la regla `_G.tele_rule` de Hyprland y devuelve la tele al workspace `8`.
- **Selector visual en Quickshell (`configs/quickshell/caelestia/modules/escaparate/`):**
  - **Atajo:** `SUPER + SHIFT + E`
  - Diálogo modal centrado en el portátil con estética Caelestia (paleta Material 3, tipografías y redondeos del sistema).
  - Muestra tarjetas con icono Material Symbol, título, detalle y píldora de atajo numérico (1–9).
  - La tarjeta activa se resalta con borde de acento y píldora «Activo».
  - **Navegación:**
    - Flechas `Arriba`/`Abajo`: seleccionar tarjetas con foco visible.
    - `Enter`: proyectar elemento seleccionado.
    - Números `1`–`9`: acceso directo al elemento correspondiente.
    - `O` o `Delete`/`Backspace`: apagar escaparate.
    - `Esc`: cerrar diálogo.
    - También operable con ratón (clic en tarjetas o botones).
  - **Interfaz IPC (para Elysium u otros módulos):**
    - `qs -c caelestia ipc call escaparate toggle`
    - `qs -c caelestia ipc call -- escaparate show <id>` (o `showItem <id>`)
    - `qs -c caelestia ipc call escaparate off`
    - `qs -c caelestia ipc call escaparate list`

---

### 3. Soltar en la tele (Portales / Drag & Drop)

Integración completa con el sistema de portales gravitatorios Gargantua de Caelestia (`modules/portals/`).

- **Ubicación del portal:** **Borde inferior** de la pantalla del portátil (`edge: "bottom"`).
  - *¿Por qué el borde inferior?*
    1. **Borde superior:** reservado para Warp / Olimpo (móvil y tablet).
    2. **Borde derecho:** reservado para Chromecast («Гоiniная»). Además, la tele HDMI está situada lógicamente a la derecha (`x=1920`); situar el portal en el borde derecho provocaría colisiones accidentales al cruzar el ratón entre pantallas.
    3. **Borde inferior:** ofrece una banda amplia (`width * 0.62`, `height: 140 * u`), limpia, sin conflicto con otros destinos ni con el puntero.
- **Condición de presencia:** El portal inferior solo se activa y dibuja cuando `hasTeleHdmi` es verdadero (se detecta una pantalla HDMI conectada en `Screens.screens`). Si no hay cable HDMI conectado, el borde inferior permanece inactivo y no interfiere en absoluto.
- **Acción al soltar:**
  - Vídeos (`.mp4`, `.mkv`, `.webm`, etc.) → se proyectan en bucle con `mpv` a pantalla completa en la tele.
  - Imágenes (`.jpg`, `.png`, `.webp`, `.gif`, etc.) → se muestran a pantalla completa en la tele.
  - URLs (`http://`, `https://`) o archivos `.html` → se abren con `chromium --app`.
- **Efectos visuales:** Usa el mismo ShaderEffect de portal gravitatorio (`portal.frag.qsb` con vector normal hacia abajo `outward = (0, 1)`), absorción del icono del archivo arrastrado, y tarjeta persistente de estado HUD.

---

## Estructura de archivos

```
configs/
├── caelestia/
│   ├── escaparate.example.json   # Plantilla de configuración
│   └── escaparate-reloj.html     # Reloj de sala minimalista para escaparate
├── hypr/
│   └── hyprland/
│       └── keybinds.lua          # Atajos SUPER+SHIFT+T y SUPER+SHIFT+E
└── quickshell/
    └── caelestia/
        ├── shell.qml             # Registro del módulo escaparate
        └── modules/
            ├── escaparate/
            │   ├── Content.qml           # Contenido del diálogo y navegación
            │   ├── EscaparateCard.qml    # Componente tarjeta de escaparate
            │   └── EscaparateDialog.qml  # Ventana overlay, atajos e IPC
            └── portals/
                ├── Portal.qml            # Adaptado para soportar edge: "bottom"
                └── Portals.qml           # Integración del portal Tele HDMI inferior
widgets/
├── tele-window                   # Script toggle ventana a tele
└── escaparate                    # Gestor CLI de escaparate (list/status/show/open-target/off)
install.sh                        # Instalador actualizado para los nuevos helpers
docs/
└── TELE-SOFA.md                  # Esta documentación
```

## Pruebas y verificación

1. **Atajo `SUPER + SHIFT + T` (`tele-window`):**
   - Probado con ventana de prueba (`foot --app-id teletest`).
   - Trasladó la ventana al monitor 1 (HDMI-A-1) a pantalla completa (`fullscreen: 2`).
   - Al pulsarlo de nuevo, devolvió la ventana a `eDP-2` sin pantalla completa (`fullscreen: 0`).
2. **Escaparate (`widgets/escaparate` y diálogo Quickshell):**
   - Apertura del diálogo con `SUPER + SHIFT + E` e IPC `escaparate toggle`.
   - Proyección de vídeo (`video-demo`): reproducción verificada en HDMI-A-1 sin perder el foco en el portátil.
   - Proyección de reloj HTML (`reloj-sala`): Chromium en modo app con vigilante de recarga automática.
   - Apagado con `escaparate off`: cierra las ventanas y devuelve HDMI-A-1 al workspace `8`.
3. **Soltar en la tele (Portales):**
   - Probado con `qs -c caelestia ipc call portals dropHdmi <archivo>`.
   - Generación y animación del horizonte de sucesos en el borde inferior con tarjeta HUD «Mostrando en la tele HDMI».
