# Changelog

## Unreleased

### Side-switch pause for timed unilateral work (issue #35)

- Unilateral cool-down positions no longer ask you to count the side switch
  yourself: 15 s for the first side, a 5-second "Switch sides" pause, then
  15 s for the second — an app that gives audio cues even to the warm-up
  now counts the switch too. The pause rides on top of the reserved three
  minutes, within the "≈" every estimate has always carried; `cooldownMin`
  and the golden fixtures are untouched.
- Per-side holds run the same pause between sides, and the second side now
  starts itself on the usual go-tone — no tap needed with hands busy in a
  side plank. The recorded actual is still the smaller of the two sides,
  and the mis-tap grace on a stopped side still returns the set.
- The pause opens with its own signal — the go-tone inverted, a falling
  two-tone — so eyes-closed stretching can tell "switch sides" from "new
  position"; a medium haptic mirrors it under silent mode. The usual 3-2-1
  ticks precede the end of each side; none play inside the pause.
- One shared app-layer constant (`sideSwitchPauseSec = 5`), deliberately
  not a user setting. Per-side rep exercises are untouched — they are
  self-paced.

### How much rest is enough (issue #36)

- Fresh installs now start with two spread-out rest days (Sunday and
  Wednesday) instead of Sunday alone. Six strength sessions a week is ~3.7
  hits per movement pattern — overuse territory for slow-adapting connective
  tissue; five sits at the top of the safe corridor. Existing installs are
  untouched: a stored settings file keeps whatever week it has, including
  one written before the key existed.
- "How it works" gained a "Weekly rhythm" section: 3–4 workouts a week is
  the sweet spot — muscle adapts in weeks, tendons in months, and rest days
  protect the slower half.
- The rest-day picker in Settings carries the one-line recommendation
  ("2–3 rest days a week") — guidance, not a gate: any spread still works.
  The six-day default also quietly contradicted the no-guilt philosophy;
  this closes the cheapest known strike at the engine's uniform-feedback
  weakness by lowering stress frequency itself.

### The cool-down the estimate always promised (issue #28)

- Every "≈ N min" estimate since 1.0 has reserved three minutes for a
  cool-down that did not exist. Now it does: six stretch positions × 30 s
  between the last exercise and the rating — the block materialises exactly
  the minutes already promised, so no estimate anywhere changes.
- Composition is deterministic from what was actually performed: hip flexors
  and chest-and-shoulders first, three positions mapped from the session's
  movements (deduplicated, topped up from a pool of nine), the rest pose
  always last. A short workout stretches its three performed movements.
- Same manners as the warm-up: per-position skip, whole-block skip, wall-
  clock countdown that absorbs backgrounding. Per-side positions take one
  30 s slot with a "15 s per side" hint.
- Honest edges: "Finish now" goes straight to the rating (whoever cut the
  workout short is out of time by definition); a workout of pure skips gets
  no cool-down; process death during the block restores to the rating. The
  cool-down counts toward the duration written to Health — it is part of
  the workout.
- No levels, no journal entry, engine and golden fixtures untouched.

### A workout for the days there is no time (issue #27)

- Today offers a short version under Start: three of the session's six
  exercises, warm-up and cool-down included, around a third of the clock.
  The other three are recorded as honest skips — levels frozen, the counter
  and the rotation advancing exactly as they would have.
- Which three: the pull slot always (shoulder balance is not negotiable), the
  first movement of the current rotation window, and the lowest-level
  movement of what remains. Because the window shifts by three over eight
  rotating patterns, that anchor visits all eight within any eight
  consecutive sessions — nothing is starved even for someone who only ever
  trains short.
- The session is not regenerated: it is the same list Today shows, so an
  interrupted short workout resumes short, and its resume card counts "of 3".
- The choice is never remembered. Every day opens on the full workout, and
  nothing anywhere says "again?".
- The engine gained two read-only helpers (the rotation anchor and the
  duration estimate for a list of exercises) so the app layer holds no copy
  of either formula. Behaviour and the golden fixtures are unchanged.
