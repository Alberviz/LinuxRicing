# Plan: Warp con teclado en el PC (Super+Espacio) — lo que falta de la v2.18/v2.19.1

Diseño aprobado: `~/proyectos/olimpo/docs/diseno-v2.18-warp-teclado.md` (leer entero, incluida la tabla de decisiones) y
`diseno-v2.19.1-pulido.md` §3 y §7. Estado a 2026-11-12: del §7 solo se hizo el shader AE1/binario y la fusión al soltar
entre los dos agujeros (`f29ab42`). **No existe** el atajo con portales: `warp lanzar` llama a `qs ipc call warp lanzar`,
y en el QML no hay ningún target `warp`, así que siempre cae al plan B (manda directo o, sin selección, el portapapeles).

## Hecho cuando (cada fase): shell relanzado desde Hyprland, disparador real y captura, no «compila»

- **Fase 0 — arreglo de la detección en Dolphin.** Reproducir tocar y mantener Super+Espacio con archivos seleccionados.
  Causa sospechada: el Ctrl+C sintético por `ydotool` no llega con Super pulsado (el log del 10:25 dio `rutas=[]`).
  Verifica: `$XDG_RUNTIME_DIR/warp/lanzar.log` con `rutas=[…]` reales.
- **Fase 1 — espigón de los dos riesgos del diseño.** Con `keyboardFocus: Exclusive`, ¿llegan Espacio, 1/2/3, Esc y el
  soltar Super a la capa, y el lanzador de Caelestia (`SUPER + SUPER_L` release) se queda cerrado? Decide plan A (soltar
  Super envía) o plan B (Enter o segundo Espacio).
- **Fase 2 — `IpcHandler` `warp` único** (no dentro del `Variants` por pantalla: ya hubo un aviso de handler duplicado)
  con `lanzar(json)`, que enruta a la pantalla enfocada, abre los portales con foco, vuelan las teselas al último destino;
  toque rápido = enviar; Super mantenido + Espacio = cambiar de portal; Shift suma destinos (fusión); Esc cancela.
- **Fase 3 — `warp lanzar`:** sin selección, el umbral (U1), no mandar nunca el portapapeles solo (P lo manda);
  quitar el doble envío si el IPC tarda; Super+Shift+Espacio (agujero blanco).
- **Fase 4 — instalación:** `~/.local/bin/warp` y `~/.config/quickshell/caelestia` son copias; averiguar de dónde las
  instala `install.sh` antes de editar nada, commit en LinuxRicing.

## Fase 5 — presencia de los portales en el PC: **decidido A, lente real** (Alberto, 2026-11-12) · prioridad alta

Petición literal: «los discos son demasiado transparentes… que curvara de verdad lo que tuviera detrás con más fuerza y los
discos tuvieran más fuerza… tienen que actuar más sobre lo que se ve en la pantalla». Hoy `portal.frag` pinta un cielo
sintético y no toca lo de detrás. El móvil y Olimpo (la app) se quedan como están: solo el PC.

### Diseño

1. **Captura congelada, no en vivo.** Al pasar `win.active` a verdadero (antes de que el portal cobre `vis`), cada ventana
   por pantalla hace una captura única con `ScreencopyView { captureSource: screen; live: false }` (+ `captureFrame()`), la
   mete en un `ShaderEffectSource` oculto (`live: false`) y la pasa a `Portal.qml` como sampler `bg`. Congelada evita el
   bucle (el portal saldría en su propia captura) y cuesta una sola captura por arrastre. Se descarta al acabar (`!active`).
2. **Shader (`portal.frag`, modo 0 AE1).** Nuevos uniforms: `bg` (sampler), `quadPos` y `scrSize` (px, para pasar de
   coordenadas del quad a UV de pantalla), `lente` (0 sin captura, 1 con captura; escala con `vis`·`en`).
   - Desvío tipo Einstein: la muestra se toma en `uv − dir · α(r)` con `α = k·Rs²/r` y recorte suave a 0 en el borde del quad
     (sin costura). `k` sube con `en` (la energía del arrastre) para que se note más al acercarte.
   - Anillo de Einstein: segunda imagen invertida (`uv + dir·α`) con brillo, justo fuera de la sombra.
   - Sombra negra **sólida** (alfa 1 dentro de `Rs`), disco de acreción más opaco y brillante (alfa ≥ 0,9 en el núcleo,
     halo aditivo), efecto Doppler más marcado.
   - Sin captura lista (`lente = 0`) cae al cielo sintético de hoy: nada se rompe.
