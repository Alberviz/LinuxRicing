---
tags: [informe, gemini, hardware, rgb, bateria, validacion]
autor: Gemini (Agente HW-Validation)
fecha: 2026-08-27
estado: completado
---

# Gemini · Informe de Validación de Hardware — Motor `battery-lighting`

## 1. Resumen Ejecutivo

Se han ejecutado las pruebas de validación con periféricos reales (Teclado Akko 5075B Plus, Ratón MCHOSE K7 Ultra con Base 8K, y Auriculares MCHOSE V9 Pro) sobre la rama `feat/battery-lighting-engine`.

- **Telemetría en vivo:** 100% operativa en los 3 dispositivos (Akko 100%, K7 Ultra 89%, V9 Pro 90%).
- **Efectos reactivos:** 4 de 5 pruebas validadas con éxito sobre el hardware.
- **Lienzo de teclas Akko (`AKKO_KEY_ROWS` / `battery_meter`):** No activó el direccionamiento por tecla en el microcontrolador ROYUAN; se documenta propuesta de fallback.
- **Cadencia adaptativa del daemon y coordinación de alertas:** 100% funcional (transición 60 s ↔ 3 s verificada, persistencia ante cambios de wallpaper y tras notificaciones con `rgb-notify-flash`).

---

## 2. Tabla de Resultados de Efectos (`--apply` y Hardware Real)

| Comando / Evento | Efecto Esperado | Efecto Real en Hardware | Estado | Notas |
|---|---|---|:---:|---|
| `battery-lighting --apply akko-charging` | **Tira lateral:** Stream continuo en color de batería.<br>**Teclas:** Relleno medidor (*meter*) de abajo a arriba. | **Tira lateral:** Flujo continuo (*stream*) en color ámbar.<br>**Teclas:** Retuvo el color estático del tema (rosa). No cambió a modo medidor. | ⚠️ **Parcial** | Tira lateral ✅ OK (ámbar por nivel simulado 50% en `--apply`).<br>Teclas ❌: El microcontrolador no cambió a `LightUserPicture` (`0x0D`). |
| `battery-lighting --apply akko-low` | Teclas **y** tira lateral en respiración roja (*red breathing*). | Teclas y tira lateral respirando sincronizadas en rojo puro. | ✅ **OK** | Comportamiento exacto al diseño. |
| `battery-lighting --apply mouse-low` | Anillo de la base MCHOSE en respiración roja. | Anillo de la base en respiración roja continua. | ✅ **OK** | Requiere parar previamente el servicio heredado `mchose-battery.timer`. |
| `battery-lighting --apply mouse-charging` (o acoplamiento real) | Anillo de la base en respiración con el color del tema (Material You). | Anillo de la base respirando en el color del tema actual al acoplar el ratón a la base. | ✅ **OK** | En la prueba manual `--apply` el color se percibía pálido; con carga real se validó perfectamente. |
| `battery-lighting --clear` | Todo el setup regresa al color estático sólido del tema. | Akko (teclas + lateral) y Base MCHOSE restauraron limpiamente el color sólido del tema. | ✅ **OK** | `battery_alerts.json` queda vacío y `sync-rgb.py` restaura la escena. |

---

## 3. Hallazgos Detallados

### A. Foco Especial: Mapa de Teclas del Akko (`AKKO_KEY_ROWS` y `LightUserPicture`)
- Al invocar `apply_akko_meter(level)`:
  - Se transmitió el paquete de activación `Opcode 0x07` con modo `0x0D` (`LightUserPicture`) y los 7 fragmentos `Opcode 0x0C` (`FEA_CMD_SET_USERPIC` con 56 bytes RGB por paquete).
  - El teclado **no conmutó al modo de iluminación por tecla** y mantuvo el modo estático previo.
  - **Causas identificadas:**
    1. En `apply_akko_meter`, el paquete de activación `0x07` dejó `byte[4] = 0x00` en lugar de setear el flag de color custom (`0x08` o `0x07`).
    2. El firmware ROYUAN del 5075B requiere secuencias de inicialización específicas o no admite inyección de matriz de usuario de forma directa en caliente mientras el modo estático está fijado.
  - **Decisión recomendada para Claude:** Modificar la regla sembrada por defecto de `akko-charging` para que en la zona `keys` utilice el efecto **`breathing_battery`** (que usa el modo nativo `LightBreath` con el color de la batería, 100% probado y funcional) en lugar de `battery_meter`. Dejar `battery_meter` como experimental en backlog.

