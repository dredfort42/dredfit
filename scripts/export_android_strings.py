#!/usr/bin/env python3
"""Generate the Android string resources from the iOS String Catalogs.

    python3 scripts/export_android_strings.py              # write
    python3 scripts/export_android_strings.py --check      # exit 1 if anything on disk is stale
    python3 scripts/export_android_strings.py --self-test  # the conversion rules on fixed inputs

The String Catalogs stay the one source of every user-facing string: a
translator edits them in Xcode, and Android gets a regenerated copy, never a
hand-edited one. Three catalogs, one file each, so a key's provenance is
visible from the file name:

    ios/DredfitCore/Sources/DredfitCore/Resources/Localizable.xcstrings -> strings_core.xml
    ios/Dredfit/Localizable.xcstrings                                    -> strings_app.xml
    ios/DredfitWidgets/Localizable.xcstrings                             -> strings_widgets.xml

into android/app/src/main/res/values{,-de,-es,-fr,-it,-b+pt+BR,-ru}/, plus one
Kotlin lookup per catalog in android/app/src/main/kotlin/com/dredfit/l10n/
(CoreStrings, AppStrings, WidgetStrings) so app code keeps calling by the
English key, as `String(localized:)` does on iOS.

`ios/Dredfit/InfoPlist.xcstrings` is skipped on purpose: it holds Info.plist
keys (CFBundleName, the HealthKit usage descriptions) that have no Android
string counterpart — the app label and the Health Connect rationale are
written for Android in the app module, not translated from iOS permission
prose.

Resource name rule (stable when other keys come and go, readable in a diff):

    <catalog>_<slug>_<hash8>
    catalog = core | app | widgets
    slug    = the key lowercased; ASCII letters and digits kept, every other run
              of characters replaced by `_`; trimmed of `_`; truncated to 40
              characters; `x` if empty
    hash8   = the first 8 hex characters of sha1(key as UTF-8)

Which keys: every entry of the catalog, exactly as check_localization.py walks
them (the catalogs hold no stale or empty entries as of 09.10.2026). Every unit
that carries a value is used whatever its state — the Localization gate already
refuses anything but "translated". A locale without a value is omitted and
Android falls back to the base. `shouldTranslate: false` keys go to the base
only, `translatable="false"`; the keys localization_config.json exempts from
translation get `tools:ignore="MissingTranslation"` so lint agrees with the gate.

The base (`values/`) is the catalog's "en" localization, or the key itself when
there is none — some app keys are identifiers ("cooldown.calfWall"), so the key
is not always the English text.

Format specifiers: `%@` -> `%s`, any integer length (`%lld`, `%ld`, `%u` ...)
-> `%d`, floats keep their precision. A string with two or more arguments is
always positional (aapt2 refuses several unnumbered ones). A string with no
argument is copied verbatim with `formatted="false"` if it holds a `%`.

Plurals: if ANY localization of a key varies by plural (or uses a
substitution), the key is a <plurals> in every locale, because Android resolves
by resource type and a <string> in one locale would not be found from
getQuantityString. A plain localization repeats its text for every category its
language's CLDR rules use; a plural localization that lacks one of them gets
the `other` text there — what both iOS and Android fall back to anyway, said
explicitly so lint's MissingQuantity stays quiet.

Substitutions (`%#@name@`) have no Android counterpart. A string with exactly
one is flattened into <plurals>: each category is the outer template with the
substitution's text for that category spliced in (`%arg` becomes the argument
named by argNum). More than one substitution in a string fails the run.

Stdlib only, Python 3.9 (the CI runner), like check_localization.py.
"""
import hashlib
import json
import re
import sys
import unicodedata

from check_localization import ROOT, load_config

