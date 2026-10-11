#!/usr/bin/env python3
"""Fail if the Google Play listing breaks a rule a script can decide.

    python3 store/playstore/tools/check_listing.py           # listing/ + the frame captions
    python3 store/playstore/tools/check_listing.py --list    # the rules and their reasons

The listing is tracked as one file per Play field and locale
(`store/playstore/listing/<locale>/<field>.txt`) precisely so that this can
count it: Play Console truncates nothing and warns about little, and the App
Store package taught that a storefront text nobody counted ships with whatever
is in it.

What it checks, all without judgement:

* **Play's limits** — title 30, short description 80, full description 4000,
  what's new 500, a line break counted as two — and that every locale carries
  all four fields;
* **the translation rules**, imported rather than restated: every rule of
  `scripts/check_release_texts.py` (the App Store package's — the Russian `е`,
  mixed scripts, French spacing and apostrophes, the German dash), plus the
  rules of `scripts/check_translation_rules.py` that the package does not have
  (informal address in five languages, units, double spaces, the German
  "Training");
* **another platform's words** — Apple, iPhone, iOS, App Store, HealthKit,
  Live Activity, Dynamic Island, iCloud, and Apple Health under its local names
  (Salud, Saúde, Santé, «Здоровье»…) wherever they are not the start of Health
  Connect's own. Every listing claim must be true on Android, and these name
  things the Android app does not have; every iOS text this listing was
  adapted from carried several of them;
* **Play's metadata policy** where a script can read it: no ranking, price or
  promotional words ("no ads" included) and no calls to action in the title
  and the short description, no emoji, no words in capitals, no repeated
  punctuation or line break in the title and the short description;
* **two apostrophe styles** in one text, the trace of a paste;
* **a locale left in English**: a field identical to its en-US twin;
* **the frame captions and the feature graphic's line** in `captions.py`,
  through the same rules — on iOS
  "captions are checked by NOTHING", and an English phrase reached the German
  storefront that way.

Not checked: terminology, tone, whether a claim is true. Those stay a
reviewer's pass against the Android code.

**Every rule is proved to be able to fail** before anything is checked: both
imported rule sets run their own self-tests, and each rule added here is run on
a string that must trip it and one that must not. A predicate gone inert reads
exactly like a clean listing.

Intentional exceptions go in `check_listing_config.json` next to this file,
keyed by rule id, `{"allow": [<hit>, ...], "why": "<reason>"}` — an iOS word
that a sentence explains on purpose, say. There are none today.

Stdlib only, Python 3.9, like the scripts it imports.
"""
import importlib.util
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
LISTING = HERE.parent / "listing"
CONFIG = HERE / "check_listing_config.json"

# Play's locale code → the code the shared rules are keyed by.
LOCALES = {"en-US": "en", "ru-RU": "ru", "es-ES": "es", "pt-BR": "pt-BR",
           "de-DE": "de", "fr-FR": "fr", "it-IT": "it"}

# Play Console's limits, per field: title, short and full description in
# support.google.com/googleplay/android-developer/answer/113469; what's new is
# the release-notes box, 500 per language.
LIMITS = {"title": 30, "short_description": 80, "full_description": 4000, "whats_new": 500}


def play_length(text):
    """Characters as Play may count them: a line break as two. A browser form
    submits a textarea's breaks as CRLF, and how the console counts them was
    not observed — so the count that cannot be wrong is the larger one."""
    return len(text) + text.count("\n")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


release = _load("check_release_texts", ROOT / "scripts" / "check_release_texts.py")
catalog = _load("check_translation_rules", ROOT / "scripts" / "check_translation_rules.py")

# The package's rules win where both scripts define one id: the README of
# store/playstore promises the package's rules "unchanged".
_release_ids = {r["id"] for r in release.RULES}
ALL = list(LOCALES.values())
# The catalogs' double-space rule leaves English out (English is the catalogs'
# source, read elsewhere); a listing's English is shipped text like the rest.
_EVERY_LOCALE = {"double-space"}
SHARED_RULES = list(release.RULES) + [dict(r, locales=ALL) if r["id"] in _EVERY_LOCALE else r
                                      for r in catalog.RULES if r["id"] not in _release_ids]

