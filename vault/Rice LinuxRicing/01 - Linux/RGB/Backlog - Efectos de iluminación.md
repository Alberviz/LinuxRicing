---
tags: [rice, rgb, backlog, ideas]
actualizado: 2026-08-27
---

# Backlog · Efectos de iluminación

Ideas de funciones para el [[Centro de Iluminación RGB]] y para el control RGB en general. **Esto no es código todavía**: es la lista de "esto se podría añadir en el futuro". Cada entrada lleva un valor estimado y un coste aproximado.

Leyenda de coste: 🟢 barato · 🟡 medio · 🔴 caro / requiere trabajo de base.

---

## v1 — en construcción

| Idea | Notas | Coste |
|---|---|---|
| **Panel superpuesto centrado** que sustituye la tarjeta inline | Patrón `AreaPicker`, capa Wayland, cierra al clicar fuera | 🟡 |
| **Estado de reposo: seguir tema / color fijo** | Selector + paleta de presets (colores del tema + fijos comunes) + campo hex | 🟡 |
| **Interruptor on/off por dispositivo ARGB** | Cada dispositivo decide si se apunta a la sincronización global | 🟡 |
| **Efecto al cargar** (base) | Migrar lo existente: tema / batería / firmware / ola | 🟢 |
| **Alerta de batería baja** (base) + umbral | Migrar lo existente: roja / ola / ninguna / fija | 🟢 |
| **Motor de "efecto temporal → restaurar"** | Base reutilizable para todos los efectos reactivos: snapshot del estado, aplica efecto, restaura | 🟡 |
| **Flash al recibir notificación** | Modos: rojo · color de acento · **complementario** (tono +180° en HSV). Nº de pulsos configurable. Engancha en `services/Notifs.qml`. Cuidado: probablemente el flash NO toca OpenRGB (bus SMBus lento) — solo base + teclado + tira | 🟡 |

---

## v1.1 — siguiente iteración (alto valor, coste contenido)

| Idea | Descripción | Coste |
|---|---|---|
| **Perfiles / escenas** | Guardar combinaciones ("Trabajo", "Cine", "Noche", "Fiesta") y cambiarlas con un clic o atajo | 🟡 |
| **Apagado maestro** | Un botón que apaga todas las luces (de noche) y otro que restaura el estado anterior | 🟢 |
| **Brillo por dispositivo** | Hoy está hardcoded (base 100, teclado 4). Deslizador por dispositivo | 🟡 |
| **Color individual por dispositivo** | En vez de un color global, cada dispositivo el suyo | 🟡 |
| **Vista previa en vivo** | Al pasar el ratón por un preset, aplicarlo temporalmente sin guardar | 🟢 |
| **Atajo global** | Abrir el panel y alternar "todo on/off" desde Hyprland | 🟢 |
| **Nivel de urgencia de la notificación** | `critical` = flash rojo intenso · `normal` = pulso suave · `low` = nada | 🟢 |
| **Color por app de notificación** | Discord=blurple, WhatsApp/Telegram=verde, correo=azul, calendario=ámbar. Mapa app→color | 🟡 |
| **Indicador "No molestar"** | Mientras DND está activo, LED fijo tenue o tira apagada | 🟢 |

---

## Más adelante — efectos ambientales y reactivos

