#!/usr/bin/env python3
"""Fail if the App Store / TestFlight package breaks a rule a script can decide.

    python3 scripts/check_release_texts.py                     # newest appstore/release_texts_*.md
    python3 scripts/check_release_texts.py path/to/file.md ...
    python3 scripts/check_release_texts.py --list              # the rules and their reasons

`check_translation_rules.py` gates the String Catalogs and says in its own
docstring that the App Store package cannot be gated, because
`appstore/release_texts_*.md` is gitignored and never reaches a runner. That is
true of CI and was read as "nothing checks it at all" — so the package shipped
with defects the catalogs could not have: on 2026-09-06 the 2.3.0 file carried
**eleven Russian words written with a LATIN `e` inside Cyrillic** (лeгкой, трeх,
остаeтся …), because the "ё → е" rule had been applied with the wrong keyboard.
The check that was supposed to catch it counted «ё», found none, and reported
success: a predicate proves only the absence of the character written into it.

So this runs locally, by hand, before the package is copied into App Store
Connect. It carries only what a script can decide without judgement —
characters, scripts, typography, lengths, coverage — and deliberately not
terminology, tone or naturalness, for the same reason its sibling refuses them.

**Every rule is proved to be able to fail.** Before checking anything it runs
each rule against a string that must trip it and one that must not, and refuses
to report success if a predicate has gone inert. Three of six engine gates once
died before their first check and read exactly like passing.

Intentional exceptions go in `scripts/release_texts_config.json`, keyed by rule
id, each with the reason it is allowed.

Stdlib only, Python 3.9 (same floor as the other two checks).
"""
import json
import pathlib
import re
import sys

NBSP = " "      # French: before ':'
NNBSP = " "     # French: before ';!?' and inside guillemets
ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "scripts" / "release_texts_config.json"

# The seven shipping locales, in the order the package lists them.
LOCALES = ["en", "ru", "es", "pt-BR", "de", "fr", "it"]

# What App Store Connect accepts, per field. A field absent from this table is
# read but not length-checked.
LIMITS = {
    "Name": 30,
    "Subtitle": 30,
    "Promotional Text": 170,
    "Keywords": 100,
    "Description": 4000,
    "What's New": 4000,
    "Beta App Description": 4000,
    "What to Test": 4000,
}

# Fields that must exist in every locale when they exist in any. A TestFlight-only
# package legitimately carries no Description; a showcase legitimately carries no
# What to Test. What is not allowed is a field present in six locales and missing
# in the seventh — that is how a locale ships in English.
COVERAGE_FIELDS = sorted(LIMITS)

SECTION = re.compile(
    r"^#{2,4}\s*(?P<field>.+?)\s*\((?P<loc>[A-Za-z]{2}(?:-[A-Za-z]{2,4})?)\)\s*$\n+"
    r"(?P<body>(?:(?!^#).*\n)*)",
    re.M,
)


def body_of(match):
    """The field's text. A trailing '---' belongs to the MARKDOWN, not the field:
    counted, it added five characters to the last locale of every section and
    once reported an Italian Description as exactly 4000 when it was 3995."""
    return re.sub(r"\n*-{3,}\s*$", "", match.group("body")).strip()


def _find_all(pattern, text, flags=0):
    return [m.group(0) for m in re.finditer(pattern, text, flags)]


def mixed_script(text):
    """A word that mixes Cyrillic and Latin. Homoglyphs (а с е о р х у) look
    identical and survive every eyeball pass; App Store Connect ships them."""
    return _find_all(r"[А-Яа-яЁё]+[A-Za-z][А-Яа-яЁё]*|[A-Za-z]+[А-Яа-яЁё][A-Za-z]*", text)


def _fr_spacing(text):
    """French wants U+00A0 before ':' and U+202F before ';!?' and inside the
    guillemets. Only a PLAIN space is a violation — no space at all is a
    different (and rarer) defect, and flagging it here would bury this one."""
    bad = []
    for m in re.finditer(r" (?=[:])", text):
        bad.append("plain space before ':'")
    for m in re.finditer(r" (?=[;!?])", text):
        bad.append("plain space before '%s'" % text[m.end():m.end() + 1])
    for m in re.finditer(r"« (?! )| »", text):
        bad.append("plain space inside guillemets")
    return bad


RULES = [
    dict(id="mixed-script", locales=LOCALES,
         why="a word mixing Cyrillic and Latin — a homoglyph typed for the letter it looks like",
         find=mixed_script,
         bad="лeгкой", good="лёгкой"),
    dict(id="ru-yo", locales=["ru"],
         why="Russian product text uses е, never ё",
         find=lambda t: _find_all(r"[ёЁ]", t),
         bad="лёгкой", good="легкой"),
    dict(id="fr-apostrophe", locales=["fr"],
         why="French uses the typographic apostrophe ’, never '",
         find=lambda t: _find_all(r"'", t),
         bad="l'app", good="l’app"),
    dict(id="fr-spacing", locales=["fr"],
         why="U+00A0 before ':' and U+202F before ';!?' and inside guillemets",
         find=_fr_spacing,
         bad="la séance est prête : oui", good="la séance est prête" + NBSP + ": oui"),
    dict(id="it-apostrophe", locales=["it"],
         why="Italian uses the typographic apostrophe ’, never '",
         find=lambda t: _find_all(r"'", t),
         bad="l'app", good="l’app"),
    dict(id="de-em-dash", locales=["de"],
         why="German uses the short dash –, never the long —",
         find=lambda t: _find_all(r"—", t),
         bad="Training — bereit", good="Training – bereit"),
]
RULES_BY_ID = {r["id"]: r for r in RULES}


