# Dredfit

**Adaptive bodyweight training for iOS. Zero setup — open the app, your workout is ready.**

Dredfit works like a thermostat. There is no onboarding quiz, no goal picker, no timer settings. The app starts you at a conservative minimum and regulates itself: it proposes a plan, you do it, you answer one question — *how did it go?* — and the next workout adjusts. Within two or three sessions the system converges on your real level and then keeps the load right at the edge of what you can do, which is where progress happens.

No equipment. No account. No network. Your entire training state is eleven small numbers on your device.

## How it works

The engine (`DredfitCore`) is built on three mechanisms:

**One integer per movement pattern.** Progress in each of 9 movement patterns (squat, horizontal push, hinge, pull, vertical push, lunge, core-front, core-side, calves) is a single level `L ∈ [0, 31]`. The level *encodes* both the exercise variation and the rep target:

```
tier = 1 + L / 8        # which variation: 4 tiers from knee push-up to archer push-up
reps = 8 + L % 8        # 8…15 reps (or 20…55 s for holds)
```

Double progression falls out of the encoding for free: reach 15 reps and the next level up automatically switches you to a harder variation at 8 reps. The level history *is* the progress chart.

**Deterministic rotation.** Every session has 6 exercises: the pull pattern is always included (weekly pull volume stays ≥ push volume — shoulder health), and the other 8 patterns rotate through 5 slots so that over any 8 consecutive sessions each appears exactly 5 times. No randomness anywhere: the same state always generates the same workout.

**A feedback regulator.** After the workout, one tap: *tough / on plan / easy* → −1 / +1 / +2 levels for the session's patterns. During the workout you can record a per-exercise actual ("went differently") that overrides the rating for that pattern. Three consecutive shortfalls on a pattern trigger an automatic deload (−3). Levels never go below 0. That's the whole model.

The 36-exercise library (9 patterns × 4 tiers) is classic calisthenics — squat to shrimp squat, knee push-up to archer push-up — each with reviewed, plain-language technique steps and common mistakes, in English and Russian.

## The app

SwiftUI, iOS 17+, iPhone, portrait. Three tabs and one flow:

- **Today** — the generated plan and one Start button; a completed state once you're done.
- **Workout** — one exercise at a time: a big number, set dots, a date-based rest ring with a 3-2-1 audio countdown, in-the-moment actual adjustment.
- **Rating** — the one question, with an honest summary of anything you adjusted.
- **Calendar** — filled days are tappable history (what you did, with actuals); planned days are outlines; missed days are deliberately not shamed.
- **Progress** — total level, a line across sessions, per-pattern level bars.

State is one JSON file in Application Support. Old records survive every update — new fields are optional, migrations are decode-level.

## Architecture

```
DredfitCore/            Swift package — the engine, pure functions, no UI imports
  Engine.swift          state → session; state × feedback → state
  Library.swift         36 exercises (generated from a bilingual source table)
  Resources/            String Catalog (en source, ru translation)
  Tests/
    EngineTests.swift   invariants: encoding, rotation, balance, deload, caps
    EdgeCaseTests.swift boundary behavior
    GoldenTests.swift   bit-for-bit match against the reference implementation
    Fixtures/golden.json

Dredfit/                SwiftUI app target
  AppStore.swift        the only mutable state + JSON persistence
  Views/                Today, WorkoutFlow, Feedback, Progress, Calendar,
                        History, Technique, NextWorkout
  Design/Theme.swift    ink scale + one accent color
```

The engine was first written and verified as a JavaScript reference (2,150+ property checks and scenario simulations), then ported to Swift. `golden.json` is the reference's recorded trace — 46 steps across 4 scenarios — and the Swift port must reproduce it exactly. Changing engine behavior means changing the reference first, re-verifying, regenerating fixtures, then porting. Plausible-but-different is a failing test, not a judgment call.

## Testing

Three layers, ~60 automated tests:

| Layer | What it covers |
|---|---|
| Core invariants + golden | encoding bijectivity, rotation properties, pull:push balance, deload timing, override caps, reference parity |
| App unit tests | persistence round-trips, corrupted-file recovery, legacy-record migration, rest-day calendar math |
| UI tests | the full workout flow, in-workout adjustment, history, cold-start routing, relaunch persistence |

Plus `TESTPLAN.md`: a manual QA checklist (locale passes, date rollover, backgrounding during rest) and a registry of found issues with their status.

## Building

1. Open the Xcode project (iOS 17+, Xcode 15+).
2. The `DredfitCore` package is local — add it via *File → Add Package Dependencies → Add Local* if not already linked.
3. `⌘U` on the package first: golden tests are the gate.
4. Run on any iPhone simulator. UI tests expect an English locale and use `--uitest-reset`.

## Localization

English is the source language; Russian ships complete (335+ strings including all exercise technique). Both catalogs are generated from one bilingual table, so the languages cannot drift apart. Russian copy is idiomatic — reviewed specifically to avoid anglicisms and calques.

## Design principles

One accent color. System typography. No gamification, no streaks, no guilt: a missed day stays a quiet outline in the calendar, because the engine adapts anyway. The app asks the user exactly one question per day, and it's answerable with one thumb.

## Status & roadmap

Working MVP, tested on device. Possible next steps: exit-confirmation during a workout, smarter handling of skipped exercises, a configurable rest day, an optional pull-up-bar module (vertical pulling is the one honest gap of the no-equipment format), local notification on training days.

## Disclaimer

Dredfit is a general-fitness tool for healthy adults, not medical advice. Sharp or joint pain means stop; consult a physician before starting if you have cardiovascular or joint conditions.