- Along the way: the rating screen's summary now labels its lists separately
  — "Adjusted" only over adjusted rows, "Skipped" over skips — and says each
  thing once: skipped rows are dimmed names with no per-row echo of the
  header. The only per-row word left is "not finished" on a "Finish now"
  interruption, precisely because it differs from the header. VoiceOver
  still reads every row with its state.

### The jubilee remembers where you started (issue #26)

- Anniversary milestones ({10, 25, 50, 100, then every 50}) now carry a
  "Then → now" comparison with the first workout, built from the levelsAfter
  snapshots the journal has kept since 1.1: "Then: Knee push-up · 3×8 — Now:
  Push-up · 3×14", plus how long ago that first workout was (weeks, months
  from week nine).
- The movement shown is the one with the largest level gain; ties resolve in
  rotation order. Every number comes from the core's own encoding
  (`Level.decode`), so the v2.3 per-tier floors are respected and no level
  arithmetic lives in the app layer.
- The milestone share card carries the same two lines — still no body
  metrics, no names; the level curve gives up room rather than crowding the
  footer.
- Honest degradations: a journal without snapshots, a history without growth,
  or a bar module younger than the first snapshot simply show the jubilee as
  before. Standing still is never dressed up as progress.

### The "why" behind every movement (issue #25)

- Every technique sheet ends with an "In life" line translating the movement
  into everyday ability — "lifting a bag, a child, a suitcase — with your
  hips, not your lower back". The app explained *how* since 1.0; this is the
  first time it says *why*.
- The "New variation" milestone carries the same line under the variation
  name: an unlock reads as an ability gained, not an index incremented. Set
  bands and jubilees are deliberately left alone — volume and habit are not
  abilities.
- A closed list of four standout variations (pistol squat, push-up, pull-up,
  chest-to-wall handstand push-up) overrides the movement line where the
  variation says more than the movement. The override → base rule lives in
  one place (`LifeBenefit`), shared by both surfaces.
- Copy discipline, enforced in review rather than code: every line is a fact
  of mechanics, never a health promise. 15 new keys × 4 languages; the
  engine, the state format and the golden fixtures are untouched.

## 1.7.1

A fix release: signals you can actually hear, reminders that know the workout
is already done, and a journal that is never overwritten by a launch that
could not read it. No new features; the engine, the state format and the
journal format are untouched, so there are no migrations.

### Countdown and reminders

- The 3-2-1 countdown and the tone at zero play at **media** volume through an
  ambient audio session. They used to be the system Tink/Tock sounds, which
  follow the *ringer* volume — routinely near zero while music plays at full
  volume, so the signals drowned exactly when they were needed. They still mix
  with whatever is already playing instead of pausing it, and the silent
  switch still mutes them (haptics remain the silent-mode channel).
- The audio session is primed when the workout opens, so the first tick is no
  longer the one that pays for warming it up.
- Reminders are one-shot notifications per upcoming training date within a
  28-day window instead of a weekly repeating series. A workout finished in
  the morning takes tonight's reminder down with it, tomorrow's still stands,
  and every activation slides the window forward.

### Data safety

- A state file that exists but cannot be read — data protection before the
  first unlock, a transient I/O failure — now freezes persistence instead of
  starting empty and overwriting the journal on the next save. The scene
  becoming active retries the read and unfreezes it. While frozen the app
  never shows the first-run onboarding, never publishes an empty widget
  snapshot, leaves the pending reminder window untouched, and refuses to
  export or import a backup — an empty file that looks like a backup is how
  a scare turns into real data loss. A launch the user has already worked in
  stays frozen: swapping the journal in mid-session would erase what they
  just did and leave the workout unable to record itself.
- Apple Health export: the backfill re-checks the toggle between records, so
  switching Health off stops it; it flags a record by identity instead of by
  an index captured before the save, so an import that replaces the journal
  mid-export can no longer mark the wrong workout; and the exported duration
  is clamped to at least a minute, because HealthKit rejects an interval that
  does not move forward and one bad record used to block the whole tail.
