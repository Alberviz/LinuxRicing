# Modo servidor (consola pura) — botón de ultra ahorro en Caelestia

**Fecha:** 2026-09-10
**Autor:** Claude (Sonnet 5)
**Estado:** Implementado
**Rama:** `feat/modo-servidor-consola` (desde `refactor/background-modularize`)

---

## 1. Objetivo

Un botón en la tarjeta *Quick Toggles* de Caelestia que deja el portátil en
**consola pura** ("modo servidor"), matando todo proceso de fondo no esencial para
que el equipo dure lo máximo en batería con el servidor de Minecraft abierto.

Es un escalón **por encima** del `PowerSaving.qml` existente (que se queda dentro de
Hyprland/Caelestia, recortado): el modo servidor **cierra el entorno gráfico entero**.

## 2. Qué se para y qué sobrevive

| Se apaga en modo servidor | Sobrevive (intacto) |
|---|---|
| Hyprland + Quickshell (`isolate multi-user.target`) | `minecraft-server.service` (user@1000 + linger) |
| `openrgb`, `argb-wave`, `battery-lighting`, `laura`, `mchose-audio-cleanup`, `ydotool`, `appimagelauncherd` | `minecraft-telegram-bot.service` |
| Procesos sueltos: `sync-rgb.py`, `mchose-battery`, `magichome-control`, `desktop-deck-helper`, `gtasks` | `playitd` (servicio de sistema) |
| Bluetooth (`rfkill block bluetooth`) | **La red WiFi** — el servidor la necesita |
| Perfil de CPU → `power-saver` | `user@1000.service` (gestor de usuario con linger) |
| LEDs de periféricos (best-effort: `openrgb --mode static --color 000000`) | |

El servidor de Minecraft y el bot cuelgan de `user@1000.service`, que corre con
**linger activado** y es independiente de la sesión gráfica. `playitd` es un servicio
de sistema. Por eso cerrar el escritorio no corta ninguna partida ni el túnel.

## 3. Componentes

```
 Botón "Server mode" (Toggles.qml)
        │ doble toque (confirmación: cierra el escritorio)
        ▼
 ServerMode.qml (singleton, services/)
        │ Quickshell.execDetached(["caelestia-server-mode", "on"])
        ▼
 ~/.local/bin/caelestia-server-mode  {on|off|status}
        │  - powerprofilesctl / systemctl --user stop / pkill / rfkill
        │  - sudo /usr/local/bin/caelestia-server-mode-root <verbo>
        ▼
 /usr/local/bin/caelestia-server-mode-root  {console|desktop|issue-on|issue-off}
        (root; NOPASSWD acotado vía /etc/sudoers.d/caelestia-server-mode)
```

- **`services/ServerMode.qml`** — singleton. `armed` + timer de 5 s para la
  confirmación de doble toque; `activate()` lanza el script; `IpcHandler` con target
  `serverMode` (`activate`, `isArmed`).
- **`widgets/caelestia-server-mode`** — el motor (bash). `on` / `off` / `status`.
- **`widgets/volver-escritorio`** — atajo de una línea (`caelestia-server-mode off`)
  para el camino de vuelta desde la consola.
- **`configs/system/caelestia-server-mode-root`** — helper privilegiado, 4 verbos
  fijos. Instalado en `/usr/local/bin/` (root:root 0755).
- **`configs/system/caelestia-server-mode.sudoers`** — regla `NOPASSWD` restringida
  EXACTAMENTE al helper. Instalada en `/etc/sudoers.d/caelestia-server-mode` (0440)
  tras validar con `visudo -c`.
- **UI:** `modules/utilities/cards/Toggles.qml` (delegado `serverMode`, icono `dns` /
  `power_settings_new` cuando está armado) y
  `modules/nexus/pages/panels/UtilitiesPanel.qml` (fila de ajustes).
- **Semilla:** `configs/caelestia/shell.json` añade `utilities.quickToggles` con
  `serverMode` incluido.
- **`install.sh`** — sección 3b/3c: copia los scripts de usuario e instala (con sudo)
  el helper + la regla sudoers validada.

## 4. Volver al escritorio

Desde la consola, tras iniciar sesión en el tty:

```
volver-escritorio
```

Restaura Bluetooth, servicios cosméticos y perfil `balanced`, y ejecuta
`systemctl isolate graphical.target` (que puede cortar la propia shell del tty al
reactivarse `greetd`; por eso las restauraciones baratas van **antes**). `/etc/issue`
muestra un recordatorio de este comando mientras el modo está activo.

## 5. Verificación

1. `qmllint` / `caelestia shell -d` → `INFO: Configuration Loaded` sin errores nuevos.
2. El botón aparece en *Quick Toggles*; primer toque → toast de confirmación; segundo
   toque en <5 s → cae a consola.
3. Desde otra máquina: el servidor de Minecraft sigue respondiendo (jugadores online).
4. `volver-escritorio` devuelve la sesión de Hyprland y rearranca los servicios.
