#!/usr/bin/env python3
"""Compose the App Store creative assets (iOS 27+): the product page header
and the search results asset, per locale (owner's choice: layouts A and B
of the drafts, now `header` and `search`).

    python3 compose_creative.py --raw /path/to/raw --out /path/to/out [--locales en,ru]
    python3 compose_creative.py --check     # measure all seven locales, write nothing

Apple's sizes: header 21:9 = 3840x1646, search results 3:2 (1920x1280 ...
3840x2560). Both are written as RGB PNG: the asset library refuses an alpha
channel, and a PNG saved from an RGBA canvas keeps one even when every pixel is
opaque.

NO CAPTION HERE IS WRITTEN FOR THIS FILE. Every word is looked up:
  - slot captions come from `jobs` in compose.py (reviewed in seven languages,
    and each one already checked against the screen it sits on);
  - the app name and subtitle come from the release texts (§6), the strings
    that are live in the store today.
So a caption edited for the screenshots reaches these assets on the next run,
and a phrase that exists in no reviewed table cannot reach them at all.
"""
import argparse
import contextlib
import glob
import importlib.util
import io
import os
import re
import sys
import tempfile

from PIL import Image, ImageDraw

TOOLS = os.path.dirname(os.path.abspath(__file__))
LOCALES = ["en", "ru", "es", "pt-br", "de", "fr", "it"]


def _load_compose():
    """Import compose.py for its helpers and its `jobs`.

    compose.py is a script: importing it COMPOSES every frame whose raw exists
    and writes it into store/appstore/screenshots. So it is imported with both
    of its directories pointed at an empty scratch dir — no raw exists there,
    nothing is composed, nothing is written — and its 70 "skip" lines muted.
    Its own gates (70 jobs, locale folders, caption width) still run.
    """
    saved = {k: os.environ.get(k) for k in ("RAW_DIR", "OUT_DIR")}
    with tempfile.TemporaryDirectory() as empty:
        os.environ["RAW_DIR"] = os.environ["OUT_DIR"] = empty
        try:
            spec = importlib.util.spec_from_file_location(
                "compose", os.path.join(TOOLS, "compose.py"))
            if spec is None or spec.loader is None:
                raise SystemExit("cannot load compose.py next to this script")
            mod = importlib.util.module_from_spec(spec)
            with contextlib.redirect_stdout(io.StringIO()):
                spec.loader.exec_module(mod)
        finally:
            for k, v in saved.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
    return mod


C = _load_compose()

# (slot, locale) -> (headline lines, subtitle), straight from compose.jobs.
CAPTIONS = {}
for _raw, _lines, _sub, _out in C.jobs:
    _slot, _loc = os.path.basename(_raw).rsplit(".", 1)[0].split("_", 1)
    CAPTIONS[(_slot, _loc)] = (list(_lines), _sub)


def _release_texts_path():
    """The newest store/appstore/release_texts_<x.y.z>.md, by version."""
    env = os.environ.get("RELEASE_TEXTS")
    if env:
        return env
    paths = glob.glob(os.path.join(TOOLS, os.pardir, "release_texts_*.md"))

    def version(p):
        m = re.search(r"release_texts_(\d+)\.(\d+)\.(\d+)\.md$", p)
        return tuple(int(x) for x in m.groups()) if m else (-1,)
    paths = [p for p in paths if version(p) != (-1,)]
    if not paths:
        raise SystemExit("no release_texts_x.y.z.md in store/appstore "
                         "(local-only file; set RELEASE_TEXTS=...)")
    return max(paths, key=version)


def _store_names(path):
    """locale -> (Name, Subtitle) from §6 of the release texts.

    The section heading ends in the locale code in backticks; the two table
    rows carry the field in backticks. A locale missing either field is an
    error, not a fallback to English.
    """
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out, loc = {}, None
    for line in text.splitlines():
        m = re.match(r"^### 6\.\d+ .*`([A-Za-z-]+)`\s*$", line)
        if m:
            loc = m.group(1).lower()
            out[loc] = {}
            continue
        m = re.match(r"^\| (Name|Subtitle) \| `([^`]+)` \|", line)
        if m and loc is not None:
            out[loc][m.group(1)] = m.group(2)
    missing = [lc for lc in LOCALES
               if set(out.get(lc, {})) != {"Name", "Subtitle"}]
    if missing:
        raise SystemExit(f"{path}: no Name/Subtitle for {missing}")
    return {lc: (out[lc]["Name"], out[lc]["Subtitle"]) for lc in LOCALES}


