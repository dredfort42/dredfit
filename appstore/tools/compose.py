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
    (f"{RAW}/today_es.png",      ["Cero configuración."], "Abre la app: tu entrenamiento ya está listo.", f"{OUT}/es/s1.png"),
    (f"{RAW}/today_pt-br.png",   ["Zero configuração."], "Abra o app — seu treino está pronto.", f"{OUT}/pt-br/s1.png"),
    (f"{RAW}/today_de.png",      ["Nichts einzurichten"], "Öffne die App – dein Training steht bereit.", f"{OUT}/de/s1.png"),
    (f"{RAW}/today_fr.png",      ["Rien à configurer."], "Ouvre l’app, la séance est prête.", f"{OUT}/fr/s1.png"),
    (f"{RAW}/today_it.png",      ["Zero configurazioni."], "Apri l’app: l’allenamento è pronto.", f"{OUT}/it/s1.png"),
    # --- 2. rating_ — the differentiator: one question, and the plan moves.
    (f"{RAW}/rating_en.png",     ["It adapts to you"], "One tap after the workout — the next one adapts.", f"{OUT}/en/s2.png"),
    (f"{RAW}/rating_ru.png",     ["Подстраивается", "под тебя"], "Одно касание после тренировки — следующая изменится.", f"{OUT}/ru/s2.png"),
    (f"{RAW}/rating_es.png",     ["Se adapta a ti"], "Un toque después del entrenamiento: el siguiente se adapta.", f"{OUT}/es/s2.png"),
    (f"{RAW}/rating_pt-br.png",  ["Se adapta a você"], "Um toque depois do treino — o próximo se adapta.", f"{OUT}/pt-br/s2.png"),
    (f"{RAW}/rating_de.png",     ["Es passt sich dir an"], "Ein Fingertipp nach dem Training – das nächste passt sich an.", f"{OUT}/de/s2.png"),
    (f"{RAW}/rating_fr.png",     ["S’adapte à toi"], "Une pression après la séance, la suivante s’ajuste.", f"{OUT}/fr/s2.png"),
    (f"{RAW}/rating_it.png",     ["Si adatta a te"], "Un tocco dopo l’allenamento — il prossimo cambia.", f"{OUT}/it/s2.png"),
    # --- 3. handsfree_ — new in 2.1.0, and the wave's own promise: the hold
    #        intro, said by the screen that says it in words (R23/R28).
    #        Taken on the walk to the rating, not on a route of its own.
    (f"{RAW}/handsfree_en.png",   ["Put the phone down"], "One tap runs the whole exercise. Sound counts you in and out.", f"{OUT}/en/s3.png"),
    (f"{RAW}/handsfree_ru.png",   ["Телефон", "можно положить"], "Одно касание — и упражнение идет само. Звук ведет счет.", f"{OUT}/ru/s3.png"),
    (f"{RAW}/handsfree_es.png",   ["Deja el teléfono", "en el suelo"], "Un toque hace todo el ejercicio. El sonido cuenta por ti.", f"{OUT}/es/s3.png"),
    (f"{RAW}/handsfree_pt-br.png", ["Largue o celular", "no chão"], "Um toque comanda todo o exercício. O som marca início e fim.", f"{OUT}/pt-br/s3.png"),
    (f"{RAW}/handsfree_de.png",   ["Leg das Handy weg"], "Ein Tipp für die ganze Übung – der Ton zählt dich rein und raus.", f"{OUT}/de/s3.png"),
    (f"{RAW}/handsfree_fr.png",   ["Pose le téléphone"], "Une pression lance tout l’exercice. Le son marque le début et la fin.", f"{OUT}/fr/s3.png"),
    (f"{RAW}/handsfree_it.png",   ["Appoggia il telefono"], "Un tocco avvia tutto l’esercizio. Il suono segna inizio e fine.", f"{OUT}/it/s3.png"),
    # --- 4. probe_ — new in 2.0.0, replaces milestone_ (see the note below),
    #        and the first of the seven slots that only have to confirm.
    (f"{RAW}/probe_en.png",      ["Nothing unlocks itself"], "One set of the next movement decides — not a calendar.", f"{OUT}/en/s4.png"),
    (f"{RAW}/probe_ru.png",      ["Само ничего", "не откроется"], "Один подход следующего движения решает — не календарь.", f"{OUT}/ru/s4.png"),
    (f"{RAW}/probe_es.png",      ["Nada se desbloquea solo"], "Una serie del siguiente movimiento decide — no un calendario.", f"{OUT}/es/s4.png"),
    (f"{RAW}/probe_pt-br.png",   ["Nada se desbloqueia", "sozinho"], "Uma série do próximo movimento decide — não um calendário.", f"{OUT}/pt-br/s4.png"),
    (f"{RAW}/probe_de.png",      ["Nichts schaltet sich", "von selbst frei"], "Eine Probe der nächsten Bewegung entscheidet – kein Kalender.", f"{OUT}/de/s4.png"),
    (f"{RAW}/probe_fr.png",      ["Rien ne se débloque", "tout seul"], "Une série de la variante suivante décide, pas le calendrier.", f"{OUT}/fr/s4.png"),
    (f"{RAW}/probe_it.png",      ["Niente si sblocca", "da solo"], "Decide una serie del movimento nuovo, non il calendario.", f"{OUT}/it/s4.png"),
    # --- 5. technique_ — new in 2.1.0. The sheet FROM THE PLAN: `planned:
    #        true` lives in one place in the project (TodayView.swift:46) and
    #        is what draws the step below, so no other door composes this.
    (f"{RAW}/technique_en.png",   ["Always a version", "you can do"], "Technique for every movement — and the easier version.", f"{OUT}/en/s5.png"),
    (f"{RAW}/technique_ru.png",   ["Всегда есть", "вариация полегче"], "У каждого движения — техника и вариация полегче.", f"{OUT}/ru/s5.png"),
    (f"{RAW}/technique_es.png",   ["Siempre hay una versión", "que puedes hacer"], "Técnica para cada movimiento — y la variación más fácil.", f"{OUT}/es/s5.png"),
    (f"{RAW}/technique_pt-br.png", ["Sempre existe uma", "variação possível"], "Técnica para cada movimento — e a variação mais fácil.", f"{OUT}/pt-br/s5.png"),
    (f"{RAW}/technique_de.png",   ["Immer eine", "leichtere Variante"], "Technik zu jeder Bewegung – und die leichtere Variante.", f"{OUT}/de/s5.png"),
    (f"{RAW}/technique_fr.png",   ["Toujours une", "variante plus facile"], "La technique de chaque mouvement — et la variante plus facile.", f"{OUT}/fr/s5.png"),
    (f"{RAW}/technique_it.png",   ["Sempre c’è una", "variante che puoi fare"], "Tecnica per ogni movimento — e la variante più facile.", f"{OUT}/it/s5.png"),
    # --- 6. set_
    (f"{RAW}/set_en.png",        ["One focus at a time"], "Big numbers, one tap per set.", f"{OUT}/en/s6.png"),
    (f"{RAW}/set_ru.png",        ["Одно дело за раз"], "Крупные цифры, одно касание на подход.", f"{OUT}/ru/s6.png"),
    (f"{RAW}/set_es.png",        ["Una cosa a la vez"], "Números grandes, un toque por serie.", f"{OUT}/es/s6.png"),
    (f"{RAW}/set_pt-br.png",     ["Um foco por vez"], "Números grandes, um toque por série.", f"{OUT}/pt-br/s6.png"),
    (f"{RAW}/set_de.png",        ["Ein Fokus auf einmal"], "Große Zahlen, ein Fingertipp pro Satz.", f"{OUT}/de/s6.png"),
    (f"{RAW}/set_fr.png",        ["Une série à la fois"], "De grands chiffres, une pression par série.", f"{OUT}/fr/s6.png"),
    (f"{RAW}/set_it.png",        ["Un obiettivo alla volta"], "Numeri grandi, un tocco per ogni serie.", f"{OUT}/it/s6.png"),
    # --- 7. skip_ — the decision inside the workout (§38.2).
    (f"{RAW}/skip_en.png",       ["Too much today?"], "Skip a set while you are doing it. The clock follows.", f"{OUT}/en/s7.png"),
    (f"{RAW}/skip_ru.png",       ["Сегодня многовато?"], "Пропусти подход прямо по ходу. Время пересчитается.", f"{OUT}/ru/s7.png"),
    (f"{RAW}/skip_es.png",       ["¿Hoy es demasiado?"], "Omite una serie mientras entrenas. El tiempo se ajusta solo.", f"{OUT}/es/s7.png"),
    (f"{RAW}/skip_pt-br.png",    ["Hoje é demais?"], "Pule uma série durante o treino. O tempo se recalcula.", f"{OUT}/pt-br/s7.png"),
    (f"{RAW}/skip_de.png",       ["Heute zu viel?"], "Überspringe einen Satz mitten im Training – die Zeit passt sich an.", f"{OUT}/de/s7.png"),
    (f"{RAW}/skip_fr.png",       ["Trop pour aujourd’hui ?"], "Passe une série en pleine séance. Le temps se recalcule.", f"{OUT}/fr/s7.png"),
    (f"{RAW}/skip_it.png",       ["Oggi è troppo?"], "Salta una serie durante l’allenamento: il tempo si ricalcola.", f"{OUT}/it/s7.png"),
    # --- 8. progress_
    (f"{RAW}/progress_en.png",   ["Progress you can see"], "Every movement, step by step.", f"{OUT}/en/s8.png"),
    (f"{RAW}/progress_ru.png",   ["Прогресс,", "который видно"], "Каждое движение, ступень за ступенью.", f"{OUT}/ru/s8.png"),
    (f"{RAW}/progress_es.png",   ["Progreso que puedes ver"], "Cada movimiento, paso a paso.", f"{OUT}/es/s8.png"),
    (f"{RAW}/progress_pt-br.png", ["Progresso que você vê"], "Cada movimento, passo a passo.", f"{OUT}/pt-br/s8.png"),
    (f"{RAW}/progress_de.png",   ["Fortschritt,", "den du siehst"], "Jede Bewegung, Stufe für Stufe.", f"{OUT}/de/s8.png"),
    (f"{RAW}/progress_fr.png",   ["Une progression visible"], "Chaque mouvement, cran après cran.", f"{OUT}/fr/s8.png"),
    (f"{RAW}/progress_it.png",   ["Progressi che", "si vedono"], "Ogni movimento, un gradino alla volta.", f"{OUT}/it/s8.png"),
    # --- 9. howitworks_ — the number in the subtitle IS the section count of
    #        HowItWorksView (twelve today). Re-read that file every release;
    #        the checklist names this frame by RAW, never by slot number.
    (f"{RAW}/howitworks_en.png", ["No black box"], "Twelve plain facts about how the plan moves.", f"{OUT}/en/s9.png"),
    (f"{RAW}/howitworks_ru.png", ["Без черного ящика"], "Двенадцать простых фактов о том, как движется план.", f"{OUT}/ru/s9.png"),
    (f"{RAW}/howitworks_es.png", ["Sin caja negra"], "Doce datos claros sobre cómo se mueve el plan.", f"{OUT}/es/s9.png"),
    (f"{RAW}/howitworks_pt-br.png", ["Sem caixa preta"], "Doze fatos simples sobre como o plano se move.", f"{OUT}/pt-br/s9.png"),
    (f"{RAW}/howitworks_de.png", ["Keine Blackbox"], "Zwölf einfache Fakten darüber, wie der Plan sich bewegt.", f"{OUT}/de/s9.png"),
    (f"{RAW}/howitworks_fr.png", ["Pas de boîte noire"], "Douze faits simples sur le régulateur.", f"{OUT}/fr/s9.png"),
    (f"{RAW}/howitworks_it.png", ["Niente scatola nera"], "Dodici fatti semplici su come si muove il piano.", f"{OUT}/it/s9.png"),
    # --- 10. comeback_ — the subtitle was rewritten in 2.0.0: the card promises
    #         a depth that GROWS WITH THE BREAK, not a fixed "couple of steps".
    (f"{RAW}/comeback_en.png",   ["Breaks are normal"], "The longer the break, the lower the plan meets you.", f"{OUT}/en/s10.png"),
    (f"{RAW}/comeback_ru.png",   ["Возвращаться легко"], "Чем длиннее перерыв, тем ниже встретит план.", f"{OUT}/ru/s10.png"),
    (f"{RAW}/comeback_es.png",   ["Las pausas son normales"], "Cuanto más larga la pausa, más abajo te espera el plan.", f"{OUT}/es/s10.png"),
    (f"{RAW}/comeback_pt-br.png", ["Pausas são normais"], "Quanto mais longa a pausa, mais abaixo o plano espera você.", f"{OUT}/pt-br/s10.png"),
    (f"{RAW}/comeback_de.png",   ["Trainingspausen", "sind normal"], "Je länger die Pause, desto tiefer holt dich der Plan ab.", f"{OUT}/de/s10.png"),
    (f"{RAW}/comeback_fr.png",   ["Les coupures,", "c’est normal"], "Plus la coupure est longue, plus bas le plan te retrouve.", f"{OUT}/fr/s10.png"),
    (f"{RAW}/comeback_it.png",   ["Le pause sono normali"], "Più lunga la pausa, più in basso ti aspetta il piano.", f"{OUT}/it/s10.png"),
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
# 2.1.0: THE ORDER CHANGED AGAIN AND TWO SLOTS WERE REPLACED — `handsfree_`
# entered at 3 and `technique_` at 5, `rest_` and `dial_` left, and slots 4 and
# 6…10 all moved. Recapture is total for a third, independent reason as well:
# Localizable.xcstrings changed in this wave, which stales every frame.
#
# WHY THE TWO THAT LEFT LEFT, and the distinction matters more than the fact:
#
# `rest_` left because its PROMISE is weak. "Rest is timed for you" is what a
# visitor assumes any training app already does, so the slot spent a selling
# position confirming an expectation. Slot 3 says the strong version of the
# same thing: the whole exercise is timed, not the pause between its sets.
#
# `dial_` left ALIVE. This is not the `milestone_` lesson below and must not be
# read as one — nothing about that frame was false. Three checks, all made
# before the slot was dropped: (1) its capture path stood on the FIRST exercise
# of seed A, which counter 11 makes `push_h`; (2) `Library+Push.swift:25` gives
# that rung "Incline push-up", `unit: .reps` — a reps screen, so "Did fewer
# reps?" was true of it; (3) the shipped 2.0.0 raw showed exactly that screen,
# a big 6 over "reps" with the `− 6 + OK` strip open. `WentDifferentlyButton`
# is on every reps set to this day (`WorkoutFlowView+Work.swift:245`). It lost
# its slot ON VALUE: the control is already legible as a button on slots 6 and
# 7, and the promise behind it ("it bends to you") is what slot 2 sells with a
# whole screen. A future wave that wants it back needs no repair — it needs a
# weaker frame to displace, and the `exercise-adjust` walk put back into
# StoreScreenshots.swift.reference.
#
# A slot that changes meaning changes its caption in all seven languages, and
# the author can only measure the pair he writes. The five he cannot are STAGED
# as `TRANSLATOR:<lang>` and closed per instructions/TRANSLATOR_PROMPT.md and
# GLOSSARY.md, one agent per language. How many are open right now is not
# written here — read the `jobs` table, or run the script and let the gate at
# the bottom name them; a count in prose is stale by the next wave.
#
# The fr captions carry U+202F before `?` on purpose. It is a real character
# and it survives an edit only if you write it as chr(0x202F) — a literal typed
# into a heredoc collapses to a plain space, silently, and no gate sees it.

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

