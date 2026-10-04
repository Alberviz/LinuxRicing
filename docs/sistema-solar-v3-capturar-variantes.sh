#!/usr/bin/env bash
# Captura las 3 variantes de composición del sistema solar v3.
# EJECUTAR SÓLO tras reiniciar el equipo / re-enchufar el monitor externo:
# ahora mismo `grim` cuelga porque eDP-2 está en x=-3840 (gotcha #1 del
# runbook: la asociación monitor<->GPU se pierde y grim/Canvas mueren).
#
# Deja la variante 1 activa al terminar.
set -e
REPO=/home/alberviz/LinuxRicing/.worktrees/sistema-solar-v3
SIM_REPO=$REPO/configs/quickshell/caelestia/modules/background/solarsystem/Sim.js
SIM_DEPLOY=$HOME/.config/quickshell/caelestia/modules/background/solarsystem/Sim.js
OUT=/tmp/claude-1000/-home-alberviz-LinuxRicing/4b95c1a3-3cf7-4d1f-a205-562552e3a022/scratchpad

restart() {
  pkill -9 -x qs; pkill -9 -f quickshell; sleep 2.5
  rm -rf ~/.cache/quickshell/qmlcache
  ( qs -c caelestia -n -d 2>&1 & ) ; sleep 6
}

inject_agents() {
  qs -c caelestia ipc call agents clearAll || true
  qs -c caelestia ipc call agents start   '{"id":"cap-run-1","name":"Codex","provider":"codex","task":"prueba","address":"","ws":1,"startTime":'"$(date +%s%3N)"'}'
  qs -c caelestia ipc call agents start   '{"id":"cap-run-2","name":"Runner","provider":"otro","task":"prueba","address":"","ws":1,"startTime":'"$(date +%s%3N)"'}'
  qs -c caelestia ipc call agents notify  '{"id":"cap-done-1","name":"Claude","provider":"claude","status":"Completado","address":"","ws":1}'
  qs -c caelestia ipc call agents notify  '{"id":"cap-done-2","name":"Gemini","provider":"gemini","status":"Completado","address":"","ws":1}'
  sleep 2
}

shoot() {
  local n=$1
  local cur; cur=$(hyprctl activeworkspace -j | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
  hyprctl dispatch 'hl.dsp.focus({ workspace = 8 })'; sleep 1.5
  grim -o eDP-2 "$OUT/composicion-v$n.png"
  hyprctl dispatch "hl.dsp.focus({ workspace = $cur })"
  echo "  -> $OUT/composicion-v$n.png"
}

for V in 1 2 3; do
  echo "== variante $V =="
  sed -i "s/^    layoutVariant: [0-9],/    layoutVariant: $V,/" "$SIM_REPO"
  cp "$SIM_REPO" "$SIM_DEPLOY"
  restart
  inject_agents
  shoot "$V"
done

# dejar la 1 activa
sed -i "s/^    layoutVariant: [0-9],/    layoutVariant: 1,/" "$SIM_REPO"
cp "$SIM_REPO" "$SIM_DEPLOY"
qs -c caelestia ipc call agents clearAll || true
restart
echo "Listo. Variante 1 activa. Capturas en $OUT/composicion-v{1,2,3}.png"