def self_test():
    """A rule that cannot fail is not a rule, it is a decoration."""
    proved = 0
    for rule in RULES:
        if not rule["find"](rule["bad"]):
            print("FAIL: rule %s did not flag its own bad sample %r"
                  % (rule["id"], rule["bad"]))
            return None
        if rule["find"](rule["good"]):
            print("FAIL: rule %s flagged its own good sample %r"
                  % (rule["id"], rule["good"]))
            return None
        proved += 1
    # The length rule has no sample: prove it on a string built to exceed.
    if not over_limit("Keywords", "x" * (LIMITS["Keywords"] + 1)):
        print("FAIL: the length rule did not flag a field over its limit")
        return None
    if over_limit("Keywords", "x" * LIMITS["Keywords"]):
        print("FAIL: the length rule flagged a field exactly at its limit")
        return None
    proved += 1

    # …and so does coverage, which is the one rule with no text to look at: it
    # is a claim about the SET of sections, so it is proved on a synthetic file
    # rather than on a string.
    complete = "".join("#### Keywords (%s)\n\nx\n\n" % loc for loc in LOCALES)
    short = complete.replace("#### Keywords (it)\n\nx\n\n", "")
    found = []
    check_text(complete, "self-test", {}, found)
    if found:
        print("FAIL: the coverage rule flagged a file that has all seven locales")
        return None
    check_text(short, "self-test", {}, found)
    if not any(p[3] == "locale-coverage" for p in found):
        print("FAIL: the coverage rule did not flag a locale that is missing")
        return None
    return proved + 1


def over_limit(field, text):
    limit = LIMITS.get(field)
    return limit is not None and len(text) > limit


def load_config():
    if CONFIG.exists():
        return json.loads(CONFIG.read_text(encoding="utf-8"))
    return {}


def newest_package():
    files = sorted((ROOT / "appstore").glob("release_texts_*.md"))
    return [files[-1]] if files else []


def check_file(path, config, problems):
    return check_text(pathlib.Path(path).read_text(encoding="utf-8"), path, config, problems)


def check_text(text, path, config, problems):
    """Split from `check_file` so the self-test can prove the coverage rule on a
    synthetic package rather than on a real one."""
    seen = {}
    fields_checked = 0

    for m in SECTION.finditer(text):
        field, loc = m.group("field"), m.group("loc")
        body = body_of(m)
        if loc not in LOCALES:
            continue
        seen.setdefault(field, set()).add(loc)
        fields_checked += 1

        if over_limit(field, body):
            problems.append((path, field, loc, "field-limit",
                             "%d characters, limit %d" % (len(body), LIMITS[field])))

        for rule in RULES:
            if loc not in rule["locales"]:
                continue
            allowed = set(config.get(rule["id"], {}).get("allow", []))
            hits = [h for h in rule["find"](body) if h not in allowed]
            if hits:
                sample = ", ".join(sorted(set(hits))[:6])
                problems.append((path, field, loc, rule["id"], sample))

    # A field present in some locales and missing in others is how one storefront
    # quietly ships in English.
    for field, locales in sorted(seen.items()):
        if field not in COVERAGE_FIELDS:
            continue
        missing = [l for l in LOCALES if l not in locales]
        if missing:
            problems.append((path, field, "-", "locale-coverage",
                             "missing: " + ", ".join(missing)))
    return fields_checked


def main(argv):
    if "--list" in argv:
        for rule in RULES:
            print("%-16s %-28s %s" % (rule["id"], ",".join(rule["locales"]), rule["why"]))
        print("%-16s %-28s %s" % ("field-limit", "all",
                                  "App Store Connect limits: "
                                  + ", ".join("%s %d" % (k, v) for k, v in sorted(LIMITS.items()))))
        print("%-16s %-28s %s" % ("locale-coverage", "all",
                                  "a field present in one locale must be present in all seven"))
        return 0

    proved = self_test()
    if proved is None:
        return 2

    paths = [a for a in argv if not a.startswith("-")] or newest_package()
    if not paths:
        print("FAIL: no release texts file to check "
              "(appstore/release_texts_*.md is gitignored — it exists only locally)")
        return 2

    config = load_config()
    problems = []
    checked = 0
    for path in paths:
        checked += check_file(path, config, problems)

    for path, field, loc, rule_id, detail in problems:
        why = RULES_BY_ID.get(rule_id, {}).get("why", {
            "field-limit": "App Store Connect rejects the field",
            "locale-coverage": "a missing field ships that storefront in English",
        }.get(rule_id, ""))
        print("%s: error: [%s] %s — %s" % (path, loc, rule_id, why))
        print("    field: %s" % field)
        print("    found: %s" % detail)

    n_rules = len(RULES) + 2
    if problems:
        print("\nFAIL: %d problem(s) against %d rules over %d fields in %d file(s)."
              % (len(problems), n_rules, checked, len(paths)))
        print("A rule that is wrong about this package is answered in "
              "scripts/release_texts_config.json, with the reason.")
        return 1
    print("PASS: %d fields in %d file(s) obey all %d rules "
          "(self-test: %d/%d rules proved able to fail)."
          % (checked, len(paths), n_rules, proved, n_rules))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
