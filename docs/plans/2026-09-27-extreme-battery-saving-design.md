# Diseño Técnico: Optimización Extrema de Batería y Conmutación de Refresco (144Hz ↔ 60Hz)

- **Fecha:** 2026-09-27
- **Autor:** Antigravity / Gemini
- **Estado:** Propuesta / En curso
- **Hardware objetivo:** Lenovo LOQ / Legion (83GS) — Intel Alder Lake-HX (iGPU UHD 770) + NVIDIA GeForce RTX 4050 Max-Q/Mobile + Pantalla 1080p 144Hz (`eDP-2`).

---

## 1. Contexto y Diagnóstico Inicial

En la primera fase de ahorro (`docs/plans/2026-09-08-power-saving-battery-mode-design.md`), se implementó:
- Detección reactiva de desconexión AC (`UPower.onBattery`) y perfil `power-saver` en `PowerSaving.qml`.
- Fondo negro puro y apagado de widgets en `Background.qml`.
- Supresión de animaciones (`0 ms` en `Anim.qml`) y composición aligerada en Hyprland.
- Descarga total de Laura (`laura.service`) liberando 1.5 GB–2.7 GB de RAM/VRAM.

### Diagnóstico de Telemetría Real en Batería (Medido en el sistema):
- **Consumo actual en reposo:** **24.39 W** (autonomía estimada: ~1.7 h al 68%).
- **Tasa de refresco:** Fijada a **144.00 Hz** en batería.
- **dGPU NVIDIA:** Permanece en estado **P3 consumiendo 9.88 W** a 0% de uso.
- **Intel Turbo Boost:** Activado (`intel_pstate/no_turbo = 0`). Genera picos de hasta 55W+ por tareas breves.
- **WiFi Power Save:** Desactivado (`Power save: off` a 22 dBm).
- **Audio Codec Power Save:** Desactivado (`snd_hda_intel/parameters/power_save = 0`).
- **Servicios cosméticos en bucle:** `argb-wave.service` activo en bucle i2c continuo.

---

## 2. El porqué del fallo de la IA anterior (144Hz → 60Hz)

Una IA previa afirmó erróneamente que no se podía cambiar la tasa de refresco dinámicamente mediante `hyprctl`.

### La Causa Técnica:
En configuraciones tradicionales de Hyprland (`hyprland.conf`), se utiliza:
```bash
hyprctl keyword monitor "eDP-2,1920x1080@60,auto,1"
```
Sin embargo, en este sistema Hyprland utiliza la configuración basada en **Lua** (`hyprland.lua`). Al ejecutar `hyprctl keyword`, el compositor rechaza el comando con:
```
keyword can't work with non-legacy parsers. Use eval.
```
La IA interpretó el rechazo como imposibilidad de cambio dinámico.

### La Solución Verificada:
El cambio dinámico en caliente funciona inmediatamente ejecutando la evaluación Lua a través de IPC:
```bash
# Cambiar a 60 Hz en batería:
hyprctl eval "hl.monitor({ output = 'eDP-2', mode = '1920x1080@60.00Hz' })"

# Restaurar a 144 Hz en corriente:
hyprctl eval "hl.monitor({ output = 'eDP-2', mode = '1920x1080@144.00Hz' })"
```
Al omitir `position` o reutilizar la posición actual, Hyprland conserva las coordenadas espaciales, escala y perfiles de color sin parpadeos ni reinicio del compositor.

---

## 3. Catálogo de Mejoras para Ahorro Extremo

| Área | Medida | Impacto Estimado | Estado Actual |
| :--- | :--- | :--- | :--- |
| **Pantalla** | Conmutación 144Hz → 60Hz en batería vía `PowerSaving.qml` | ~2.5 W – 4.0 W | Verificado manualmente |
| **dGPU** | Forzar suspensión Runtime D3 (`D3cold` / 0W) en la RTX 4050 | ~8.0 W – 10.0 W | P3 consumiendo 9.88W |
| **CPU** | Desactivar Intel Turbo Boost en batería (`no_turbo = 1`) | ~5.0 W – 15.0 W (en picos) | `no_turbo = 0` |
| **WiFi** | Activar ahorro de energía IEEE 802.11 (`iw set power_save on`) | ~0.8 W – 1.5 W | Desactivado (`off`) |
| **Audio** | Activar reposo del codec Intel (`snd_hda_intel power_save=1`) | ~0.3 W – 0.7 W | Desactivado (`0`) |
| **Servicios** | Detener `argb-wave.service` y atenuar LEDs de periféricos | ~1.0 W – 2.5 W | Activo |
| **Brillo** | Reducir brillo al 35% y DPMS sleep a 2-3 minutos de inactividad | ~2.0 W – 3.5 W | Manual |

**Potencial de Ahorro Combinado:** El consumo del equipo en reposo/ofimática puede descender de **~24.4 W a ~9 W – 12 W**, multiplicando la autonomía de **~1.7 horas a más de 4–5 horas**.

---

## 4. Integración en `PowerSaving.qml`

Se añaden métodos reactivos dentro del singleton existente:

```qml
function setInternalMonitorHz(hz: int): void {
    const mon = Hypr.monitors.values.find(m => m.name.startsWith("eDP"));
    const output = mon ? mon.name : "eDP-2";
    Quickshell.execDetached([
        "hyprctl", "eval",
        `hl.monitor({ output = '${output}', mode = '1920x1080@${hz}.00Hz' })`
    ]);
}
```

- Al dispararse `active = true`:
  - `applyHyprlandConfs()` ejecuta `setInternalMonitorHz(60)`.
  - Detiene `argb-wave.service` junto a `laura.service`.
- Al dispararse `active = false`:
  - `restoreHyprlandConfs()` ejecuta `setInternalMonitorHz(144)`.
  - Restaura `argb-wave.service` y `laura.service`.
