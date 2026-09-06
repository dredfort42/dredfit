#!/usr/bin/env python3
"""Fail if a shipped translation breaks a rule the localization gate cannot see.

    python3 scripts/check_translation_rules.py                  # tracked *.xcstrings
    python3 scripts/check_translation_rules.py path/to/File.xcstrings ...
    python3 scripts/check_translation_rules.py --list           # the rules and their reasons

`check_localization.py` answers "is every key translated into every shipping
language". It cannot answer "is the translation still the one the canon asked
for", and the seven-language review of 2026-09 measured what that costs: 41
Russian strings had drifted back to "ё", 36 German strings to the long dash, 22
Italian technique steps to the straight apostrophe, and every one of them passed
a green Localization check. A gate of completeness is not a gate of truthfulness
(the same lesson the v3.0 wave wrote down after five English strings shipped as
their own keys), so this is the second gate, and it only carries rules a script
can decide without judgement: characters, units, forms of address, placeholders.

What it deliberately does NOT carry: terminology, naturalness, tone, length.
Those are the translator's judgement (`instructions/TRANSLATOR_PROMPT.md`) and a
reviewer's, and a script that guessed at them would cry wolf until someone
turned it off. The website (`sitegen/content`) and the App Store package
(`appstore/release_texts_*.md`) are gitignored and never reach a runner, so they
cannot be gated here at all — they stay the translator's pass, by hand.

**Every rule is proved to be able to fail.** Before checking anything, the
script runs each rule against a string that must trip it and one that must not,
and refuses to report success if a predicate has gone inert. Three of six engine
gates once died before their first check and read exactly like passing; a rule
that cannot fail is not a rule, it is a decoration.

Intentional exceptions go in `translation_rules_config.json`, keyed by rule and
by "<catalog path>::<key>", each with the reason it is allowed. There are none
today: the catalogs are clean on all of these as of the 2026-09 wave.

Stdlib only, Python 3.9 (the CI runner), same as check_localization.py.
"""
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
CONFIG = HERE / "translation_rules_config.json"

NBSP = "\u00a0"       # espace insécable — French, before ":"
NNBSP = "\u202f"      # espace fine insécable — French, before ";!?" and inside guillemets
APOSTROPHE = "\u2019"  # the curly apostrophe

LOCALES = ["ru", "es", "pt-BR", "de", "fr", "it"]

# A capital "Sie"/"Lei" at the start of a sentence is "she/it", not the formal
# address: German "Eine übersprungene Übung … Sie bleibt genau dort" is correct
# du-German and was a false positive of the review's first sweep. Only a
# mid-sentence one is the formal pronoun.
SENTENCE_START = re.compile(r'(?:^|[.!?:;–—\n]\s*|[«"„]\s*)$')

PLACEHOLDER = re.compile(r'%(?:\d+\$)?(?:lld|ld|d|@|s|f|\.\d+f|lu|u)|%#@\w+@')


def _positional(spec: str) -> str:
    """'%2$lld' and '%lld' consume the same kind of argument."""
    return re.sub(r'%\d+\$', '%', spec)


def specifiers(text, substitutions=None):
    """Multiset of format specifiers, with %#@name@ expanded to what it prints.

    A locale may wrap a number in a plural substitution where English prints it
    bare (ru "%#@exercises@" against en "%lld exercises"), and that is correct,
    not a defect — so the comparison is over the arguments consumed, not over
    the literal specifiers.
    """
    subs = substitutions or {}
    counts = {}
    for match in PLACEHOLDER.finditer(text or ""):
        spec = match.group(0)
        if spec.startswith("%#@"):
            name = spec[3:-1]
            entry = subs.get(name) or {}
            fmt = entry.get("formatSpecifier")
            spec = "%" + fmt if fmt else spec
        spec = _positional(spec)
        counts[spec] = counts.get(spec, 0) + 1
    return counts


# --------------------------------------------------------------------------
# The rules. Each one: which locales it applies to, why it exists, a finder that
# returns the offending excerpts, and the pair that proves it can fail.
# --------------------------------------------------------------------------

def _find_all(pattern, text, flags=0):
    return [m.group(0) for m in re.finditer(pattern, text, flags)]


def _fr_spacing(text):
    hits = []
    for match in re.finditer(r'[:;!?»]', text):
        i = match.start()
        char = match.group(0)
        prev = text[i - 1] if i else ""
        if char == ":":
            # 12:30 is a time, not a colon needing the space
            if prev.isdigit() and i + 1 < len(text) and text[i + 1].isdigit():
                continue
            if prev not in (NBSP, ""):
                hits.append("%r before ':' (want U+00A0)" % prev)
        elif char == "»":
            if prev not in (NNBSP, ""):
                hits.append("%r before '»' (want U+202F)" % prev)
        else:
            if re.match(r'[?!;]', prev):   # "!!" and "?!" are one mark
                continue
            if prev not in (NNBSP, ""):
                hits.append("%r before %r (want U+202F)" % (prev, char))
    for match in re.finditer(r'«(.)', text):
        if match.group(1) != NNBSP:
            hits.append("%r after '«' (want U+202F)" % match.group(1))
    return hits


