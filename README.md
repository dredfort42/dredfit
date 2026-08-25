# Dredfit

[![CI](https://github.com/dredfort42/dredfit/actions/workflows/ci.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/ci.yml)
[![Lint](https://github.com/dredfort42/dredfit/actions/workflows/lint.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/lint.yml)
[![Localization](https://github.com/dredfort42/dredfit/actions/workflows/localization.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/localization.yml)
[![CodeQL](https://github.com/dredfort42/dredfit/actions/workflows/codeql.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/codeql.yml)

[dredfit.com](https://dredfit.com/) · [App Store](https://apps.apple.com/app/id6791739610)

**Adaptive bodyweight training for iOS. Zero setup — open the app, your workout is ready.**

Dredfit works like a thermostat. There is no quiz, no goal picker, no timer settings. The app starts you at a conservative minimum and regulates itself: it proposes a plan, you do it, you answer one question — *how did it go?* — and the next workout adjusts. Tell it what you actually managed on the first workout and it lands on your real level right away; answer with a rating alone and it converges over a handful of sessions. Either way it then keeps the load right at the edge of what you can do, which is where progress happens.

No equipment required. No account. No network. Your entire training state is a session counter plus two small integers per movement pattern — a level and a fail-streak — on your device.

## How it works

The engine (`DredfitCore`) is built on three mechanisms:

**One integer per movement pattern.** Progress in each movement pattern is a single level `L ∈ [0, 47]`. The level *encodes* the exercise variation, the rep target and the set count all at once:

```text
band = L / 8                       # 0…5
tier = min(4, 1 + band)            # which variation: 4 tiers from knee push-up to archer push-up
sets = 3 + max(0, band - 3)        # 3 sets (L ≤ 31), 4 sets (32…39), 5 sets (40…47)
reps = repStart[tier] + L % 8      # floors 8/6/5/4 → 8…15 on tier 1, 4…11 on tier 4
hold = holdLadder[tier][L % 8]     # a ~10% step per rung → 20…39 s on tier 1, 10…19 s on tier 4
```

Double progression falls out of the encoding for free: top out a tier's rep range and the next level up switches you to a harder variation, restarting low. The floor drops as the variation gets harder, so a new tier lands softly instead of jumping from an easy fifteen straight into a hard eight. Above tier 4 the same mechanism keeps working by adding a set instead of a variation, so the ceiling is 5 × 11 rather than a dead end. The level history *is* the progress chart.

**Deterministic rotation.** Every session has 6 exercises. One slot is always a pull, for shoulder health — the tested invariant is that weekly pull volume stays at least 70% of combined pushing volume. The other 8 patterns rotate through the remaining 5 slots so that over any 8 consecutive sessions each appears exactly 5 times. No randomness anywhere: the same state always generates the same workout.

**A feedback regulator.** After the workout, one tap: *tough / on plan / easy* → −1 / +1 / +2 levels for the session's patterns. During the workout you can record a per-exercise actual ("went differently") that overrides the rating for that pattern — upward moves are capped, downward moves are not. The cap is per movement and per variation, because tissue is: calves climb a single step per workout at every variation, the vertical push from the wall handstand up, and every pattern on its fourth variation, where the archer variants and the set bands live. Everything else keeps two. Three consecutive shortfalls on a pattern trigger an automatic deload (−3). A skipped exercise is neutral: its level and streak are left untouched rather than judged. When a movement is simply too much today, the answer is a handle rather than a diagnosis: *give me an easier variation* drops it a rung, *fewer sets* takes one off, and both take effect on the plan in front of you — the app does not ask where it hurts, and it never quietly removes a movement for weeks. Levels never go below 0, and level 0 — three sets of eight in the easiest variation of each movement — is the declared bottom of the product rather than a hole to climb out of. Time is the one input that isn't a tap: a week away eases every pattern down a step without saying anything about it, and past two weeks the app offers to meet you lower still — the longer the break, the further down. That's the whole model.

**The pull-up bar module.** Vertical pulling is the one honest gap of a no-equipment format. Turn the bar on in settings and every other session swaps the floor pull for a vertical one — bar hang, negative pull-up, partial, full pull-up — tracked as its own independent level. Turn it off and the branch freezes without losing progress.

The 40-exercise library is 10 patterns × 4 tiers: 8 rotating patterns (32), the fixed pull slot (4), and the bar branch (4). Classic calisthenics — squat to shrimp squat, knee push-up to archer push-up — each with reviewed, plain-language technique steps and common mistakes, in English, Russian, Spanish, Brazilian Portuguese, German, French and Italian.

## The app

SwiftUI, iOS 17+, iPhone, portrait. Three tabs, a settings sheet reachable from all of them, and one flow:

- **Today** — the generated plan and one Start button, with nothing to agree to first: the line above says how long the full workout takes and how short it can be made from inside it, and each movement offers an easier variation. A completed state once you're done, with a card for the next workout. If a session was cut short by iOS reclaiming memory or a swipe-kill, this is where it is offered back.
- **Workout** — warm-up, then one exercise at a time: a big number, set dots, a date-based rest ring with a 3-2-1 audio countdown, a hold timer for static exercises, in-the-moment actual adjustment, and the decision about the length of the session: skip this set, or the rest of a movement's sets — with what is left of the workout on screen, recalculated as you go. Unilateral holds get a counted pause to switch sides. A cool-down closes the session before the rating — six stretches, half of them chosen from what you just trained. Every position of both guided blocks opens with a five-second "Get ready" naming what is coming, skippable by a tap for anyone already in place, and every timed screen of those blocks can be paused — the doorbell is not a reason to pretend a stretch happened, and resuming counts you back in before continuing from the second it stopped on. Every countdown is wall-clock based, so locking the phone mid-rest loses nothing — and the position is snapshotted on every transition, so neither does losing the process. Leaving asks first, and offers to finish early rather than discard.
- **Rating** — the one question on three equal cards, with an honest summary of anything you adjusted, skipped or left unfinished.
- **Calendar** — filled days are tappable history (what you did, with actuals and skips); *upcoming* planned days are outlines; today gets an accent ring; rest days a quiet fill; missed days are left as plain dimmed numbers, deliberately unmarked and unshamed.
- **Progress** — total level, a line chart across sessions with per-pattern projections, a weekly summary, per-pattern level bars.
- **Settings** — rest days, the pull-up bar, sounds and haptics, a reminder on training days, Apple Health export, backup export/import.

Beyond the app itself: **widgets** in every size — small, medium and large on the home screen, all three lock-screen accessories — showing workout / done / rest day and flipping at midnight without the app running; a **Live Activity** that puts the rest countdown on the lock screen and in the Dynamic Island, **Apple Health** export (write-only — completed workouts become strength-training samples, nothing is ever read), and **local reminders** on training days.

State is one JSON file in Application Support. Old records survive every update — new fields are optional, migrations are decode-level. Backup export/import round-trips the whole thing as plain JSON.

## Architecture

```text
DredfitCore/            Swift package — the engine, pure functions, no UI imports
  Engine.swift          state → session; state × session × feedback → state
  Library.swift         40 exercises, hand-written to mirror the JS reference
  Resources/            String Catalog (en source; ru, es, pt-BR, de, fr, it translations)
  Tests/
    EngineTests.swift    invariants: encoding, rotation, balance, deload, caps
    EngineV23Tests.swift zero-level calibration, comeback, per-tier rep/hold floors
    EdgeCaseTests.swift  boundary behavior
    GoldenTests.swift    bit-for-bit match against the reference implementation
    Fixtures/golden.json

Dredfit/                SwiftUI app target
  AppStore.swift        the only mutable state + JSON persistence; also owns
                        the Health export flags and the in-progress snapshot
  HealthStore.swift     write-only HealthKit bridge, stateless
  LiveActivityController.swift, WidgetBridge.swift
  Views/                Today, WorkoutFlow, Feedback, Progress, Calendar,
                        History, Technique, NextWorkout, Settings,
                        Onboarding, HowItWorks, Milestone, ShareCard
  Design/Theme.swift    ink scale + one accent (and its soft tint)

DredfitWidgets/         widget extension — TodayStatusWidget, RestLiveActivity
Shared/                 the App Group snapshot contract

docs/                   the dredfit.com site — GitHub Pages, static, no build
  index.html            landing + privacy.html, mirrored under ru/ es/ pt-br/ de/ fr/ it/
  CNAME, robots.txt, sitemap.xml, og.png
```

The engine was first written and verified as a JavaScript reference (14,029 property checks and scenario simulations), then ported to Swift. `golden.json` is the reference's recorded trace — 183 steps across 14 scenarios — and the Swift port must reproduce it exactly. Changing engine behavior means changing the reference first, re-verifying, regenerating fixtures, then porting. Plausible-but-different is a failing test, not a judgment call. (The JS reference lives outside this repository; the recorded fixture is what ships.)

## Testing

Three layers, 665 automated tests:

| Layer | Count | What it covers |
| --- | --- | --- |
| Core invariants + golden | 271 | encoding bijectivity, rotation properties, pull:push balance, deload timing, override caps, skip semantics, bar-branch independence, lenient state decode, feedback replay safety, the silent decay and its non-stacking with the comeback, the per-movement growth ceiling checked cell by cell against the reference table — including the pull's frequency cells, the sub-step of v2.22 (the plan grows one set at a time, the top rung of a variation never mixes, and the cancelled hold-this-level input leaves no trace), the do-no-harm gate of v2.7 (calibration bounded by the neighboring tier, comeback landing ceilings with the set-band snap, the decay resetting the streak), the v2.8 polish (exact-plan facts stepping like "on plan", banded rest), the sets handle of v2.25 (the hold between returned sets, the postcondition repair, and the unit change landing by time under load), the two handles of v2.26 (an easier variation always leaves the tier, fewer sets stops at the floor of two, and a set comes back only when strength does — never on a timer), the three rules of a set skipped mid-workout in v2.27 (the skip lands after the rating and both orders are asserted, the floor is not a place to record a dose of 0, and one tap per movement is what makes a long session fit), the fixture's provenance manifest, the 40 variation identities pinned by value, reference parity, and a JS↔Swift differential test over 10,000 trajectories |
| App unit tests | 337 | persistence round-trips, corrupted-file quarantine, a frozen journal and its reload, legacy-record migration, in-progress snapshot validity, rest-day calendar math, Health export ordering and idempotence — including the import lineage rule that keeps a foreign journal visible to Health, the one-shot reminder window, day-anchor rollover and the cold-launch activation that runs the blind-zone decay, the widget snapshot, its backward compatibility and the per-day timeline words, the variation-debut badge and the performed movement that feeds it, the quiet training-run signal derived from the journal, the care note's acknowledgement and its tolerant decode, share-card wording and its level curve, cool-down composition, the get-ready transition, its floor-and-wall supplement and the minutes both blocks fit into, the way back in from a pause, rest extension up to its cap, the easier-variation handle and the result it promises, the skip inside the workout — the order it reaches the engine in, the floor below which it becomes a skipped movement, and the minutes it takes off the number on screen, the per-set facts and the asymmetric rule that carries a shortfall forward but never a surplus, the progress chart's gap band and the line that may accompany it, the jubilee's then-and-now comparison, the life-benefit override, and the plan recorded when it reaches the screen so a descent stays honest against a plan that was only looked at |
| UI tests | 57 | the full workout flow, in-workout adjustment, hold mis-tap grace, resume after a kill, the three exit paths, skipping a set and the rest of a movement, the cool-down, the side-switch pause, the get-ready transition, pausing and resuming a guided block, both guided blocks asking before they start, pulling the variation handle and seeing the plan redraw, extending a rest, position technique sheets, history, relaunch persistence, and the release smoke walked end to end in English and Russian |

Plus [TESTPLAN.md](TESTPLAN.md): a manual QA checklist (locale passes, date rollover, backgrounding during rest, device-only integrations) and a registry of found issues with their status.

CI runs the unit suites on every push — that is the gate for merges and releases. UI tests are slow and occasionally flaky on shared runners, so they run nightly on their own and gate nothing; they are run locally before cutting a release branch instead.

## Building

1. Open the Xcode project (iOS 17+, Xcode 15+).
2. The `DredfitCore` package is local — add it via *File → Add Package Dependencies → Add Local* if not already linked.
3. `⌘U` on the package first: golden tests are the gate.
4. Run on any iPhone simulator. UI tests expect an English locale and drive the app through DEBUG-only launch flags — `--uitest-reset` for a clean slate, `--uitest-fast` to collapse rest countdowns, `--uitest-long-transition` to hold a "Get ready" transition open so the tests that tap it are not racing its ten seconds, and a few that seed a specific state (`--uitest-milestone`, `--uitest-comeback`, `--uitest-comeback-long`, `--uitest-restday`, `--uitest-onboarding`, `--uitest-weak-link`, `--uitest-handled`).

## Localization

English is the source language; Russian, Spanish, Brazilian Portuguese, German, French and Italian each ship complete — 563 translated keys across four String Catalogs, including all exercise technique. English base strings live inline at each call site; translations live in the catalogs. Every translation is idiomatic rather than literal: Russian avoids anglicisms and calques and uses `е` rather than `ё` throughout; Spanish, Brazilian Portuguese, German, French and Italian address the reader informally (`tú` / `você` / lowercase `du` / `tu`) and take their exercise and pattern vocabulary from the same glossary as the [marketing site](https://dredfit.com/), which ships in the same seven languages.

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

Shipping. Working on device, tested across all seven locales.

Planned work and deliberately-rejected ideas are tracked in the project backlog (`instructions/BACKLOG.md`, kept alongside the engine specification outside this repository).

## Disclaimer

Dredfit is a general-fitness tool for healthy adults, not medical advice. Sharp or joint pain means stop; consult a physician before starting if you have cardiovascular or joint conditions.
