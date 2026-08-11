#!/usr/bin/env python3
"""Provenance manifest for the golden fixture (issue #104).

The reference contour (spec, adaptive_engine.js, verify2.js, make_golden.js)
deliberately lives outside this repository, so "which reference produced this
fixture" used to be an unprovable claim. This script writes
DredfitCore/Tests/DredfitCoreTests/Fixtures/reference-manifest.json with the
generator string and sha256 hashes of the four contour files and of
golden.json itself. ManifestTests asserts the bundled fixture matches the
manifest, so CI fails on any fixture changed without provenance.

Run it as step 4bis of the reference protocol — right after
`node make_golden.js`:

    python3 scripts/update_reference_manifest.py            # rewrite
    python3 scripts/update_reference_manifest.py --check    # verify only

The manifest is never edited by hand, same rule as the fixture.
"""

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REFERENCE = ROOT / "reference"
FIXTURES = ROOT / "DredfitCore" / "Tests" / "DredfitCoreTests" / "Fixtures"
GOLDEN = FIXTURES / "golden.json"
MANIFEST = FIXTURES / "reference-manifest.json"
CONTOUR = ["SPEC-v2.md", "adaptive_engine.js", "make_golden.js", "verify2.js"]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build() -> dict:
    missing = [n for n in CONTOUR if not (REFERENCE / n).exists()]
    if missing:
        sys.exit(f"FAIL: reference contour incomplete, missing: {', '.join(missing)}\n"
                 "The manifest can only be produced next to the local reference/.")
    generator = json.loads(GOLDEN.read_text())["generator"]
    return {
        "generator": generator,
        "golden.json": sha256(GOLDEN),
        "reference": {name: sha256(REFERENCE / name) for name in CONTOUR},
    }


def main() -> None:
    fresh = build()
    payload = json.dumps(fresh, indent=2, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        if not MANIFEST.exists():
            sys.exit("FAIL: reference-manifest.json is missing — run without --check first.")
        if MANIFEST.read_text() != payload:
            stored = json.loads(MANIFEST.read_text())
            for key in ("generator", "golden.json"):
                if stored.get(key) != fresh[key]:
                    print(f"  {key}: manifest {stored.get(key)} != actual {fresh[key]}")
            for name in CONTOUR:
                a, b = stored.get("reference", {}).get(name), fresh["reference"][name]
                if a != b:
                    print(f"  reference/{name}: manifest {a} != actual {b}")
            sys.exit("FAIL: the manifest does not match the working tree — "
                     "regenerate golden.json and rerun this script.")
        print("OK: the manifest matches the reference contour and the fixture.")
        return
    MANIFEST.write_text(payload)
    print(f"written: {MANIFEST.relative_to(ROOT)} (generator {fresh['generator']})")


if __name__ == "__main__":
    main()
