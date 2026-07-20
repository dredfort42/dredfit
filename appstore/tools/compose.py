#!/usr/bin/env python3
"""Compose framed App Store screenshots in the existing Dredfit style.

Style constants measured from appstore/screenshots/en/s1.png:
canvas 1320x2868, bg gradient (246,245,242)->(237,235,230),
frame rect (119,448)-(1200,2715) color (26,26,28) radius ~166, border 30,
screen rect (149,476)-(1170,2687) radius ~136, pill 320x92 at y506 centered,
headline Helvetica Bold 106 color (17,18,20) top y190 (one line) / 186+118 (two),
subtitle Helvetica 43 color (110,112,117) top y324 (one line) / y441 (two).
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1320, 2868
BG_TOP, BG_BOT = (246, 245, 242), (237, 235, 230)
FRAME = (26, 26, 28)
FX0, FY0, FX1, FY1 = 119, 448, 1200, 2715
SX0, SY0, SX1, SY1 = 149, 476, 1170, 2687
FRAD, SRAD = 166, 136
PILL_W, PILL_H, PILL_Y = 320, 92, 506
HEAD = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 106, index=1)
SUB = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 43, index=0)
HEAD_C, SUB_C = (17, 18, 20), (110, 112, 117)

def gradient():
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        t = y / (H - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOT))
        for x in range(W):
            px[x, y] = c
    return im

def rounded_layer(size, boxes, scale=4):
    """boxes: list of (xy, radius, fill). Returns RGBA layer drawn supersampled."""
    big = Image.new("RGBA", (size[0] * scale, size[1] * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    for (x0, y0, x1, y1), rad, fill in boxes:
        d.rounded_rectangle([x0 * scale, y0 * scale, x1 * scale, y1 * scale],
                            radius=rad * scale, fill=fill)
    return big.resize(size, Image.LANCZOS)

def text_centered(canvas, text, font, fill, top):
    d = ImageDraw.Draw(canvas)
    bbox = d.textbbox((0, 0), text, font=font)
    x = (W - (bbox[2] - bbox[0])) // 2 - bbox[0]
    d.text((x, top - bbox[1]), text, font=font, fill=fill)

def compose(raw_path, headline_lines, subtitle, out_path):
    canvas = gradient()
    # two-line headlines push the whole device down, as in the original set
    dy = 117 if len(headline_lines) > 1 else 0
    layer = rounded_layer((W, H), [
        ((FX0, FY0 + dy, FX1, FY1 + dy), FRAD, FRAME + (255,)),
        ((SX0, SY0 + dy, SX1, SY1 + dy), SRAD, (255, 255, 255, 255)),
    ])
    canvas.paste(layer, (0, 0), layer)

    raw = Image.open(raw_path).convert("RGB")
    sw = SX1 - SX0 + 1
    scaled = raw.resize((sw, round(raw.height * sw / raw.width)), Image.LANCZOS)
    sh = SY1 - SY0 + 1
    scaled = scaled.crop((0, 0, sw, sh))
    # cover the simulator status bar with the app's own top background colour,
    # inside the screen bitmap so the rounded mask keeps the corners clean
    strip_c = scaled.getpixel((24, 96))
    ImageDraw.Draw(scaled).rectangle([0, 0, sw, 130], fill=strip_c)
    mask = rounded_layer((sw, sh), [((0, 0, sw - 1, sh - 1), SRAD, (255, 255, 255, 255))])
    canvas.paste(scaled, (SX0, SY0 + dy), mask.split()[3])

    pill = rounded_layer((W, H), [((W // 2 - PILL_W // 2, PILL_Y + dy,
                                    W // 2 + PILL_W // 2, PILL_Y + dy + PILL_H),
                                   PILL_H // 2, (0, 0, 0, 255))])
    canvas.paste(pill, (0, 0), pill)

    if len(headline_lines) == 1:
        text_centered(canvas, headline_lines[0], HEAD, HEAD_C, 190)
        text_centered(canvas, subtitle, SUB, SUB_C, 324)
    else:
        text_centered(canvas, headline_lines[0], HEAD, HEAD_C, 186)
        text_centered(canvas, headline_lines[1], HEAD, HEAD_C, 304)
        text_centered(canvas, subtitle, SUB, SUB_C, 441)
    canvas.save(out_path)
    print("wrote", out_path)

import os

# Both overridable, so a recapture never has to edit this file:
#   RAW_DIR=/path/to/raw python3 compose.py
RAW = os.environ.get("RAW_DIR", "/tmp/dredfit-raw")
OUT = os.environ.get("OUT_DIR",
                     os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  os.pardir, "screenshots"))

jobs = [
    (f"{RAW}/today_en.png",      ["Zero setup."], "Open the app — your workout is ready.", f"{OUT}/en/s1.png"),
    (f"{RAW}/today_ru.png",      ["Ноль настроек."], "Открой приложение — тренировка готова.", f"{OUT}/ru/s1.png"),
    (f"{RAW}/set_en.png",        ["One focus at a time"], "Big numbers, one tap per set.", f"{OUT}/en/s2.png"),
    (f"{RAW}/set_ru.png",        ["Один фокус за раз"], "Крупные цифры, один тап на подход.", f"{OUT}/ru/s2.png"),
    (f"{RAW}/rest_en.png",       ["Rest is timed for you"], "60 seconds, counted down automatically.", f"{OUT}/en/s3.png"),
    (f"{RAW}/rest_ru.png",       ["Отдых отсчитается", "сам"], "60 секунд — таймер уже запущен.", f"{OUT}/ru/s3.png"),
    (f"{RAW}/rating_en.png",     ["It adapts to you"], "One tap — the next workout adjusts.", f"{OUT}/en/s4.png"),
    (f"{RAW}/rating_ru.png",     ["Подстраивается под", "тебя"], "Один тап — следующая тренировка изменится.", f"{OUT}/ru/s4.png"),
    (f"{RAW}/progress_en.png",   ["Progress you can see"], "Every muscle group, level by level.", f"{OUT}/en/s5.png"),
    (f"{RAW}/progress_ru.png",   ["Прогресс, который", "видно"], "Каждая группа мышц, уровень за уровнем.", f"{OUT}/ru/s5.png"),
    (f"{RAW}/dial_en.png",       ["Life happens —", "adjust"], "Did fewer reps? Record it right at the exercise.", f"{OUT}/en/s6.png"),
    (f"{RAW}/dial_ru.png",       ["Вышло иначе?", "Поправь"], "Факт записывается прямо у упражнения.", f"{OUT}/ru/s6.png"),
    (f"{RAW}/milestone_en.png",  ["New step unlocked"], "A harder variation, one calm screen. No confetti.", f"{OUT}/en/s7.png"),
    (f"{RAW}/milestone_ru.png",  ["Новая ступень"], "Вариация сложнее — один спокойный экран. Без конфетти.", f"{OUT}/ru/s7.png"),
    (f"{RAW}/howitworks_en.png", ["No black box"], "Seven plain facts about how the plan moves.", f"{OUT}/en/s8.png"),
    (f"{RAW}/howitworks_ru.png", ["Без черного ящика"], "Семь простых фактов о том, как движется план.", f"{OUT}/ru/s8.png"),
    (f"{RAW}/comeback_en.png",   ["Breaks are normal"], "The plan meets you a couple of steps lower.", f"{OUT}/en/s9.png"),
    (f"{RAW}/comeback_ru.png",   ["Возвращаться легко"], "План встретит тебя на пару ступеней ниже.", f"{OUT}/ru/s9.png"),
]
# Partial recaptures are normal (milestone/comeback need the older capture
# driver from git history) — frames without a fresh raw keep their last set.
import os
for j in jobs:
    if os.path.exists(j[0]):
        compose(*j)
    else:
        print("skip (no raw):", j[0])
