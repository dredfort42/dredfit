#!/usr/bin/env python3
"""Draw the Play icon (512 × 512) and the feature graphic (1024 × 500).

    python3 store/playstore/tools/graphics.py

Both are drawn from the icon master, store/appstore/icons/final_light.svg —
three circles on white: near-black, the accent orange, a grey ring. It is
geometry, so it is re-drawn here at the target size rather than rasterised by
a converter the repo does not have; the numbers below are the SVG's own,
read on a 1024 viewBox.

Play's rules (support.google.com/googleplay/android-developer/answer/9866151):
the icon is a 32-bit PNG with alpha, 512 × 512, at most 1024 KB, full square —
Play cuts the corners itself; the feature graphic is a 24-bit PNG without
alpha, 1024 × 500, not pure white, with nothing that matters near its edges.

The feature graphic carries the word-mark and one line — the App Store
subtitle each locale already ships — so it is written once per locale;
a graphic in English on the German page is the storefront in English.
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, os.pardir, "graphics")

INK, ACCENT, RING = (17, 18, 20), (232, 89, 12), (167, 169, 173)
# final_light.svg, viewBox 0 0 1024 1024
CIRCLES = [(206, "fill", INK), (512, "fill", ACCENT), (818, "ring", RING)]
CY, R, STROKE = 512, 112, 26

HELVETICA = "/System/Library/Fonts/Helvetica.ttc"
BG_TOP, BG_BOT = (238, 236, 231), (226, 223, 216)   # the frames' warm grey, one step deeper
SUB_C = (110, 112, 117)

# The App Store subtitle per locale (store/appstore/release_texts_2.5.0.md §6).
TAGLINE = {
    "en-US": "Home training that adapts",
    "ru-RU": "План подстраивается под тебя",
    "es-ES": "El plan se adapta a ti",
    "pt-BR": "O plano se adapta a você",
    "de-DE": "Der Plan passt sich dir an",
    "fr-FR": "Le plan s’adapte à toi",
    "it-IT": "Il piano si adatta a te",
}


def mark(size, background):
    """The icon's artwork on a `size`-pixel square, drawn 4× and scaled down."""
    k = 4 * size / 1024
    big = Image.new("RGBA", (4 * size, 4 * size), background)
    d = ImageDraw.Draw(big)
    for cx, kind, color in CIRCLES:
        if kind == "fill":
            d.ellipse([(cx - R) * k, (CY - R) * k, (cx + R) * k, (CY + R) * k], fill=color)
        else:
            outer, inner = R + STROKE / 2, R - STROKE / 2
            d.ellipse([(cx - outer) * k, (CY - outer) * k, (cx + outer) * k, (CY + outer) * k], fill=color)
            d.ellipse([(cx - inner) * k, (CY - inner) * k, (cx + inner) * k, (CY + inner) * k], fill=background)
    return big.resize((size, size), Image.LANCZOS)


def icon():
    path = os.path.join(OUT, "icon-512.png")
    mark(512, (255, 255, 255, 255)).save(path, optimize=True)
    return path


def feature(locale):
    w, h = 1024, 500
    img = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        img.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOT)))
    img = img.resize((w, h))
    d = ImageDraw.Draw(img)
    word = ImageFont.truetype(HELVETICA, 132, index=1)
    sub = ImageFont.truetype(HELVETICA, 38, index=0)
    left = 96
    wb = d.textbbox((0, 0), "Dredfit", font=word)
    sb = d.textbbox((0, 0), TAGLINE[locale], font=sub)
    block = (wb[3] - wb[1]) + 34 + (sb[3] - sb[1])
    top = (h - block) // 2
    d.text((left - wb[0], top - wb[1]), "Dredfit", font=word, fill=INK)
    d.text((left - sb[0], top + (wb[3] - wb[1]) + 34 - sb[1]), TAGLINE[locale], font=sub, fill=SUB_C)
    right_edge = left + max(wb[2] - wb[0], sb[2] - sb[0])
    # The three circles, without the icon's white square: the mark, not the tile.
    tile = 240
    m = mark(tile, (0, 0, 0, 0))
    x = w - 72 - tile
    if x < right_edge + 40:
        raise SystemExit("%s: the tagline runs into the mark (%d px wide)" % (locale, right_edge))
    img.paste(m, (x, (h - tile) // 2), m)
    path = os.path.join(OUT, "feature-graphic", locale + ".png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    print("wrote", os.path.relpath(icon()))
    for locale in TAGLINE:
        print("wrote", os.path.relpath(feature(locale)))


if __name__ == "__main__":
    main()