- The backup file is built when the user actually shares it, instead of being
  rewritten into the temporary directory on every settings and engine change.

### Site

- All four landing pages gained an FAQ section — free, offline, equipment,
  data, breaks, beginners — with matching FAQPage structured data.

### Housekeeping

- Version markers ("v1.5:", "v2.2:") are gone from code comments: the git
  history already records when a thing arrived, and a comment should explain
  the code as it stands.
- 182 → 198 automated tests: the frozen-journal launch and its reload, the
  work a reload must not overwrite, the widget snapshot and reminder window a
  frozen launch must leave alone, Health export under a journal that moves
  mid-flight, a disabled toggle mid-backfill, and non-positive durations. The
  Health suite moved into its own file.

## 1.7.0

Localization release: Spanish and Brazilian Portuguese join English and
Russian, each complete. The engine is untouched — no state, journal or
settings format changes, and no migrations.

### Localization

- Spanish and Brazilian Portuguese ship complete: every screen, all exercise
  technique and common mistakes, onboarding, settings, the widget and the
  Live Activity — 444 keys across four String Catalogs. Both address the
  reader informally (tú / você) and take their exercise and pattern
  vocabulary from the shared glossary; each reads as idiomatic rather than
  literal, and Spanish is neutral (no vosotros, no narrow regionalisms).
- Spanish and Portuguese count strings that always read plural now inflect:
  "1 completado" / "1 concluído", not "1 completados".

### Terminology

- English now separates the two senses that "step" used to carry — the
  exercise you do is a *variation*, the unit of level change is a *step*:
  "New step" → "New variation", "step N of 4" → "variation N of 4".
- Russian follows the same split: the rating captions moved from "+1 шаг" to
  "+1 ступень" (вариация / ступень).

### Site

- The marketing site is now four languages (en, ru, es, pt-BR), served from
  `docs/`.

## 1.6.0

Design-audit wave (2026-07): the three findings that cost user trust —
workouts dying with the process, an Exit that could only discard, and a
rating screen that nudged toward "On plan" — plus a contrast pass.

### Workouts survive

- The flow snapshots its position (exercise, set, rest countdown, actuals,
  skips) into the state file on every phase transition. If iOS evicts the
  app mid-workout — or it is swipe-killed — Today offers "Continue the
  workout?" with "Start over" as the alternative for up to three hours.
  Completing, discarding or resetting clears the snapshot; a corrupt
  snapshot degrades to "nothing to resume" without touching the journal.
- The snapshot carries a fingerprint of the generated exercise list: a
  session number alone is not identity (the bar toggle and an accepted
  comeback regenerate a different session under the same number), and a
  mismatched snapshot is never offered. A snapshot with no actual progress
  (warm-up just ended, first set untouched) is not offered either — that
  launch gets the plain Start, warm-up included. A kill on the rating
  screen resumes onto the rating screen, not the last set.
- Snapshot writes deliberately skip the WidgetKit poke that every other
  persisted change makes: none of the widget's three states can change
  while a workout is running, and 35 reloads of identical content per
  session would spend the day's refresh budget for nothing.
- Exit now confirms when there is progress on the clock, and offers
  "Finish now": the remaining exercises are marked as skipped (keeping
  their level, as skips always did) and the flow proceeds to the rating —
  running out of time no longer means losing the workout. The exercise cut
  mid-way is labelled "not finished" on the rating summary; only fully
  untouched ones read "skipped". With nothing done yet, Exit still leaves
  quietly.

### Honest inputs

- The three rating cards carry equal visual weight. The filled "On plan"
  card read as "the correct answer is the middle one" — a nudge aimed at
  the regulator's only input. Order alone now carries the scale.
- "next: +1 rep" became "next: +1 step" (also in Today's and history's
  rating captions): a step up can be a new, harder variation, not a rep.

### Calendar

- Past days without a workout no longer wear the "planned" ring — they are
  plain dimmed numbers, as the header always promised. "Planned" is future
  only, and VoiceOver stays equally silent about missed days.
