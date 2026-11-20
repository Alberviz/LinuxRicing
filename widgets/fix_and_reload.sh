#!/bin/bash
set -e

echo "1. Reemplazando quickshell-git por el paquete oficial quickshell..."
sudo pacman -Rdd --noconfirm quickshell-git || true
sudo pacman -S --noconfirm quickshell

echo "2. Aplicando la tarjeta corregida de periféricos en el Dashboard..."
sudo cp /home/alberviz/Descargas/Resources_Peripherals.qml /etc/xdg/quickshell/caelestia/modules/dashboard/dash/Resources.qml

echo "3. Reiniciando Caelestia Shell..."
killall qs quickshell || true
sleep 0.5
caelestia shell -d

echo "¡Listo! El widget de escritorio y el Dashboard están activos y actualizados."