# Words of another platform. Case-sensitive on purpose: "ios" inside a word
# is Spanish or Portuguese, "iOS" is Apple's.
OTHER_PLATFORM = re.compile(
    r"\bApple\b|\biPhone\b|\biPad\b|\biOS\b|\bApp Store\b|\bHealthKit\b|\biCloud\b"
    r"|\bApp Privacy\b|\bDynamic Island\b|\bLive Activit(?:y|ies)\b|\bLive-Aktivität\w*"
    r"|\b[Aa]ctividad(?:es)? en vivo\b|\b[Aa]tividades? ao [Vv]ivo\b|\b[Aa]ctivités? en direct\b"
    r"|\b[Aa]ttività [Ll]ive\b|\bSiri\b"
    # Apple Health under its local names — each one only where it is not the
    # start of Health Connect's own local name, which the listing does use.
    r"|\bHealth\b(?! Connect)|\bSalud\b(?! conectada)|(?<!Conexão )\bSaúde\b"
    r"|\bSanté\b(?! Connect)|\bSalute\b|«?Здоровье»?(?! и спорт)")

# Play's metadata policy: store performance, rank, price or promotion, Play
# programs, and calls to action — in the fields that sit beside the icon.
PROMO = re.compile(
    r"#\s?1\b|\b(?:free|best|top|new|sale|discount|popular|no ads|download now|install now|get it now"
    r"|editor'?s choice|app of the year|million downloads"
    r"|бесплатн\w*|лучш\w*|топ|новинк\w*|скидк\w*|скача\w*"
    r"|gratis|grátis|gratuit\w*|kostenlos|mejor(?:es)?|melhor(?:es)?|meilleur(?:e|s|es)?|miglior[ei]?|beste[nrs]?"
    r"|nuev[oa]s?|nov[oa]s?|neu\w*|nouve(?:au|lle)s?|nuov[oa]|descuento|desconto|rabatt\w*"
    r"|réduction|sconto|oferta|angebot\w*|offerta|promo\w*"
    r"|ad-free|без рекламы|sin anuncios|sem anúncios|werbefrei|ohne werbung|sans pub\w*|senza pubblicità"
    # "descarga" alone is the glossary's es/pt-BR "deload", not a call to action.
    r"|descárga\w+|descarga ya|baixe já|baixe agora|lade\w* jetzt|télécharge\w*|scarica\w*)\b",
    re.I)

# Pictographs, dingbats, arrows, the clocks and watches of Misc Technical,
# ‼ and ⁉, and the emoji presentation selector — written as code points,
# because the characters themselves vanish in review.
EMOJI = re.compile("[%s]" % "".join(
    "%s-%s" % (chr(a), chr(b)) for a, b in ((0x1F000, 0x1FAFF), (0x2600, 0x27BF), (0x2B00, 0x2BFF),
                                            (0x2190, 0x21FF), (0x2300, 0x23FF), (0x203C, 0x203C),
                                            (0x2049, 0x2049), (0xFE0F, 0xFE0F))))

# A word of three letters or more written in capitals — three, because the
# emphasis this listing dropped was "in ONE set" / "en UNA serie". Acronyms
# that are spelled that way in any language are the allowed list.
ACRONYMS = {"JSON"}


def _caps(text):
    return [w for w in re.findall(r"[^\W\d_]{3,}", text) if w.isupper() and w not in ACRONYMS]


def _mixed_apostrophes(text):
    """Both the straight and the typographic apostrophe in one text: fr and it
    have their own rule for the straight one; elsewhere either style is fine,
    two styles side by side are a paste from another source."""
    return ["' and ’"] if "'" in text and "’" in text else []


