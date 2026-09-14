---
fileClass: Backlog
tipo: tarea
estado: hecha
prioridad: 1
area: caelestia
origen: Alberto
esfuerzo: L
creado: 2026-09-14
diagnostico: "[[Diagnóstico y Handoff — Panel de WiFi en Caelestia]]"
tags:
  - backlog
---

El subsistema de WiFi de Caelestia solo funciona con redes ya guardadas; conectar a
una red **nueva** está roto en los dos sitios donde se puede intentar. Todo el código
implicado viene intacto del upstream (`caelestia-dots`), nunca se ha tocado ni
arreglado en este repo. Diagnóstico completo con archivo:línea de cada causa en
[[Diagnóstico y Handoff — Panel de WiFi en Caelestia]].

- [x] **(M)** Popout rápido no conecta: `network` se pierde al cambiar de vista
      (`Content.qml`/`WirelessPassword.qml`) y `Nmcli.qml` fuerza BSSID+wpa-psk con
      timeout de 4s demasiado corto.
- [x] **(S)** Popout rápido: contraseñas largas desbordan la tarjeta —
      sustituir el `ListView` de puntos artesanal por un `StyledTextField` con
      `echoMode: Password`.
- [x] **(M)** Nexus (Centro de Control): pulsar una red no guardada no abre ningún
      diálogo de contraseña — no existe ese flujo, hay que crearlo.
- [x] **(S)** Nexus: `AddNetworkPage.qml` tiene el campo de contraseña sin anclar
      (colapsa a altura 0), fuerza red oculta y `wpa-psk` fijo.
