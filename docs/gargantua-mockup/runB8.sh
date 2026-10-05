#!/bin/sh
# B8: piel nueva (mockB8.frag) sobre la geometría/caché de B7 (mockB7_geo.frag)
cd "$(dirname "$0")" || exit 1
for f in noise5 mockB7_geo mockB8 bloom4 composite5; do /usr/lib/qt6/bin/qsb --qt6 -o $f.frag.qsb $f.frag || exit 1; done
timeout 180 qml6 mockB8.qml || exit 1
python3 - <<'PY'
from PIL import Image
im = Image.open('B8-tema.png').convert('RGB')
z = im.crop((760,0,1920,700)); z.save('B8-zoom-tema.png')
g = Image.open('ref-gemini-vision.jpg').convert('RGB').crop((1416,20,2816,820))
h = 700; g = g.resize((int(g.width*h/g.height), h), Image.LANCZOS)
f = im.resize((int(1920*h/1080), h), Image.LANCZOS)
c = Image.new('RGB', (f.width+g.width+10, h), (30,30,30)); c.paste(f,(0,0)); c.paste(g,(f.width+10,0)); c.save('B8-vs-gemini.png')
PY
