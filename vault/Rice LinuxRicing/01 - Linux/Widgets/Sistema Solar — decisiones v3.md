---
tags: [rice, ui, sistema-solar, decisiones]
estado: en-curso
actualizado: 2026-09-03
---

# 🪐 Sistema Solar v3 — registro de decisiones

Decisiones de diseño de la v3 (escritorio a pantalla completa). Alberto no está
durante la implementación; los agentes deciden y anotan aquí. Espejo de la tabla
§8 de `docs/sistema-solar-v3-DISENO.md` — **si cambias una, cámbiala en los dos
sitios.**

## Cerradas con Alberto

- **Variante D.** Agujero negro «música» masivo y detallado en la **esquina
  superior derecha**, saliéndose ~30 % de cuadro, disco de acreción en diagonal
  cruzando la pantalla. Descartadas A (centro), B (guardada como reserva), C
  (disco de fondo).
- **Binario Laura ↔ Configuración**, lejos del agujero (centro-izquierda). Dos
  soles: **Laura primario**, **Configuración secundario**.
- **Agentes** orbitan Laura (0 si no hay; más = más satélites; en curso más
  vivos). **Dispositivos conectados** orbitan Configuración (desconectado → no
  aparece).
- **Escritorio vacío salvo el reloj.** Wallpaper fuera → fondo negro (referencia
  de trabajo).
- **Movimiento lento.** Es un sistema informativo e (a futuro) interactivo.
- **Prioridad: el diseño.** Interacción y reactividad (Laura activa, etc.), después.
- **El binario NO deriva alrededor del agujero.** Alberto: seguir la física
  estaría bien pero no tiene sentido para la utilidad — los blancos de
  información/clic tienen que estar donde el usuario los espera. Baricentro del
  binario **fijo en pantalla**. Principio: posiciones estables y predecibles.
- **El cinturón de tareas se incluye ya** (circumbinario, tenue, densidad = backlog).

## Tomadas por el agente (revisar si algo chirría)

- **D-1** · Wallpaper apagado tras flag `showWallpaper: false`, restaurable. La
  paleta sigue saliendo de `Colours.palette` para cuando vuelva. *(El plan
  original decía mantener el wallpaper; se revisa al terminar el diseño.)*
- **D-3** · Color de Laura a decidir con capturas entre `m3secondary` y
  `m3tertiary` (contraste con el disco cálido del agujero). Config = `m3primary`.
- **D-5** · Las **zonas LED** (MagicHome, tira Akko, anillo base K7) **no se
  dibujan** en esta tanda; el adaptador se queda. Vuelven «más adelante».
- **D-6** · Componentes `Desktop*`/`Deck*` se **comentan, no se borran**
  (reversibles; patrones reutilizables para la interacción).
- **D-7** · Interacción y reactividad fuera de alcance; la vista se diseña para
  poder añadir entrada luego sin reestructurar.

## Historial

- **2026-09-03** — Brainstorming de composición (Claude). 4 posibilidades
  (maqueta en el repo `docs/sistema-solar-v3-mockup/`; también
  [artifact `0951108d`](https://claude.ai/code/artifact/0951108d-14ed-46df-8a48-9264b32df0ab)).
  Alberto elige D. Se guarda B como reserva. Se prepara la rama
  `feat/sistema-solar-v3` y el traspaso (`docs/sistema-solar-v3-DISENO.md` +
  `-PROMPT.md`). Revisada D-2: el binario no deriva.
