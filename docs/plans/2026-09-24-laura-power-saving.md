# Desactivación de Laura en Modo Ahorro Implementation Plan

> **For Gemini:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Evitar que el asistente Laura cargue modelos de IA en arranque con batería y apagarlo automáticamente en modo ahorro para liberar RAM/GPU y ahorrar batería.

**Architecture:** Modificación de `assistant/laura.service` con `ConditionACPower=true` para el arranque, ampliación de `PowerSaving.qml` para detener/arrancar `laura.service` reactivamente en cambios de energía, y actualización de `assistant/laura-toggle` para informar al usuario de manera contextual al pulsar `Super+A`.

**Tech Stack:** systemd (user service), QML / Quickshell, Python 3.

---

### Task 1: Añadir `ConditionACPower=true` a `assistant/laura.service`

**Files:**
- Modify: `assistant/laura.service:5-10`
- Sync: `~/.config/systemd/user/laura.service`

**Step 1: Modificar la unidad systemd**
Añadir `ConditionACPower=true` en la sección `[Unit]`:
```ini
[Unit]
Description=Laura — asistente de voz local
After=graphical-session.target pipewire.service
Wants=pipewire.service
ConditionACPower=true
```

**Step 2: Sincronizar y recargar el daemon systemd de usuario**
```bash
cp assistant/laura.service ~/.config/systemd/user/laura.service
systemctl --user daemon-reload
```

**Step 3: Verificar que systemd reconoce la condición**
```bash
systemctl --user show laura.service -p ConditionACPower,ConditionsOk
```
Expected: `ConditionACPower=yes`, y `ConditionsOk=no` si está actualmente desenchufado.

**Step 4: Commit**
```bash
git add assistant/laura.service
git commit -m "feat(assistant): omitir arranque de Laura en batería con ConditionACPower"
```

---

### Task 2: Actualizar `PowerSaving.qml` para gestionar el ciclo de vida de Laura

**Files:**
- Modify: `configs/quickshell/caelestia/services/PowerSaving.qml`
- Sync: `~/.config/quickshell/caelestia/services/PowerSaving.qml`

**Step 1: Añadir lógica de detención y restauración en `PowerSaving.qml`**
Añadir propiedad de seguimiento y llamadas `Quickshell.execDetached`:
- Cuando `active` pasa a `true` (en batería o power-saver):
  - Detener el servicio: `systemctl --user stop laura`
  - Marcar `lauraAutoStopped = true`
- Cuando `active` pasa a `false` (en corriente CA / balanced / performance):
  - Si `lauraAutoStopped == true`: `systemctl --user start laura`
  - Restaurar `lauraAutoStopped = false`

**Step 2: Sincronizar archivo a `~/.config/quickshell/caelestia/services/PowerSaving.qml`**
```bash
cp configs/quickshell/caelestia/services/PowerSaving.qml ~/.config/quickshell/caelestia/services/PowerSaving.qml
```

**Step 3: Reiniciar Caelestia Shell según regla obligatoria**
```bash
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```
Expected: `INFO: Configuration Loaded` sin errores.

**Step 4: Comprobar que `laura.service` se detiene inmediatamente al estar en batería**
```bash
systemctl --user is-active laura
```
Expected: `inactive` (o `failed`/`deactivating` inmediatamente pasando a `inactive`).

**Step 5: Commit**
```bash
git add configs/quickshell/caelestia/services/PowerSaving.qml
git commit -m "feat(power): detener y reanudar Laura automáticamente según estado de batería"
```

---

### Task 3: Actualizar `assistant/laura-toggle` con notificación contextual

**Files:**
- Modify: `assistant/laura-toggle:10-23`

**Step 1: Modificar `laura-toggle` para detectar batería/ahorro al fallar la conexión**
Si el socket no responde o no existe:
- Comprobar si `powerprofilesctl get` es `power-saver` o `/sys/class/power_supply/AC*/online` es 0 o `/sys/class/power_supply/BAT*/status` es `Discharging`.
- Si está en ahorro/batería:
  `notify-send -a Laura -i battery-profile-powersave-symbolic 'Laura en reposo' 'El asistente está desactivado en batería para maximizar la autonomía.'`
- En caso contrario:
  `notify-send -a Laura -i dialog-error-symbolic 'Laura' 'El daemon no está corriendo'`

**Step 2: Probar `laura-toggle` manualmente**
```bash
./assistant/laura-toggle
```
Expected: Notificación de "Laura en reposo" emitida correctamente con código de salida limpio.

**Step 3: Commit**
```bash
git add assistant/laura-toggle
git commit -m "feat(assistant): avisar en laura-toggle cuando el daemon esté en reposo por batería"
```

---

### Task 4: Verificación Integral y Documentación

**Step 1: Comprobar procesos en ejecución y memoria liberada**
```bash
ps aux | grep -iE "laurad\.py|whisper"
```
Expected: Ningún proceso `laurad.py` consumiendo RAM.

**Step 2: Probar cambio de perfil simulado o real**
Probar `powerprofilesctl set balanced` (si estuviera enchufado) o comprobar logs de `journalctl --user -u laura`.

**Step 3: Actualizar bitácora de sesión en `vault/🎯 Hoy.md`**
Registrar la tarea realizada según `AGENTS.md`.

**Step 4: Integrar y mergear la rama `feat/laura-power-saving` de vuelta a la rama base**
