#!/usr/bin/env python3
"""Every gate the release checklist NAMES must run and print its clean line.

The audit of 26.08.2026 found three of the six gates listed in `TESTPLAN.md`
dying with a `TypeError` before their first check, and one printing a hit
nobody had looked at. Nothing went red: a gate that is never run is
indistinguishable from a gate that passed. It was the second wave in a row
with that failure, so the rule moved out of anyone's head and into this
script.

The gate list is READ OUT OF `TESTPLAN.md`, deliberately — the tracked
checklist is what a release is judged against, so adding a row there is what
makes a gate run, and a row nobody can run fails here instead of reading as
done.

    python3 scripts/check_engine_gates.py            # run every gate
    python3 scripts/check_engine_gates.py --contract # parse only, run nothing

`--contract` is what CI can do. The gates themselves live in `reference/`,
which is gitignored and never checked out on a runner, so the running of them
is a LOCAL gate — part of the release procedure in `.github/WORKFLOWS.md`.
What CI still catches is a checklist row that names no command, or names no
clean line, or a table that stopped parsing at all.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTPLAN = ROOT / "TESTPLAN.md"
REFERENCE = ROOT / "reference"
HEADING = "## Engine gates before a release"

# A row is: | `command` | `marker` | prose |
ROW = re.compile(r"^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|")


def gates() -> list[tuple[str, str]]:
    """(command, the literal its output must contain) for every table row."""
    text = TESTPLAN.read_text(encoding="utf-8")
    if HEADING not in text:
        sys.exit(f"{TESTPLAN.name}: section '{HEADING}' is gone — "
                 "the gate list has no home any more")
    section = text.split(HEADING, 1)[1].split("\n## ", 1)[0]
    found = [(m.group(1), m.group(2)) for line in section.splitlines()
             if (m := ROW.match(line))]
    if not found:
        sys.exit(f"{TESTPLAN.name}: the gate table parses to nothing. Each row "
                 "must read | `command` | `clean line` | why |")
    return found


def blame(done: subprocess.CompletedProcess) -> str:
    """The one line worth quoting from a gate that died.

    Not the last line: a node stack trace ends with the interpreter version,
    which says nothing about why the gate is red. The thrown error does.
    """
    err = [ln.strip() for ln in done.stderr.splitlines() if ln.strip()]
    for line in err:
        if "Error" in line:
            return line
    if err:
        return err[0]
    out = [ln.strip() for ln in done.stdout.splitlines() if ln.strip()]
    return out[-1] if out else ""


def run(command: str, marker: str) -> str | None:
    """None when the gate is clean, otherwise why it is not."""
    # `node` gates are written to be run from inside the reference contour;
    # everything else is a repo script and runs from the root.
    cwd = REFERENCE if command.startswith("node ") else ROOT
    try:
        done = subprocess.run(command, shell=True, cwd=cwd, timeout=1800,
                              capture_output=True, text=True)
    except subprocess.TimeoutExpired:
        return "did not finish in 30 minutes"
    output = done.stdout + done.stderr
    # Both halves are checked, and the exit code first: the defect this script
    # exists for is a gate that DIED before printing anything, which an output
    # search alone reports as "marker missing" — true, but not the reason.
    if done.returncode != 0:
        return f"exited {done.returncode}" + (f" — {why}" if (why := blame(done)) else "")
    if marker not in output:
        return f"ran, but never printed {marker!r}"
    return None


def main() -> int:
    contract_only = "--contract" in sys.argv[1:]
    rows = gates()
    print(f"{len(rows)} gate(s) named in {TESTPLAN.name}")
    if contract_only:
        for command, marker in rows:
            print(f"  · {command}  →  must print {marker!r}")
        print("contract OK — every row names a command and a clean line")
        return 0
    if not REFERENCE.is_dir():
        print(f"FAIL: {REFERENCE} is not here. The gates live in the reference "
              "contour, which is gitignored — run this from a checkout that "
              "has one, or pass --contract.", file=sys.stderr)
        return 2
    failed = []
    for command, marker in rows:
        why = run(command, marker)
        print(f"  {'ok  ' if why is None else 'FAIL'}  {command}"
              + ("" if why is None else f"  — {why}"))
        if why is not None:
            failed.append(command)
    if failed:
        print(f"\n{len(failed)} of {len(rows)} gates did not report clean.",
              file=sys.stderr)
        return 1
    print(f"\nall {len(rows)} gates ran and reported clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
