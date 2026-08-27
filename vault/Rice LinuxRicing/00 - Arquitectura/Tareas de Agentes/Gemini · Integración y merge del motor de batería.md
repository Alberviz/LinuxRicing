---
tags: [tarea-agente, gemini, git, integracion, rgb, bateria]
para: Gemini
de: Claude
creado: 2026-08-27
estado: pendiente
requiere: que 'QML-panel' y 'hw-validation' hayan entregado sus informes
---

# Gemini · Integración y merge — motor de batería (Fase 1 + Fase 2)

> **Eres el agente `integrador`.** Solo entras cuando existan los dos informes:
> `Gemini · Panel QML — INFORME.md` y `Gemini · Validación de hardware — INFORME.md`.
> **No programas features.** Solo integras ramas, corres checks, resuelves conflictos
> mecánicos y, con el visto bueno de Alberto, mergeas a `main`.

## 0. Estado de las ramas

- `feat/battery-lighting-engine` — el motor backend (Claude). En `origin`. Base: `main`.
- `feat/battery-panel-ui` — el panel QML (agente `QML-panel`). Sale de `feat/battery-lighting-engine`.
- Puede haber commits de arreglo de `rgb/battery-lighting` de Claude tras la validación de hardware — sobre `feat/battery-lighting-engine`. Haz `git fetch` y míralo.

## 1. Comprobación previa (antes de tocar nada)

Lee los dos informes. **Si `hw-validation` reporta arreglos pendientes en
`rgb/battery-lighting` que Claude aún no ha hecho → PARA.** Avisa a Alberto de que falta
el arreglo de Claude antes de integrar. No integres sobre un motor con fallos conocidos.

## 2. Merge del panel QML dentro de la rama del motor

```bash
git fetch origin
git worktree add .worktrees/integracion feat/battery-lighting-engine
cd .worktrees/integracion
git merge origin/feat/battery-panel-ui
```
Conflictos esperables (los dos agentes tocaron `configs/quickshell/caelestia/modules/rgbcontrol/`):
- `NotificacionesView.qml`, `AkkoCard.qml`, `DispositivosView.qml`, `KeyboardPreview.qml` — resolución **mecánica**: quédate con ambos conjuntos de cambios (el motor no tocó QML, así que casi seguro es merge limpio; si no, el lado de `QML-panel` manda en esos 4 ficheros).
- No debería haber conflictos en `rgb/` ni en `services/BatteryLightingConfig.qml`.

## 3. Batería de checks (todos deben pasar)

```bash
python3 -m pytest rgb/tests/ -q                         # 48+ passed, sin fallos
python3 -c "import ast; [ast.parse(open(f).read()) for f in ['rgb/battery-lighting','rgb/mchose-battery','rgb/sync-rgb.py','rgb/rgb-notify-flash','widgets/mchose-battery','rgb/mchose-lighting']]; print('scripts OK')"
diff -q rgb/mchose-battery widgets/mchose-battery        # SIN salida
diff -q widgets/Background.qml configs/quickshell/caelestia/modules/background/Background.qml  # SIN salida
qmllint configs/quickshell/caelestia/modules/rgbcontrol/*.qml configs/quickshell/caelestia/services/*.qml  # sin errores nuevos
grep -rn "AkkoConfig\|MchoseConfig" configs/quickshell/  # VACÍO
grep -rn "mchose-config\|mchose-battery.timer\|trigger-lighting" --include='*.sh' --include='*.py' --include='*.service' .  # solo la línea de limpieza de install.sh y los tests
bash -n install.sh
python3 rgb/battery-lighting --dump                      # corre, JSON válido
```
Si alguno falla y no es trivial de arreglar (un import, un espacio) → PARA y avisa a Alberto / Claude. **No inventes arreglos de lógica.**

## 4. Verificación visual del panel (con Alberto)

```bash
caelestia shell -k && sleep 1 && caelestia shell -d
caelestia shell ipc call rgb openTab 2
```
Alberto revisa: la sección «Reacciones de batería» aparece con las reglas sembradas;
añadir una regla (V9 → batería baja → acción anillo base / rojo respiración) actualiza
`~/.config/caelestia/battery-lighting.json`; «Probar» dispara el efecto; las fichas de
Akko y Base ya no tienen sección de batería; el log de quickshell sin errores
`BatteryLightingConfig:` / `BatteryRuleCard:` / `BatteryActionRow:`.

## 5. Commit de la integración + push

```bash
git commit --no-edit   # si el merge dejó conflictos resueltos; si fue fast-forward no hace falta
git push origin feat/battery-lighting-engine
```

## 6. Merge a `main` (SOLO con «adelante» explícito de Alberto)

```bash
git checkout main && git pull
git merge --ff-only feat/battery-lighting-engine   # debería ser fast-forward; si no, avisa
git push origin main
git worktree remove .worktrees/integracion
git branch -d feat/battery-panel-ui feat/battery-lighting-engine
git push origin --delete feat/battery-panel-ui feat/battery-lighting-engine
```
Si `--ff-only` falla (alguien movió `main`): `git merge feat/battery-lighting-engine` normal, resuelve conflictos mecánicos, avisa si hay dudas.

## 7. Post-merge

- `install.sh` en la máquina de Alberto para instalar `battery-lighting` + el `.service` y retirar `mchose-battery.timer`.
- `systemctl --user enable --now battery-lighting.service`.
- Entrada en `vault/Rice LinuxRicing/00 - Arquitectura/Base de Datos de Errores.md`: qué se aprendió (validación del lienzo Akko, colisiones evitadas con `battery_alerts.json`, cadencia RF, el bug de test-pollution del `LOG_FILE` ya arreglado).
- Nodo(s) en el Code Graph para `[[battery-lighting]]`, `[[BatteryLightingConfig.qml]]`, `[[BatteryRuleCard.qml]]`, `[[BatteryActionRow.qml]]` con sus enlaces.

## 8. Informe

`vault/Rice LinuxRicing/00 - Arquitectura/Tareas de Agentes/Gemini · Integración — INFORME.md`:
qué se mergeó, resultado de cada check, conflictos resueltos, estado final (mergeado a main / pendiente), y qué queda.