| Idea | Descripción | Coste |
|---|---|---|
| **Espejo del OSD de volumen/brillo** | Al subir/bajar volumen, la tira/base dibuja una barra de progreso de color 1-2 s | 🟡 |
| **Aviso de "comando largo terminado"** | Hook de fish: al acabar un comando que tardó >N s, flash verde/rojo según código de salida. Útil para compilaciones | 🟡 |
| **Recordatorio de calendario** | 5 min antes de una reunión, la base respira en ámbar | 🔴 (integración calendario) |
| **Reactivo a música** | Color de la carátula del álbum actual (MPRIS / `Players.qml`) o pulso al ritmo (CAVA ya integrado en el visualizador orbital) | 🟡 |
| **Ambilight / screen mirroring** para la tira | Color medio del borde de la pantalla en tiempo real al ver vídeo o jugar. Ya está en `FUTURE_ROADMAP.md §1` | 🔴 |
| **Medidor de CPU/GPU/temperatura** | Gradiente verde→ámbar→rojo en la tira según carga o temperatura. Refresco lento (5-10 s) por el bus SMBus | 🟡 |
| **Cambio circadiano** | De día colores fríos y brillo alto, de noche cálidos y tenues, sincronizado con `gammastep` / hora | 🟡 |
| **Modo cine** | Al detectar pantalla completa de mpv/navegador, atenuar o apagar todo salvo un bias light suave tras el monitor | 🟡 |
| **Modo juego** | `GameMode.qml` ya existe: al activarlo, todo pasa a un preset "gaming" o al color del juego | 🟡 |
| **Pomodoro / Luz de concentración** | Ya existe a medias en `Background.qml`: trabajo = color foco, descanso = color relax. Integrar en el panel | 🟡 |
| **Batería baja del portátil** | Si el instalador detecta portátil: pulso ámbar→rojo | 🟢 |
| **Transiciones suaves** | Fade entre colores en vez de saltos, donde el hardware lo permita | 🟡 |
| **Perfil de arranque** | Restaurar el último estado al iniciar sesión, no siempre el tema | 🟢 |
| **Programación horaria** | Escena X a tal hora (systemd timer) | 🟡 |

---

## Requiere ingeniería inversa de hardware (habilita features)

| Pendiente | Qué desbloquea | Coste |
|---|---|---|
| **Cuerpo del ratón K7 Ultra** (resolver `target 0x06` vs `0x07`) | Controlar el LED del ratón, no solo la base | 🔴 |
| **Direccionamiento por-LED de la base** | Anillo como aro de progreso: % de batería, % de Pomodoro, medidor de carga | 🔴 |
| **Mapa completo de mode-IDs del firmware de la base** | Hay contradicción entre `mchose-base-test` y `mchose-pcap-analyzer` | 🟡 |
| **Batería real del teclado Akko** | Hoy es un stub que devuelve 100 % | 🟡 |
| **Brillo / velocidad del teclado y de la tira por protocolo** | Deslizadores reales para esos dispositivos | 🟡 |

---

## Infra y calidad (no son features, pero desatascan)

| Tarea                                                                                            | Motivo                                                                                                                                         | Coste |
| ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| **Esquema y CLI unificados** `rgb-config`                                                        | Fusionar `mchose-config.json` + el nuevo `rgb-config.json` en uno solo                                                                         | 🟡    |
| **Un solo `mchose-battery`**                                                                     | Quitar la divergencia `rgb/` vs `widgets/` (payload de `red_static`)                                                                           | 🟢    |
| **Script de sync repo↔sistema** + `install.sh` completo                                          | Hoy `install.sh` no despliega `mchose-config` ni `mchose-lighting`; los dos `Background.qml` se editan a mano                                  | 🟡    |
| **Daemon único `rgbd`**                                                                          | Centralizar estado, eventos, restauración y cola de efectos temporales, en vez de 3 vías (`sync-rgb`, `mchose-battery`, `argb-wave`) pisándose | 🔴    |
| **Tests de humo**                                                                                | Script que aplica un color conocido a cada dispositivo y pide confirmación visual                                                              | 🟢    |
| **Aviso si un dispositivo no responde**                                                          | Base desconectada, OpenRGB caído, tira sin red                                                                                                 | 🟢    |
| **Detección de wave/target del cuerpo del ratón** documentada en [[Iluminación - Estado actual]] | Cerrar las divergencias de `target` entre commits                                                                                              | 🟢    |

---

## Preguntas abiertas

- ¿El flash por notificación debe tocar OpenRGB (placa/RAM/ventiladores) o solo los periféricos rápidos? Riesgo de saturar el bus SMBus con pulsos rápidos.
- ¿"Complementario" respecto a qué? ¿Al color de reposo configurado, o al color que el dispositivo tenga en ese instante (que puede ser un efecto)?
- ¿Los perfiles/escenas se sincronizan con el tema o lo sobrescriben mientras están activos?
- ¿Merece la pena el daemon único `rgbd` o seguimos con scripts sueltos coordinados por config?
