# Dredfit

[![CI](https://github.com/dredfort42/dredfit/actions/workflows/ci.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/ci.yml)
[![Lint](https://github.com/dredfort42/dredfit/actions/workflows/lint.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/lint.yml)
[![Localization](https://github.com/dredfort42/dredfit/actions/workflows/localization.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/localization.yml)
[![CodeQL](https://github.com/dredfort42/dredfit/actions/workflows/codeql.yml/badge.svg)](https://github.com/dredfort42/dredfit/actions/workflows/codeql.yml)

[dredfit.com](https://dredfit.com/) · [App Store](https://apps.apple.com/app/id6791739610)

**Adaptive bodyweight training for iOS. Zero setup — open the app, your workout is ready.**

Dredfit works like a thermostat. There is no quiz, no goal picker, no timer settings. The app starts you at a conservative minimum and regulates itself: it proposes a plan, you do it, you answer one question — *how did it go?* — and the next workout adjusts. Tell it what you actually managed on the first workout and it lands on where you actually are right away; answer with a rating alone and it converges over a handful of sessions. Either way it then keeps the load right at the edge of what you can do, which is where progress happens.

No equipment required. No account. No network. Your entire training state is a session counter plus, for each movement pattern, the variation you are on, the dose you do, a body weight if you have given one, and a short journal of what you have actually shown — on your device.

## How it works

The engine (`DredfitCore`) rests on one principle, stated in a sentence: **the
engine does not predict — the engine measures.** Nothing can be assigned that
you have not already done. Every number in your plan is either something you
showed, or that same thing plus one rep in one set. Everything below follows
from that.

**A position is a variation and a dose.** There is no single number per movement
and no arithmetic that derives one from another. What a movement has is what you
can point at: *which* variation you are on, *how much* of it per set, and *how
many* sets — plus a journal of the doses you have actually shown in each
variation. That journal is what a descent lands on. Not a floor: the last dose
you really did.

```text
squat   variation 3 of 6   3 × 9      journal: v1→15, v2→13, v3→9
pull    variation 2 of 7   9-8-8      journal: v1→15, v2→8
core    variation 1 of 5   3 × 30 s   journal: v1→30
```

Reps run 4…15 in steps of 1, holds 15…45 s in steps of 5. Sets start at 3, and
bands of 4 and 5 exist only on the top variation of a ladder; two is the floor.
A growth step lands on **one set**, not on all of them — `3×8` becomes `9-8-8`,
then `9-9-8`, then `3×9` — so overshooting costs one rep in one set instead of a
whole variation.

**The probe: you try the next movement before it becomes your plan.** When the
dose reaches the top of the grid, the **last working set is replaced** by one
set of the next variation, at 4 reps or 15 seconds. A replacement, not an extra
set, so the session does not get longer for trying. Manage it and the next
workout starts you there at 3×4. Fall short or skip it and nothing moves — the
working sets still count and the probe comes round again. A failed probe is
information, not a failure, and the app says so on screen.

**The ladders are built so no rung is a leap.** 59 positions across 10 patterns,
four to seven variations each — the lengths genuinely differ, four for lunges,
seven for the hinge. The rule is written down and checked by a number: the load
of one position may not exceed the previous by more than **×1.5**. Across the 48
comparable boundaries of the shipped library there are **zero gaps**, and the
largest step is ×1.49. Every position's difficulty is stated in the spec with
its provenance rather than falling out of an encoding.

**Deterministic rotation.** Every session has 6 exercises. One slot is always a
pull, for shoulder health — the tested invariant is that weekly pull volume
stays at least 70 % of combined pushing volume. The other 8 patterns rotate
through the remaining 5 slots so that over any 8 consecutive sessions each
appears exactly 5 times. No randomness anywhere: the same state always generates
the same workout.

**A feedback regulator.** After the workout, one tap: *tough / on plan / easy* →
−1 / +1 / +2 steps for the session's patterns. "Easy, could do more" is the one
rating that claims more than the plan, so it is offered only for a plan done in
full; honesty downward is never gated. During the workout you can record a
per-exercise actual that outranks the rating for that pattern — and when your
sets show more than the plan, the next plan starts from what you showed. Upward moves are capped
at two steps per workout, and at one wherever the tissue doing the work needs
the slower pace. Three consecutive shortfalls trigger an automatic deload (−3).
A skipped exercise is neutral: its position and streak are left untouched rather
than judged. When a movement is too much today, the answer is a handle rather
than a diagnosis: *give me an easier variation* drops it a rung, landing on the
largest dose the journal says is no more work than you were already doing. It
lives on the movement's own card, one tap from the plan, and it asks before it
acts — the way back up a ladder is a probe, not a tap. Offered before a workout
and not during one: a session is fixed when you start it. Inside the workout you can also skip a set or the rest of a movement
without being judged for it. The app never asks where it hurts,
and it never quietly removes a movement for weeks. Time is the one input that
isn't a tap: a week away eases every pattern down a step without saying anything
about it, and past two weeks the app offers to meet you lower still — the longer
the break, the further down, and never below something you have actually done. A
*regular* long cycle is not a break: the engine reads a rhythm from your last
eight intervals, so coming every ten days is read as a cycle rather than as ten
days off.

**The pull-up bar module.** Vertical pulling is the one honest gap of a
no-equipment format. Turn the bar on in settings and every other session swaps
the floor pull for a vertical one — its own seven-rung ladder from a bar hang
through scapular pulls and assisted negatives to a full pull-up, tracked
independently. Turn it off and the branch freezes without losing progress. It is
also the one boundary in the whole library where the unit changes, from seconds
to reps, and it is crossed **only** by a probe: seconds and reps were never
comparable, and the old engine's rule for comparing them is deleted.

**A clean start takes about 32 minutes**, and can be cut to about 24 from inside
the workout. Everything grows from there; a topped-out session is around 96
minutes, or 41 cut to the floor. Warm-up is 6 positions from a pool of 9 and
runs 255 to 260 seconds: four moves of the pool have a halfway boundary their
own steps name — two are done one side at a time, two are circles that reverse —
and each splits its slot in half with a counted pause between the halves. The
cool-down picks 6 of 9 the same way, half of them from what you just trained.

## The app

SwiftUI, iOS 17+, iPhone, portrait. Three tabs, a settings sheet reachable from all of them, and one flow:

- **Today** — the generated plan and one Start button, with nothing to agree to first: the line above says how long the full workout takes and how short it can be made from inside it, and tapping a movement opens its card — technique, common mistakes, what it is for in life, and the variation one step below it. A completed state once you're done, with a card for the next workout. If a session was cut short by iOS reclaiming memory or a swipe-kill, this is where it is offered back.
- **Workout** — warm-up, then one exercise at a time: a big number, set dots, a date-based rest ring with a 3-2-1 audio countdown, a hold timer for static exercises, in-the-moment actual adjustment for sets of reps, and the decision about the length of the session: skip this set, or the rest of a movement's sets — each asked before it happens, because a workout has no undo — with what is left of the workout on screen, recalculated as you go. A hold exercise costs **one tap**: **Start exercise** runs the whole movement, each set counting itself in when its rest ends, so the phone is not touched again until the movement is over. The one thing that screen takes beforehand is the time on the clock — **Set the time** raises it, or lowers it on a day when the plan is too much — and it governs every set of the exercise; a set cut short still governs the sets after it, capped by what was set. During a hold the primary control names the figure it will write (**Stop · 60 s**), less a stated three-second allowance for the walk to the phone, because a tap lands after the effort has stopped; inside the first three seconds it names nothing, because that tap cancels the set. Unilateral holds get a counted pause to switch sides and run both sides from the same number. When the movement is behind, every one of its sets is on one screen with any of them one tap from correction — the first time a set other than the last could be corrected at all — and a set that ended under a thumb says so with a **≈**. A cool-down closes the session before the rating — six stretches, half of them chosen from what you just trained. Every position of both guided blocks opens with a ten-second "Get ready" naming what is coming — fifteen where you have to get down to the floor or reach a wall — skippable by a tap for anyone already in place, a move or stretch with a halfway boundary runs half its slot at a time, with a counted pause and a tone of its own at the switch — and the words follow what is actually switched, a side or a direction, and every timed screen of those blocks can be paused — the doorbell is not a reason to pretend a stretch happened, and resuming counts you back in before continuing from the second it stopped on. Every start tap buys a five-second count-in before the clock under your thumb starts moving, so nothing jumps up while your hand is still leaving the glass — a rest cut short by hand included; a set the run opens by itself needs none, because the rest before it is the lead-in and ends on the go that starts the hold. That rest is also the one clock in the workout that acts without you, so it is the one that can be paused: everywhere else the app is waiting for a tap, and stepping away costs nothing. Every countdown is wall-clock based, so locking the phone mid-rest loses nothing — and the position is snapshotted on every transition, so neither does losing the process. Leaving asks first, and offers to finish early rather than discard.
- **Rating** — the one question on three equal cards, with an honest summary of anything you adjusted, skipped or left unfinished. “Easy, could do more” dims when anything fell short, with one line under the three saying why: it is the only rating that claims *more* than the plan, so the plan has to have been finished for it. Honesty downward is never gated.
- **Calendar** — filled days are tappable history (what you did, with actuals and skips); *upcoming* planned days are outlines; today gets an accent ring; rest days a quiet fill; missed days are left as plain dimmed numbers, deliberately unmarked and unshamed.
- **Progress** — total steps, a line chart across sessions with per-pattern projections, a weekly summary, and a bar per pattern measured along **its own** ladder, with its own denominator and a tick where each variation begins. Ten ladders of genuinely different lengths share no single axis, because one would be a fiction. A workout recorded before the ladders were rebuilt says it has no number on this scale rather than inventing one.
- **Settings** — rest days, the pull-up bar, sounds and haptics, a reminder on training days, Apple Health (export, a body weight kept in step with Health, and a switch that leaves calories out — for a watch recording the same workouts, or for no estimate at all), backup export/import.

Beyond the app itself: **widgets** in every size — small, medium and large on the home screen, all three lock-screen accessories — showing workout / done / rest day and flipping at midnight without the app running; a **Live Activity** that puts the rest countdown on the lock screen and in the Dynamic Island, **Apple Health** (completed workouts become functional-strength-training samples carrying an estimated active-energy figure; weight, height, age, sex and resting energy are read on the device to compute it, and workouts are read to cancel it when another app recorded the same session — nothing is transmitted), and **local reminders** on training days.

State is one JSON file in Application Support. Old records survive every update — new fields are optional and record-level decoding means one unreadable entry cannot discard the file. The one structural change the engine has made, the move off the level scale, carries a saved plan across positionally rather than starting anyone over: 470 of the 480 possible positions land no heavier than they were, and the ten that don't are holds coming *up* to the shortest hold the app now offers (re-swept against the shipped 3.3.0 reference; unchanged). Backup export/import round-trips the whole thing as plain JSON.

## Architecture

```text
DredfitCore/            Swift package — the engine, pure functions, no UI imports
  Engine.swift          state → session; state × session × feedback → state
  SubStep.swift         a position and its measure: variation, sets, dose,
                        sub-step, cut — and the ordinal that counts growth
                        events from the bottom of a ladder (no inverse, §40.3)
  Dose.swift            the two grids: reps 4…15 by 1, holds 15…45 s by 5
  Session.swift         rotation, slots, the cuts and their one fixed order
  Feedback.swift        ratings, per-set facts, the probe's verdict
  Descent.swift         where a rating lands a pattern — on the journal, never
                        on a floor
  Breaks.swift          silent decay, comeback, the rhythm window
  Handles.swift         the athlete's controls — the engine entry points
  SetsHandle.swift      the second axis of a position ("less of it")
  MigrationV2.swift     the positional v2 → v3 carry-over (§41.7)
  Library*.swift        59 positions across 10 patterns, 4–7 variations each,
                        hand-written to mirror the JS reference
  WarmupTechnique.swift the warm-up pool's technique
  EngineState.swift     the persisted state, decodeLenient, the sanitizer
  Resources/            String Catalog (en source; ru, es, pt-BR, de, fr, it)
  Tests/
    EngineTests.swift      invariants: rotation, balance, deload, caps, skips
    EngineV3Tests.swift    positions, the probe, the journal, entry at 3×4
    DescentSweepTests.swift  a descent never lands heavier — swept, not spot-checked
    LibraryPinTests.swift  the 59 variation identities pinned by value
    GoldenTests.swift      bit-for-bit match against the reference implementation
    ManifestTests.swift    the fixture's provenance
    Fixtures/golden.json

Dredfit/                SwiftUI app target
  AppStore.swift        the only mutable state + JSON persistence; split by
                        extension (+Cadence/Calendar/Comeback/Handles/Signals/
                        Health/Reminders/Backup) — every mutating decision
                        stays in AppStore.swift proper
  HealthStore.swift     HealthKit bridge, stateless: writes the workout and
                        its energy sample, reads the five values the estimate
                        needs plus the workouts that cancel it
  EnergyEstimate.swift  what a session costs — segmentation, the MET table and
                        the three-rung resting ladder; pure, nonisolated
  LiveActivityController.swift, WidgetBridge.swift
  Views/Today/          plan rows, length, comeback and migration cards
  Views/Workout/        the flow, its chrome, warm-up, cool-down, block pause,
                        rating, milestone, technique
  Views/Progress/       progress, calendar, history, share card
  Views/Settings/       settings, onboarding, "How it works"
  Design/Theme.swift    ink scale + one accent (and its soft tint)

DredfitWidgets/         widget extension — TodayStatusWidget, RestLiveActivity
Shared/                 the App Group snapshot contract

docs/                   the dredfit.com site — GitHub Pages, static, no build
  index.html            landing + privacy.html, mirrored under ru/ es/ pt-br/ de/ fr/ it/
  CNAME, robots.txt, sitemap.xml, og.png
```

The engine was first written and verified as a JavaScript reference, then ported
to Swift. The reference suite currently runs **74 772 property checks with 0
failures**, alongside an acceptance script of 20 blocks and a model sweep that
walks **59 264 transitions** without once assigning more than "what you showed,
plus one". `golden.json` is the reference's recorded trace — **28 scenarios, 282
steps**, stamped `adaptive_engine.js v3.3.0` — and the Swift port must reproduce
it exactly. Changing engine behavior means changing the spec first, then the
reference, re-verifying, regenerating fixtures, then porting. Plausible-but-
different is a failing test, not a judgment call. (The JS reference lives
outside this repository; the recorded fixture is what ships.)

## Testing

Three layers, 657 automated tests: 70 core + 513 app units + 74 UI tests, all confirmed green on this wave's run — core `[70/70]`, app units `Executed 513 tests, with 0 failures`, and UI a single `** TEST SUCCEEDED **` with no `Failing tests:` section and zero runner relaunches, so the closing tally belongs to the one session that ran (`Executed 74 tests, with 0 failures (0 unexpected) in 2670.6s`, simulator erased before the run).

| Layer | Count | What it covers |
| --- | --- | --- |
| Core invariants + golden | 70 | rotation properties and the pull:push balance, the growth caps per movement, deload timing, skip semantics, bar-branch independence, lenient state decode and the sanitizer, feedback replay safety, the silent decay and its non-stacking with the comeback, the rhythm window, the probe (offered only off the journal, resolved at 4, entering at 3×4, and never lengthening the session), a descent swept across every ladder for "never heavier", the positional v2 → v3 carry-over, the 59 variation identities pinned by value, the fixture's provenance manifest, and a bit-for-bit replay of the reference's recorded trace |
| App unit tests | 513 | persistence round-trips, corrupted-file quarantine, a frozen journal and its reload, legacy-record migration, in-progress snapshot validity, rest-day calendar math, Health export ordering and idempotence including the import-lineage rule, the one-shot reminder window, day-anchor rollover and the cold-launch activation that runs the blind-zone decay, the widget snapshot with its backward compatibility and per-day timeline words, the variation-debut badge, the quiet training-run signal derived from the journal, the care note's acknowledgement and tolerant decode, share-card wording, cool-down composition, the get-ready transition and the count-in before every clock, the way back in from a pause, rest extension up to its cap, the easier-variation handle — the result it promises, that reading it writes nothing, and the one boundary in the library where the step below changes the unit — the line that says where that handle lives and the flag that spends it, the skip inside the workout — its order into the engine, the floor below which it becomes a skipped movement, and the minutes it takes off the number on screen — the per-set facts and the asymmetric rule that carries a shortfall forward but never a surplus, the probe's channel from the screen to the engine, the gate that keeps "easy" for a plan done in full, the progress chart's gap band and the axis drawing every date it asks for, the jubilee's then-and-now, the life-benefit override, the guard that no catalog entry may equal its own key in any language, the plan recorded when it reaches the screen so a descent stays honest, the time a declared hold runs for and the writer that changes one set without truncating the rest, the workout snapshot's hold fields and their absence in a snapshot written before them, what the probe showed — kept in the journal and read back, clamped like every other stored number — and the history line built from it, which takes its verdict from the position the session ended on rather than from a second copy of the pass rule, and the Health calorie estimate — its segmentation, the resting ladder and the order it degrades in, the plan as a ceiling over the wall clock, the guided blocks charged for what they ran rather than what they promised, the rule that no work means no calorie, and the revision stamp that any change to the model has to move |
| UI tests | 74 | the full workout flow, in-workout adjustment, one tap running a whole hold exercise, the time set before a hold — its survival of a kill, of a skipped set, and its ABSENCE from the movement after it — the exercise summary and the correction of a set that is not the last, hold mis-tap grace, resume after a kill, the three exit paths, skipping a set and the rest of a movement, the cool-down, the side-switch pause, the get-ready transition, pausing and resuming a guided block, both guided blocks asking before they start, the plan carrying no per-movement handle at all, the variation handle in the technique sheet — absent on the bottom rung and inside a running workout, asking before it acts and redrawing the sheet and the plan when it does — extending a rest, position technique sheets, history, relaunch persistence, onboarding, the comeback, and the release smoke walked end to end in English and Russian |

Counts are what the runners execute: `swift test` on the package, and the app
target with `-skip-testing:DredfitUITests`. The first two are green on
`develop`; the UI suite is slow, occasionally flaky on shared runners, and gates
nothing — see the register below for what is known red in it.

Beyond the automated layers the engine has its own gate chain outside the repo,
run by `python3 scripts/check_engine_gates.py`: the reference's property suite,
an acceptance script, a model sweep, a static audit, and the fixture manifest.
The runner exists because three of six gates once died before their first check,
which reads exactly like passing.

Plus [TESTPLAN.md](TESTPLAN.md): a manual QA checklist (locale passes, date
rollover, backgrounding during rest, device-only integrations) and a registry of
found issues with their status.

CI runs the unit suites on every push — that is the gate for merges and
releases. UI tests run nightly on their own and gate nothing; they are run
locally before cutting a release branch instead.

## Building

1. Open the Xcode project (iOS 17+, Xcode 15+).
2. The `DredfitCore` package is local — add it via *File → Add Package Dependencies → Add Local* if not already linked.
3. `⌘U` on the package first: golden tests are the gate. From the command line the package needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, because `xcode-select` points at the Command Line Tools.
4. Run on any iPhone simulator. UI tests expect an English locale and drive the app through DEBUG-only launch flags — `--uitest-reset` for a clean slate, `--uitest-fast` to collapse rest countdowns, `--uitest-long-transition` to hold a "Get ready" transition open so the tests that tap it are not racing its ten seconds, `--uitest-hold-short` / `--uitest-hold-long` to seed a hold's planned length at either end of its corridor, and a few that seed a specific state (`--uitest-milestone`, `--uitest-comeback`, `--uitest-comeback-long`, `--uitest-restday`, `--uitest-onboarding`, `--uitest-session2`, `--uitest-long-session`).

## Localization

English is the source language; Russian, Spanish, Brazilian Portuguese, German, French and Italian each ship complete — 723 of 728 keys translated across four String Catalogs (378 app + 329 core + 18 widgets + 3 InfoPlist) — five keys are exempt from the check, not identical across languages: two `%lld` placeholders marked `shouldTranslate: false`, `CFBundleName` and ` · %@` genuinely are identical everywhere, but `on %@` is translated in four languages (`de: "am %@"`, `es: "el %@"`, `fr: "le %@"`, `it: "%@"`) and only missing in ru and pt-BR, where `AppStore.nextTrainingDateLabel` composes the phrase in code instead of the catalog; `check_localization.py`'s own exception list only names three of the five, so the gate is green without seeing all of them. All exercise technique is translated. English base strings live inline at each call site; translations live in the catalogs. Every translation is idiomatic rather than literal: Russian avoids anglicisms and calques and uses `е` rather than `ё` throughout; Spanish, Brazilian Portuguese, German, French and Italian address the reader informally (`tú` / `você` / lowercase `du` / `tu`) and take their exercise and pattern vocabulary from the same glossary as the [marketing site](https://dredfit.com/), which ships in the same seven languages.

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

Shipping. Working on device, tested across all seven locales. The App Store carries 1.9.0; the engine on `develop` is 3.3.0, and the wave that ships it has not been released yet.

Planned work and deliberately-rejected ideas are tracked in the project backlog (`instructions/BACKLOG.md`, kept alongside the engine specification outside this repository).

## Disclaimer

Dredfit is a general-fitness tool for healthy adults, not medical advice. Sharp or joint pain means stop; consult a physician before starting if you have cardiovascular or joint conditions.
