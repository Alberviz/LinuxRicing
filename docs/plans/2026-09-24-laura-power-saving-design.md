# Diseño: Desactivación de Laura en Modo Ahorro y Batería

- **Fecha:** 2026-09-24
- **Estado:** Validado
- **Área:** `assistant/`, `configs/quickshell/caelestia/services/`

---

## 1. Contexto y Motivación

El asistente de voz local Laura (`laurad.py`) arranca como un servicio de usuario (`laura.service`) habilitado en `graphical-session.target`. Durante su inicio:
1. Precarga los modelos neuronales Faster-Whisper, PyTorch, Silero VAD y Kokoro TTS.
2. Consume de forma permanente entre **1.5 GB y 2.7 GB de memoria RAM/VRAM**.
3. Inicializa contextos CUDA / PyTorch que impiden que la GPU y la CPU alcancen sus estados de suspensión de ultra-bajo consumo (*C-states* profundos).
4. Si se invoca una interacción por voz, el procesamiento simultáneo de Whisper, Ollama (Qwen 4B) y Kokoro genera picos de consumo de hasta 30W–50W+, agotando la batería rápidamente.

El objetivo de este diseño es asegurar que en modo ahorro (portátil desenchufado, perfil `power-saver` o batería baja) el asistente esté completamente descargado de la memoria, consumiendo **0 W y 0 MB adicionales de RAM**, y que el sistema informe al usuario de manera clara si intenta invocarlo.

---

## 2. Arquitectura de la Solución

La solución opera en tres capas complementarias:

### A. Prevención en Arranque (`assistant/laura.service`)
* Se añade la directiva nativa de systemd:
  ```ini
  ConditionACPower=true
  ```
* **Comportamiento:** Si el portátil arranca sin estar conectado al cargador de corriente (CA / AC), systemd evalúa la condición como falsa y **omite el inicio del servicio**.
* No se ejecuta Python, no se cargan modelos y la condición no genera errores ni disparadores de reinicio (`RestartSec`).

### B. Ciclo de Vida Reactivo en Caliente (`PowerSaving.qml`)
* En `configs/quickshell/caelestia/services/PowerSaving.qml`, la propiedad reactiva `active` detecta:
  * `UPower.onBattery` (desconectado del cargador).
  * `PowerProfiles.profile === PowerProfile.PowerSaver`.
  * `isLowBattery` (nivel de carga ≤ 20%).
* **Al entrar en ahorro (`active = true`):**
  * Comprueba si `laura.service` está activo (`systemctl --user is-active --quiet laura`).
  * Si está activo, lo detiene con `systemctl --user stop laura` y marca la variable interna `lauraAutoStopped = true`.
  * Libera inmediatamente toda la RAM y recursos de GPU.
* **Al salir de ahorro (`active = false`):**
  * Si `lauraAutoStopped == true` (o como restauración de servicios de escritorio), ejecuta `systemctl --user start laura`.
  * Limpia la variable `lauraAutoStopped = false`.
  * `Laura.qml` restablece la conexión al socket automáticamente en cuanto el daemon vuelve a estar listo.

### C. Feedback Amigable al Usuario (`assistant/laura-toggle`)
* Si el usuario pulsa el atajo de Laura (`SUPER + A` o `SUPER + SHIFT + A`) mientras está en batería o modo ahorro:
  * `laura-toggle` detecta que el socket no está disponible.
  * Verifica si el sistema está en batería o perfil `power-saver` (mediante `powerprofilesctl get` o `upower -i /org/freedesktop/UPower/devices/battery_BAT0`).
  * En lugar de mostrar un error críptico («El daemon no está corriendo»), emite una notificación elegante con `notify-send`:
    * Título: *Laura en reposo*
    * Icono: *battery-profile-powersave-symbolic*
    * Cuerpo: *El asistente está desactivado en batería para maximizar la autonomía.*

---

## 3. Manejo de Errores y Casos Límite

| Escenario | Comportamiento |
| :--- | :--- |
| **Arranque desenchufado** | `laura.service` se omite por `ConditionACPower=true`. Consumo 0. |
| **Enchufar cargador tras arrancar con batería** | `PowerSaving.qml` detecta `active = false` y arranca `laura.service`. |
| **Desenchufar cargador en mitad de sesión** | `PowerSaving.qml` detecta `active = true`, detiene `laura.service`, liberando la RAM. |
| **Pulsar Super+A en modo ahorro** | Notificación informativa indicando que está en reposo por batería. |
| **Caída inesperada de Laura con cable (AC)** | `laura-toggle` muestra notificación de error real («El daemon no está corriendo»). |

---

## 4. Plan de Verificación

1. **Prueba estática y de sintaxis:**
   * Validar sintaxis del archivo systemd con `systemd-analyze verify`.
   * Validar sintaxis de `PowerSaving.qml` mediante reinicio de Caelestia shell (`caelestia shell -d`).
   * Validar script `laura-toggle` ejecutándolo directamente.
2. **Prueba dinámica:**
   * Verificar parada del servicio al activar modo ahorro (`systemctl --user is-active laura`).
   * Verificar liberación de memoria y procesos Python asociados.
   * Probar pulsación de `laura-toggle` y confirmar notificación contextual.
   * Verificar reactivación limpia al conectar cargador / desactivar modo ahorro.
