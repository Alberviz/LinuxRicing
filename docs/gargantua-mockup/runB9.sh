#!/bin/sh
# B9: caché (mockB9_geo) a 6°, 9° y 12° + sombreado artístico (mockB9.frag). Hoja de ángulos al final.
cd "$(dirname "$0")" || exit 1
for f in noise5 mockB9_geo mockB9 bloom4 composite5; do /usr/lib/qt6/bin/qsb --qt6 -o $f.frag.qsb $f.frag || exit 1; done
for d in 6 9 12; do timeout 180 qml6 mockB9.qml -- $d || exit 1; done
mv B9-test-rojo-09.png B9-test-rojo.png; rm -f B9-test-rojo-06.png B9-test-rojo-12.png   # el recomendado es 9°
python3 - <<'PY'
from PIL import Image, ImageDraw
h = 560
tiles = []
for t in ['06', '09', '12']:
    im = Image.open('B9-%s.png' % t).convert('RGB').crop((760, 0, 1920, 700))
    tiles.append((im.resize((int(im.width*h/im.height), h), Image.LANCZOS), 'B9 %s°' % t.lstrip('0')))
g = Image.open('ref-gemini-vision.jpg').convert('RGB').crop((1416, 20, 2816, 820))
tiles.append((g.resize((int(g.width*h/g.height), h), Image.LANCZOS), 'Gemini'))
W = max(t[0].width for t in tiles)
sheet = Image.new('RGB', (2*W + 30, 2*h + 30), (25, 25, 25))
d = ImageDraw.Draw(sheet)
for i, (im, lab) in enumerate(tiles):
    x, y = 10 + (i % 2) * (W + 10), 10 + (i // 2) * (h + 10)
    sheet.paste(im, (x, y)); d.text((x + 10, y + 10), lab, fill=(255, 255, 255))
sheet.save('B9-angulos.png')
PY
