#!/bin/sh
# Recompila shaders, renderiza A1/A2 y genera los recortes de zoom.
cd "$(dirname "$0")" || exit 1
for f in mockA bloom composite; do /usr/lib/qt6/bin/qsb --qt6 -o $f.frag.qsb $f.frag || exit 1; done
timeout 90 qml6 mockA.qml || exit 1
python3 - <<'P'
from PIL import Image
for n in ('A1','A2'):
    full = 'A1-tema' if n=='A1' else 'A2-calido'
    im = Image.open(full+'.png').convert('RGB')
    im.crop((1100,0,1920,560)).resize((1640,1120), Image.LANCZOS).save(n+'-zoom.png')
P
