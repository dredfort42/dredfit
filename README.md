# Dredfit

[![CI](https://github.com/dredfort42/dredfit/actions/workflows/ci.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/ci.yml)
[![Lint](https://github.com/dredfort42/dredfit/actions/workflows/lint.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/lint.yml)
[![Localization](https://github.com/dredfort42/dredfit/actions/workflows/localization.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/localization.yml)
[![CodeQL](https://github.com/dredfort42/dredfit/actions/workflows/codeql.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/codeql.yml)

**Adaptive bodyweight training for iOS. Zero setup — open the app, your workout is ready.**

Dredfit works like a thermostat. There is no quiz, no goal picker, no timer settings. The app starts you at a conservative minimum and regulates itself: it proposes a plan, you do it, you answer one question — *how did it go?* — and the next workout adjusts. Tell it what you actually managed on the first workout and it lands on your real level right away; answer with a rating alone and it converges over a handful of sessions. Either way it then keeps the load right at the edge of what you can do, which is where progress happens.

No equipment required. No account. No network. Your entire training state is a session counter plus two small integers per movement pattern — a level and a fail-streak — on your device.

## How it works

The engine (`DredfitCore`) is built on three mechanisms:

**One integer per movement pattern.** Progress in each movement pattern is a single level `L ∈ [0, 47]`. The level *encodes* the exercise variation, the rep target and the set count all at once:

```
band = L / 8                     # 0…5
tier = min(4, 1 + band)          # which variation: 4 tiers from knee push-up to archer push-up
sets = 3 + max(0, band - 3)      # 3 sets (L ≤ 31), 4 sets (32…39), 5 sets (40…47)
reps = 8 + L % 8                 # 8…15 reps (or 20…55 s for holds)
```

Double progression falls out of the encoding for free: reach 15 reps and the next level up automatically switches you to a harder variation at 8 reps. Above tier 4 the same mechanism keeps working by adding a set instead of a variation, so the ceiling is 5 × 15 rather than a dead end. The level history *is* the progress chart.

**Deterministic rotation.** Every session has 6 exercises. One slot is always a pull, for shoulder health — the tested invariant is that weekly pull volume stays at least 70% of combined pushing volume. The other 8 patterns rotate through the remaining 5 slots so that over any 8 consecutive sessions each appears exactly 5 times. No randomness anywhere: the same state always generates the same workout.

**A feedback regulator.** After the workout, one tap: *tough / on plan / easy* → −1 / +1 / +2 levels for the session's patterns. During the workout you can record a per-exercise actual ("went differently") that overrides the rating for that pattern — upward moves are capped at +2 per session, downward moves are not. Three consecutive shortfalls on a pattern trigger an automatic deload (−3). A skipped exercise is neutral: its level and streak are left untouched rather than judged. Levels never go below 0. That's the whole model.

**The pull-up bar module.** Vertical pulling is the one honest gap of a no-equipment format. Turn the bar on in settings and every other session swaps the floor pull for a vertical one — bar hang, negative pull-up, partial, full pull-up — tracked as its own independent level. Turn it off and the branch freezes without losing progress.

The 40-exercise library is 10 patterns × 4 tiers: 8 rotating patterns (32), the fixed pull slot (4), and the bar branch (4). Classic calisthenics — squat to shrimp squat, knee push-up to archer push-up — each with reviewed, plain-language technique steps and common mistakes, in English, Russian, Spanish and Brazilian Portuguese.

## The app

SwiftUI, iOS 17+, iPhone, portrait. Three tabs, a settings sheet reachable from all of them, and one flow:

- **Today** — the generated plan and one Start button; a completed state once you're done, with a card for the next workout. If a session was cut short by iOS reclaiming memory or a swipe-kill, this is where it is offered back.
- **Workout** — warm-up, then one exercise at a time: a big number, set dots, a date-based rest ring with a 3-2-1 audio countdown, a hold timer for static exercises, in-the-moment actual adjustment, per-exercise skip. Every countdown is wall-clock based, so locking the phone mid-rest loses nothing — and the position is snapshotted on every transition, so neither does losing the process. Leaving asks first, and offers to finish early rather than discard.
- **Rating** — the one question on three equal cards, with an honest summary of anything you adjusted, skipped or left unfinished.
- **Calendar** — filled days are tappable history (what you did, with actuals and skips); *upcoming* planned days are outlines; today gets an accent ring; rest days a quiet fill; missed days are left as plain dimmed numbers, deliberately unmarked and unshamed.
- **Progress** — total level, a line chart across sessions with per-pattern projections, a weekly summary, per-pattern level bars.
- **Settings** — rest days, the pull-up bar, sounds and haptics, a reminder on training days, Apple Health export, backup export/import.

Beyond the app itself: a **home-screen widget** (workout / done / rest day, flipping at midnight without the app running), a **Live Activity** that puts the rest countdown on the lock screen and in the Dynamic Island, **Apple Health** export (write-only — completed workouts become strength-training samples, nothing is ever read), and **local reminders** on training days.

State is one JSON file in Application Support. Old records survive every update — new fields are optional, migrations are decode-level. Backup export/import round-trips the whole thing as plain JSON.

## Architecture

```
DredfitCore/            Swift package — the engine, pure functions, no UI imports
  Engine.swift          state → session; state × session × feedback → state
  Library.swift         40 exercises, hand-written to mirror the JS reference
  Resources/            String Catalog (en source, ru translation)
  Tests/
    EngineTests.swift   invariants: encoding, rotation, balance, deload, caps
    EdgeCaseTests.swift boundary behavior
    GoldenTests.swift   bit-for-bit match against the reference implementation
    Fixtures/golden.json

Dredfit/                SwiftUI app target
  AppStore.swift        the only mutable state + JSON persistence; also owns
                        the Health export flags and the in-progress snapshot
  HealthStore.swift     write-only HealthKit bridge, stateless
  LiveActivityController.swift, WidgetBridge.swift
  Views/                Today, WorkoutFlow, Feedback, Progress, Calendar,
                        History, Technique, NextWorkout, Settings
  Design/Theme.swift    ink scale + one accent (and its soft tint)

DredfitWidgets/         widget extension — TodayStatusWidget, RestLiveActivity
Shared/                 the App Group snapshot contract
```

The engine was first written and verified as a JavaScript reference (4,150 property checks and scenario simulations), then ported to Swift. `golden.json` is the reference's recorded trace — 133 steps across 9 scenarios — and the Swift port must reproduce it exactly. Changing engine behavior means changing the reference first, re-verifying, regenerating fixtures, then porting. Plausible-but-different is a failing test, not a judgment call. (The JS reference lives outside this repository; the recorded fixture is what ships.)

## Testing

Three layers, 182 automated tests:

| Layer | Count | What it covers |
|---|---|---|
| Core invariants + golden | 61 | encoding bijectivity, rotation properties, pull:push balance, deload timing, override caps, skip semantics, bar-branch independence, lenient state decode, feedback replay safety, reference parity |
| App unit tests | 88 | persistence round-trips, corrupted-file quarantine, legacy-record migration, in-progress snapshot validity, rest-day calendar math, Health export ordering and idempotence, reminder scheduling, day-anchor rollover, widget snapshot |
| UI tests | 33 | the full workout flow, in-workout adjustment, hold mis-tap grace, resume after a kill, the three exit paths, history, relaunch persistence |

Plus [TESTPLAN.md](TESTPLAN.md): a manual QA checklist (locale passes, date rollover, backgrounding during rest, device-only integrations) and a registry of found issues with their status.

CI runs the unit suites on every push — that is the gate for merges and releases. UI tests are slow and occasionally flaky on shared runners, so they run nightly on their own and gate nothing; they are run locally before cutting a release branch instead.

## Building

1. Open the Xcode project (iOS 17+, Xcode 15+).
2. The `DredfitCore` package is local — add it via *File → Add Package Dependencies → Add Local* if not already linked.
3. `⌘U` on the package first: golden tests are the gate.
4. Run on any iPhone simulator. UI tests expect an English locale and use `--uitest-reset`.

## Localization

English is the source language; Russian, Spanish and Brazilian Portuguese each ship complete — 440 strings across four String Catalogs, including all exercise technique. English base strings live inline at each call site; translations live in the catalogs. Every translation is idiomatic rather than literal: Russian avoids anglicisms and calques and uses `е` rather than `ё` throughout; Spanish and Brazilian Portuguese address the reader informally (`tú` / `você`) and take their exercise and pattern vocabulary from the same glossary as the marketing site.

## Design principles

One accent color. System typography. No gamification, no streaks, no guilt: a missed day stays a quiet outline in the calendar, because the engine adapts anyway. The app asks the user exactly one question per day, and it's answerable with one thumb.

No third-party dependencies, no network calls, no analytics of any kind — the App Store privacy label "Data Not Collected" is literally true.

## Continuous integration

Every push and PR runs the gate — unit tests (Core + app), SwiftLint, and a
String Catalog completeness check. UI tests run nightly and gate nothing;
CodeQL, secret scanning, and PR-title linting run alongside as advisory checks. Releases are tagged `vX.Y.Z`, which publishes a GitHub
Release from the matching `CHANGELOG.md` section. Full details, the release
procedure, and how to enable branch protection are in
[`.github/WORKFLOWS.md`](.github/WORKFLOWS.md).

## Status

Shipping. Working on device, tested across all four locales.

Planned work and deliberately-rejected ideas are tracked in the project backlog (`instructions/BACKLOG.md`, kept alongside the engine specification outside this repository).

## Disclaimer

Dredfit is a general-fitness tool for healthy adults, not medical advice. Sharp or joint pain means stop; consult a physician before starting if you have cardiovascular or joint conditions.
