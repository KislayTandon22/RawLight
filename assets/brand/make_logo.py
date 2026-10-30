"""Generates the RawLight app icon: six aperture blades in rose-red with "RL" in the opening."""
import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter

S = 4096
C = S / 2
FONT = "../fonts/Inter-SemiBold.ttf"
ROSE = (242, 58, 92)      # #F23A5C red, slightly pink
ROSE_LIGHT = (255, 120, 150)
ROSE_DARK = (176, 24, 62)

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def pt(r, deg): return (C + r * math.cos(math.radians(deg)), C + r * math.sin(math.radians(deg)))

img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
for y in range(S):                      # deep near-black background with a rose tint
    d.line([(0, y), (S, y)], fill=lerp((30, 10, 16), (10, 5, 8), y / S))

R, r, twist = 1560, 620, 28
for k in range(6):
    a0, a1 = k * 60 - 90, (k + 1) * 60 - 90
    poly = [pt(R, a0), pt(R, a1), pt(r, a1 + twist), pt(r, a0 + twist)]
    blade = Image.new("RGB", (S, S))
    bd = ImageDraw.Draw(blade)
    for y in range(S):                  # per-blade top-light gradient
        bd.line([(0, y), (S, y)], fill=lerp(ROSE_LIGHT if k % 2 else ROSE, ROSE_DARK, y / S))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    img.paste(blade, (0, 0), mask)
    d.line(poly + [poly[0]], fill=(14, 6, 10), width=26, joint="curve")   # blade gap

d.ellipse([C - R - 36, C - R - 36, C + R + 36, C + R + 36], outline=ROSE_DARK, width=44)   # rim
hole = Image.new("L", (S, S), 0)
ImageDraw.Draw(hole).ellipse([C - r * 1.05, C - r * 1.05, C + r * 1.05, C + r * 1.05], fill=255)
img.paste((12, 6, 9), (0, 0), hole)

f = ImageFont.truetype(FONT, 760)
tw = d.textlength("RL", font=f)
d.text((C - tw / 2, C), "RL", font=f, fill=(255, 226, 232), anchor="ls" if False else "lm")

img.resize((1024, 1024), Image.LANCZOS).save("rawlight-1024.png")
print("ok")
