"""make_icon.py - regenerate the sonelle app icon (concept #1: sound wave).
Draws with Pillow at 4x then downscales (smooth edges) -> multi-size .ico + 256 png.
Run: python make_icon.py    (Pillow only; no SVG rasterizer needed).
Recolor by editing COL_TILE / COL_WAVE below."""
import os, math
from PIL import Image, ImageDraw

COL_TILE = (0x24, 0x1A, 0x33, 255)   # deep plum
COL_WAVE = (0xFF, 0x9B, 0x85, 255)   # coral
SUP = 4
S = 256 * SUP
sc = S / 100.0
def P(v): return v * sc

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
tile = [P(2), P(2), P(98), P(98)]
try:
    d.rounded_rectangle(tile, radius=P(22), fill=COL_TILE)
except AttributeError:
    d.rectangle(tile, fill=COL_TILE)

x0, x1, amp, humps = 20, 80, 14, 2.5
pts = []
for i in range(0, 121):
    x = x0 + (x1 - x0) * i / 120.0
    y = 50 - amp * math.sin(2 * math.pi * humps * (x - x0) / (x1 - x0))
    pts.append((P(x), P(y)))
W = int(7 * sc)
d.line(pts, fill=COL_WAVE, width=W, joint="curve")
r = W / 2.0
for e in (pts[0], pts[-1]):
    d.ellipse([e[0] - r, e[1] - r, e[0] + r, e[1] + r], fill=COL_WAVE)

out = img.resize((256, 256), Image.LANCZOS)
base = os.path.dirname(os.path.abspath(__file__))
out.save(os.path.join(base, "sonelle.png"))
out.save(os.path.join(base, "sonelle.ico"),
         sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("wrote sonelle.ico + sonelle.png in", base)
