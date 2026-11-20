#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Por favor ejecuta este script con sudo: sudo ./setup_udev.sh"
  exit 1
fi

echo "Creando /etc/udev/rules.d/99-mchose.rules..."
cat << 'RULES' > /etc/udev/rules.d/99-mchose.rules
# MCHOSE V9 Pro (Auriculares)
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="291d", ATTRS{idProduct}=="385d", MODE="0666", TAG+="uaccess"

# MCHOSE K7 Ultra (Ratón)
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3837", ATTRS{idProduct}=="1001", MODE="0666", TAG+="uaccess"
RULES

echo "Recargando reglas udev..."
udevadm control --reload-rules && udevadm trigger

echo "¡Listo! Permisos configurados correctamente."