PLAY_RULES = [
    dict(id="other-platform", locales=ALL, fields=None,
         why="names a platform or a feature the Android app does not have",
         find=lambda t: [m.group(0) for m in OTHER_PLATFORM.finditer(t)],
         bad="A Live Activity counts it down on iPhone", good="A notification counts it down"),
    dict(id="play-promo", locales=ALL, fields={"title", "short_description"},
         why="Play forbids ranking, price, promotion and calls to action beside the icon",
         find=lambda t: [m.group(0) for m in PROMO.finditer(t)],
         bad="Best free workouts — download now", good="Home training that adapts"),
    dict(id="emoji", locales=ALL, fields=None,
         why="Play forbids emoji in the listing's text",
         find=lambda t: EMOJI.findall(t),
         bad="Train at home \U0001F4AA", good="Train at home"),
    dict(id="all-caps", locales=ALL, fields=None,
         why="Play forbids ALL CAPS beyond a brand; a heading in capitals reads as shouting",
         find=_caps,
         bad="+1 rep in ONE set", good="Where it starts, in JSON"),
    dict(id="mixed-apostrophes", locales=ALL, fields=None,
         why="two apostrophe styles in one text",
         find=_mixed_apostrophes,
         bad="That's your phone’s backup", good="That's your phone's backup"),
    dict(id="short-format", locales=ALL, fields={"title", "short_description"},
         why="Play's title and short description: no line breaks, no repeated punctuation",
         find=lambda t: [m.group(0) for m in re.finditer(r"\n|([!?.])\1+", t)],
         bad="Train at home!!", good="Train at home. It adapts."),
]
RULES = SHARED_RULES + PLAY_RULES
RULES_BY_ID = {r["id"]: r for r in RULES}


def over_limit(field, text):
    return play_length(text) > LIMITS[field]


def self_test():
    """None if every rule here and in the two imported scripts can fail, else
    the reason it cannot."""
    if release.self_test() is None:
        return "check_release_texts.py's own self-test failed"
    broken = catalog.self_test()
    if broken:
        return "check_translation_rules.py's own self-test failed: " + "; ".join(broken)
    for rule in PLAY_RULES:
        if not rule["find"](rule["bad"]):
            return "rule %s did not flag its own bad sample %r" % (rule["id"], rule["bad"])
        if rule["find"](rule["good"]):
            return "rule %s flagged its own good sample %r" % (rule["id"], rule["good"])
    if not over_limit("short_description", "x" * 81) or over_limit("short_description", "x" * 80):
        return "the length rule does not stop at exactly 80 characters"
    if not over_limit("short_description", "x" * 79 + "\n") or over_limit("short_description", "x" * 78 + "\n"):
        return "the length rule does not count a line break as two characters"
    # Coverage, the English twin and the allow list are claims about a whole
    # listing, so they are proved on synthetic ones rather than on a string.
    whole = {loc: {f: "%s %s" % (loc, f) for f in LIMITS} for loc in LOCALES}
    if check_listing(whole, {}, []):
        return "a complete, distinct listing was flagged"
    short = {loc: dict(fields) for loc, fields in whole.items()}
    del short["it-IT"]["whats_new"]
    if not any(p[2] == "coverage" for p in check_listing(short, {}, [])):
        return "the coverage rule did not flag a missing field"
    twin = {loc: dict(fields) for loc, fields in whole.items()}
    twin["de-DE"]["title"] = twin["en-US"]["title"]
    if not any(p[2] == "same-as-en" for p in check_listing(twin, {}, [])):
        return "the English-twin rule did not flag a field left in English"
    edge = {loc: dict(fields) for loc, fields in whole.items()}
    edge["es-ES"]["whats_new"] += " "
    if not any(p[2] == "edge-space" for p in check_listing(edge, {}, [])):
        return "the edge-space rule did not flag a trailing space"
    ios = {loc: dict(fields) for loc, fields in whole.items()}
    ios["ru-RU"]["full_description"] = "Импорт с iPhone"
    if not any(p[2] == "other-platform" for p in check_listing(ios, {}, [])):
        return "the other-platform rule did not reach a listing field"
    if check_listing(ios, {"other-platform": {"allow": ["iPhone"]}}, []):
        return "an allowed hit was still flagged"
    return None


def read_listing():
    listing = {}
    for loc in LOCALES:
        listing[loc] = {}
        for field in LIMITS:
            path = LISTING / loc / (field + ".txt")
            if path.exists():
                # One trailing newline is the editor's, not Play's.
                text = path.read_text(encoding="utf-8")
                listing[loc][field] = text[:-1] if text.endswith("\n") else text
    return listing


