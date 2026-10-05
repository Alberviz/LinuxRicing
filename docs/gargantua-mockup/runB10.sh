#!/bin/sh
# B10: forma. A = física (disco r_out≈35, sombra pequeña); B = artística (r_out 10.5, gravedad débil lejos).
# Ambas a 6° y giro de pantalla -0.30. Hoja B10-vs-gemini.png al final.
cd "$(dirname "$0")" || exit 1
for f in noise5 mockB10_geo mockB10 bloom4 composite5; do /usr/lib/qt6/bin/qsb --qt6 -o $f.frag.qsb $f.frag || exit 1; done
for v in A B; do timeout 240 qml6 mockB10.qml -- $v || exit 1; done
python3 - <<'PY'
from PIL import Image, ImageDraw
h = 460
tiles = [(Image.open('B10-A.png').convert('RGB'), 'B10-A (fisica)'),
         (Image.open('B10-B.png').convert('RGB'), 'B10-B (artistica)'),
         (Image.open('ref-gemini-vision.jpg').convert('RGB').crop((1416, 20, 2816, 820)), 'Gemini')]
ims = [(im.resize((int(im.width*h/im.height), h), Image.LANCZOS), l) for im, l in tiles]
W = sum(i.width for i, _ in ims) + 10*(len(ims)+1)
s = Image.new('RGB', (W, h + 20), (25, 25, 25)); d = ImageDraw.Draw(s); x = 10
for im, l in ims:
    s.paste(im, (x, 10)); d.text((x + 10, 20), l, fill=(255, 255, 255)); x += im.width + 10
s.save('B10-vs-gemini.png')
PY
