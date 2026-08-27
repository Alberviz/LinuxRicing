---
tags: [qa, bugs, rgb, bateria, background]
actualizado: 2026-08-27
relacionado: "[[Base de Datos de Errores]]", "[[BATTERY_LIGHTING_HANDOFF]]"
---

# QA · Motor de Batería — registro de bugs

> [!info] Cómo funciona esto
> **Alberto** prueba el panel y los efectos, y **añade bugs abajo** con el formato de
> plantilla. El agente **`qa-fixer`** de Gemini drena la lista: coge el primer bug
> `🔴 abierto`, lo reproduce, lo arregla en su propio worktree, lo verifica, commitea a
> `main` (o a una rama si es grande) y lo marca `✅ resuelto` con el commit y una línea de
> qué era. Los bugs `🟡 en curso` no se tocan (otro agente los tiene).

## Estado del sistema

- Motor mergeado a `main` @ `b084a4e`. 51 tests pytest en verde.
- Panel QML: sección «Reacciones de batería» en Notificaciones.
- Instalado: (marca aquí cuando hayas hecho `install.sh` y activado el `.service`).

---

## Plantilla de bug (copiar)

```
### BUG-NNN · <título corto>
- **estado:** 🔴 abierto
- **dónde:** <panel / efecto / daemon / config …>
- **repro:** <pasos exactos>
- **esperado:** <qué debería pasar>
- **real:** <qué pasa>
- **notas:** <capturas, logs de `journalctl --user -u battery-lighting -f`, etc.>
```

---

## Bugs

### BUG-001 · Desplegables del panel salen expandidos y la página no scrollea
- **estado:** ✅ resuelto — commits `e5eaa95` + `b084a4e` (StyledFlickable + WheelHandler + tarjetas colapsadas por defecto). Verificado por Alberto.
- **dónde:** panel · pestaña Notificaciones
- **real (era):** las `BatteryRuleCard` salían desplegadas y el contenido desbordaba la
  pantalla sin scroll → imposible interactuar.

<!-- Alberto: añade los nuevos aquí abajo -->