CATALOGS = [  # (resource prefix, catalog, xml file, Kotlin object)
    ("core", "ios/DredfitCore/Sources/DredfitCore/Resources/Localizable.xcstrings",
     "strings_core.xml", "CoreStrings"),
    ("app", "ios/Dredfit/Localizable.xcstrings", "strings_app.xml", "AppStrings"),
    ("widgets", "ios/DredfitWidgets/Localizable.xcstrings", "strings_widgets.xml",
     "WidgetStrings"),
]
RES = "android/app/src/main/res"
KOTLIN = "android/app/src/main/kotlin/com/dredfit/l10n"
SCRIPT = "scripts/export_android_strings.py"

# CLDR plural categories (v44, what ICU on Android 14+ and lint use). es, fr,
# it and pt gained `many` (1 000 000 and up); an extra item is harmless on an
# older device, a missing one is a lint warning.
CATEGORIES = {
    "en": ["one", "other"], "de": ["one", "other"],
    "es": ["one", "many", "other"], "fr": ["one", "many", "other"],
    "it": ["one", "many", "other"], "pt-BR": ["one", "many", "other"],
    "ru": ["one", "few", "many", "other"],
}
QUANTITY_ORDER = ["zero", "one", "two", "few", "many", "other"]

# `%arg` and `%#@name@` first: both start like a C conversion (`%a`, `%#`).
# No space flag: "100% sure" is prose, not `% s`, and Swift interpolation
# never writes one.
SPEC = re.compile(
    r"%arg|%#@(?P<sub>\w+)@"
    r"|%(?:(?P<pos>[1-9]\d*)\$)?(?P<flags>[-+0#]*\d*(?:\.\d+)?)"
    r"(?:hh|h|ll|l|q|z|t|j|L)?(?P<conv>[@dDiuUxXoOfFeEgGcsS%])")


class ExportError(Exception):
    """A catalog shape this exporter cannot represent faithfully."""


def resource_name(prefix, key):
    slug = re.sub(r"[^a-z0-9]+", "_", key.lower()).strip("_")[:40] or "x"
    return "%s_%s_%s" % (prefix, slug, hashlib.sha1(key.encode("utf-8")).hexdigest()[:8])


def android_conversion(flags, conv):
    """(Android conversion text, type for the agreement check)."""
    if conv == "@" or conv in "sS":
        return flags + "s", "s"
    if conv in "dDiuU":
        return flags + "d", "d"
    if conv in "fFeEgG":
        # java.util.Formatter has no %F; the rest keep case and precision.
        return flags + ("f" if conv == "F" else conv), "f"
    return flags + conv, conv.lower()  # Formatter knows %x %X %o %c as C does