def _formal_de(text):
    hits = []
    for match in re.finditer(r'\bSie\b|\bIhnen\b|\bIhr(?:e|em|en|er|es)?\b', text):
        if match.group(0) == "Sie" and SENTENCE_START.search(text[:match.start()]):
            continue
        hits.append(match.group(0))
    return hits


def _formal_it(text):
    return [m.group(0) for m in re.finditer(r'\bLei\b', text)
            if not SENTENCE_START.search(text[:m.start()])]


RULES = [
    dict(id="ru-yo", locales=["ru"],
         why="the canon spells shipped strings with е, never ё",
         find=lambda t: _find_all(r'[ёЁ]', t),
         bad="Всё лёгкое", good="Все легкое"),
    dict(id="ru-formal-address", locales=["ru"],
         why="athlete-facing strings are on ты, never вы",
         find=lambda t: _find_all(r'\b[Вв]ы\b|\b[Вв]ас\b|\b[Вв]ам\b|\b[Вв]аш\w*', t),
         bad="Введите ваши числа", good="Введи свои числа"),
    dict(id="fr-spacing", locales=["fr"],
         why="U+00A0 before ':', U+202F before ';!?' and inside guillemets",
         find=_fr_spacing,
         bad="Essai : fait", good="Essai" + NBSP + ": fait"),
    dict(id="fr-apostrophe", locales=["fr"],
         why="the typographic apostrophe ’, never '",
         find=lambda t: _find_all(r"'", t),
         bad="l'app", good="l" + APOSTROPHE + "app"),
    dict(id="fr-formal-address", locales=["fr"],
         why="athlete-facing strings are on tu, never vous",
         find=lambda t: _find_all(r'\bvous\b|\bvotre\b|\bvos\b', t, re.I),
         bad="Passez si vous êtes prêt", good="Passe si tu es prêt"),
    dict(id="it-apostrophe", locales=["it"],
         why="the typographic apostrophe ’, never '",
         find=lambda t: _find_all(r"'", t),
         bad="dov'era", good="dov" + APOSTROPHE + "era"),
    dict(id="it-formal-address", locales=["it"],
         why="athlete-facing strings are on tu, never Lei",
         find=_formal_it,
         bad="Se Lei preferisce", good="Lei resta dov" + APOSTROPHE + "era"),
    dict(id="de-em-dash", locales=["de"],
         why="the canon dash is the short – with spaces, not —",
         find=lambda t: _find_all(r'—', t),
         bad="Ein Satz — zurück", good="Ein Satz – zurück"),
    dict(id="de-minute-abbrev", locales=["de"],
         why="the unit is min, not Min.",
         find=lambda t: _find_all(r'\bMin\.', t),
         bad="etwa 23 Min.", good="etwa 23 min"),
    dict(id="de-workout", locales=["de"],
         why="the canon word for тренировка is Training, not Workout",
         find=lambda t: _find_all(r'\bWorkout\w*', t),
         bad="Ein Workout heute", good="Ein Training heute"),
    dict(id="de-formal-address", locales=["de"],
         why="athlete-facing strings are on du (lowercase), never Sie/Ihnen/Ihr",
         find=_formal_de,
         bad="Bitte legen Sie das Telefon weg", good="Leg das Telefon weg"),
    dict(id="es-formal-address", locales=["es"],
         why="athlete-facing strings are on tú, never usted",
         find=lambda t: _find_all(r'\busted(?:es)?\b', t, re.I),
         bad="Si usted quiere", good="Si quieres"),
    dict(id="weight-units", locales=LOCALES,
         why="the app never weighs anything in text; seconds and minutes only, "
             "and the body-weight row formats its unit in code",
         find=lambda t: _find_all(r'\b(?:kg|lbs?)\b', t, re.I),
         bad="80 kg", good="80 s"),
    dict(id="double-space", locales=LOCALES,
         why="two spaces in a row are a typo the editor hides",
         find=lambda t: ["%d spaces in a row" % len(m.group(0))
                         for m in re.finditer(r'  +', t)],
         bad="one  two", good="one two"),
]

RULES_BY_ID = {rule["id"]: rule for rule in RULES}


def load_config():
    if not CONFIG.exists():
        return {}
    data = json.loads(CONFIG.read_text(encoding="utf-8"))
    return {rule: dict(entries) for rule, entries in data.items()
            if not rule.startswith("_")}


