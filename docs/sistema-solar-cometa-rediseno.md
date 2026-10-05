# Rediseño del cometa de tareas («meteorito») — exploración y plan

**Estado:** aparcado el 2026-10-05. Alberto pidió mockups, los vio y decidió no seguir hasta tener
claro el cómo. Tarea: `vault/Backlog/Rediseño visual del cometa de tareas (meteorito).md`
(`estado: idea`, prioridad 5). Esto documenta todo lo explorado para retomarlo sin repetir.

## 1. Punto de partida (el cometa actual)

- **Datos** (`configs/quickshell/caelestia/modules/background/solarsystem/Sim.js`, bloque «Cometa de
  tareas», ~l.368): un único cometa en una elipse amplia y lenta (~7 min/vuelta, `2π/420 · dt ·
  zComet`) alrededor del binario. Centro `bary + (0.06w, -0.04h)`, `rx = 0.27w`, `ry ≤ 0.27h`,
  inclinación `-0.10`. Cola contra el avance, `len = (46 + 14·min(n,18))·S`. **Sin tareas, no
  existe** (`comet = null`). Entrada: `values.taskCount`.
- **Dibujo** (`SolarSystem.qml`, «COMETA DE TAREAS», ~l.813): todo `Rectangle`/`Shape` en GPU:
  órbita (ShapePath, tenue; sube con hover `zComet`), cola de polvo (rectángulo 9 px, gradiente
  `colSecondary`), cola de iones (2 px, `colInk`), cabeza = halo (`colPrimary` 0.40, 4r) + núcleo
  (1.6r). Al enfocar (`zComet`) aparece una columna con las 3 próximas tareas; clic en la cabeza
  (`MouseArea` 48 px) emite `cometClicked()` → panel de tareas (`TasksPanel.qml`).
- **Limitación**: de las tareas solo se usa el **recuento**. `root.taskList` ya trae
  `[{prio, title}]` ordenado por prioridad, pero el dibujo no lo aprovecha.

## 2. Qué se quiere resolver

1. El cometa es muy pobre visualmente (línea + punto).
2. Debe **comunicar** cuántas tareas hay y cuáles son urgentes sin abrir nada (el escritorio es una
   herramienta informativa; ver memoria `solar-system-desktop-is-a-tool`).
3. Idea nueva de Alberto (2026-10-05): **nube de polvo estelar / nube de asteroides donde cada mota
   o roca es una tarea.**
4. Relacionado con la tarea de comportamiento «Cometa de tareas reactivo al número de tareas».

## 3. Mockup

`docs/sistema-solar-v3-mockup/cometa-variantes.html` (Canvas 2D, autocontenido). Parámetros de URL:
`n` (tareas), `p` (urgentes P1), `t` (segundos), `z` (zoom de detalle), `hover=1`, `live=0`.

```bash
chromium --headless --no-sandbox --disable-gpu --hide-scrollbars --window-size=1360,1900 \
  --virtual-time-budget=2500 --screenshot=/tmp/cometa.png \
  "file://$PWD/docs/sistema-solar-v3-mockup/cometa-variantes.html?n=9&p=2&live=0&t=-3&z=1.6"
```

Captura de referencia: `docs/sistema-solar-v3-mockup/cometa-variantes.png`.

## 4. Variantes exploradas

| | Idea | Codificación de datos | Pros | Contras |
|---|---|---|---|---|
| **0 · Actual** | línea + halo + punto | solo longitud de cola | ya existe, barato | pobre, casi sin información |
| **A · Roca** | meteorito rocoso poligonal que gira, cráteres, luz desde el sol, polvo curvo + cola de iones azulada recta (lejos del sol) | n → tamaño y cola; P1 → resplandor rojo | muy bonito, lo más «meteorito» | solo transmite «hay tareas» |
| **B · Bola de fuego** | plasma con partículas y chispas | n → cola; **color = urgencia** (ámbar → rojo con proporción P1/n) | vistoso | ruidoso como fondo; muchas partículas |
| **C · Enjambre** | una roca por tarea en fila; la cabeza es la más prioritaria | P1 = grandes y rojas; resto tenues | se cuenta a ojo | parece una lista; sigue siendo cola lineal |
| **D · Cuentas** | cola segmentada: una cuenta por tarea, P1 rojas primero, anillo que late si hay P1 | 1 cuenta = 1 tarea | lo más legible y sobrio, barato | menos «espacial» |
| **E · Polvo estelar** | nube difusa alargada; cada tarea = mota luminosa con resplandor propio, a la deriva; cabeza = prioritaria; P1 laten en rojo | 1 mota = 1 tarea | cumple la idea de Alberto; nebulosa creíble; barato en GPU | cuesta contar con muchas; la nube puede salirse de pantalla |
| **F · Campo de asteroides** | sin cola: nube suelta de asteroides (forma/tamaño/giro propios), P1 más grandes y con brasa roja | 1 asteroide = 1 tarea | fuerte «cada tarea es una roca» | la forma global de la nube es menos reconocible |

