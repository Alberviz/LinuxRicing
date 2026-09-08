# Diseño Técnico: Modo Ahorro Máximo en Caelestia (Batería y Fondo Negro)

**Fecha:** 2026-09-08  
**Autor:** Antigravity / Gemini  
**Estado:** Validado  

---

## 1. Objetivos y Requisitos

1. **Ahorro extremo de energía al desconectar corriente:**
   - Detectar cuando el equipo esté en batería (`UPower.onBattery`) o cuando el perfil sea `power-saver`, o cuando la batería baje de 20%.
   - Minimizar todo consumo inútil de GPU y CPU.
2. **Fondo negro puro y desconexión de widgets en `Background.qml`:**
   - Desactivar la carga de fondo de pantalla (`active: false` en `Wallpaper`), garantizando fondo negro plano (`#000000`).
   - Desactivar `DesktopCircularMedia` (detiene visualizador Cava y bucle GL).
   - Desactivar `DesktopPeripherals`, `DesktopWidgetDeck` y `DesktopLedStrip` (`active: false`, eliminando timers y subprocesos).
   - Mantener visible el reloj (`DesktopClock`), pero desconectar efectos costosos de `MultiEffect` (blur y shadow).
3. **Animaciones instantáneas en Quickshell:**
   - En `Anim.qml`, forzar duración `0 ms` cuando el modo ahorro esté activo, anulando el renderizado de frames en transiciones.
4. **Optimización de compositor Hyprland y perfil de CPU:**
   - Conmutar el perfil del sistema a `power-saver` mediante `PowerProfiles`.
   - Desactivar animaciones, blur y sombras en Hyprland dinámicamente con `Hypr.extras.applyOptions()`. Restaurar al volver a enchufar.

---

## 2. Arquitectura de Componentes

```
                  ┌──────────────────────┐
                  │ UPower / DisplayDev  │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │  PowerSaving.qml     │ (Singleton en services/)
                  │  - active: bool      │
                  │  - applies Hyprland  │
                  │  - switches CPU prof │
                  └──────────┬───────────┘
                             │
     ┌───────────────────────┼────────────────────────┐
     ▼                       ▼                        ▼
┌──────────────┐     ┌───────────────┐        ┌──────────────┐
│Background.qml│     │   Anim.qml    │        │ Hyprland     │
│- Black bg    │     │- duration: 0  │        │- anims: 0    │
│- No wallpaper│     │  (no frame    │        │- blur: 0     │
│- Clock only  │     │   churn)      │        │- shadow: 0   │
│- No widgets  │     └───────────────┘        └──────────────┘
└──────────────┘
```

---

## 3. Plan de Verificación

1. Comprobación de sintaxis QML e inicio con `caelestia shell -d`.
2. Prueba con `powerprofilesctl set power-saver` y con simulación/evento de desconexión de corriente.
3. Confirmación de que el fondo sea negro puro, los widgets desaparezcan excepto el reloj, y las animaciones sean instantáneas.
4. Confirmación de que al volver a corriente o cambiar de perfil se restaure el wallpaper, widgets y animaciones.
