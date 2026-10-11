#!/usr/bin/env python3
"""Compose the Google Play phone screenshots in the iOS set's style.

    RAW_DIR=/path/to/screens python3 store/playstore/tools/compose_play.py

The raws are the PNGs `ScreenshotWalk` and `WidgetScreenshots` write on the
emulator (`/sdcard/Android/data/com.dredfit.dredfit/files/screens/`, pulled
whole): `<lang>-light-<screen>.png` and `widget-<lang>-light-<size>.png`. How
to take them is in this folder's README.

The look is store/appstore/tools/compose.py's, re-measured for Play's canvas:
the same background gradient, Helvetica Bold headline over a Helvetica
subtitle, the device in the same near-black — but 1440 × 2560, because Play
promotes only 9:16 portrait frames of at least 1080 × 1920
(support.google.com/googleplay/android-developer/answer/9866151), and the
iPhone's 1320 × 2868 is neither. The device is a punch-hole phone, not an
iPhone: the frame must not draw hardware the listing's platform does not have.

The status bar is the emulator's own under demo mode (12:00, full battery,
Wi-Fi). Demo mode's `notifications visible false` does not hide the app's own
ongoing-workout icon on API 37, so `clean_status_bar` blanks every icon between
the clock and the middle of the bar — notification icons live nowhere else.

Captions live in `captions.py`, are checked by `check_listing.py` (the same
translation rules and forbidden words as the listing texts), and are measured
here before anything is drawn: a line that would be clipped stops the run, the
lesson of the 2.0.0 iOS set, whose clipped captions nobody saw.
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

from captions import CAPTIONS, LANG, SLOTS

W, H = 1440, 2560
BG_TOP, BG_BOT = (246, 245, 242), (237, 235, 230)
FRAME = (26, 26, 28)
RAW_W, RAW_H = 1080, 2424          # Pixel 10a emulator, 420 dpi
SW = 860                           # screen width on the canvas
SH = round(SW * RAW_H / RAW_W)     # 1930
BEZEL = 28
SX0 = (W - SW) // 2
SY0 = 458                          # screen top under a one-line headline
SRAD, FRAD = 78, 78 + BEZEL
TWO_LINE_DY = 128                  # a second headline line pushes the device down
HELVETICA = "/System/Library/Fonts/Helvetica.ttc"
HEAD = ImageFont.truetype(HELVETICA, 116, index=1)
SUB = ImageFont.truetype(HELVETICA, 47, index=0)
HEAD_C, SUB_C = (17, 18, 20), (110, 112, 117)
SAFE_PAD = 8


def gradient():
    top = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        top.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOT)))
    return top.resize((W, H))


def rounded(size, boxes, scale=4):
    """An RGBA layer of rounded rectangles / circles, drawn supersampled."""
    big = Image.new("RGBA", (size[0] * scale, size[1] * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    for kind, (x0, y0, x1, y1), rad, fill in boxes:
        box = [x0 * scale, y0 * scale, x1 * scale, y1 * scale]
        if kind == "circle":
            d.ellipse(box, fill=fill)
        else:
            d.rounded_rectangle(box, radius=rad * scale, fill=fill)
    return big.resize(size, Image.LANCZOS)


def placed(text, font):
    """(x to draw at, left ink, right ink) for a line centred on the canvas."""
    b = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), text, font=font)
    x = (W - (b[2] - b[0])) // 2 - b[0]
    return x, x + b[0], x + b[2]


def draw_caption(canvas, lines, subtitle):
    d = ImageDraw.Draw(canvas)

    def line(text, font, fill, top):
        x, _, _ = placed(text, font)
        d.text((x, top - d.textbbox((0, 0), text, font=font)[1]), text, font=font, fill=fill)

    if len(lines) == 1:
        line(lines[0], HEAD, HEAD_C, 207)
        line(subtitle, SUB, SUB_C, 353)
    else:
        line(lines[0], HEAD, HEAD_C, 203)
        line(lines[1], HEAD, HEAD_C, 331)
        line(subtitle, SUB, SUB_C, 481)


def clean_status_bar(raw):
    """Blank every status-bar icon between the clock and the middle of the bar."""
    bg = raw.getpixel((RAW_W // 2, 4))
    px = raw.load()

    def ink(x):
        return any(sum(abs(a - b) for a, b in zip(px[x, y], bg)) > 60 for y in range(40, 101))

    runs, start = [], None
    for x in range(RAW_W // 2 + 1):
        on = x < RAW_W // 2 and ink(x)
        if on and start is None:
            start = x
        elif not on and start is not None:
            runs.append((start, x - 1))
            start = None
    merged = []
    for run in runs:      # the clock's digits are one run, not five
        if merged and run[0] - merged[-1][1] < 12:
            merged[-1] = (merged[-1][0], run[1])
        else:
            merged.append(run)
    # A run at the very edge is not ink but the scrim's corner around a sheet
    # (How it works): taken for the clock, it once had the clock blanked.
    merged = [run for run in merged if run[0] >= 40]
    for x0, x1 in merged[1:]:
        ImageDraw.Draw(raw).rectangle([x0 - 4, 30, x1 + 4, 110], fill=bg)
    return raw


def device(canvas, raw, dy):
    sy0 = SY0 + dy
    layer = rounded((W, H), [
        ("rect", (SX0 - BEZEL, sy0 - BEZEL, SX0 + SW + BEZEL, sy0 + SH + BEZEL), FRAD, FRAME + (255,)),
    ])
    canvas.paste(layer, (0, 0), layer)
    screen = clean_status_bar(raw.convert("RGB")).resize((SW, SH), Image.LANCZOS)
    mask = rounded((SW, SH), [("rect", (0, 0, SW, SH), SRAD, (255, 255, 255, 255))])
    canvas.paste(screen, (SX0, sy0), mask.split()[3])
    # The punch-hole camera, centred in the status bar like the Pixel's.
    cy = sy0 + round(70 * SW / RAW_W)
    hole = rounded((W, H), [("circle", (W // 2 - 15, cy - 15, W // 2 + 15, cy + 15), 0, FRAME + (255,))])
    canvas.paste(hole, (0, 0), hole)


def widget_card(path):
    """The widget as the launcher draws it (WidgetHost's RemoteViews, cut from
    the screen), without the host's grey around its rounded corners: what is
    connected to the crop's corners in the host colour becomes transparent."""
    im = Image.open(path).convert("RGB")
    host = im.getpixel((0, 0))
    marked = im.copy()
    sentinel = (255, 0, 255)
    for corner in ((0, 0), (im.width - 1, 0), (0, im.height - 1), (im.width - 1, im.height - 1)):
        if marked.getpixel(corner) == host:
            ImageDraw.floodfill(marked, corner, sentinel, thresh=0)
    r, g, b = ImageChops.difference(marked, Image.new("RGB", im.size, sentinel)).split()
    alpha = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v else 0)
    card = im.convert("RGBA")
    card.putalpha(alpha)
    return card.crop(alpha.getbbox())


