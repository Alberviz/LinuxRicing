# Motor de iluminación reactiva a la batería — Handoff

> **▶ para retomar:** el motor está **mergeado a `main`** (commit `b084a4e`). Backend
> completo y probado (51 tests), panel QML en Notificaciones, validado con hardware.
> Lo que queda: QA de Alberto (ver `QA · Motor de Batería.md` en el vault) + un backlog
> pequeño. Nada bloquea.

## Qué se construyó

- **`rgb/battery-lighting`** — daemon systemd `--user` con motor de reglas: enruta eventos
  de batería (cargando / baja / crítica) de los 3 periféricos a efectos de luz en 4
  destinos (anillo base MCHOSE, teclado Akko [teclas + tira], tira MagicHome, torre OpenRGB).
  Config en `~/.config/caelestia/battery-lighting.json` (se auto-siembra y migra de
  `akko-config.json` + `mchose-config.json`). CLI: `--daemon --tick --apply <id> --clear --dump`.
- **`configs/quickshell/caelestia/services/BatteryLightingConfig.qml`** — singleton, contrato
  de esquema con el motor. **Este es el fichero delicado: cambios aquí = cambios en el motor.**
- **`modules/rgbcontrol/BatteryRuleCard.qml` + `BatteryActionRow.qml`** — la UI. Sección
  «Reacciones de batería» en `NotificacionesView.qml`.
- `mchose-battery` adelgazado a solo telemetría (+ espejo `widgets/mchose-battery`).
- `sync-rgb.py` y `rgb-notify-flash` respetan `~/.cache/battery_alerts.json` (no pisan alertas).
- `systemd/battery-lighting.service`, `install.sh` actualizado.
- **Borrados:** `mchose-config{,.py}`, `mchose-charging-mode{,.py}`, `mchose-lowbat-mode`,
  `systemd/mchose-battery.{service,timer}`, `services/AkkoConfig.qml`, `services/MchoseConfig.qml`.
  `rgb/mchose-lighting` se mantiene (aplicación manual de modos).

## Instalar en la máquina

```bash
git pull                       # en el checkout principal
./install.sh                   # instala battery-lighting + el .service, retira mchose-battery.timer
systemctl --user enable --now battery-lighting.service
```

## Decisiones tomadas

- **Duplicación de helpers HID entre scripts:** deliberada (estilo del repo: un fichero por
  herramienta, sin módulos compartidos). No es deuda.
- **`battery_meter` en teclas del Akko:** el firmware ROYUAN del 5075B **no conmuta** al modo
  lienzo por-tecla. Default = `breathing_battery`. `battery_meter` queda seleccionable pero
  **experimental** (comentado en `EFFECTS` del motor).
- **`battery_meter` en la torre (OpenRGB):** v1 = color sólido por nivel. Relleno animado
  real (integrado con `argb-wave.py`) = **v2, backlog**.

## Backlog (ninguno bloquea)

1. Código muerto: `get_akko_battery_level_color` + import `colorsys` en `rgb/sync-rgb.py`.
2. `rgb-notify-flash restore()` — caso raro: si el binario `battery-lighting` no está
   instalado, los dispositivos con alerta no vuelven ni a tema ni a alerta.
3. Riesgo latente (no reproducido): con solo `akko_keyboard:sidestrip` reclamado,
   `sync-rgb.py` omite el paquete `0x08` de despertar RF — si el backlight se congela en
   blanco durante una alerta de tira lateral por 2.4 GHz, es esto.
4. `battery_meter` real (teclado y torre) — experimental.
5. Notificación de batería baja real: no probada en hardware (baterías altas). Cubierta por 48 tests.
6. Limpiar worktrees: `.worktrees/battery-lighting-engine`, `.worktrees/qml-battery-panel`,
   y los que dejara Gemini (`.worktrees/fixes`, `.worktrees/integracion`).

## Notas de agentes (proceso, en el vault)

`vault/Rice LinuxRicing/00 - Arquitectura/Tareas de Agentes/` — 4 handoffs de Claude + 4
informes de Gemini (QML-panel, hw-validation, integrador, fixes). Registro completo de
decisiones en `.superpowers/sdd/2026-08-27-battery-lighting-engine/progress.md` (gitignored,
en el worktree — cópialo si borras el worktree).