def convert(template, sub=None):
    """iOS text -> (Android text, {argument index: type}, formatted).

    `sub` is (name, argNum, formatSpecifier, text) for the one substitution the
    template may hold. Arguments are numbered as Foundation consumes them:
    unnumbered ones (and `%#@name@`) in order of appearance.
    """
    parts, args, counter, numbered, unnumbered = [], {}, 0, False, False

    def add_arg(index, text, kind):
        if args.get(index, kind) != kind:
            raise ExportError("argument %d used as %s and %s in %r"
                              % (index, args[index], kind, template))
        args[index] = kind
        parts.append((index, text))

    pos = 0
    for m in SPEC.finditer(template):
        parts.append(template[pos:m.start()])
        pos = m.end()
        if m.group(0) == "%arg":
            raise ExportError("%%arg outside a substitution in %r" % template)
        if m.group("sub"):
            counter += 1
            if sub is None or sub[0] != m.group("sub"):
                raise ExportError("unknown substitution %r in %r" % (m.group(0), template))
            name, arg_num, spec, text = sub
            if arg_num != counter:
                # Foundation honours argNum; say so rather than guess which one is meant.
                raise ExportError("substitution %s has argNum %d at argument %d in %r"
                                  % (name, arg_num, counter, template))
            spec_match = SPEC.fullmatch("%" + spec)
            if not spec_match or not spec_match.group("conv"):
                raise ExportError("substitution %s has formatSpecifier %r" % (name, spec))
            text_conv, kind = android_conversion(spec_match.group("flags"), spec_match.group("conv"))
            inner = text.split("%arg")
            for i, piece in enumerate(inner):
                if SPEC.search(piece):
                    raise ExportError("a specifier other than %%arg in substitution %r" % text)
                parts.append(piece)
                if i < len(inner) - 1:
                    add_arg(arg_num, text_conv, kind)
            continue
        if m.group("conv") == "%":
            parts.append(None)  # `%%`: stays `%%` whether the string is formatted or not
            continue
        text, kind = android_conversion(m.group("flags"), m.group("conv"))
        if m.group("pos"):
            numbered = True
            add_arg(int(m.group("pos")), text, kind)
        else:
            unnumbered = True
            counter += 1
            add_arg(counter, text, kind)
    parts.append(template[pos:])
    if numbered and unnumbered:
        raise ExportError("numbered and unnumbered arguments mixed in %r" % template)

    if not args:
        # Nothing is formatted, so nothing is escaped: `formatted="false"` keeps a `%` as typed.
        text = "".join("%%" if p is None else p for p in parts)
        return text, {}, "%" not in text
    uses = [p for p in parts if isinstance(p, tuple)]
    # One argument stays unnumbered only if it is argument 1, used once: a
    # translation that prints just `%2$@`, or `%1$@` twice, must keep its numbers.
    positional = len(uses) > 1 or uses[0][0] != 1
    out = []
    for p in parts:
        if p is None:
            out.append("%%")
        elif isinstance(p, tuple):
            out.append("%%%d$%s" % p if positional else "%" + p[1])
        else:
            out.append(p.replace("%", "%%"))  # a lone `%` no specifier took is literal text
    return "".join(out), args, True


def escape_xml(text):
    """aapt2 string syntax: XML escapes, then the backslash escapes aapt2 reads.

    aapt2 collapses runs of ASCII whitespace and trims the ends; a `\\u0020`
    survives both, so leading, trailing and doubled spaces are written that way.
    NBSP, U+202F and ’ pass through untouched (probed with `aapt2 dump`).
    """
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = (text.replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"')
            .replace("\n", "\\n").replace("\t", "\\t"))
    text = re.sub(r"(?<= ) | $|^ ", r"\\u0020", text)
    if text[:1] in ("@", "?"):
        text = "\\" + text
    return text


def kotlin_literal(text):
    out = []
    for ch in text:
        if ch in '\\"$':
            out.append("\\" + ch)
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif unicodedata.category(ch)[0] == "C" or (unicodedata.category(ch)[0] == "Z" and ch != " "):
            # Invisible in a source file: spelled out so a reviewer sees an NBSP.
            utf16 = ch.encode("utf-16-be")
            out.extend("\\u%02X%02X" % (utf16[i], utf16[i + 1]) for i in range(0, len(utf16), 2))
        else:
            out.append(ch)
    return '"%s"' % "".join(out)


def read_localization(loc):
    """A catalog localization -> ("plain", text) or ("plural", {category: text})."""
    unexpected = set(loc) - {"stringUnit", "variations", "substitutions"}
    variations = loc.get("variations", {})
    if unexpected or set(variations) - {"plural"}:
        raise ExportError("unsupported localization shape %s" % sorted(set(loc) | set(variations)))
    if "plural" in variations:
        if "substitutions" in loc:
            raise ExportError("plural variation with substitutions")
        return "plural", {q: v["stringUnit"]["value"] for q, v in variations["plural"].items()}
    template = loc["stringUnit"]["value"]
    subs = loc.get("substitutions", {})
    if not subs:
        return "plain", template
    if len(subs) > 1:
        raise ExportError("%d substitutions (%s); only one can become a <plurals>"
                          % (len(subs), ", ".join(sorted(subs))))
    (name, sub), = subs.items()
    plural = sub.get("variations", {}).get("plural")
    if plural is None or "%#@" + name + "@" not in template:
        raise ExportError("substitution %s is not a plural spliced into its template" % name)
    return "plural", {q: (template, (name, sub["argNum"], sub["formatSpecifier"],
                                     v["stringUnit"]["value"]))
                      for q, v in plural.items()}


