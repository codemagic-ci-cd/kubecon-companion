#!/usr/bin/env python3
"""Generates the app icons (PWA, favicon, Android, iOS) with no dependencies.

Design: Codemagic blue gradient (#0031EA -> #008BF7) with a white map pin,
on the dark page color #01091A. Run from the repo root:

    python3 tool/make_icons.py
"""
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DARK = (0x01, 0x09, 0x1A)
BLUE_A = (0x00, 0x31, 0xEA)
BLUE_B = (0x00, 0x8B, 0xF7)
WHITE = (0xFF, 0xFF, 0xFF)


def write_png(path, size, pixels, alpha=True):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        row = pixels[y * size * 4:(y + 1) * size * 4]
        if alpha:
            raw.extend(row)
        else:  # RGB only: the App Store rejects icons with an alpha channel
            for i in range(0, len(row), 4):
                raw.extend(row[i:i + 3])

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6 if alpha else 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def in_round_rect(x, y, inset, radius):
    lo, hi = inset, 1 - inset
    if x < lo or x > hi or y < lo or y > hi:
        return False
    cx = min(max(x, lo + radius), hi - radius)
    cy = min(max(y, lo + radius), hi - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def in_pin(x, y, scale):
    # Teardrop pin centred in the icon; `scale` shrinks it for maskable icons.
    x = 0.5 + (x - 0.5) / scale
    y = 0.5 + (y - 0.5) / scale
    cx, cy, r, apex = 0.5, 0.43, 0.2, 0.8
    hole = (x - cx) ** 2 + (y - cy) ** 2 <= 0.075 ** 2
    if hole:
        return False
    if (x - cx) ** 2 + (y - cy) ** 2 <= r ** 2:
        return True
    sin_a = r / (apex - cy)
    if cy + r * sin_a <= y <= apex:
        # Cone tangent to the circle: tan(asin(r / (apex - cy))).
        half = (apex - y) * sin_a / (1 - sin_a ** 2) ** 0.5
        return abs(x - cx) <= half
    return False


def render(size, maskable=False, full_bleed=False):
    ss = 3  # supersampling per axis
    px = bytearray(size * size * 4)
    for py in range(size):
        for pxl in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    x = (pxl + (sx + 0.5) / ss) / size
                    y = (py + (sy + 0.5) / ss) / size
                    t = (x + y) / 2
                    grad = tuple(a + (b - a) * t for a, b in zip(BLUE_A, BLUE_B))
                    if maskable or full_bleed:
                        color, alpha = grad, 1.0
                    elif in_round_rect(x, y, 0.0, 0.22):
                        color, alpha = grad, 1.0
                    else:
                        color, alpha = DARK, 0.0
                    if alpha and in_pin(x, y, 0.72 if maskable else 1.0):
                        color = WHITE
                    acc[0] += color[0] * alpha
                    acc[1] += color[1] * alpha
                    acc[2] += color[2] * alpha
                    acc[3] += alpha
            n = ss * ss
            a = acc[3] / n
            i = (py * size + pxl) * 4
            if a > 0:
                px[i] = int(acc[0] / acc[3])
                px[i + 1] = int(acc[1] / acc[3])
                px[i + 2] = int(acc[2] / acc[3])
            px[i + 3] = int(a * 255)
    return px


def main():
    web = os.path.join(ROOT, "web")
    targets = [
        (os.path.join(web, "icons", "Icon-192.png"), 192, False, False),
        (os.path.join(web, "icons", "Icon-512.png"), 512, False, False),
        (os.path.join(web, "icons", "Icon-maskable-192.png"), 192, True, False),
        (os.path.join(web, "icons", "Icon-maskable-512.png"), 512, True, False),
        (os.path.join(web, "favicon.png"), 32, False, False),
    ]
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    for d in sorted(os.listdir(res)) if os.path.isdir(res) else []:
        p = os.path.join(res, d, "ic_launcher.png")
        if d.startswith("mipmap") and os.path.exists(p):
            targets.append((p, png_size(p)[0], False, False))
    ios = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    if os.path.isdir(ios):
        for name in sorted(os.listdir(ios)):
            if name.endswith(".png"):
                p = os.path.join(ios, name)
                # iOS icons must be opaque; the OS applies the corner mask.
                targets.append((p, png_size(p)[0], False, True))

    cache = {}
    for path, size, maskable, full in targets:
        key = (size, maskable, full)
        if key not in cache:
            cache[key] = render(size, maskable, full)
        write_png(path, size, cache[key], alpha=not full)
        print(f"wrote {os.path.relpath(path, ROOT)} ({size}px)")


if __name__ == "__main__":
    main()
