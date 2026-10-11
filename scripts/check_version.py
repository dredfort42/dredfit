#!/usr/bin/env python3
"""Verify the project version is consistent before a release is cut.

    python3 scripts/check_version.py release/1.7.0   # from a branch/ref name
    python3 scripts/check_version.py 1.7.0           # from a bare version
    python3 scripts/check_version.py --android       # an Android build

Given the expected marketing version (taken from the release/hotfix branch
name, or passed directly), this checks that:

  * every MARKETING_VERSION in the Xcode project equals that version,
  * every CURRENT_PROJECT_VERSION (build number) is identical across targets,
  * that build number is greater than the one at the highest older v* tag
    (skipped with a notice when git, the tags or that tag's project are not
    available — a shallow clone, say),
  * CHANGELOG.md has a "## <version>" section.

Android's version (android/gradle.properties) is only reported there, as a
notice when its dredfit.versionName is not that version: an iOS release must
not wait on a Play build. `--android` is the gate for that build instead
(android/tools/build-release.sh runs it), and checks that:

  * dredfit.versionName equals the tree's MARKETING_VERSION — one product
    version on both platforms (owner decision, 11.10.2026),
  * dredfit.versionCode is a positive integer above every code an
    android-vX.Y.Z+CODE tag already carries, whatever its version: Play
    refuses a code it has seen, and an Android-only fix ships the same
    versionName with the next code. Tags on the checked-out commit itself are
    left out, so the tagged build re-checks clean,
  * CHANGELOG.md has a "## <versionName> (Android)" section.

It catches the classic "forgot to bump one target" and "forgot the changelog
entry" mistakes before a tag turns them into a shipped build. Stdlib only.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "ios" / "Dredfit.xcodeproj" / "project.pbxproj"
CHANGELOG = ROOT / "CHANGELOG.md"

ANDROID_PROPERTIES = ROOT / "android" / "gradle.properties"

MARKETING_RE = re.compile(r"MARKETING_VERSION = ([^;]+);")
BUILD_RE = re.compile(r"CURRENT_PROJECT_VERSION = ([^;]+);")
# As java.util.Properties — Gradle's reader — splits a line: the key, then
# "=", ":" or blanks with blanks around them. The value keeps its trailing
# blanks, as Gradle's does (and "6 ".toInt() fails the build there too).
ANDROID_NAME_RE = re.compile(
    r"^[ \t\f]*dredfit\.versionName(?:[ \t\f]*[=:][ \t\f]*|[ \t\f]+)(.*)$",
    re.MULTILINE)
ANDROID_CODE_RE = re.compile(
    r"^[ \t\f]*dredfit\.versionCode(?:[ \t\f]*[=:][ \t\f]*|[ \t\f]+)(.*)$",
    re.MULTILINE)
# android-v2.5.0+1: the build rides as semver build metadata, which is what it
# is — the same version, another build. A "-b1" suffix would read as a
# pre-release, sorting before 2.5.0.
ANDROID_TAG_RE = re.compile(r"android-v\d+\.\d+\.\d+\+([1-9][0-9]*)")


def version_from_arg(arg: str) -> str:
    """`release/1.7.0` -> `1.7.0`, `v1.7.0` -> `1.7.0`, `1.7.0` -> `1.7.0`."""
    tail = arg.rsplit("/", 1)[-1].strip()
    return tail[1:] if tail.startswith("v") else tail


def git(*args: str) -> str:
    """stdout of a git command run at the repo root; raises on any failure."""
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout


def previous_build(expected: str):
    """(tag, build) at the highest v* tag older than `expected`, or a string
    saying why it cannot be determined.

    Older by version, not by date: a release branch re-checked after its own
    tag is pushed must compare against the release before it, not itself.
    """
    want = tuple(int(p) for p in expected.split("."))
    try:
        tags = git("tag", "--list", "v*").split()
    except (OSError, subprocess.CalledProcessError) as exc:
        return f"git tags unavailable ({exc.__class__.__name__})"
    older = []
    for tag in tags:
        m = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag)
        if m and tuple(int(g) for g in m.groups()) < want:
            older.append((tuple(int(g) for g in m.groups()), tag))
    if not older:
        return "no older v* tag found (a clone without tags?)"
    tag = max(older)[1]
    try:
        text = git("show", f"{tag}:ios/Dredfit.xcodeproj/project.pbxproj")
    except (OSError, subprocess.CalledProcessError):
        return f"cannot read the project at {tag} (shallow clone?)"
    try:
        build = max(int(b) for b in BUILD_RE.findall(text))
    except ValueError:
        return f"no integer CURRENT_PROJECT_VERSION at {tag}"
    return tag, build


RELEASE_BODY_MAX = 125_000

# One extractor, not two: release.yml posts exactly what changelog_section.py
# prints, so the size checked here has to come from that same function. A second
# copy of the parsing would drift, and the drift would only show up as an HTTP
# 422 after the tag was already pushed.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from changelog_section import section_for  # noqa: E402


def release_body_len(changelog: str, version: str) -> int:
    """Length of the body release.yml would post, trailing newline included."""
    section = section_for(version, changelog)
    return 0 if section is None else len(section) + 1  # + the print() newline


def android_version():
    """(versionName values, versionCode values) in android/gradle.properties.
    Raises OSError when the file cannot be read."""
    text = ANDROID_PROPERTIES.read_text(encoding="utf-8")
    return ANDROID_NAME_RE.findall(text), ANDROID_CODE_RE.findall(text)


def tagged_codes():
    """[(code, tag)] for every android-vX.Y.Z+CODE tag not on HEAD, or a
    string saying why the tags cannot be read."""
    try:
        tags = git("tag", "--list", "android-v*").split()
        here = set(git("tag", "--points-at", "HEAD", "--list",
                       "android-v*").split())
    except (OSError, subprocess.CalledProcessError) as exc:
        return f"git tags unavailable ({exc.__class__.__name__})"
    found = []
    for tag in tags:
        m = ANDROID_TAG_RE.fullmatch(tag)
        if m and tag not in here:
            found.append((int(m.group(1)), tag))
    return found


def check_android() -> int:
    """The gate for an Android build: one product version, a fresh code."""
    errors, notices = [], []
    marketing = sorted(set(MARKETING_RE.findall(
        PBXPROJ.read_text(encoding="utf-8"))))
    try:
        names, codes = android_version()
    except OSError as exc:
        names, codes = [], []
        errors.append(f"cannot read android/gradle.properties "
                      f"({exc.__class__.__name__})")
    if len(marketing) != 1:
        errors.append(f"MARKETING_VERSION is {marketing or '(none)'}; the "
                      f"product version must be one x.y.z")
    elif names != marketing:
        errors.append(f"dredfit.versionName is {names or '(none)'}, expected "
                      f"'{marketing[0]}' (iOS's MARKETING_VERSION)")
    else:
        # Android's notes are its own section: iOS's "## x.y.z" may have
        # shipped long before, and a GitHub Release was made from it as it
        # stood. The heading is the one changelog_section.py can print.
        heading = f"{names[0]} (Android)"
        section = section_for(heading, CHANGELOG.read_text(encoding="utf-8"))
        if not section or not section.strip():
            errors.append(f"CHANGELOG.md has no '## {heading}' section")
    highest = None
    if len(codes) != 1 or not re.fullmatch(r"[1-9][0-9]*", codes[0]):
        errors.append(f"dredfit.versionCode is {codes or '(none)'}, expected "
                      f"one positive integer")
    else:
        tagged = tagged_codes()
        if isinstance(tagged, str):
            notices.append(f"versionCode not compared with the tags: {tagged}")
        elif not tagged:
            notices.append("no android-vX.Y.Z+CODE tag yet: nothing to "
                           "compare the versionCode with")
        else:
            highest = max(tagged)
            if int(codes[0]) <= highest[0]:
                errors.append(
                    f"dredfit.versionCode is {codes[0]}, but {highest[1]} "
                    f"already used {highest[0]}; Play refuses a code it has "
                    f"seen — bump it above {highest[0]}")

    print(f"MARKETING_VERSION: {marketing or '(none)'}")
    print(f"Android versionName: {names or '(none)'}")
    print(f"Android versionCode: {codes or '(none)'}")
    if highest:
        print(f"Highest tagged versionCode: {highest[0]} ({highest[1]})")
    print()
    for n in notices:
        print(f"NOTICE: {n}")
    if errors:
        for e in errors:
            print(f"FAIL: {e}")
        return 1
    print(f"PASS: Android {names[0]} (versionCode {codes[0]}) carries the "
          f"product version and a code no tag has used.")
    return 0


def main(argv: list) -> int:
    if len(argv) >= 2 and argv[1] == "--android":
        return check_android()
    if len(argv) < 2:
        print("usage: check_version.py <release/x.y.z | x.y.z>", file=sys.stderr)
        return 2
    expected = version_from_arg(argv[1])
    if not re.fullmatch(r"\d+\.\d+\.\d+", expected):
        print(f"ERROR: '{argv[1]}' does not yield an x.y.z version (got "
              f"'{expected}').", file=sys.stderr)
        return 2

    text = PBXPROJ.read_text(encoding="utf-8")
    marketing = sorted(set(MARKETING_RE.findall(text)))
    builds = sorted(set(BUILD_RE.findall(text)))

    errors = []
    if not marketing:
        errors.append("no MARKETING_VERSION found in project.pbxproj")
    elif marketing != [expected]:
        errors.append(
            f"MARKETING_VERSION is {marketing}, expected all to be '{expected}'")
    if len(builds) != 1:
        errors.append(
            f"CURRENT_PROJECT_VERSION differs across targets: {builds}")

    # Build numbers climb across releases; a forgotten bump otherwise shows
    # up only at upload, after the tag. A notice, not a failure, when the
    # history is missing: a skipped check beats a red run that only says the
    # checkout was shallow.
    notices = []
    previous = previous_build(expected)
    if isinstance(previous, str):
        notices.append(f"build number not compared with an older tag: "
                       f"{previous}")
    elif len(builds) == 1:
        tag, prev = previous
        try:
            current = int(builds[0])
        except ValueError:
            notices.append(f"build number not compared with {tag}: "
                           f"'{builds[0]}' is not an integer")
        else:
            if current <= prev:
                errors.append(
                    f"CURRENT_PROJECT_VERSION is {current}, but {tag} already "
                    f"shipped build {prev}; bump it above {prev}")

    heading = re.compile(rf"^##\s+{re.escape(expected)}\s*$", re.MULTILINE)
    changelog = CHANGELOG.read_text(encoding="utf-8")
    if not heading.search(changelog):
        errors.append(f"CHANGELOG.md has no '## {expected}' section")
    else:
        # The section is posted to the GitHub Release verbatim, and the API
        # rejects a body over 125 000 characters with HTTP 422. That refusal
        # lands in release.yml — AFTER the tag is pushed, when the cheapest
        # recovery is to move a published tag. Checked here instead, because
        # release-checks.yml runs on the release BRANCH: 2.0.0 absorbed twenty
        # waves into one section, reached 147 408 characters, and failed that
        # way for real.
        size = release_body_len(changelog, expected)
        if size > RELEASE_BODY_MAX:
            errors.append(
                f"the '## {expected}' section is {size:,} characters; "
                f"the GitHub Release body caps at {RELEASE_BODY_MAX:,} "
                f"(over by {size - RELEASE_BODY_MAX:,})")

    # Android is reported here, never failed: an iOS-only release keeps its
    # verdict while Android still carries the version it last shipped.
    # `--android` gates the Android build when that one ships.
    try:
        android_names, _ = android_version()
    except OSError as exc:
        notices.append(f"Android version not read ({exc.__class__.__name__})")
    else:
        if android_names != [expected]:
            notices.append(
                f"Android dredfit.versionName is {android_names or '(none)'}, "
                f"not '{expected}' — fine for an iOS-only release; "
                f"`check_version.py --android` gates an Android build")

    print(f"Expected version: {expected}")
    print(f"MARKETING_VERSION: {marketing or '(none)'}")
    print(f"CURRENT_PROJECT_VERSION (build): {builds or '(none)'}")
    if not isinstance(previous, str):
        print(f"Previous release: {previous[0]} (build {previous[1]})")
    print()
    for n in notices:
        print(f"NOTICE: {n}")
    if errors:
        for e in errors:
            print(f"FAIL: {e}")
        return 1
    print(f"PASS: version {expected} is consistent (build "
          f"{builds[0]}) and has a changelog entry.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
