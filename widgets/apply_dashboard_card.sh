#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
  echo "Por favor ejecuta este script con sudo: sudo ./apply_dashboard_card.sh"
  exit 1
fi

DEST="/etc/xdg/quickshell/caelestia/modules/dashboard/dash/Resources.qml"
if [ ! -f "${DEST}.bak" ]; then
  cp "$DEST" "${DEST}.bak"
  echo "Copia de seguridad guardada en ${DEST}.bak"
fi

cp /home/alberviz/Descargas/Resources_Peripherals.qml "$DEST"
echo "¡Tarjeta de periféricos instalada en el Dashboard con éxito!"
