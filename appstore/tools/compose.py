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
    # --- 3. probe_ — new in 2.0.0, replaces milestone_ (see the note below).
    (f"{RAW}/probe_en.png",      ["Nothing unlocks itself"], "One set of the next movement decides — not a calendar.", f"{OUT}/en/s3.png"),
    (f"{RAW}/probe_ru.png",      ["Само ничего", "не откроется"], "Один подход нового движения решает — не календарь.", f"{OUT}/ru/s3.png"),
    (f"{RAW}/probe_es.png",      ["Nada se desbloquea solo."], "Una serie del siguiente movimiento decide — no un calendario.", f"{OUT}/es/s3.png"),
    (f"{RAW}/probe_pt-br.png",   ["Nada se desbloqueia sozinho"], "Uma série do próximo movimento decide — não um calendário.", f"{OUT}/pt-br/s3.png"),
    (f"{RAW}/probe_de.png",      ["Nichts schaltet sich", "von selbst frei"], "Eine Probe der nächsten Bewegung entscheidet – nicht der Kalender.", f"{OUT}/de/s3.png"),
    (f"{RAW}/probe_fr.png",      ["Rien ne se débloque", "tout seul"], "Une série de la variante suivante décide, pas le calendrier.", f"{OUT}/fr/s3.png"),
    (f"{RAW}/probe_it.png",      ["Niente si sblocca", "da solo"], "Decide una serie del movimento nuovo, non il calendario.", f"{OUT}/it/s3.png"),
    # --- 4. set_ — the first of the seven that confirm.
    (f"{RAW}/set_en.png",        ["One focus at a time"], "Big numbers, one tap per set.", f"{OUT}/en/s4.png"),
    (f"{RAW}/set_ru.png",        ["Один фокус за раз"], "Крупные цифры, одно касание на подход.", f"{OUT}/ru/s4.png"),
    (f"{RAW}/set_es.png",        ["Un enfoque a la vez"], "Números grandes, un toque por serie.", f"{OUT}/es/s4.png"),
    (f"{RAW}/set_pt-br.png",     ["Um foco por vez"], "Números grandes, um toque por série.", f"{OUT}/pt-br/s4.png"),
    (f"{RAW}/set_de.png",        ["Ein Fokus auf einmal"], "Große Zahlen, ein Fingertipp pro Satz.", f"{OUT}/de/s4.png"),
    (f"{RAW}/set_fr.png",        ["Une série à la fois"], "De grands chiffres, une pression par série.", f"{OUT}/fr/s4.png"),
    (f"{RAW}/set_it.png",        ["Un solo obiettivo alla volta"], "Numeri grandi, un tocco per ogni serie.", f"{OUT}/it/s4.png"),
    # --- 5. skip_ — the decision inside the workout (§38.2).
    (f"{RAW}/skip_en.png",       ["Too much today?"], "Skip a set while you are doing it. The clock follows.", f"{OUT}/en/s5.png"),
    (f"{RAW}/skip_ru.png",       ["Сегодня многовато?"], "Пропусти подход прямо на тренировке. Время пересчитается.", f"{OUT}/ru/s5.png"),
    (f"{RAW}/skip_es.png",       ["¿Hoy es demasiado?"], "Omite una serie mientras entrenas. El tiempo se ajusta solo.", f"{OUT}/es/s5.png"),
    (f"{RAW}/skip_pt-br.png",    ["Hoje é demais?"], "Pule uma série durante o treino. O tempo se recalcula.", f"{OUT}/pt-br/s5.png"),
    (f"{RAW}/skip_de.png",       ["Heute zu viel?"], "Überspringe einen Satz mitten im Training – die Zeit passt sich an.", f"{OUT}/de/s5.png"),
    (f"{RAW}/skip_fr.png",       ["Trop pour aujourd’hui ?"], "Passe une série en pleine séance. Le temps se recalcule.", f"{OUT}/fr/s5.png"),
    (f"{RAW}/skip_it.png",       ["Oggi è troppo?"], "Salta una serie durante l’allenamento: il tempo si ricalcola.", f"{OUT}/it/s5.png"),
    # --- 6. progress_
    (f"{RAW}/progress_en.png",   ["Progress you can see"], "Every movement, step by step.", f"{OUT}/en/s6.png"),
    (f"{RAW}/progress_ru.png",   ["Прогресс, который", "видно"], "Каждое движение, ступень за ступенью.", f"{OUT}/ru/s6.png"),
    (f"{RAW}/progress_es.png",   ["Progreso que puedes ver"], "Cada movimiento, paso a paso.", f"{OUT}/es/s6.png"),
    (f"{RAW}/progress_pt-br.png", ["Progresso que você vê"], "Cada movimento, passo a passo.", f"{OUT}/pt-br/s6.png"),
    (f"{RAW}/progress_de.png",   ["Fortschritt,", "den du siehst"], "Jede Bewegung, Stufe für Stufe.", f"{OUT}/de/s6.png"),
    (f"{RAW}/progress_fr.png",   ["Une progression visible"], "Chaque mouvement, cran après cran.", f"{OUT}/fr/s6.png"),
    (f"{RAW}/progress_it.png",   ["Progressi che si", "vedono"], "Ogni movimento, un gradino alla volta.", f"{OUT}/it/s6.png"),
    # --- 7. howitworks_ — the number in the subtitle IS the section count of
    #        HowItWorksView (twelve today). Re-read that file every release.
    (f"{RAW}/howitworks_en.png", ["No black box"], "Twelve plain facts about how the plan moves.", f"{OUT}/en/s7.png"),
    (f"{RAW}/howitworks_ru.png", ["Без черного ящика"], "Двенадцать простых фактов о том, как движется план.", f"{OUT}/ru/s7.png"),
    (f"{RAW}/howitworks_es.png", ["Sin caja negra"], "Doce datos claros sobre cómo se mueve el plan.", f"{OUT}/es/s7.png"),
    (f"{RAW}/howitworks_pt-br.png", ["Sem caixa preta"], "Doze fatos simples sobre como o plano se move.", f"{OUT}/pt-br/s7.png"),
    (f"{RAW}/howitworks_de.png", ["Keine Blackbox"], "Zwölf einfache Fakten darüber, wie der Plan sich bewegt.", f"{OUT}/de/s7.png"),
    (f"{RAW}/howitworks_fr.png", ["Pas de boîte noire"], "Douze faits simples sur le régulateur.", f"{OUT}/fr/s7.png"),
    (f"{RAW}/howitworks_it.png", ["Niente scatola nera"], "Dodici fatti semplici su come si muove il piano.", f"{OUT}/it/s7.png"),
    # --- 8. comeback_ — the subtitle was rewritten in 2.0.0: the card promises
    #        a depth that GROWS WITH THE BREAK, not a fixed "couple of steps".
    (f"{RAW}/comeback_en.png",   ["Breaks are normal"], "The longer the break, the lower the plan meets you.", f"{OUT}/en/s8.png"),
    (f"{RAW}/comeback_ru.png",   ["Возвращаться легко"], "Чем длиннее перерыв, тем ниже встретит план.", f"{OUT}/ru/s8.png"),
    (f"{RAW}/comeback_es.png",   ["Las pausas son normales"], "Cuanto más larga la pausa, más bajo te recibe el plan.", f"{OUT}/es/s8.png"),
    (f"{RAW}/comeback_pt-br.png", ["Pausas são normais"], "Quanto mais longa a pausa, mais abaixo o plano espera você.", f"{OUT}/pt-br/s8.png"),
    (f"{RAW}/comeback_de.png",   ["Trainingspausen", "sind normal"], "Je länger die Pause, desto tiefer holt dich der Plan ab.", f"{OUT}/de/s8.png"),
    (f"{RAW}/comeback_fr.png",   ["Les coupures, c’est normal"], "Plus la coupure est longue, plus bas le plan te retrouve.", f"{OUT}/fr/s8.png"),
    (f"{RAW}/comeback_it.png",   ["Le pause sono normali"], "Più lunga la pausa, più in basso ti aspetta il piano.", f"{OUT}/it/s8.png"),
    # --- 9. rest_ — 60 s is the band-3 pause (EngineConfig.restSetByBand).
    (f"{RAW}/rest_en.png",       ["Rest is timed for you"], "60 seconds, counted down automatically.", f"{OUT}/en/s9.png"),
    (f"{RAW}/rest_ru.png",       ["Отдых отсчитается", "сам"], "60 секунд — таймер уже запущен.", f"{OUT}/ru/s9.png"),
    (f"{RAW}/rest_es.png",       ["El descanso se cuenta solo."], "60 segundos, con cuenta regresiva automática.", f"{OUT}/es/s9.png"),
    (f"{RAW}/rest_pt-br.png",    ["O descanso é cronometrado"], "60 segundos, contados automaticamente.", f"{OUT}/pt-br/s9.png"),
    (f"{RAW}/rest_de.png",       ["Die Pause läuft für dich"], "60 Sekunden, automatisch heruntergezählt.", f"{OUT}/de/s9.png"),
    (f"{RAW}/rest_fr.png",       ["Le repos se compte", "tout seul"], "60 secondes — décompte automatique.", f"{OUT}/fr/s9.png"),
    (f"{RAW}/rest_it.png",       ["Il recupero ha", "un timer tutto suo"], "60 secondi, conto alla rovescia automatico.", f"{OUT}/it/s9.png"),
    # --- 10. dial_
    (f"{RAW}/dial_en.png",       ["Life happens —", "adjust"], "Did fewer reps? Record it right at the exercise.", f"{OUT}/en/s10.png"),
    (f"{RAW}/dial_ru.png",       ["Вышло иначе?", "Поправь"], "Факт записывается прямо у упражнения.", f"{OUT}/ru/s10.png"),
    (f"{RAW}/dial_es.png",       ["Pasan cosas —", "ajusta."], "¿Hiciste menos repeticiones? Anótalo en el mismo ejercicio.", f"{OUT}/es/s10.png"),
    (f"{RAW}/dial_pt-br.png",    ["Foi diferente?", "Ajuste."], "Fez menos repetições? Registre direto no exercício.", f"{OUT}/pt-br/s10.png"),
    (f"{RAW}/dial_de.png",       ["Läuft mal anders –", "trag's ein"], "Weniger Wiederholungen gemacht? Trag es direkt bei der Übung ein.", f"{OUT}/de/s10.png"),
    (f"{RAW}/dial_fr.png",       ["Ça s’est passé autrement", "Ajuste"], "Le fait se note directement sur l’exercice.", f"{OUT}/fr/s10.png"),
    (f"{RAW}/dial_it.png",       ["La vita a volte", "cambia i piani"], "Hai fatto meno ripetizioni? Registralo proprio lì, sull’esercizio.", f"{OUT}/it/s10.png"),
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
# All 70 captions are translated as of 2.0.0. The es/pt-BR/de/fr/it lines were
# staged as `TODO-i18n` first rather than left carrying their 1.9.0 text: five
# of the ten slots changed their caption or their neighbour, and NOTHING IN CI
# READS THIS FILE — check_localization.py and the required Localization check
# walk String Catalogs only. An English phrase that reaches the German
# storefront fails no run, so a placeholder has to fail the EYE instead. Keep
# that staging habit for the next slot change: write the marker, then close it
# per instructions/TRANSLATOR_PROMPT.md and GLOSSARY.md, one agent per language.
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

for j in jobs:
    if os.path.exists(j[0]):
        compose(*j)
    else:
        print("skip (no raw):", j[0])