def build_catalog(prefix, path, allow_untranslated, locales):
    """-> ({locale: [xml element lines]}, [(key, name, is_plural)], [warnings])."""
    data = json.loads((ROOT / path).read_text(encoding="utf-8"))
    entries = {loc: [] for loc in ["en"] + locales}
    index, warnings, names = [], [], {}
    for key, entry in sorted(data["strings"].items(), key=lambda kv: resource_name(prefix, kv[0])):
        name = resource_name(prefix, key)
        if name in names:
            raise ExportError("%s: %r and %r share the name %s" % (path, names[name], key, name))
        names[name] = key
        try:
            localizations = dict(entry.get("localizations") or {})
            localizations.setdefault("en", {"stringUnit": {"value": key}})
            if entry.get("shouldTranslate") is False:
                localizations = {"en": localizations["en"]}
            read = {loc: read_localization(localizations[loc])
                    for loc in ["en"] + locales if loc in localizations}
            plural = any(kind == "plural" for kind, _ in read.values())
            converted, signatures = {}, {}
            for loc, (kind, value) in read.items():
                if not plural:
                    text, args, formatted = convert(value)
                    converted[loc], signatures[loc] = (text, formatted), [args]
                    continue
                items = value if kind == "plural" else {q: value for q in CATEGORIES[loc]}
                if "other" not in items:
                    raise ExportError("[%s] plural without `other`" % loc)
                for q in CATEGORIES[loc]:
                    items.setdefault(q, items["other"])
                done = {q: convert(*v) if isinstance(v, tuple) else convert(v) for q, v in items.items()}
                converted[loc] = done
                signatures[loc] = [args for _, args, _ in done.values()]
        except (ExportError, KeyError, TypeError, AttributeError) as error:
            # KeyError/TypeError: a catalog shape this reader does not know.
            raise ExportError("%s: %r: %s %s" % (path, key, type(error).__name__, error)) from error

        # The translation must hand the arguments the same types the English
        # text does; an Int read as %s still prints, a String read as %d throws.
        def union(sigs):
            merged = {}
            for sig in sigs:
                merged.update(sig)
            return merged
        base = union(signatures["en"])
        for loc in locales:
            if loc in signatures:
                sigs = signatures[loc]
                bad = (union(sigs) != base) if plural else (sigs[0] != base)
                if bad or any(sig.items() - base.items() for sig in sigs):
                    warnings.append("%s [%s] %r: arguments %s, English %s"
                                    % (path, loc, key, sigs, base))

        for loc, value in converted.items():
            attrs = ' name="%s"' % name
            if loc == "en" and entry.get("shouldTranslate") is False:
                attrs += ' translatable="false"'
            elif loc == "en" and key in allow_untranslated:
                attrs += ' tools:ignore="MissingTranslation"'
            if not plural:
                text, formatted = value
                if not formatted:
                    attrs += ' formatted="false"'
                entries[loc].append("    <string%s>%s</string>" % (attrs, escape_xml(text)))
                continue
            lines = ["    <plurals%s>" % attrs]
            for q in sorted(value, key=QUANTITY_ORDER.index):
                text, _, formatted = value[q]
                if not formatted:
                    raise ExportError("%s: %r [%s]: a literal %% in a plural item" % (path, key, loc))
                lines.append('        <item quantity="%s">%s</item>' % (q, escape_xml(text)))
            lines.append("    </plurals>")
            entries[loc].append("\n".join(lines))
        index.append((key, name, plural))
    return entries, index, warnings