def apply_rules(text, rule_locale, field, where, config, problems):
    for rule in RULES:
        if rule_locale not in rule["locales"]:
            continue
        if field is not None and rule.get("fields") and field not in rule["fields"]:
            continue
        if field is None and rule.get("fields"):
            continue      # a caption is not a title: field-scoped rules skip it
        allowed = set(config.get(rule["id"], {}).get("allow", []))
        hits = [h for h in rule["find"](text) if h not in allowed]
        if hits:
            problems.append((where, field or "caption", rule["id"],
                             ", ".join(sorted(set(map(repr, hits)))[:6])))


def check_listing(listing, config, captions):
    problems = []
    for loc, rule_locale in LOCALES.items():
        fields = listing.get(loc, {})
        for field, limit in LIMITS.items():
            text = fields.get(field)
            if not text or not text.strip():
                problems.append((loc, field, "coverage", "missing or empty"))
                continue
            if over_limit(field, text):
                problems.append((loc, field, "field-limit", "%d characters with line breaks counted twice, "
                                 "limit %d" % (play_length(text), limit)))
            if text != text.strip():
                problems.append((loc, field, "edge-space", "leading or trailing whitespace"))
            if loc != "en-US" and text == listing.get("en-US", {}).get(field):
                problems.append((loc, field, "same-as-en", "identical to en-US"))
            apply_rules(text, rule_locale, field, loc, config, problems)
    for loc, slot, text in captions:
        apply_rules(text, LOCALES[loc], None, "%s %s" % (loc, slot), config, problems)
    return problems


def load_captions():
    """(locale, slot, text) for every caption line compose_play.py draws."""
    captions = _load("captions", HERE / "captions.py")
    lines = []
    for slot, _screen in captions.SLOTS:
        if slot not in captions.CAPTIONS:
            lines.append((None, slot, "no captions for this slot"))
    for slot, by_locale in captions.CAPTIONS.items():
        missing = [loc for loc in LOCALES if loc not in by_locale]
        if missing:
            lines.append((None, slot, "missing locales: " + ", ".join(missing)))
        for loc, (headline, subtitle) in by_locale.items():
            for text in list(headline) + [subtitle]:
                lines.append((loc, slot, text))
    if set(captions.FEATURE_TAGLINE) != set(LOCALES):
        lines.append((None, "feature-graphic", "the tagline does not cover every locale"))
    for loc, text in captions.FEATURE_TAGLINE.items():
        lines.append((loc, "feature-graphic", text))
    return lines


def load_config():
    if not CONFIG.exists():
        return {}
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def main(argv):
    if "--list" in argv:
        for rule in RULES:
            scope = ",".join(sorted(rule["fields"])) if rule.get("fields") else "all fields"
            print("%-20s %-34s %s" % (rule["id"], scope, rule["why"]))
        print("%-20s %-34s %s" % ("field-limit", "all fields", "Play's limits: "
                                  + ", ".join("%s %d" % kv for kv in LIMITS.items())))
        print("%-20s %-34s %s" % ("coverage", "all fields", "every locale carries every field"))
        print("%-20s %-34s %s" % ("same-as-en", "all fields", "a field identical to en-US ships that locale in English"))
        print("%-20s %-34s %s" % ("edge-space", "all fields", "leading or trailing whitespace Play would keep"))
        return 0

    reason = self_test()
    if reason:
        print("FAIL (self-test): " + reason)
        return 2

    config = load_config()
    captions = load_captions()
    uncovered = [(slot, text) for loc, slot, text in captions if loc is None]
    problems = check_listing(read_listing(), config,
                             [c for c in captions if c[0] is not None])
    problems += [("captions", slot, "coverage", text) for slot, text in uncovered]
    for where, field, rule_id, detail in problems:
        why = RULES_BY_ID.get(rule_id, {}).get("why", "")
        print("%s: %s: [%s] %s%s" % (where, field, rule_id, detail, " — " + why if why else ""))
    n_rules = len(RULES) + 4
    if problems:
        print("\nFAIL: %d problem(s) against %d rules." % (len(problems), n_rules))
        return 1
    print("PASS: %d locales × %d fields and %d caption lines obey all %d rules "
          "(self-tests: both imported rule sets and %d Play rules proved able to fail)."
          % (len(LOCALES), len(LIMITS), len(captions), n_rules, len(PLAY_RULES)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