**Recomendación del agente:** **E** (opcionalmente con la cabeza rocosa de A) como cometa
principal; **D** si se prioriza sobriedad/legibilidad. A y B solo como inspiración visual.

## 5. Decisiones abiertas (por qué está aparcado)

1. **¿Qué es una mota?** ¿1 tarea = 1 mota (hasta cuántas? hoy se capa en 18) o agrupar las
   cola larga («+12 más») en polvo difuso sin mota individual?
2. **¿Qué codifica cada atributo?** Propuesto: prioridad → color/tamaño/brillo (P1 rojo, laten);
   estado `en-curso` → ¿más brillo o rotación? `esfuerzo` S/M/L → ¿tamaño? ¿Se usa todo o solo prioridad?
3. **Interacción:** hover sobre una mota → ¿tooltip con su título? ¿clic en mota → abre esa tarea en
   Obsidian (hoy el clic abre el panel)? El hover actual enfoca el cometa entero (`zComet`).
4. **Forma y colocación:** ¿la nube sigue la órbita elíptica y se orienta contra el avance, o es un
   cúmulo centrado en la cabeza? ¿Qué hacer cuando la nube sale del borde de pantalla (girar hacia
   el lado con espacio / recortar)?
5. **Cero tareas:** hoy no hay cometa. ¿Mantener (recomendado) o dejar un resto tenue?
6. **Mezcla:** ¿cabeza de A + nube de E? ¿cuentas de D como modo compacto?

## 6. Plan de implementación (cuando se retome)

Rama `feat/cometa-rediseno` (feature → rama dedicada y merge, ver CLAUDE.md).

1. **Datos** — `SolarSystem.qml` ya recibe `taskList`; pasarla al layout (`Sim.js`) o leerla desde un
   `Repeater` en el `cometLayer`. Limitar a ~18 motas. Posición de cada mota **determinista por
   índice** (hash como `rnd(i)` del mockup) + deriva lenta, para que no «salte» al cambiar la lista.
2. **Render sin Canvas** — cada mota = `Rectangle` redondo con `RadialGradient`/imagen de halo
   precalculada (no `shadowBlur`); velo de la nube = 1–2 `Rectangle`/`Shape` con gradiente radial
   escalado y rotado. Polvo de fondo (≈100–150 granos): **un solo** `ShaderEffect` o `Canvas` pintado
   una vez al cambiar datos, o `Repeater` pequeño; nada de bucles por grano.
3. **Animación** — la deriva y el latido P1 con **un** `Timer` de intervalo regulable (p. ej. 33 ms
   solo cuando el cometa está visible y hay tareas), parado en reposo/oculto. Prohibido
   `FrameAnimation { running: true }` incondicional (CLAUDE.md). El movimiento orbital ya lo da el
   reloj de `Sim.js`.
4. **Integración** — conservar `zComet`, la `MouseArea` y `cometClicked()`; mantener `comet == null`
   sin tareas. Mover la etiqueta de «3 próximas tareas» según decisión 3.
5. **Despliegue y verificación** — sincronizar a `~/.config/quickshell/caelestia/` y **restart
   completo** del shell (`caelestia shell -k …; caelestia shell -d`), comprobar
   `INFO: Configuration Loaded` sin errores y CPU ~0 % en reposo. **Alberto prueba a mano.**

## 7. Coste previsto

Esfuerzo M. Riesgos: rendimiento de partículas en QML (por eso §6.2/6.3) y desbordamiento de la nube
por el borde de pantalla.