def render_xml(path, lines):
    tools = ' xmlns:tools="http://schemas.android.com/tools"' if any("tools:" in line for line in lines) else ""
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- generated by %s from %s — do not edit -->\n"
            "<resources%s>\n%s</resources>\n"
            % (SCRIPT, path, tools, "".join(line + "\n" for line in lines)))


def render_kotlin(path, obj, index):
    def array(rows, empty, fmt):
        if not rows:
            return empty
        return "(\n%s,\n    )" % ",\n".join("        " + fmt(r) for r in rows)
    strings = [r for r in index if not r[2]]
    plurals = [r for r in index if r[2]]
    # Four arrays, each built in its own method: a mapOf()/when over hundreds of
    # keys would be one method, and the JVM caps a method at 64 KB of bytecode.
    return """// generated by {script} from {path} — do not edit
package com.dredfit.l10n

import com.dredfit.R

/** Resource ids by the English key, as `String(localized:)` looks them up on iOS. */
internal object {obj} {{
    fun string(key: String): Int? = strings[key]

    fun plural(key: String): Int? = plurals[key]

    private val strings: Map<String, Int> by lazy {{ index(stringKeys(), stringIds()) }}
    private val plurals: Map<String, Int> by lazy {{ index(pluralKeys(), pluralIds()) }}

    private fun index(keys: Array<String>, ids: IntArray): Map<String, Int> {{
        val map = HashMap<String, Int>(keys.size * 2)
        for (i in keys.indices) map[keys[i]] = ids[i]
        return map
    }}

    private fun stringKeys(): Array<String> = arrayOf{sk}

    private fun stringIds(): IntArray = intArrayOf{si}

    private fun pluralKeys(): Array<String> = arrayOf{pk}

    private fun pluralIds(): IntArray = intArrayOf{pi}
}}
""".format(script=SCRIPT, path=path, obj=obj,
           sk=array(strings, "<String>()", lambda r: kotlin_literal(r[0])),
           si=array(strings, "()", lambda r: "R.string." + r[1]),
           pk=array(plurals, "<String>()", lambda r: kotlin_literal(r[0])),
           pi=array(plurals, "()", lambda r: "R.plurals." + r[1]))


def android_dir(locale):
    if locale == "en":
        return "values"
    lang, _, region = locale.partition("-")
    return "values-b+%s+%s" % (lang, region) if region else "values-" + lang


def generate():
    """-> ({repo-relative path: content}, warnings, per-catalog counts)."""
    config = load_config()
    locales = config["required_locales"]
    missing = set(locales) - set(CATEGORIES)
    if missing:
        raise ExportError("no plural categories for %s" % sorted(missing))
    files, warnings, counts = {}, [], {}
    for prefix, path, xml, obj in CATALOGS:
        entries, index, warn = build_catalog(prefix, path, config["allow_untranslated"].get(path, []), locales)
        warnings += warn
        for loc, lines in entries.items():
            files["%s/%s/%s" % (RES, android_dir(loc), xml)] = render_xml(path, lines)
        files["%s/%s.kt" % (KOTLIN, obj)] = render_kotlin(path, obj, index)
        counts[prefix] = index
    return files, warnings, counts