STORE = _store_names(_release_texts_path())

# --- drawing --------------------------------------------------------------

# Fonts and colours are compose.py's, so the assets sit next to the
# screenshots as one family; only the size changes with the canvas.
def head(size):
    return C.HEAD.font_variant(size=size)


def sub(size):
    return C.SUB.font_variant(size=size)


def background(w, h):
    """compose.gradient() at another size (it is hard-wired to 1320x2868)."""
    col = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        col.putpixel((0, y), tuple(round(a + (b - a) * t)
                                   for a, b in zip(C.BG_TOP, C.BG_BOT)))
    return col.resize((w, h))


_PHONES = {}


def phone(raw_path):
    """The device of compose.compose(), alone, as an RGBA image at its native
    1082 px width: same frame, radii, screen inset and pill."""
    if raw_path in _PHONES:
        return _PHONES[raw_path]
    fw, fh = C.FX1 - C.FX0 + 1, C.FY1 - C.FY0 + 1
    sx, sy = C.SX0 - C.FX0, C.SY0 - C.FY0
    sw, sh = C.SX1 - C.SX0 + 1, C.SY1 - C.SY0 + 1
    dev = C.rounded_layer((fw, fh), [((0, 0, fw - 1, fh - 1), C.FRAD, C.FRAME + (255,))])
    with Image.open(raw_path) as im:
        raw = im.convert("RGB")
    scaled = raw.resize((sw, round(raw.height * sw / raw.width)), Image.LANCZOS)
    scaled = scaled.crop((0, 0, sw, sh))
    # Same status-bar cover as compose.compose() (kept in step by hand: that
    # function draws device and caption in one go and exposes neither part).
    strip_c = scaled.getpixel((24, 96))
    ImageDraw.Draw(scaled).rectangle([0, 0, sw, 130], fill=strip_c)
    mask = C.rounded_layer((sw, sh), [((0, 0, sw - 1, sh - 1), C.SRAD, (255, 255, 255, 255))])
    dev.paste(scaled.convert("RGBA"), (sx, sy), mask.split()[3])
    py = C.PILL_Y - C.FY0
    pill = C.rounded_layer((fw, fh), [((fw // 2 - C.PILL_W // 2, py,
                                        fw // 2 + C.PILL_W // 2, py + C.PILL_H),
                                       C.PILL_H // 2, (0, 0, 0, 255))])
    dev.alpha_composite(pill)
    _PHONES[raw_path] = dev
    return dev


def place_phone(canvas, raw_path, x, y, height):
    dev = phone(raw_path)
    w = round(dev.width * height / dev.height)
    small = dev.resize((w, height), Image.LANCZOS)
    canvas.paste(small, (x, y), small)
    return (x, y, x + w, y + height)


def phone_width(height):
    return round((C.FX1 - C.FX0 + 1) * height / (C.FY1 - C.FY0 + 1))


class Clipped(Exception):
    pass


# --- line breaks ------------------------------------------------------------
#
# The drafts were wrapped greedily, and greedy wrapping breaks by width, not
# by sense: it left "Es passt sich dir / an" (a separable prefix alone), a
# lone last word in en/pt-br/fr, and an it line ending on the article "il".
# compose.py never meets this because its headline breaks are written by hand
# (`headline_lines`); these layouts have narrower columns, so their breaks are
# written by hand too — here, keyed by the reviewed text they break.
#
# Rules, enforced on every line that is not the reviewed text's own:
#   - a line is never a single word (a dash glued to its word counts as none);
#   - a line never ends on an article;
#   - a line never starts with a dash: the dash stays at the end of the
#     clause it closes (the ru/en convention), which is where the sense breaks.
# A text that fits on one line is drawn on one line and needs no entry.
# An entry whose text no longer exists in compose.py or the release texts
# fails `--check`: it would otherwise silently stop applying.
BREAKS = {
    # header: the store subtitle
    "Home training that adapts": ["Home training", "that adapts"],
    "План подстраивается под тебя": ["План", "подстраивается", "под тебя"],
    "El plan se adapta a ti": ["El plan", "se adapta a ti"],
    "O plano se adapta a você": ["O plano", "se adapta", "a você"],
    "Der Plan passt sich dir an": ["Der Plan", "passt sich", "dir an"],
    "Le plan s’adapte à toi": ["Le plan", "s’adapte à toi"],
    "Il piano si adatta a te": ["Il piano", "si adatta a te"],
    # search: slot 2 subtitle
    "One tap after the workout — the next one adapts.":
        ["One tap after the workout —", "the next one adapts."],
    "Одно касание после тренировки — следующая подстроится.":
        ["Одно касание", "после тренировки —", "следующая подстроится."],
    "Un toque después del entrenamiento: el siguiente se adapta.":
        ["Un toque después", "del entrenamiento:", "el siguiente se adapta."],
    "Um toque depois do treino — o próximo se adapta.":
        ["Um toque depois do treino —", "o próximo se adapta."],
    "Ein Fingertipp nach dem Training – das nächste passt sich an.":
        ["Ein Fingertipp", "nach dem Training –", "das nächste passt sich an."],
    "Une pression après la séance, la suivante s’ajuste.":
        ["Une pression après la séance,", "la suivante s’ajuste."],
    "Un tocco dopo l’allenamento — il prossimo si adatta.":
        ["Un tocco dopo l’allenamento —", "il prossimo si adatta."],
}

# Breaks the owner signed off although they break a rule above — the way
# compose.py's own `headline_lines` are trusted as written. «План» stands
# alone because the header column is fixed (owner, 06.10.2026).
REVIEWED_BREAKS = {"План подстраивается под тебя"}

ARTICLES = {
    "en": {"a", "an", "the"},
    "ru": set(),
    "es": {"el", "la", "los", "las", "un", "una"},
    "pt-br": {"o", "a", "os", "as", "um", "uma"},
    "de": {"der", "die", "das", "den", "dem", "des", "ein", "eine", "einen"},
    "fr": {"le", "la", "les", "un", "une", "l’"},
    "it": {"il", "lo", "la", "i", "gli", "le", "un", "uno", "una", "l’"},
}
DASHES = ("—", "–")


def bad_break(line, loc):
    """Why a wrapped line breaks against the sense, or None."""
    words = [w for w in line.split(" ") if w not in DASHES]
    if len(words) < 2:
        return "lone word"
    if line.split(" ")[0] in DASHES:
        return "starts with a dash"
    if words[-1].lower() in ARTICLES[loc]:
        return "ends on an article"
    return None


def lines_for(text, font, width, loc):
    """One reviewed line of text -> the lines to draw. The words and their
    order are always the reviewed ones; only the breaks are ours. A line
    wider than the column is a failure, never a reason to shrink the font."""
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    if d.textlength(text, font=font) <= width:
        return [text]
    if text not in BREAKS:
        raise Clipped(f"{text!r} needs two lines and has no entry in BREAKS")
    lines = BREAKS[text]
    if " ".join(lines) != text:
        raise Clipped(f"BREAKS entry does not spell its text: {lines!r}")
    for line in lines:
        if d.textlength(line, font=font) > width:
            raise Clipped(f"{line!r} wider than {width}px")
        why = None if text in REVIEWED_BREAKS else bad_break(line, loc)
        if why:
            raise Clipped(f"{line!r}: {why}")
    return lines


def text_block(blocks, width, loc):
    """blocks: list of (reviewed lines or text, font, colour, gap_after).
    Returns (laid-out rows, total height)."""
    rows, total = [], 0
    for content, font, colour, gap in blocks:
        given = content if isinstance(content, list) else [content]
        lines = [x for line in given for x in lines_for(line, font, width, loc)]
        asc, desc = font.getmetrics()
        lh = round((asc + desc) * 1.08)
        for line in lines:
            rows.append((line, font, colour, total))
            total += lh
        total += gap
    return rows, total


def draw_rows(canvas, rows, x, top, width):
    """Draws the rows; returns the ink box of each, for the zone check."""
    d = ImageDraw.Draw(canvas)
    inks = []
    for line, font, colour, dy in rows:
        d.text((x, top + dy), line, font=font, fill=colour)
        ink = d.textbbox((x, top + dy), line, font=font)
        if ink[0] < x - 1 or ink[2] > x + width + 1 or ink[1] < 0 or ink[3] > canvas.height:
            raise Clipped(f"{line!r} ink {ink} outside column {x}..{x + width}")
        inks.append((repr(line), ink))
    return inks


# --- the two layouts the owner chose -------------------------------------
#
# Each returns an RGB canvas. `raw(slot)` resolves the locale's raw. The font
# sizes are set by the longest single word of the seven locales (ru
# "Подстраивается", 1310 px at 160): `--check` fails if one no longer fits.

HEADER = (3840, 1646)
SEARCH = (3840, 2560)


# Where the header is really seen. Measured by the owner in App Store
# Connect's Device Preview (iPhone, Product Page, 06.10.2026), in asset px:
# the iPhone shows only x 330…3530 of the 3840, and draws a back button and a
# share button OVER the image. The 2.5.0 draft lost the "D" of the wordmark
# and the top of the third phone to exactly these. SAFE is that crop with a
# margin; the button circles are widened to whole rectangles. The page also
# stretches the image's top edge, blurred, behind the status bar — so the top
# edge is left as plain background.
HEADER_SAFE = (520, 0, 3320, 1646)
HEADER_BUTTONS = [(0, 0, 900, 470), (2900, 0, 3840, 470)]
# At the ~0.2x the iPhone shows it, a 110 px cap height is ~22 px on screen.
HEADER_MIN_CAP = 110
HEADER_WORDMARK = head(300)
HEADER_SUB_SIZE = 154
# One phone size and position in every locale (owner, 06.10.2026): en's.
HEADER_PHONE_H = 1116
# The one exception, with its reason (owner, 06.10.2026): ru's subtitle
# breaks «План / подстраивается / под тебя», and «подстраивается» is 1177 px
# at the 154 px subtitle — wider than the 1004 px column en's phones leave.
# 994 is the tallest phone that leaves room for it. Bottom edge and step stay
# en's, so only the top of the cascade moves.
HEADER_PHONE_H_BY_LOCALE = {"ru": 994}


def check_zones(boxes, safe, buttons):
    """boxes: (what, (x0, y0, x1, y1)). Raises on anything outside `safe` or
    overlapping a button rectangle."""
    for what, (x0, y0, x1, y1) in boxes:
        if x0 < safe[0] or y0 < safe[1] or x1 > safe[2] or y1 > safe[3]:
            raise Clipped(f"{what} {(x0, y0, x1, y1)} leaves the safe zone {safe}")
        for bx0, by0, bx1, by1 in buttons:
            if x0 < bx1 and x1 > bx0 and y0 < by1 and y1 > by0:
                raise Clipped(f"{what} {(x0, y0, x1, y1)} enters a button zone "
                              f"{(bx0, by0, bx1, by1)}")


def header(loc, raw):
    """Brand line + a workout in three screens: the plan, the hands-free
    hold, the one-tap rating (slots 1, 3, 2), stepping down left to right in
    the order a workout meets them. The step also keeps the third phone below
    the share button while the first two use the height between the buttons.

    Phones are the same in every locale but those in HEADER_PHONE_H_BY_LOCALE
    (same bottom edge and step); the text column is the room left of them. A subtitle that does not fit breaks by sense (BREAKS), then
    shrinks — never below HEADER_MIN_CAP, and never by shrinking the phones."""
    w, h = HEADER
    sx0, _sy0, sx1, _sy1 = HEADER_SAFE
    cv = background(w, h)
    _name, subtitle = STORE[loc]
    gap_text, gap = 120, 40
    step = round(HEADER_PHONE_H * 0.13)
    below = HEADER_BUTTONS[1][3]           # the third phone starts under the button
    bottom = max(below - 2 * step, (h - (HEADER_PHONE_H + 2 * step)) // 2) \
        + 2 * step + HEADER_PHONE_H        # the third phone's bottom edge, en's
    ph = HEADER_PHONE_H_BY_LOCALE.get(loc, HEADER_PHONE_H)
    if ph > HEADER_PHONE_H:
        raise Clipped(f"phone override {ph} is taller than the default {HEADER_PHONE_H}")
    pw = phone_width(ph)
    top = bottom - 2 * step - ph
    px = sx1 - (3 * pw + 2 * gap)
    col_w = px - gap_text - sx0
    last = None
    for size in range(HEADER_SUB_SIZE, 0, -1):
        font = sub(size)
        cap = font.getbbox("H")
        if cap[3] - cap[1] < HEADER_MIN_CAP:
            raise Clipped(f"{last} — even at the {HEADER_MIN_CAP} px cap floor")
        try:
            lines_for(subtitle, font, col_w, loc)
            break
        except Clipped as e:
            last = e
    boxes = []
    for i, slot in enumerate(["today", "handsfree", "rating"]):
        boxes.append((f"phone {slot}",
                      place_phone(cv, raw(slot), px + i * (pw + gap), top + i * step, ph)))
    rows, th = text_block([("Dredfit", HEADER_WORDMARK, C.HEAD_C, 50),
                           (subtitle, font, C.SUB_C, 0)], col_w, loc)
    # centred on the phones, but a three-line subtitle must not lift the
    # wordmark into the back button's zone
    text_top = max(top + (ph + 2 * step - th) // 2, below + 20)
    boxes += draw_rows(cv, rows, sx0, text_top, col_w)
    check_zones(boxes, HEADER_SAFE, HEADER_BUTTONS)
    return cv


def search(loc, raw):
    """The differentiator stated plainly: slot 2's caption beside the rating
    screen and, next to it, the same workout's plan as Today showed it
    before the rating."""
    w, h = SEARCH
    cv = background(w, h)
    ph = 1800
    pw, gap = phone_width(ph), 90
    px = 180
    for i, slot in enumerate(["rating", "today"]):
        place_phone(cv, raw(slot), px + i * (pw + gap), (h - ph) // 2, ph)
    lines, subtitle = CAPTIONS[("rating", loc)]
    col_x = px + 2 * pw + gap + 120
    col_w = w - 200 - col_x
    rows, th = text_block([(lines, head(160), C.HEAD_C, 70),
                           (subtitle, sub(104), C.SUB_C, 0)], col_w, loc)
    draw_rows(cv, rows, col_x, (h - th) // 2, col_w)
    return cv


LAYOUTS = {"header": header, "search": search}


def stale_breaks():
    """BREAKS entries whose text is no longer a reviewed caption."""
    live = {t for lines, s in CAPTIONS.values() for t in lines + [s]}
    live |= {t for pair in STORE.values() for t in pair}
    return [t for t in BREAKS if t not in live]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--raw", help="dir with <slot>_<locale>.png raws")
    ap.add_argument("--out", help="output dir; files go to <out>/<locale>/<layout>.png")
    ap.add_argument("--locales", default=",".join(LOCALES))
    ap.add_argument("--check", action="store_true",
                    help="lay out every locale on a blank phone, write nothing")
    a = ap.parse_args(argv)
    locs = [x.strip() for x in a.locales.split(",") if x.strip()]
    bad = [x for x in locs if x not in LOCALES]
    if bad:
        ap.error(f"unknown locale(s) {bad}; known: {LOCALES}")
    if not a.check and not (a.raw and a.out):
        ap.error("--raw and --out are required unless --check")

    failures = [f"stale BREAKS entry: {t!r}" for t in stale_breaks()]
    with tempfile.TemporaryDirectory() as tmp:
        blank = None
        if a.check:
            blank = os.path.join(tmp, "blank.png")
            Image.new("RGB", (1320, 2868), "white").save(blank)
        for loc in locs:
            def raw(slot, loc=loc):
                if blank:
                    return blank
                p = os.path.join(a.raw, f"{slot}_{loc}.png")
                if not os.path.exists(p):
                    raise FileNotFoundError(p)
                return p
            for name, fn in LAYOUTS.items():
                try:
                    cv = fn(loc, raw).convert("RGB")
                except (Clipped, FileNotFoundError) as e:
                    failures.append(f"{loc}/{name}: {e}")
                    continue
                if a.check:
                    print("fits", f"{loc}/{name}")
                    continue
                out = os.path.join(a.out, loc, f"{name}.png")
                os.makedirs(os.path.dirname(out), exist_ok=True)
                cv.save(out)
                print("wrote", out)
    if failures:
        raise SystemExit("not composed:\n  " + "\n  ".join(failures))


if __name__ == "__main__":
    sys.exit(main())