def widgets(canvas, raws, dy):
    """The medium and the large layout of the one widget, on a panel — no
    phone around them, because no launcher was photographed and a drawn one
    would be invented. The small layout (the day alone) is in both of them."""
    scale, gap, pad = 1.3, 48, 60
    cards = [widget_card(p) for p in raws]
    cards = [c.resize((round(c.width * scale), round(c.height * scale)), Image.LANCZOS) for c in cards]
    col_w = max(c.width for c in cards)
    left = (W - col_w) // 2
    top = SY0 - BEZEL + dy
    panel_h = sum(c.height for c in cards) + gap * (len(cards) - 1) + 2 * pad
    panel = rounded((W, H), [("rect", (left - pad, top, left + col_w + pad, top + panel_h), FRAD,
                              (216, 213, 206, 255))])
    canvas.paste(panel, (0, 0), panel)
    y = top + pad
    for card in cards:
        canvas.paste(card, (left + (col_w - card.width) // 2, y), card)
        y += card.height + gap


def check_widths():
    over = []
    for slot, by_locale in CAPTIONS.items():
        for loc, (lines, sub) in by_locale.items():
            for text, font in [(t, HEAD) for t in lines] + [(sub, SUB)]:
                _, left, right = placed(text, font)
                if min(left, W - right) < SAFE_PAD:
                    over.append("%s/%s %r: %d px of margin" % (loc, slot, text, min(left, W - right)))
    return over


def main():
    raw_dir = os.environ.get("RAW_DIR")
    if not raw_dir:
        sys.exit("RAW_DIR=<folder of pulled screens> is required")
    out_dir = os.environ.get("OUT_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                     os.pardir, "screenshots"))
    missing_slots = [s for s, _ in SLOTS if set(CAPTIONS.get(s, {})) != set(LANG)]
    if missing_slots:
        sys.exit("captions missing a locale: " + ", ".join(missing_slots))
    over = check_widths()
    if over:
        sys.exit("captions clipped by the %d px canvas — shorten the phrase or break the "
                 "headline by its sense, never shrink the font:\n  " % W + "\n  ".join(over))
    missing = []
    for loc, lang in LANG.items():
        for slot, screen in SLOTS:
            if screen is None:
                raws = [os.path.join(raw_dir, "widget-%s-light-%s.png" % (lang, s))
                        for s in ("medium", "large")]
            else:
                raws = [os.path.join(raw_dir, "%s-light-%s.png" % (lang, screen))]
            absent = [r for r in raws if not os.path.exists(r)]
            if absent:
                missing += absent
                continue
            lines, sub = CAPTIONS[slot][loc]
            dy = TWO_LINE_DY if len(lines) > 1 else 0
            canvas = gradient()
            draw_caption(canvas, lines, sub)
            if screen is None:
                widgets(canvas, raws, dy)
            else:
                raw = Image.open(raws[0])
                if raw.size != (RAW_W, RAW_H):
                    sys.exit("%s is %dx%d, not the %dx%d this layout is measured for"
                             % (raws[0], raw.width, raw.height, RAW_W, RAW_H))
                device(canvas, raw, dy)
            path = os.path.join(out_dir, loc, slot + ".png")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            canvas.convert("RGB").save(path, optimize=True)
            print("wrote", os.path.relpath(path))
    # A partial set is the failure to fear: a stale frame keeps its place
    # silently, so a missing raw fails the run instead of skipping a frame.
    if missing:
        sys.exit("raws missing, those frames were not written:\n  " + "\n  ".join(missing))


if __name__ == "__main__":
    main()
