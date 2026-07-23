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
    if not heading.search(CHANGELOG.read_text(encoding="utf-8")):
        errors.append(f"CHANGELOG.md has no '## {expected}' section")

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
