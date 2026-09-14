---
fileClass: Backlog
tipo: tarea
estado: pendiente
prioridad: 3
area: caelestia
origen: Alberto
esfuerzo: S
creado: 2026-09-14
diagnostico: "[[Diagnóstico y Handoff — Panel de WiFi en Caelestia]]"
tags:
  - backlog
---

Investigado el repo oficial `caelestia-dots/shell`: **ya hay dos PRs abiertos sin
mergear** que cubren la mayor parte de nuestros fixes (PR #1869 y PR #1881 — ver
[[Diagnóstico y Handoff — Panel de WiFi en Caelestia]] §6). Nuestra rama
`feat/wifi-panel-fixes` ya se reconcilió para adoptar su mismo diseño. Esto cambia el
plan: **no tiene sentido abrir un PR propio que compita con esos dos**.

- [ ] Confirmar con pruebas manuales reales (Alberto) que todo funciona sin
      regresiones antes de tocar nada upstream.
- [ ] Comentar en [PR #1869](https://github.com/caelestia-dots/shell/pull/1869) y
      [PR #1881](https://github.com/caelestia-dots/shell/pull/1881) confirmando que el
      enfoque funciona bien en un tercer setup (igual que ya hizo otro usuario en
      #1869) — ayuda a que se mergeen antes.
- [ ] Proponer un PR propio **solo** con lo que no cubre ningún PR existente: el fix
      visual de desbordamiento de contraseñas (`WirelessPassword.qml` →
      `StyledTextField`) y el arreglo de layout/comportamiento de
      `AddNetworkPage.qml` (anclaje roto, modo oculto por defecto).
- [ ] Revisar si `caelestia-dots/shell` tiene `CONTRIBUTING.md` o convenciones propias
      de PR antes de abrir nada.