# --- The caption must fit the canvas. -----------------------------------
#
# 2.0.0 shipped seven captions whose glyphs ran off the 1320 px canvas: the
# composer centres a line and CLIPS whatever falls outside, so a German
# subtitle lost its first word and an Italian headline lost its first and
# last letter — with no error, no warning and no gate. Nothing in CI reads
# this file (check_localization.py walks String Catalogs only), and the raw
# screen inside the frame looked perfect, so the eye that reviewed the set
# read the sentence it EXPECTED rather than the one on the canvas.
#
# The measurement is the composer's own, not an estimate: same fonts, same
# `textbbox`, same integer centring as `text_centered` — an approximation
# here would be a second thing to keep in sync with the first.
#
# SAFE_PAD is 8 and not a comfortable 24 on purpose. It is a CLIPPING gate,
# not a taste gate: the 2.0.0 set the owner approved contains a line 1302 px
# wide (es/s3), and a stricter number would fail captions that are already
# signed off — a gate that cries about approved work is a gate people learn
# to bypass. TIGHT below is the taste half, and it only prints.
SAFE_PAD, TIGHT_PAD = 8, 24


def _placed(text, font):
    """(left, right) of the ink once `text_centered` has centred it."""
    b = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), text, font=font)
    x = (W - (b[2] - b[0])) // 2 - b[0]
    return x + b[0], x + b[2]


