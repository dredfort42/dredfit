#!/usr/bin/env python3
"""Fail if any shipping language is missing translations in a String Catalog.

    python3 scripts/check_localization.py                 # checks tracked *.xcstrings
    python3 scripts/check_localization.py path/to/File.xcstrings ...

English is the source language, so its strings live in the keys themselves and
need no localization entry. Every other shipping language (see
localization_config.json -> required_locales) must, for each key, have a
localization whose every unit is in the "translated" state. A key that is
absent for a required language, or present but still "new" / "needs_review" /
"stale", fails the check.

Intentional exceptions — keys identical to the source in all languages (pure
punctuation, the brand name) — are listed under allow_untranslated in the
config, or marked "shouldTranslate": false in Xcode (both are honored here).

Stdlib only (runs on the CI runner's Python 3.9), same rules as sitegen and
appstore/tools.
"""
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
CONFIG = HERE / "localization_config.json"

FINAL_STATES = {"translated"}


def load_config() -> dict:
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def tracked_xcstrings() -> list:
    """All *.xcstrings tracked by git (so .build/ and worktrees are excluded)."""
    out = subprocess.run(
        ["git", "ls-files", "*.xcstrings"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    return [line for line in out.splitlines() if line.strip()]


def iter_states(value: dict):
    """Yield every stringUnit 'state' under a localization value.

    Handles both a flat stringUnit and nested variations (plural/device),
    to whatever depth Xcode nests them.
    """
    if not isinstance(value, dict):
        return
    unit = value.get("stringUnit")
    if isinstance(unit, dict):
        yield unit.get("state")
    variations = value.get("variations")
    if isinstance(variations, dict):
        for by_value in variations.values():
            if isinstance(by_value, dict):
                for sub in by_value.values():
                    yield from iter_states(sub)


def check_file(path: str, required: list, allowed: list) -> list:
    """Return a list of (key, locale, reason) problems for one catalog."""
    data = json.loads((ROOT / path).read_text(encoding="utf-8"))
    strings = data.get("strings", {})
    allowed_set = set(allowed)
    problems = []
    for key, entry in strings.items():
        if not isinstance(entry, dict):
            continue
        if entry.get("shouldTranslate") is False:
            continue
        if key in allowed_set:
            continue
        localizations = entry.get("localizations", {}) or {}
        for locale in required:
            if locale not in localizations:
                problems.append((key, locale, "missing"))
                continue
            states = [s for s in iter_states(localizations[locale]) if s is not None]
            bad = sorted({s for s in states if s not in FINAL_STATES})
            if not states:
                problems.append((key, locale, "empty"))
            elif bad:
                problems.append((key, locale, ", ".join(bad)))
    return problems


def main(argv: list) -> int:
    config = load_config()
    required = config["required_locales"]
    allow_map = config.get("allow_untranslated", {})

    files = argv[1:] or tracked_xcstrings()
    if not files:
        print("No .xcstrings files to check.")
        return 0

    total = 0
    for path in files:
        allowed = allow_map.get(path, [])
        problems = check_file(path, required, allowed)
        status = "OK" if not problems else f"{len(problems)} problem(s)"
        print(f"{path}: {status}")
        for key, locale, reason in problems:
            print(f"    [{locale}] {reason}: {key!r}")
        total += len(problems)

    print()
    if total:
        print(f"FAIL: {total} untranslated/incomplete string(s) across "
              f"{', '.join(required)}.")
        print("Translate them in Xcode, or (if identical to the source in "
              "every language) add the key to allow_untranslated in "
              "scripts/localization_config.json or set shouldTranslate:false.")
        return 1
    print(f"PASS: every key is translated for {', '.join(required)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
