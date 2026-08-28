#!/usr/bin/env python3
"""Compose framed App Store screenshots in the existing Dredfit style.

Style constants measured from appstore/screenshots/en/s1.png:
canvas 1320x2868, bg gradient (246,245,242)->(237,235,230),
frame rect (119,448)-(1200,2715) color (26,26,28) radius ~166, border 30,
screen rect (149,476)-(1170,2687) radius ~136, pill 320x92 at y506 centered,
headline Helvetica Bold 106 color (17,18,20) top y190 (one line) / 186+118 (two),
subtitle Helvetica 43 color (110,112,117) top y324 (one line) / y441 (two).
"""
import os

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
    # two-line headlines push the whole device down
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
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
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
    # --- 1. today_ — the first of the three visible in search results.
    (f"{RAW}/today_en.png",      ["Zero setup."], "Open the app — your workout is ready.", f"{OUT}/en/s1.png"),
    (f"{RAW}/today_ru.png",      ["Ноль настроек."], "Открой приложение — тренировка готова.", f"{OUT}/ru/s1.png"),
    (f"{RAW}/today_es.png",      ["TODO-i18n: Zero setup."], "TODO-i18n: Open the app — your workout is ready.", f"{OUT}/es/s1.png"),
    (f"{RAW}/today_pt-br.png",   ["TODO-i18n: Zero setup."], "TODO-i18n: Open the app — your workout is ready.", f"{OUT}/pt-br/s1.png"),
    (f"{RAW}/today_de.png",      ["TODO-i18n: Zero setup."], "TODO-i18n: Open the app — your workout is ready.", f"{OUT}/de/s1.png"),
    (f"{RAW}/today_fr.png",      ["TODO-i18n: Zero setup."], "TODO-i18n: Open the app — your workout is ready.", f"{OUT}/fr/s1.png"),
    (f"{RAW}/today_it.png",      ["TODO-i18n: Zero setup."], "TODO-i18n: Open the app — your workout is ready.", f"{OUT}/it/s1.png"),
    # --- 2. rating_ — the differentiator: one question, and the plan moves.
    (f"{RAW}/rating_en.png",     ["It adapts to you"], "One tap after the workout — the next one adapts.", f"{OUT}/en/s2.png"),
    (f"{RAW}/rating_ru.png",     ["Подстраивается", "под тебя"], "Одно касание после тренировки — следующая изменится.", f"{OUT}/ru/s2.png"),
    (f"{RAW}/rating_es.png",     ["TODO-i18n: It adapts to you"], "TODO-i18n: One tap after the workout — the next one adapts.", f"{OUT}/es/s2.png"),
    (f"{RAW}/rating_pt-br.png",  ["TODO-i18n: It adapts to you"], "TODO-i18n: One tap after the workout — the next one adapts.", f"{OUT}/pt-br/s2.png"),
    (f"{RAW}/rating_de.png",     ["TODO-i18n: It adapts to you"], "TODO-i18n: One tap after the workout — the next one adapts.", f"{OUT}/de/s2.png"),
    (f"{RAW}/rating_fr.png",     ["TODO-i18n: It adapts to you"], "TODO-i18n: One tap after the workout — the next one adapts.", f"{OUT}/fr/s2.png"),
    (f"{RAW}/rating_it.png",     ["TODO-i18n: It adapts to you"], "TODO-i18n: One tap after the workout — the next one adapts.", f"{OUT}/it/s2.png"),
    # --- 3. probe_ — new in 2.0.0, replaces milestone_ (see the note below).
    (f"{RAW}/probe_en.png",      ["Nothing unlocks itself"], "One set of the next movement decides — not a calendar.", f"{OUT}/en/s3.png"),
    (f"{RAW}/probe_ru.png",      ["Само ничего", "не откроется"], "Один подход нового движения решает — не календарь.", f"{OUT}/ru/s3.png"),
    (f"{RAW}/probe_es.png",      ["TODO-i18n: Nothing unlocks itself"], "TODO-i18n: One set of the next movement decides — not a calendar.", f"{OUT}/es/s3.png"),
    (f"{RAW}/probe_pt-br.png",   ["TODO-i18n: Nothing unlocks itself"], "TODO-i18n: One set of the next movement decides — not a calendar.", f"{OUT}/pt-br/s3.png"),
    (f"{RAW}/probe_de.png",      ["TODO-i18n: Nothing unlocks itself"], "TODO-i18n: One set of the next movement decides — not a calendar.", f"{OUT}/de/s3.png"),
    (f"{RAW}/probe_fr.png",      ["TODO-i18n: Nothing unlocks itself"], "TODO-i18n: One set of the next movement decides — not a calendar.", f"{OUT}/fr/s3.png"),
    (f"{RAW}/probe_it.png",      ["TODO-i18n: Nothing unlocks itself"], "TODO-i18n: One set of the next movement decides — not a calendar.", f"{OUT}/it/s3.png"),
    # --- 4. set_ — the first of the seven that confirm.
    (f"{RAW}/set_en.png",        ["One focus at a time"], "Big numbers, one tap per set.", f"{OUT}/en/s4.png"),
    (f"{RAW}/set_ru.png",        ["Один фокус за раз"], "Крупные цифры, одно касание на подход.", f"{OUT}/ru/s4.png"),
    (f"{RAW}/set_es.png",        ["TODO-i18n: One focus at a time"], "TODO-i18n: Big numbers, one tap per set.", f"{OUT}/es/s4.png"),
    (f"{RAW}/set_pt-br.png",     ["TODO-i18n: One focus at a time"], "TODO-i18n: Big numbers, one tap per set.", f"{OUT}/pt-br/s4.png"),
    (f"{RAW}/set_de.png",        ["TODO-i18n: One focus at a time"], "TODO-i18n: Big numbers, one tap per set.", f"{OUT}/de/s4.png"),
    (f"{RAW}/set_fr.png",        ["TODO-i18n: One focus at a time"], "TODO-i18n: Big numbers, one tap per set.", f"{OUT}/fr/s4.png"),
    (f"{RAW}/set_it.png",        ["TODO-i18n: One focus at a time"], "TODO-i18n: Big numbers, one tap per set.", f"{OUT}/it/s4.png"),
    # --- 5. skip_ — the decision inside the workout (§38.2).
    (f"{RAW}/skip_en.png",       ["Too much today?"], "Skip a set while you are doing it. The clock follows.", f"{OUT}/en/s5.png"),
    (f"{RAW}/skip_ru.png",       ["Сегодня многовато?"], "Пропусти подход прямо на тренировке. Время пересчитается.", f"{OUT}/ru/s5.png"),
    (f"{RAW}/skip_es.png",       ["TODO-i18n: Too much today?"], "TODO-i18n: Skip a set while you are doing it. The clock follows.", f"{OUT}/es/s5.png"),
    (f"{RAW}/skip_pt-br.png",    ["TODO-i18n: Too much today?"], "TODO-i18n: Skip a set while you are doing it. The clock follows.", f"{OUT}/pt-br/s5.png"),
    (f"{RAW}/skip_de.png",       ["TODO-i18n: Too much today?"], "TODO-i18n: Skip a set while you are doing it. The clock follows.", f"{OUT}/de/s5.png"),
    (f"{RAW}/skip_fr.png",       ["TODO-i18n: Too much today?"], "TODO-i18n: Skip a set while you are doing it. The clock follows.", f"{OUT}/fr/s5.png"),
    (f"{RAW}/skip_it.png",       ["TODO-i18n: Too much today?"], "TODO-i18n: Skip a set while you are doing it. The clock follows.", f"{OUT}/it/s5.png"),
    # --- 6. progress_
    (f"{RAW}/progress_en.png",   ["Progress you can see"], "Every movement, step by step.", f"{OUT}/en/s6.png"),
    (f"{RAW}/progress_ru.png",   ["Прогресс, который", "видно"], "Каждое движение, ступень за ступенью.", f"{OUT}/ru/s6.png"),
    (f"{RAW}/progress_es.png",   ["TODO-i18n: Progress you can see"], "TODO-i18n: Every movement, step by step.", f"{OUT}/es/s6.png"),
    (f"{RAW}/progress_pt-br.png", ["TODO-i18n: Progress you can see"], "TODO-i18n: Every movement, step by step.", f"{OUT}/pt-br/s6.png"),
    (f"{RAW}/progress_de.png",   ["TODO-i18n: Progress you can see"], "TODO-i18n: Every movement, step by step.", f"{OUT}/de/s6.png"),
    (f"{RAW}/progress_fr.png",   ["TODO-i18n: Progress you can see"], "TODO-i18n: Every movement, step by step.", f"{OUT}/fr/s6.png"),
    (f"{RAW}/progress_it.png",   ["TODO-i18n: Progress you can see"], "TODO-i18n: Every movement, step by step.", f"{OUT}/it/s6.png"),
    # --- 7. howitworks_ — the number in the subtitle IS the section count of
    #        HowItWorksView (twelve today). Re-read that file every release.
    (f"{RAW}/howitworks_en.png", ["No black box"], "Twelve plain facts about how the plan moves.", f"{OUT}/en/s7.png"),
    (f"{RAW}/howitworks_ru.png", ["Без черного ящика"], "Двенадцать простых фактов о том, как движется план.", f"{OUT}/ru/s7.png"),
    (f"{RAW}/howitworks_es.png", ["TODO-i18n: No black box"], "TODO-i18n: Twelve plain facts about how the plan moves.", f"{OUT}/es/s7.png"),
    (f"{RAW}/howitworks_pt-br.png", ["TODO-i18n: No black box"], "TODO-i18n: Twelve plain facts about how the plan moves.", f"{OUT}/pt-br/s7.png"),
    (f"{RAW}/howitworks_de.png", ["TODO-i18n: No black box"], "TODO-i18n: Twelve plain facts about how the plan moves.", f"{OUT}/de/s7.png"),
    (f"{RAW}/howitworks_fr.png", ["TODO-i18n: No black box"], "TODO-i18n: Twelve plain facts about how the plan moves.", f"{OUT}/fr/s7.png"),
    (f"{RAW}/howitworks_it.png", ["TODO-i18n: No black box"], "TODO-i18n: Twelve plain facts about how the plan moves.", f"{OUT}/it/s7.png"),
    # --- 8. comeback_ — the subtitle was rewritten in 2.0.0: the card promises
    #        a depth that GROWS WITH THE BREAK, not a fixed "couple of steps".
    (f"{RAW}/comeback_en.png",   ["Breaks are normal"], "The longer the break, the lower the plan meets you.", f"{OUT}/en/s8.png"),
    (f"{RAW}/comeback_ru.png",   ["Возвращаться легко"], "Чем длиннее перерыв, тем ниже встретит план.", f"{OUT}/ru/s8.png"),
    (f"{RAW}/comeback_es.png",   ["TODO-i18n: Breaks are normal"], "TODO-i18n: The longer the break, the lower the plan meets you.", f"{OUT}/es/s8.png"),
    (f"{RAW}/comeback_pt-br.png", ["TODO-i18n: Breaks are normal"], "TODO-i18n: The longer the break, the lower the plan meets you.", f"{OUT}/pt-br/s8.png"),
    (f"{RAW}/comeback_de.png",   ["TODO-i18n: Breaks are normal"], "TODO-i18n: The longer the break, the lower the plan meets you.", f"{OUT}/de/s8.png"),
    (f"{RAW}/comeback_fr.png",   ["TODO-i18n: Breaks are normal"], "TODO-i18n: The longer the break, the lower the plan meets you.", f"{OUT}/fr/s8.png"),
    (f"{RAW}/comeback_it.png",   ["TODO-i18n: Breaks are normal"], "TODO-i18n: The longer the break, the lower the plan meets you.", f"{OUT}/it/s8.png"),
    # --- 9. rest_ — 60 s is the band-3 pause (EngineConfig.restSetByBand).
    (f"{RAW}/rest_en.png",       ["Rest is timed for you"], "60 seconds, counted down automatically.", f"{OUT}/en/s9.png"),
    (f"{RAW}/rest_ru.png",       ["Отдых отсчитается", "сам"], "60 секунд — таймер уже запущен.", f"{OUT}/ru/s9.png"),
    (f"{RAW}/rest_es.png",       ["TODO-i18n: Rest is timed for you"], "TODO-i18n: 60 seconds, counted down automatically.", f"{OUT}/es/s9.png"),
    (f"{RAW}/rest_pt-br.png",    ["TODO-i18n: Rest is timed for you"], "TODO-i18n: 60 seconds, counted down automatically.", f"{OUT}/pt-br/s9.png"),
    (f"{RAW}/rest_de.png",       ["TODO-i18n: Rest is timed for you"], "TODO-i18n: 60 seconds, counted down automatically.", f"{OUT}/de/s9.png"),
    (f"{RAW}/rest_fr.png",       ["TODO-i18n: Rest is timed for you"], "TODO-i18n: 60 seconds, counted down automatically.", f"{OUT}/fr/s9.png"),
    (f"{RAW}/rest_it.png",       ["TODO-i18n: Rest is timed for you"], "TODO-i18n: 60 seconds, counted down automatically.", f"{OUT}/it/s9.png"),
    # --- 10. dial_
    (f"{RAW}/dial_en.png",       ["Life happens —", "adjust"], "Did fewer reps? Record it right at the exercise.", f"{OUT}/en/s10.png"),
    (f"{RAW}/dial_ru.png",       ["Вышло иначе?", "Поправь"], "Факт записывается прямо у упражнения.", f"{OUT}/ru/s10.png"),
    (f"{RAW}/dial_es.png",       ["TODO-i18n: Life happens —", "adjust"], "TODO-i18n: Did fewer reps? Record it right at the exercise.", f"{OUT}/es/s10.png"),
    (f"{RAW}/dial_pt-br.png",    ["TODO-i18n: Life happens —", "adjust"], "TODO-i18n: Did fewer reps? Record it right at the exercise.", f"{OUT}/pt-br/s10.png"),
    (f"{RAW}/dial_de.png",       ["TODO-i18n: Life happens —", "adjust"], "TODO-i18n: Did fewer reps? Record it right at the exercise.", f"{OUT}/de/s10.png"),
    (f"{RAW}/dial_fr.png",       ["TODO-i18n: Life happens —", "adjust"], "TODO-i18n: Did fewer reps? Record it right at the exercise.", f"{OUT}/fr/s10.png"),
    (f"{RAW}/dial_it.png",       ["TODO-i18n: Life happens —", "adjust"], "TODO-i18n: Did fewer reps? Record it right at the exercise.", f"{OUT}/it/s10.png"),
]
# Partial recaptures are normal — frames without a fresh raw keep their last
# set. All ten raws come from the current StoreScreenshots.swift.reference.
#
# v2.26: s10 was `resting_` — Today with a movement frozen by the pain
# channel. The channel is gone and so is the screen, so the slot carried the
# handles instead, under the raw name `handles_`.
#
# v2.27: the handles are gone the same way — the session-wide one and the
# per-movement one both left with the wave that moved the decision inside the
# workout — so the slot now carries the WORK screen: "Skip this set", the
# escape that names its landing, and the minutes left recalculated as you go.
# The raw is renamed again, to `skip_`, so nothing composes an s10 until that
# raw exists. Both renames exist for one reason: the rule "a frame without a
# fresh raw keeps its last set" would otherwise leave a removed feature
# advertised in the store through a partial recapture.
#
# v3.0: THE WHOLE SET IS STALE, not one slot. The wave replaced the level
# with a variation and a dose, so every frame that shows a plan, a bar or
# a total shows a number the app no longer produces — and the seeds behind
# them were rewritten too (seed.py). The usual "partial recapture is fine"
# does not apply here: recapture all ten raws, in all seven languages, or
# the set will mix two engines.
#
# 2.0.0: THE ORDER CHANGED AND ONE SLOT WAS REPLACED, so no s*.png keeps its
# meaning — every OUT path below now belongs to a different raw than it did in
# 1.9.0, which is a second, independent reason the recapture has to be total.
#
# `milestone_` is GONE, and not because the screen is gone. MilestoneView is
# alive and still says "New variation" for a `.variationUp` coda. What no
# capture path could produce was that coda: `--uitest-milestone` seeds one
# growth event away from a new SET BAND, and a new variation in v3 needs a
# probe the person passed inside the workout — which a seed cannot promise a
# driver will pass. So the frame the method actually produced read "More
# volume · Now 4 sets" under a headline promising a new variation. A slot
# whose capture path cannot produce what its caption promises does not get
# fixed by a better caption; it leaves.
#
# `probe_` takes its place — the same claim about growth, made by the screen
# that really carries it (the PROBE badge, the next movement's name, "One set
# to try it."), and reachable from a planted state alone (seed.py mode C).
#
# The es/pt-BR/de/fr/it lines are deliberately marked `TODO-i18n` rather than
# left carrying their 1.9.0 text: five of the ten slots changed their caption
# or their neighbour, and NOTHING IN CI READS THIS FILE — check_localization.py
# and the required Localization check walk String Catalogs only. An English
# phrase that reaches the German storefront fails no run, so the placeholder
# has to fail the EYE instead. Translators close them per
# instructions/TRANSLATOR_PROMPT.md and GLOSSARY.md, one agent per language.

# Ten slots, seven locales, and the language inside a frame must match the
# folder it is written to. Both were checked by hand until the wave that
# renumbered every slot; a mis-set OUT path is exactly the kind of edit no one
# sees until the frames are in ASC.
LOCALES = ["en", "ru", "es", "pt-br", "de", "fr", "it"]
assert len(jobs) == 70, f"jobs must be 10 frames x 7 locales, got {len(jobs)}"
for raw, _lines, _sub, out in jobs:
    raw_tag = os.path.basename(raw).rsplit(".", 1)[0].split("_", 1)[1]
    out_locale = os.path.basename(os.path.dirname(out))
    assert raw_tag == out_locale, f"{raw} writes into {out_locale}"
    assert out_locale in LOCALES, f"unknown locale folder {out_locale}"
for locale in LOCALES:
    slots = [os.path.basename(j[3]) for j in jobs if f"/{locale}/" in j[3]]
    assert sorted(slots) == sorted(f"s{i}.png" for i in range(1, 11)), \
        f"{locale} does not carry s1..s10: {slots}"

for j in jobs:
    if os.path.exists(j[0]):
        compose(*j)
    else:
        print("skip (no raw):", j[0])
