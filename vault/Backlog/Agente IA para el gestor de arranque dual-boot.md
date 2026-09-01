---
tipo: tarea
estado: pendiente
prioridad: 4
area: agentes
origen: Alberto
esfuerzo: L
creado: 2026-09-01
tags:
  - backlog
---

Un **agente de IA que controle el dispositivo/gestor de arranque** del dual-boot
(Arch Linux / CachyOS ⇄ Windows 11), **con tema visual propio** a juego con el
resto del setup.

Dos piezas:

- **Control del arranque.** El agente decide y aplica en qué sistema arranca el
  PC la próxima vez: `systemctl reboot --boot-loader-entry=…` / `bootctl
  set-oneshot` (systemd-boot) o `efibootmgr -n` para un *boot next* de una sola
  vez, sin tocar el orden permanente. Órdenes en lenguaje natural desde el chat
  del agente o desde un botón del escritorio («reinicia en Windows para jugar»,
  «vuelve a Linux»). Idealmente también: leer qué entradas hay, cuál es la de
  por defecto, y programar un arranque para más tarde.
- **Tema visual propio.** Menú de arranque (systemd-boot / rEFInd) con una skin
  Material You coherente con la paleta activa —tipografía, colores, iconos de
  cada SO—, y una tarjeta/overlay en el escritorio con la identidad del agente
  (su propio color de acento y avatar) para distinguirlo de los demás agentes.

Relacionado con la paridad Windows-Linux ([[Plan Maestro de Paridad Windows-Linux]])
y con el sistema de notificaciones de agentes (el agente de arranque también
emite toasts y usa el pip del workspace). Requiere decidir el bootloader
objetivo (hoy el del setup) y permisos (polkit / sudo acotado a `bootctl` y
`efibootmgr`).
