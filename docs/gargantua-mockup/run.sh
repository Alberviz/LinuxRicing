#!/bin/sh
# Recompila shaders, renderiza A1/A2 y genera los recortes de zoom.
cd "$(dirname "$0")" || exit 1
for f in mockA bloom composite; do /usr/lib/qt6/bin/qsb --qt6 -o $f.frag.qsb $f.frag || exit 1; done
timeout 90 qml6 mockA.qml || exit 1
python3 - <<'P'
from PIL import Image
for n in ('A3-tema','A3-test-rojo','A3-test-verde'):
    Image.open(n+'.png').convert('RGB').crop((560,0,1920,760)).save(n.replace('A3-','A3-zoom-')+'.png')
P
