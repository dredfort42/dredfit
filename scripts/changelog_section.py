#!/usr/bin/env python3
"""Print the CHANGELOG.md section for one version, for use as release notes.

    python3 scripts/changelog_section.py 1.7.0     # -> the body under "## 1.7.0"
    python3 scripts/changelog_section.py v1.7.0     # leading v is stripped

Exits 0 and prints the section body (everything between "## <version>" and the
next "## " heading) when found; exits 1 and prints nothing when the version has
no section, so a caller can fall back to a git-log changelog. Stdlib only.
"""
import pathlib
import re
import sys

CHANGELOG = pathlib.Path(__file__).resolve().parent.parent / "CHANGELOG.md"


def section_for(version: str, text: str):
    version = version[1:] if version.startswith("v") else version
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.fullmatch(rf"##\s+{re.escape(version)}\s*", line):
            start = i + 1
            break
    if start is None:
        return None
    body = []
    for line in lines[start:]:
        if re.match(r"##\s+", line):
            break
        body.append(line)
    return "\n".join(body).strip("\n")


def main(argv: list) -> int:
    if len(argv) < 2:
        print("usage: changelog_section.py <version>", file=sys.stderr)
        return 2
    section = section_for(argv[1], CHANGELOG.read_text(encoding="utf-8"))
    if not section or not section.strip():
        return 1
    print(section)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