3. **Escala PC.** Con `u = ancho/1280`, el radio ya escala; añadir un factor `fuerzaPC = clamp((ancho − 1280)/640, 0, 1)` que
   sube el radio del agujero ~15 %, el desvío y la opacidad del disco. En móvil/tablet vale 0.
4. **Binario («a los dos») y fusión:** las dos lentes suman sus desvíos; al fundirse, un solo agujero mayor.
5. **No entra:** captura en vivo, desenfoque del fondo, ni tocar la app Olimpo (`app/src/warp/shaders.ts`).

### Riesgos a comprobar primero (espigón)

- `ScreencopyView` ya se usa en `areapicker`, `lock` y `windowinfo`: comprobar que una captura de pantalla completa con
  `live: false` llega antes de 100 ms y que no incluye la propia capa overlay (se hace antes de encender el portal).
- Escalado fraccional y varias pantallas: el UV de pantalla usa el tamaño lógico del `ShellScreen`.
- Capas con transparencia/HDR: la captura puede venir con alfa; forzar `1.0`.

### Hecho cuando

- [ ] Con una ventana de texto detrás, la captura muestra el texto curvado alrededor del agujero y un anillo de imagen
      duplicada (captura con `grim`).
- [ ] Sombra y núcleo del disco opacos; ya no se ve el fondo a través del disco.
- [ ] Sin captura (simulada) vuelve al cielo sintético sin errores en el log.
- [ ] Una captura por arrastre (log) y sin caída de fotogramas con `drag-watch sim`.
- [ ] Probado con arrastre real desde Dolphin y desde Zen; el móvil y la app no cambian.

## Encargo para Fable — lente coherente e integración con el sistema (2026-11-12, tras el primer intento)

Alberto dijo (literal, resumido): iterar hasta una integración **perfecta y coherente** de las lentes gravitacionales con el
sistema, y buscar el punto óptimo entre tres cosas:
- **Coherencia:** que ocurra lo que uno espera (proporcionada al agujero, física plausible).
- **Funcionalidad:** que no se pierdan textos ni unos se traguen a otros.
- **Visual:** que se vea bonito.
Tiene permiso para cambiar lo que haga falta, donde haga falta (shader, `Portal.qml`, `Portals.qml`, textos, orden de capas).

Puntos concretos:
1. **Hay varios agujeros a la vez** (móvil, tablet, tele; hasta 3 portales). Si el ratón se acerca al centro entre el del móvil y
   el de la tablet, la lente de uno **se come al otro**: no vale. Cada lente debe quedar acotada a su agujero (sin solaparse) o
   componerse sin tragarse la del vecino. Probablemente hay que **reducir la cantidad y la agresividad del desvío** y hacerlo
   más sutil; encontrar el *sweet spot*.
2. **Textos «Móvil · Olimpo · Solo a este dispositivo»** (el HUD de cada portal): no se leen bien sobre la captura. Resolverlo
   con sombra, píldora o lo que mejor quede, siendo creativo. Además, el texto debería decir **«Tablet · Olimpo», «Móvil ·
   Olimpo», etc.** en vez de «Solo a este dispositivo» (apunte de Alberto: no debería salir solo eso).
3. Probar con capturas reales: fondos con mucho texto, portal de arriba (uno, dos y tres), derecha, cursor entre dos agujeros.
4. Primer intento de Fable cortado por el límite de 5 h (su subagente `a355421ce31e9a59e`); reanudar desde sus notas.
5. Contexto de lo ya hecho: Fase 5 de este mismo documento y las capturas de `scratchpad/lente3.png` y `lente6.png`.

## Cuándo salen los portales (decidido y puesto en `drag-watch`, 2026-11-12)

Problema: salían al seleccionar texto o mover un deslizador en una página, sin arrastrar nada. Reglas nuevas (cabecera de
`widgets/drag-watch`, copia en `~/.local/bin/drag-watch`):
- Gestor de archivos (Dolphin, Thunar…): cualquier arrastre cuenta.
- Navegador: solo si había texto seleccionado antes del clic y no cambia durante el arrastre (arrastrar una selección);
  nueva selección, deslizadores, barras y mapas no cuentan. `DRAG_WATCH_NAVEGADOR=todo` vuelve a admitir enlaces e imágenes.
- Cualquier otra ventana: nunca.
- Zona: solo se encienden al entrar el cursor en el 40 % superior o el 25 % derecho de la pantalla (`DRAG_WATCH_ZONA`).
Límite conocido: Wayland no avisa de un arrastre ajeno; en Dolphin el rectángulo de selección desde un hueco sigue pareciendo
arrastre (se mitiga con la zona). La señal real sería un `DropArea` en el borde; queda como mejora posible.
