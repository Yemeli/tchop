#!/usr/bin/env python3
"""Generate platform icon PNGs for the Tchop app.

Brand: rounded orange (#E8641B) tile with a dark "T".
Sizes emitted:
  web/icons/Icon-192.png, Icon-512.png,
  web/icons/Icon-maskable-192.png, Icon-maskable-512.png (safe-zone padding),
  web/icons/favicon.png (32px),
  macos iconset AppIcon-1024.png.
Run from the app root:  python3 tool/gen_web_icons.py
"""
import os
import struct
import zlib

APP_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = (0xE8, 0x64, 0x1B)      # #E8641B
FG = (0x0D, 0x0D, 0x0D)      # #0D0D0D


def write_png_rgb(path, w, h, rows):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes(px) for row in rows for px in (row,))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(raw)))
        f.write(chunk(b"IEND", b""))


try:
    from PIL import Image, ImageDraw, ImageFont

    def make_tile(size, glyph_scale=0.62, pad_frac=0.0):
        img = Image.new("RGB", (size, size), BG)
        d = ImageDraw.Draw(img)
        # rounded-corner effect: draw BG only inside an inset rounded rect on a
        # slightly larger canvas, then crop — simpler: round the corners of BG
        r = int(size * 0.22)
        mask = Image.new("L", (size, size), 0)
        md = ImageDraw.Draw(mask)
        md.rounded_rectangle([0, 0, size, size], radius=r, fill=255)
        base = Image.new("RGB", (size, size), BG)
        base.putalpha(mask)
        canvas = Image.new("RGB", (size, size), BG)
        canvas.paste(base, (0, 0), base)
        d = ImageDraw.Draw(canvas)
        try:
            font = ImageFont.truetype("DejaVuSans-Bold.ttf", int(size * glyph_scale))
        except OSError:
            font = ImageFont.load_default()
        d.text((size / 2, size / 2), "T", font=font, fill=FG, anchor="mm")
        if pad_frac:
            pad = int(size * pad_frac)
            inner = size - 2 * pad
            padded = Image.new("RGB", (size, size), BG)
            thumb = canvas.resize((inner, inner), Image.LANCZOS)
            padded.paste(thumb, (pad, pad))
            return padded
        return canvas

    def emit(relpath, size, maskable=False):
        img = make_tile(size, pad_frac=0.12 if maskable else 0.0)
        out = os.path.join(APP_ROOT, relpath)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        img.save(out, "PNG")

    emit("web/icons/Icon-192.png", 192)
    emit("web/icons/Icon-512.png", 512)
    emit("web/icons/Icon-maskable-192.png", 192, maskable=True)
    emit("web/icons/Icon-maskable-512.png", 512, maskable=True)
    emit("web/icons/favicon.png", 32)
    emit("macos/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png", 1024)
    print("PIL icons written.")

except ImportError:  # fallback: solid-color PNGs via zlib+struct
    def solid(w, h, color):
        return [[color for _ in range(w)] for _ in range(h)]

    jobs = [
        ("web/icons/Icon-192.png", 192, 192),
        ("web/icons/Icon-512.png", 512, 512),
        ("web/icons/Icon-maskable-192.png", 192, 192),
        ("web/icons/Icon-maskable-512.png", 512, 512),
        ("web/icons/favicon.png", 32, 32),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png", 1024, 1024),
    ]
    for rel, w, h in jobs:
        write_png_rgb(os.path.join(APP_ROOT, rel), w, h, solid(w, h, BG))
    print("fallback solid-color icons written (PIL not available).")