- The rest-day fill is a dedicated `restFill` token (#E2E3E6) instead of
  cardBG (1.07:1 — invisible on most real screens): quiet at cell size,
  still visible as the 13 pt legend dot, with an ink2 digit. The planned
  ring darkened from #D9D9DB (1.41:1) to ink3.

### Contrast pass

- New `accentText` token (#B44504, ≥4.5:1 on white) for accent-colored
  text: "actual N" in the workout, rating summary and history, "second
  side", the onboarding diagram. Rings, chart lines and dots keep #E8590C.
- Selected chips (pattern filter, rest-day picker) use ink text — accent on
  accentSoft was 2.91:1, and the fill plus stroke already say "selected".
- Informative captions moved from ink3 (2.35:1) to ink2: the first-run
  calibration hint (also bumped to 14 pt — it works exactly once), rest-day
  chip legend, Health and pull-up bar notes, "Your rating applies to the
  rest", skipped markers, empty states, the rest-day paragraph, the
  onboarding care note, "2 / 6" in the workout header, month chevrons.

### Smaller

- The app always opens on Today; the cold-start jump to the calendar after
  a completed workout is gone (Today's own "completed" state answers that
  launch, with the calendar card one tap away).
- One warm-up move can be skipped on its own ("Skip this move") without
  abandoning the whole block.
- Settings close with "Done" instead of "Got it" — settings are a place you
  act in, not a message you acknowledge.
- The Progress share button moved out of the top corner, where it floated
  beside the global settings gear pinned by a hardcoded mirror of that
  gear's metrics, into a labelled pill next to the totals it shares.

## 1.5.1

Hardening wave after a full-project review. No new features; the engine's
arithmetic is untouched (golden parity holds bit for bit).

### Data safety

- An unreadable state file is moved aside (`dredfit-state.corrupt.json`)
  instead of being silently replaced on the next save; one unreadable journal
  entry no longer discards the rest of the file; unknown engine patterns
  (e.g. after an app downgrade) decode leniently instead of wiping progress.
- Feedback replay protection: a session that does not match the engine's
  counter is rejected by both the engine and the store, so a crash between
  saving and clearing feedback can no longer advance levels twice.
- The UI-test hooks (`--uitest-*`) are compiled out of Release builds — a
  production binary can no longer be told to wipe its own journal.
- Persist failures are logged instead of swallowed.

### Apple Health

- Export is tracked per record instead of a high-water session number. A
  failed export can no longer be leapfrogged by a later success (previously
  that workout was silently lost to Health forever), "Start from scratch" no
  longer confuses the export bookkeeping, and "Only new ones" can no longer
  re-export old workouts after a reset.
- `finishWorkout` returning no workout without throwing now counts as a
  failure and stays retriable.

### Time and Live Activity

- Crossing midnight while the app sits in memory now refreshes Today, the
  calendar ring and the week summary on the next activation (previously the
  app could show yesterday's "completed" state with no Start button until a
  cold launch).
- A killed or crashed workout no longer leaves a frozen Live Activity on the
  lock screen: stale content dims, and the next launch removes orphans.
  Activity updates are serialized, so a quick "Skip rest" can no longer lose
  the race and leave a stale countdown.
- The warm-up absorbs backgrounded time instead of replaying one move per
  expiry; an accidental "Stop" in the first three seconds of a hold cancels
  the countdown instead of recording a 5-second set.

### UI, accessibility, localization

- Feedback and onboarding screens scroll at accessibility text sizes instead
  of clipping; workout "Exit", onboarding "Skip" and "Start from scratch" meet
  contrast requirements; rest-day and chart chips announce their selected
  state to VoiceOver; calendar days speak their date and state, and the month
  chevrons grew to full tap targets.
- The workout cover snapshots its session, so the rating screen no longer
  flashes the next session's data during dismissal; the share card renders
  only when its numbers changed; the review prompt waits out the dismissal
  transition instead of burning its 60-day stamp on a dropped request.
- History resolves exercise names in the current language; the calendar
  legend and grid use one planned-day color; the widget snapshot refreshes on
  every backgrounding; reminders re-request authorization after an import;
  Russian is registered in the project, the Health share purpose string is
  localized, and stale catalog entries are gone.

### Testing

- 142 → 161 automated tests: reminder scheduling (new injectable seam),
  corrupted-file quarantine, Health export ordering regressions, day-anchor
  rollover, Live Activity staleDate arithmetic, lenient decode, replay
  no-ops, config-integrity and golden-generator pins.
- The widget snapshot test injects its URL and runs on CI instead of
  self-skipping; sleep-based waits replaced with awaitable tasks; UI-test
  assertions that could never fail now target identified elements; the UI
  target retries on failure in the test plan.

## 1.5.0

Engine v2.3. Three changes to how the regulator behaves, aimed at the two
moments where the old model was worst: your very first workout, and your
first workout back after a break.

### Calibration — the first workout now counts properly

- A pointed number entered from a standing start sets the level outright
  instead of being capped at +2. Someone who does 3×20 against a 3×8 plan
  lands on their real load in one workout rather than about ten.
- The cap is unchanged everywhere else, a skip still outranks a number, and a
  number below the plan at zero leaves you at zero without starting a
  shortfall streak.
- The rating screen says so on the first workout, once, and only while no
  exact number has been entered.

### Coming back after a break

- Two weeks away or more, and Today offers to start a couple of steps lower —
  further down the longer the break, to a floor of eight steps at twenty weeks.
  Accepting recalculates the plan; declining leaves it exactly as it was. Either
  answer closes the question for that break.
- Shortfall streaks reset on return. Without that, the first hard session back
  would ride the old streak straight into a deload and drop the level twice.
- After half a year there is also a quiet option to start from scratch. The
  journal survives, and so does the pull-up bar setting.
- No push notification, no count of missed workouts, no apology asked for.

### Softer tier changes

- Reps and holds now start lower on harder variations, so moving up a tier is
  a step down in volume rather than a jump onto a harder movement at full
  reps. A pistol squat arrives at 5 per side instead of 8.
- Level arithmetic is untouched: same 48 levels, same deltas, same deload,
  same rotation. Tier 1 is identical to before.

### Copy

- Onboarding card 2 no longer promises the load "within two or three
  workouts" — it says the load becomes yours step by step. With calibration
  the old count is true only for someone who enters an exact number; the
  softer wording is honest for everyone. This deliberately changes the
  reference Russian text («и нагрузка шаг за шагом станет твоей»).

### Verification

- Reference: 4,150 property checks, 0 failures (was 3,223).
- Golden fixtures regenerated with two new scenarios (calibration, comeback).
  Every changed step in the existing fixtures was classified against the rules
  for what this change is allowed to move; nothing fell outside them.
- Core suite 38 → 56 tests, app suite gains the comeback and migration cases.

## 1.4.0

First experience and milestones. The engine is untouched in this release — the
adaptive core is identical to 1.3.0, bit for bit.

### First run

- **Onboarding.** Three cards on a fresh install, explaining the one thing the
  UI cannot show by itself: the plan moves because you answer, and the first
  workout is deliberately easy because it is a starting point, not a test.
  Skipping counts as seen.
- **"How it works"** — the first row in Settings. Six sections covering the
  level, what a rating does, deload, rotation, skips, and why there are no
  questionnaires. Every number in it matches the engine rather than rounding
  for the story.

### Milestones

- A workout that unlocks a harder variation, crosses into another set band, or
  lands on the 10th, 25th or every 50th session ends on one screen listing what
  it earned. Tier-ups above the jubilee, no confetti, no badges.
- Only upward movement is announced. A deload or a shortfall is never
  commented on.
- **Share card** — rendered on device at 1080×1350 and passed to the system
  share sheet: a milestone line, a date, the wordmark. No body metrics, no
  streak, no network. Also available from Progress as a totals card.

### Asking for a review

- One automatic trigger: closing a milestone screen, and only after five
  workouts, never following a session rated harder than planned, and at most
  once every sixty days. Settings gains an About section so a review can always
  be left on purpose instead.

### Accessibility

- Every screen honours Dynamic Type. The few display numbers that are already
  enormous by design scale to a cap rather than pushing the screen out from
  under themselves; the rest timer's ring grows with the countdown it frames.
- VoiceOver labels on the controls that were reading as bare symbol names, and
  decorative icons hidden from the rotor.

### Fixes

- A rest day showed a live plan with a Start button on Today while the widget
  said "Rest day" and the next-workout date skipped the day — three answers to
  one question. Today now agrees with both, and keeps a "Train anyway" escape
  hatch, because a rest day is the user's own setting.
- Rest days in the calendar carried no mark and read like days outside the
  month. They now have a soft fill and a legend entry.

## 1.3.0

Two development waves ship together: the engine work originally staged as 1.2.0 (which was never released) and the progress-and-integrations wave.

### Engine — v2.2

- **Level ceiling raised from 31 to 47.** Above tier 4 progression continues by adding a set instead of a variation: 3 sets up to level 31, 4 sets for 32–39, 5 sets for 40–47. The top of the system is now 5 × 15 rather than a dead end at 4 × 15.
- **Pull-up bar module.** An optional vertical-pull branch — bar hang, negative pull-up, partial pull-up, pull-up — with its own independent level. With the bar enabled, every other session swaps the floor pull for a vertical one. Turning it off freezes the branch without losing progress.
- Library grew from 36 to 40 exercises (10 patterns × 4 tiers), each with technique steps and common mistakes in both languages.
- Reference verification: 3,223 property checks, 0 failures. Golden fixtures: 7 scenarios, 113 steps, reproduced bit-for-bit by the Swift port.

### Progress and history

- **Level chart** across sessions (Swift Charts), with per-pattern projections and an "All" total view.
- **Weekly summary** — workouts and level delta for the current ISO week. A deload week honestly shows a minus.
- Per-pattern level bars, including the vertical-pull branch once it exists.

### System integrations

- **Apple Health** — write-only export of completed workouts as functional strength training. Nothing is ever read. Existing history can be backfilled; a high-water mark makes export idempotent, so a repeated backfill never creates duplicates.
- **Live Activity** — the rest countdown on the lock screen and in the Dynamic Island, ending automatically when the workout does.
- **Home-screen widget** — today's status at a glance (workout / done / rest day), flipping at midnight without the app running.

### Fixes

- Health export no longer advances its high-water mark on a failed save, so a failed workout stays retriable instead of being silently lost.
- Backfill stops at the first failure rather than marking the whole tail exported.
- Live Activity no longer races itself when a second workout starts right after the first.
- Progress chips and chart outlines use `strokeBorder`, so the outline is no longer clipped.
- The backup snapshot rebuilds when settings change while the sheet is open.
- Technique is reachable from the rest screen, not only from the plan.
- Russian strings normalized to use `е` rather than `ё` throughout.
- The widget extension's bundle version was stuck at 1.1 (build 2) while the app moved on; all four targets now ship the same version, which App Store validation requires.

### Documentation

- README rewritten to match the shipped product — it had been describing v1.0 (level range 0–31, 36 exercises, 4 golden scenarios). Two claims that were never true were also removed: the exercise library is hand-written rather than generated from a bilingual table, and the calendar does not mark rest days.
- TESTPLAN.md added: a manual QA checklist for what automation cannot cover — system integrations, wall-clock behavior, both locales — plus an issue registry.

## 1.1.0

- Honest skips (engine v2.1.1): a skipped exercise no longer inherits the session rating — its level and streak are left untouched.
- Hold timer for static exercises, with a 3-2-1 countdown; an early stop records the actual.
- Warm-up block; the screen no longer sleeps mid-workout.
- Settings: rest days, sounds and haptics, a reminder on training days.
- Local reminders, backup export/import, and a `levelsAfter` snapshot stored with each record.

## 1.0.1

- Privacy page restyled to match the landing page.

## 1.0.0

First release. Engine v2.1 (levels 0–31, 4 tiers, pull in every session), seven screens, local persistence.
