"""make_icon.py - regenerate the luna app icon (concept #47: moon phases, charcoal/lime).
Draws with Pillow at 4x then downscales (smooth edges) and writes a multi-size .ico + a 256 png.
Run: python make_icon.py    (no SVG rasterizer needed; Pillow only).
Edit COL_TILE / COL_MOON below to recolor."""
import os
from PIL import Image, ImageDraw

COL_TILE = (0x23, 0x26, 0x2B, 255)   # charcoal
COL_MOON = (0xC7, 0xF2, 0x5B, 255)   # lime
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

def circle(cx, cy, r, fill):
    d.ellipse([P(cx - r), P(cy - r), P(cx + r), P(cy + r)], fill=fill)

R = 14
circle(26, 50, R, COL_MOON)
circle(30.5, 50, R - 2, COL_TILE)
d.pieslice([P(50 - R), P(50 - R), P(50 + R), P(50 + R)], -90, 90, fill=COL_MOON)
d.ellipse([P(50 - R), P(50 - R), P(50 + R), P(50 + R)], outline=COL_MOON, width=int(2.4 * sc))
circle(74, 50, R, COL_MOON)

out = img.resize((256, 256), Image.LANCZOS)
base = os.path.dirname(os.path.abspath(__file__))
out.save(os.path.join(base, "luna.png"))
out.save(os.path.join(base, "luna.ico"),
         sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("wrote luna.ico + luna.png in", base)
