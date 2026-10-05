#!/bin/sh
cd "$(dirname "$0")" || exit 1
for f in noise5 mockB5_geo mockB5 bloom4 composite5; do /usr/lib/qt6/bin/qsb --qt6 -o $f.frag.qsb $f.frag || exit 1; done
timeout 180 qml6 mockB5.qml || exit 1
python3 - <<'P'
from PIL import Image
im = Image.open('B5-tema.png').convert('RGB')
z = im.crop((760,0,1920,700)); z.save('B5-zoom-tema.png')
ref = Image.open('../../reference_interstellar.png').convert('RGB')
h = 700; ref = ref.resize((int(ref.width*h/ref.height), h), Image.LANCZOS)
c = Image.new('RGB', (z.width+ref.width+10, h), (30,30,30)); c.paste(z,(0,0)); c.paste(ref,(z.width+10,0)); c.save('B5-vs-ref.png')
P
