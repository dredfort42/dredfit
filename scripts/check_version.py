#!/usr/bin/env python3
"""Verify the project version is consistent before a release is cut.

    python3 scripts/check_version.py release/1.7.0   # from a branch/ref name
    python3 scripts/check_version.py 1.7.0           # from a bare version

Given the expected marketing version (taken from the release/hotfix branch
name, or passed directly), this checks that:

  * every MARKETING_VERSION in the Xcode project equals that version,
  * every CURRENT_PROJECT_VERSION (build number) is identical across targets,
  * CHANGELOG.md has a "## <version>" section.

It catches the classic "forgot to bump one target" and "forgot the changelog
entry" mistakes before a tag turns them into a shipped build. Stdlib only.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "Dredfit.xcodeproj" / "project.pbxproj"
CHANGELOG = ROOT / "CHANGELOG.md"

MARKETING_RE = re.compile(r"MARKETING_VERSION = ([^;]+);")
BUILD_RE = re.compile(r"CURRENT_PROJECT_VERSION = ([^;]+);")


def version_from_arg(arg: str) -> str:
    """`release/1.7.0` -> `1.7.0`, `v1.7.0` -> `1.7.0`, `1.7.0` -> `1.7.0`."""
    tail = arg.rsplit("/", 1)[-1].strip()
    return tail[1:] if tail.startswith("v") else tail


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


def main(argv: list) -> int:
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

    print(f"Expected version: {expected}")
    print(f"MARKETING_VERSION: {marketing or '(none)'}")
    print(f"CURRENT_PROJECT_VERSION (build): {builds or '(none)'}")
    print()
    if errors:
        for e in errors:
            print(f"FAIL: {e}")
        return 1
    print(f"PASS: version {expected} is consistent (build "
          f"{builds[0]}) and has a changelog entry.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
