# android/

The Android port of Dredfit. Empty today except for these notes; the Kotlin
scaffold arrives as its own PR. The layout is fixed here first so the scaffold
has something to match and so the root `.gitignore` already carries the Android
rules (`.gradle/`, `local.properties`, `*.jks`, `*.keystore`) before the first
Gradle file lands.

The Android side lives on `develop` beside `ios/`, never on a long-lived
platform branch: the repo squash-merges, and the one thing tying the two ports
together — `ios/DredfitCore/Tests/DredfitCoreTests/Fixtures/golden.json` — is
on `develop`. A branch that lived for months would fall behind that fixture
silently, which is the defect class the reference chain exists to catch.

## What goes here

```text
android/
├── CLAUDE.md          the guide for agents — gitignored by the root pattern,
│                      like the root CLAUDE.md; picked up when work touches
│                      files under android/
├── settings.gradle.kts, build.gradle.kts, gradle.properties, gradlew
├── gradle/            wrapper + libs.versions.toml (the one version catalog)
├── core/              the Kotlin port of DredfitCore — see core/README.md
└── app/               the Compose app, widgets included — see app/README.md
```

Not here, deliberately:

- **No copy of `golden.json`.** `core` reads the Swift package's fixture
  through `../../ios/DredfitCore/Tests/DredfitCoreTests/Fixtures`; the
  manifest guards one file, and a copy is exactly what it must not allow.
- **No `widgets/` module.** Isolating an extension into its own process is an
  iOS constraint; on Android the Glance widget is a receiver inside `app`.
- **No `shared/` module.** The App Group is iOS; the two-week widget snapshot
  is a class in `app`, and the rule that the widget never computes rest days
  itself comes along unchanged.
- **No `res/raw/` for sounds.** The iOS app synthesises its countdown and
  reminder sounds in code and tracks no media file; do the same.
- **No second CHANGELOG, TESTPLAN or glossary.** One of each at the root; the
  Android side gets sections, not files.

## Rules that transfer from `ios/`

- **The judge is `golden.json`, not the Swift port.** The reference is
  `reference/adaptive_engine.js`; where Kotlin and Swift disagree, the fixture
  decides. Otherwise the Kotlin port inherits every defect of the Swift one.
- **The wire format must read iOS JSON**: `[Pattern: Int]` is encoded as an
  unkeyed array, new fields are optional with a default, and the journal
  decodes record by record. Backup export/import is the bridge from iOS to
  Android, and it works only if both sides read the same file.
- **Health Connect is write-only**, the same promise HealthKit keeps on iOS.
- **User-facing text follows `instructions/GLOSSARY.md`** in all seven
  languages; `res/values*/strings_*.xml` are generated from the String
  Catalogs by `scripts/export_android_strings.py`, one file per source
  catalog, never edited by hand — so both localization gates cover Android
  without a second source of truth.
- **File names one-to-one with Swift** (`Breaks.swift` ↔ `Breaks.kt`): after
  the port, a diff on the Swift side must point at the Kotlin file without a
  search. That is the maintenance mechanism, as important as the fixture.
- **PRs target `develop`**, Conventional Commits titles, one wave per PR. The
  Android CI job stays non-required until the app ships; when it becomes
  required, filter paths at the job level, not the workflow level — a
  workflow-level `paths:` filter leaves a required check pending on every PR
  that does not touch `android/`, and blocks the merge.