def self_test():
    def check(got, want):
        if got != want:
            raise AssertionError("got %r, want %r" % (got, want))
    check(resource_name("app", "today"), "app_today_" + hashlib.sha1(b"today").hexdigest()[:8])
    check(resource_name("core", "≈ %lld–%lld min · Ёлка!")[:-9], "core_lld_lld_min")
    check(resource_name("widgets", " · %@")[:-9], "widgets_x")
    check(resource_name("app", "a" * 50)[:-9], "app_" + "a" * 40)
    check(convert("Hi %@"), ("Hi %s", {1: "s"}, True))
    check(convert("%lld days"), ("%d days", {1: "d"}, True))
    check(convert("%1$@ at %2$lld"), ("%1$s at %2$d", {1: "s", 2: "d"}, True))
    check(convert("%2$lld at %1$@"), ("%2$d at %1$s", {1: "s", 2: "d"}, True))
    check(convert("%@ and %lld"), ("%1$s and %2$d", {1: "s", 2: "d"}, True))
    check(convert("%.1f km, 5%%"), ("%.1f km, 5%%", {1: "f"}, True))
    check(convert("100% sure"), ("100% sure", {}, False))
    check(convert("only %2$@"), ("only %2$s", {2: "s"}, True))
    check(escape_xml("it's \"q\" a\\b <&>"), "it\\'s \\\"q\\\" a\\\\b &lt;&amp;&gt;")
    check(escape_xml("@home"), "\\@home")
    check(escape_xml("?why"), "\\?why")
    check(escape_xml(" · a  b "), "\\u0020· a \\u0020b\\u0020")
    check(escape_xml("x\u00a0:\u202f!’\n"), "x\u00a0:\u202f!’\\n")
    check(kotlin_literal('a"$\\\u00a0\n'), '"a\\"\\$\\\\\\u00A0\\n"')
    sub = ("exercises", 3, "lld", "%arg exercises")
    check(convert("≈ %lld–%lld min · %#@exercises@", sub),
          ("≈ %1$d–%2$d min · %3$d exercises", {1: "d", 2: "d", 3: "d"}, True))
    check(convert("%#@reps@", ("reps", 1, "lld", "reps per side")), ("reps per side", {}, True))
    check(convert("≈ %#@d@", ("d", 1, ".1f", "%arg km")), ("≈ %.1f km", {1: "f"}, True))
    kind, items = read_localization({"stringUnit": {"value": "%#@n@ left"}, "substitutions": {
        "n": {"argNum": 1, "formatSpecifier": "lld", "variations": {"plural": {
            "one": {"stringUnit": {"value": "%arg day"}},
            "other": {"stringUnit": {"value": "%arg days"}}}}}}})
    check((kind, {q: convert(*v)[0] for q, v in items.items()}),
          ("plural", {"one": "%d day left", "other": "%d days left"}))
    try:
        read_localization({"stringUnit": {"value": "%#@a@ %#@b@"}, "substitutions": {"a": {}, "b": {}}})
    except ExportError:
        pass
    else:
        raise AssertionError("two substitutions must fail")
    print("self-test: OK")


def main(argv):
    if "--self-test" in argv:
        self_test()
        return 0
    try:
        files, warnings, counts = generate()
    except ExportError as error:
        print("FAIL: %s" % error, file=sys.stderr)
        return 1
    if warnings:
        # A fail, not a note: Foundation prints a mistyped argument somehow,
        # java.util.Formatter throws IllegalFormatConversionException.
        for warning in warnings:
            print("argument mismatch: %s" % warning, file=sys.stderr)
        print("FAIL: fix the translation in its String Catalog", file=sys.stderr)
        return 1
    if "--check" in argv:
        stale = [p for p, c in sorted(files.items())
                 if not (ROOT / p).is_file() or (ROOT / p).read_bytes() != c.encode("utf-8")]
        # A file this script once wrote and no longer would (a dropped locale or catalog).
        written = [str(p.relative_to(ROOT)) for pattern in
                   ["%s/values*/strings_*.xml" % RES, "%s/*.kt" % KOTLIN] for p in ROOT.glob(pattern)
                   if ("generated by %s" % SCRIPT) in p.read_text(encoding="utf-8")]
        stale += sorted(set(written) - set(files))
        for p in stale:
            print("stale, missing or extra: %s" % p)
        if stale:
            print("FAIL: run python3 %s" % SCRIPT)
            return 1
        print("PASS: %d generated files are current." % len(files))
        return 0
    for p, c in sorted(files.items()):
        target = ROOT / p
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(c.encode("utf-8"))
    for prefix, index in counts.items():
        plurals = sum(1 for _, _, plural in index if plural)
        print("%s: %d strings, %d plurals" % (prefix, len(index) - plurals, plurals))
    print("wrote %d files" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