def tracked_xcstrings():
    out = subprocess.run(["git", "ls-files", "*.xcstrings"],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [line for line in out.splitlines() if line.strip()]


def iter_units(value, fragment=False):
    """Every (text, substitutions, is_fragment) a localization value can print.

    A whole VALUE is what the screen shows: "≈ %lld min · %#@exercises@", and a
    plural variation of it is still a whole value. A FRAGMENT is what lives
    inside a substitution — "%arg упражнения" — and it is shipped text like any
    other, so the character rules must read it, but it consumes one argument of
    its own and must never be weighed against the whole source string. Mixing
    the two made this check's first run report 56 violations that were all its
    own misreading.
    """
    if not isinstance(value, dict):
        return
    subs = value.get("substitutions") if isinstance(value.get("substitutions"), dict) else None
    unit = value.get("stringUnit")
    if isinstance(unit, dict) and isinstance(unit.get("value"), str):
        yield unit["value"], subs, fragment
    variations = value.get("variations")
    if isinstance(variations, dict):
        for by_value in variations.values():
            if isinstance(by_value, dict):
                for nested in by_value.values():
                    for text, inner, is_fragment in iter_units(nested, fragment):
                        yield text, inner or subs, is_fragment
    if subs:
        for sub in subs.values():
            if isinstance(sub, dict):
                for text, _, _ in iter_units(sub, fragment=True):
                    yield text, None, True


def self_test():
    """A rule that cannot fail is not a rule. Prove each one both ways."""
    broken = []
    for rule in RULES:
        if not rule["find"](rule["bad"]):
            broken.append("%s: stayed silent on %r" % (rule["id"], rule["bad"]))
        if rule["find"](rule["good"]):
            broken.append("%s: fired on %r, which is correct text"
                          % (rule["id"], rule["good"]))
    # the placeholder rule is not in RULES (it needs the source); prove it here
    if specifiers("%lld of %lld") == specifiers("%lld"):
        broken.append("placeholder-parity: cannot tell two arguments from one")
    if specifiers("%lld exercises") != specifiers(
            "%#@n@", {"n": {"formatSpecifier": "lld"}}):
        broken.append("placeholder-parity: does not expand a substitution")
    sample = {"stringUnit": {"value": "%#@n@"},
              "substitutions": {"n": {"formatSpecifier": "lld", "variations": {"plural": {
                  "other": {"stringUnit": {"value": "%arg exercises"}}}}}}}
    kinds = {is_fragment for _, _, is_fragment in iter_units(sample)}
    if kinds != {False, True}:
        broken.append("fragment split: a substitution's inner text is no longer "
                      "told apart from the whole value (got %s)" % sorted(kinds))
    return broken


def check_file(path, config, violations):
    data = json.loads((ROOT / path).read_text(encoding="utf-8"))
    checked = 0
    for key, entry in sorted(data.get("strings", {}).items()):
        localizations = entry.get("localizations") or {}
        english = localizations.get("en")
        if english:
            whole = [(t, s) for t, s, is_fragment in iter_units(english) if not is_fragment]
            source, source_subs = whole[0] if whole else (key, None)
        else:
            source, source_subs = key, None
        want = specifiers(source, source_subs)
        for locale in LOCALES:
            value = localizations.get(locale)
            if not value:
                continue
            for text, subs, is_fragment in iter_units(value):
                checked += 1
                for rule in RULES:
                    if locale not in rule["locales"]:
                        continue
                    if "%s::%s" % (path, key) in config.get(rule["id"], {}):
                        continue
                    for excerpt in rule["find"](text):
                        violations.append((path, key, locale, rule["id"], excerpt, text))
                if is_fragment:
                    continue      # one argument of its own, not the whole string
                got = specifiers(text, subs)
                if got != want and "%s::%s" % (path, key) not in config.get("placeholder-parity", {}):
                    violations.append((path, key, locale, "placeholder-parity",
                                       "source %s, translation %s" % (want or "{}", got or "{}"),
                                       text))
    return checked


def main(argv):
    if "--list" in argv:
        for rule in RULES:
            print("%-22s %-28s %s" % (rule["id"], ",".join(rule["locales"]), rule["why"]))
        print("%-22s %-28s %s" % ("placeholder-parity", ",".join(LOCALES),
                                  "a translation consumes the same arguments as its source"))
        return 0

    broken = self_test()
    if broken:
        print("FAIL: the check itself is broken, so its silence would mean nothing:")
        for line in broken:
            print("  " + line)
        return 2

    paths = [a for a in argv if not a.startswith("-")] or tracked_xcstrings()
    if not paths:
        print("FAIL: no String Catalogs to check (git ls-files '*.xcstrings' came back empty)")
        return 2

    config = load_config()
    violations = []
    checked = 0
    for path in paths:
        checked += check_file(path, config, violations)

    for path, key, locale, rule_id, excerpt, text in violations:
        print("%s: error: [%s] %s (%s) — %s" % (path, locale, rule_id,
                                                RULES_BY_ID.get(rule_id, {}).get(
                                                    "why", "arguments must match"),
                                                excerpt))
        print("    key:   %s" % (key if len(key) <= 90 else key[:87] + "..."))
        print("    value: %s" % (text if len(text) <= 90 else text[:87] + "..."))

    n_rules = len(RULES) + 1
    if violations:
        print("\nFAIL: %d violation(s) of %d rules over %d translated units in %d catalogs."
              % (len(violations), n_rules, checked, len(paths)))
        print("A rule that is wrong about a string is fixed in "
              "scripts/translation_rules_config.json, with the reason.")
        return 1
    print("PASS: %d translated units in %d catalogs obey all %d rules "
          "(self-test: %d/%d rules proved able to fail)."
          % (checked, len(paths), n_rules, n_rules, n_rules))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
