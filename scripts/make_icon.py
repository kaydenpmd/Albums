"""App icon: the library's 2x2 album grid, with a bookmark on the first tile
(saved for later). The tiles have Figma's 60% corner smoothing, the iOS
squircle. Black on white, and white on black for dark mode, like the
monochrome Music icon in iOS 27.2.

    python scripts/make_icon.py Albums/Assets.xcassets/AppIcon.appiconset

writes AppIcon.png, AppIcon-Dark.png and AppIcon-Tinted.png. Needs Pillow."""
import math
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024
SS = 4  # supersample for smooth edges
W = S * SS

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def bezier(p0, p1, p2, p3, n=48):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        pts.append(tuple(mt**3 * p0[k] + 3 * mt**2 * t * p1[k] + 3 * mt * t**2 * p2[k] + t**3 * p3[k] for k in range(2)))
    return pts

def squircle_corner(R, smoothing, budget):
    """Figma's corner smoothing, as figma-squircle implements it (after Figma's
    "Desperately seeking squircles"): one corner, from the top edge to the right
    edge, in coordinates relative to the corner point (x left is negative)."""
    p = (1 + smoothing) * R
    if p > budget:
        smoothing = min(smoothing, budget / R - 1)
        p = min(p, budget)
    arc_measure = 90 * (1 - smoothing)
    arc_len = math.sin(math.radians(arc_measure / 2)) * R * math.sqrt(2)
    alpha = (90 - arc_measure) / 2
    p3p4 = R * math.tan(math.radians(alpha / 2))
    beta = 45 * smoothing
    c = p3p4 * math.cos(math.radians(beta))
    d = c * math.tan(math.radians(beta))
    b = (p - arc_len - c - d) / 3
    a = 2 * b
    pts = bezier((-p, 0), (-p + a, 0), (-p + a + b, 0), (-p + a + b + c, d))
    cx, cy = -R, R
    t0, t1 = -45 - arc_measure / 2, -45 + arc_measure / 2
    for i in range(1, 48):
        t = math.radians(t0 + (t1 - t0) * i / 48)
        pts.append((cx + R * math.cos(t), cy + R * math.sin(t)))
    q0 = (-p + a + b + c + arc_len, d + arc_len)
    pts += bezier(q0, (q0[0] + d, q0[1] + c), (q0[0] + d, q0[1] + b + c), (q0[0] + d, q0[1] + a + b + c))
    return pts

def squircle(x0, y0, x1, y1, R, smoothing=0.6):
    corner = squircle_corner(R, smoothing, min(x1 - x0, y1 - y0) / 2)
    pts = [(x1 + u, y0 + v) for u, v in corner]          # top right
    pts += [(x1 - v, y1 + u) for u, v in corner]         # bottom right
    pts += [(x0 - u, y1 - v) for u, v in corner]         # bottom left
    pts += [(x0 + v, y0 - u) for u, v in corner]         # top left
    return pts

def icon(top, bottom, tiles, bookmark, shadow_rgba, out, grayscale=False):
    img = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(img)
    for y in range(W):
        d.line([(0, y), (W, y)], fill=lerp(top, bottom, y / (W - 1)))
    img = img.convert("RGBA")

    margin, gap = 214 * SS, 48 * SS
    tile = (W - 2 * margin - gap) // 2
    radius = 46 * SS
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for i in range(4):
        x = margin + (i % 2) * (tile + gap)
        y = margin + (i // 2) * (tile + gap)
        sd.polygon(squircle(x, y + 12 * SS, x + tile, y + tile + 12 * SS, radius), fill=shadow_rgba)
        ld.polygon(squircle(x, y, x + tile, y + tile, radius), fill=tiles[i] + (255,))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18 * SS)))
    img = Image.alpha_composite(img, layer)

    # Drawn through the first tile's own shape, so it can't poke past the curve.
    bw, bh = tile * 0.26, tile * 0.40
    bx, by = margin + tile - radius * 0.6 - bw, margin
    notch = bw * 0.42
    ribbon = Image.new("L", (W, W), 0)
    ImageDraw.Draw(ribbon).polygon(
        [(bx, by), (bx + bw, by), (bx + bw, by + bh), (bx + bw / 2, by + bh - notch), (bx, by + bh)], fill=255)
    clip = Image.new("L", (W, W), 0)
    ImageDraw.Draw(clip).polygon(squircle(margin, margin, margin + tile, margin + tile, radius), fill=255)
    mask = ImageChops.multiply(ribbon, clip)
    img.paste(Image.new("RGBA", (W, W), bookmark + (255,)), (0, 0), mask)

    img = img.convert("RGB").resize((S, S), Image.LANCZOS)
    if grayscale:
        img = img.convert("L").convert("RGB")
    img.save(out)

folder = sys.argv[1]
icon((255, 255, 255), (238, 238, 242), [(20, 20, 22), (88, 88, 92), (88, 88, 92), (160, 160, 166)],
     (255, 255, 255), (0, 0, 0, 40), f"{folder}/AppIcon.png")
icon((40, 40, 44), (6, 6, 8), [(250, 250, 252), (172, 172, 178), (172, 172, 178), (104, 104, 110)],
     (0, 0, 0), (0, 0, 0, 120), f"{folder}/AppIcon-Dark.png")
icon((40, 40, 44), (6, 6, 8), [(250, 250, 252), (172, 172, 178), (172, 172, 178), (104, 104, 110)],
     (0, 0, 0), (0, 0, 0, 120), f"{folder}/AppIcon-Tinted.png", grayscale=True)
