#!/bin/sh
cd "$(dirname "$0")" || exit 1
for f in mockB bloom composite; do /usr/lib/qt6/bin/qsb --qt6 -o $f.frag.qsb $f.frag || exit 1; done
timeout 120 qml6 mockB.qml || exit 1
python3 -c "
from PIL import Image
Image.open('B-tema.png').convert('RGB').crop((560,0,1920,760)).save('B-zoom-tema.png')"