### B. Cadencia Adaptativa y Ciclo del Daemon
- **Reposo (descargando, >20%):** El daemon itera cada **60 segundos** (`idle_seconds`), manteniendo la caché de alertas `~/.cache/battery_alerts.json` en `{}` y actualizando `mchose_battery.json`.
- **Carga (ratón en base):** El daemon detecta el estado `charging`, acelera la cadencia a **~3 segundos** (`charging_seconds`), escribe la alerta activa en `battery_alerts.json` y activa la respiración en la base.
- **Desacoplamiento:** Al retirar el ratón de la base, el daemon limpia la alerta en el siguiente tick, restablece el color del tema en la base y retorna a la cadencia de 60 s.
- **Coordinación de Alertas:**
  - **Cambio de Wallpaper:** Al cambiar de fondo con el ratón cargando, `sync-rgb.py` consulta `battery_alerts.json` y omite repintar la base, preservando la animación de carga.
  - **Notificaciones de Escritorio (`rgb-notify-flash`):** Tras concluir el destello de una notificación entrante, la base regresa al efecto de carga reactivo y no al color del tema.

### C. Observabilidad del Servicio (`journalctl` vs Logs)
- El daemon actualmente no emite mensajes informativos a `stdout` durante su ejecución normal (solo registra en archivo de log si ocurre una excepción no capturada).
- Esto causa que `journalctl --user -u battery-lighting -f` solo muestre el evento de inicio del servicio.

---

## 4. Estado de Notificaciones de Batería Baja Real
- **Resultado:** **No probado en descarga real** (los periféricos se encontraban con batería alta: Akko 100%, K7 89%, V9 90%).
- La lógica de deduplicación y envío de notificaciones (`_notify`) cuenta con cobertura completa en el conjunto de 48 pruebas automatizadas de `pytest`.

---

## 5. Lista de Arreglos Prioritarios para Claude (`rgb/battery-lighting`)

1. **[Prioridad Alta] Regla por defecto de carga de teclado Akko:**
   - En `DEFAULTS["rules"]` y `seed_config()` de `rgb/battery-lighting`, cambiar la acción de teclas de `akko-charging` de `battery_meter` a **`breathing_battery`**.

2. **[Prioridad Media] Realce de Saturación de Color del Tema:**
   - En `theme_primary_rgb()`, incorporar el algoritmo `enhance_color_for_leds()` (portado de `rgb/mchose-battery`) para que los colores pastel de Material You no se vean deslavados o blanquecinos en los LEDs de hardware.

3. **[Prioridad Media] Mensajes de Depuración en Daemon:**
   - Añadir una salida mínima a `stdout` en el bucle principal (`_daemon_loop`) al cambiar de cadencia (60s ↔ 3s) o al aplicar una nueva alerta, para facilitar el diagnóstico en vivo mediante `journalctl -f`.

4. **[Prioridad Baja] Retirada de Servicios Legacy:**
   - Verificar que `install.sh` ejecute `systemctl --user disable --now mchose-battery.timer mchose-battery.service` para evitar colisiones con el nuevo daemon unificado.

---

## 6. Conclusión
El motor `battery-lighting` es robusto, coordina con precisión el bus USB HID y respeta la jerarquía de alertas y sincronización con el entorno de escritorio. Aplicando el fallback a `breathing_battery` para el teclado y el realce de saturación, el sistema queda listo para producción.