_over, _tight = [], []
for _raw, _lines, _sub, _out in jobs:
    _frame = "/".join(_out.split(os.sep)[-2:])
    for _text, _font in [(line, HEAD) for line in _lines] + [(_sub, SUB)]:
        left, right = _placed(_text, _font)
        pad = min(left, W - right)
        # A headline has two ways out (shorten, or break it in two by the
        # sense of the phrase); a subtitle has ONE — it is always a single
        # line, so only the wording can give. Hence the hint below.
        if pad < SAFE_PAD:
            _over.append(f"{_frame} {'sub' if _font is SUB else 'head'} "
                         f"{right - left} px, {pad} px of margin: {_text!r}")
        elif pad < TIGHT_PAD:
            _tight.append(f"{_frame} {pad} px: {_text!r}")
for _line in _tight:
    print("tight:", _line)
assert not _over, ("captions clipped by the 1320 px canvas — shorten the phrase "
                   "(a subtitle) or break the headline in two by its sense, "
                   "never shrink the font:\n  " + "\n  ".join(_over))

# --- A staged caption must not be able to reach the store. --------------
#
# WHY THE MARKER EXISTS, whether or not any line carries one today: NOTHING IN
# CI READS THIS FILE. check_localization.py and the required Localization check
# walk String Catalogs only, so an English phrase that reaches the German
# storefront fails no run. 2.0.0 staged its open captions as a `TODO-i18n`
# COMMENT, which the composer happily drew right past — the only thing between
# that frame and the storefront was the eye of whoever assembled the upload.
#
# So the marker is load-bearing instead. A frame whose headline or subtitle
# carries it is NOT composed — the file simply does not exist, and a file that
# does not exist cannot be dragged into ASC — and if its raw was captured (i.e.
# this was a real compose run and not a structure check) the script exits
# non-zero naming every frame that is still open. No env override: a gate with
# a bypass is a gate people learn to bypass.
MARKER = "TRANSLATOR:"

_blocked = []
for j in jobs:
    _raw, _lines, _sub, _out = j
    _frame = "/".join(_out.split(os.sep)[-2:])
    if any(MARKER in t for t in list(_lines) + [_sub]):
        print("UNTRANSLATED (not composed):", _frame,
              "←", os.path.basename(_raw))
        if os.path.exists(_raw):
            _blocked.append(f"{_frame} ({os.path.basename(_raw)})")
        continue
    if os.path.exists(_raw):
        compose(*j)
    else:
        print("skip (no raw):", _raw)

if _blocked:
    raise SystemExit("captions still staged as " + MARKER + "<lang> — these "
                     "frames have a raw and no caption, so the set is "
                     "incomplete and must not be uploaded:\n  "
                     + "\n  ".join(_blocked))
