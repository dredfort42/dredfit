# Changelog

## 1.10.0

The longest release in the project's history, and the one that changed the
least about what you see. Three multi-agent audits of the engine and its
golden contour — 2026-08-11, 2026-08-16 and 2026-08-23 — confirmed findings
faster than any single wave could carry, so this release is the remediation
itself: the engine steps from **v2.5 to v2.26** in twenty waves, each a full
pass of the reference cycle (spec → reference → verifier → golden → Swift
port). The verifier grew from 9,367 property checks to 638,696 and then came
back to **443,415** when the last wave removed two mechanisms; the golden
fixture went from 11 scenarios to 28 and back to **24** for the same reason.
Every new field decodes tolerantly — the state and journal formats still need
no migrations.

What the waves are about, in the order the priority ladder puts them:

- **Do no harm.** A descent may never add load: the "not harder" gate now
  counts sides and stands on every path down, not one of three (v2.19), and
  the engine finally has a way to say *the same exercise, but less of it* —
  sets come off without touching the level, so a plan that has to go lighter
  can (v2.25).
  "Tough" steps back exactly the way it came, one position at a time
  (v2.23). A comeback lands no heavier than your last workout (v2.12), and
  the Swift port sanitizes anything a corrupt file hands it (v2.13). The pain
  channel was rebuilt three times across v2.19, v2.20 and v2.23 and then
  **removed** in v2.26, because the 2026-08-23 audit found it broken in four
  independent places at once — see that entry for what answers "this hurts"
  now.
- **Keep the habit.** A steady rhythm stopped being read as a break
  (v2.13), and the plan parks on what you can actually do instead of
  running ahead of it — growth adds one set's worth at a time (v2.22).
  In v2.26 the lighter plan of v2.25 became something **you** reach for: two
  handles on the plan, and a session length the app announces instead of
  enforcing. The
  45-minute default of v2.24 went with the enforcing — it is the last thing
  in this release that was built and taken back.
- **Improve results.** The aim reaches the weak link instead of the loudest
  movement (v2.15), honest facts are never scored worse than a tap (v2.14),
  the push plan stopped flickering (v2.16), the pull-up ladder gained the
  rung it was missing (v2.18), and hold ladders became per-tier tables with
  a one-second entry corridor, so a single second short costs a single rung
  (v2.21).

Three things were built and withdrawn inside this same cycle: **"hold this
level"** (v2.6, withdrawn v2.22), the **pain channel** in the shape v2.19–v2.23
gave it, and the **45-minute default** (v2.24, withdrawn v2.26). None of them
reached the App Store, and nothing in a saved file carries them forward. They
keep their entries below: a changelog that quietly deletes what it got wrong is
harder to trust than one that says so.

### Engine v2.26.0 — you decide, not the app (issues #149, #150, #151, #184, #99)

This is a wave of **removal**. Two whole mechanisms come out — the pain channel
and the time budget — and two handles go in. The reason is not taste. The
2026-08-23 audit put five P0 findings on the "do no harm" rung, and every one of
them was inside the machinery this wave takes out:

| What the person did | What v2.25 did about it |
|---|---|
| Tapped "it hurt here", honestly, twice | The episode never ended — 480 cells of 480. A rating of "on plan" ended it on the sixth appearance: the honest signal locked, the convenient one released |
| Tapped "it hurt here" and then "tough" | Dose left **above** where it was before the pain |
| Used the "I was ill" lens | Plan came out **heavier** in 76 cells of 400 — the exact opposite of the offer |
| Left the default 45-minute budget alone and answered "tough" | Plan came out **twice** as heavy (×2.00). With the budget off: ×1.00 |
| Nothing at all, for 7–13 days | The silent decay landed on a plan 2–6× heavier, 18 of those transitions inside a single variation |

Three waves and a half — v2.19, v2.20, v2.23 and half of v2.25 — had gone into
the pain channel. It was broken in four independent places, and the honest exit
from its states cost ∞. The budget was newer and no better: the rungs the app
offered were 10, 15, 20 and 45 minutes, and **10, 15 and 20 produced the same
plan**, while "20" missed its own target in 100 % of sessions.

**What replaces them is not a smaller version of the same idea.** The app stops
asking where it hurts and stops fitting the workout into a number you picked
once and forgot. It **says how long the workout will take** and gives you
handles. You decide.

- **"Give me an easier variation"** — the same movement, one rung down, and the
  button shows you the name and the dose you will get before you press it. It
  always leaves the tier: a handle that answers with the same exercise is a lie
  on a button.
- **"Fewer sets" / "more sets"** — one set off or back on a single movement, down
  to a floor of two. The floor moved from one set to two, and that is what made
  the first set back cost ×1.50 instead of the ×2.00 it cost by construction
  before.
- **"Fewer sets in every movement"** — the session handle, showing both numbers
  before you agree: *37 → 26 min*. Sets come off, movements never do.
- **"Fewer movements"** — the short workout is a handle too, and no longer a
  second start button under Start: three of the six, the other three recorded as
  skips that keep their level. It says *3 of 6 · ≈ 21 min*, and the three it sets
  aside are dimmed in the plan rather than hidden, because "3 of 6" has to be
  able to say which three.
- The two compose, and the screen says so by arithmetic rather than by prose: the
  line above counts what Start will run, and the sets handle prices itself inside
  the movements that are going to be performed. They used to sit at opposite ends
  of the screen under two anonymous offers of "shorter", with numbers that read
  as a contradiction because they were pricing two different workouts.
- All of them live **on the plan**, not inside the workout, so pressing one
  redraws the plan and the announced duration together. Inside the workout what
  remains is the honest number — "went differently" — and skipping.
- **The workout's controls are reachable.** "Went differently" is a 44 pt target
  with 18 pt between it and the button that logs the set: it was as tall as its
  own text, and a thumb that landed a few points high did not miss — it finished
  the set at plan. On the rest screen "+15 s" takes a third of the row and "Skip
  rest" two thirds, because the two are not asked for equally often.
- **A set comes back when strength does, not on a timer.** Answering "tough" or
  skipping never returns one.

**Level 0 is now a declared floor, not a hole.** The easiest workout the app can
build is three sets of eight in the gentlest variation of each of six movements,
about 34 minutes; the shortest it can build at all, with the handle pulled to the
floor, is **about 25 minutes**. There is no rung below tier 1 and there will not
be one. Two things follow, and both are said out loud rather than left to be
found: the "15-minute session" that Settings used to offer never existed at any
setting, and someone who has twenty minutes is better served by a different app.
The App Store description and the landing page now say so.

**What got worse, and by how much.** A wave that only tells you about the
simplification is an advertisement. Removing the budget removed the thing that
was keeping sessions short for people who never touched a setting, and the
person it costs most is the one training six times a week and answering "easy":

| | v2.25 | v2.26 |
|---|---|---|
| Median session, training 6×/week | **41 min** | **65 min** |
| Longest session on that trajectory | 45 min | **99 min** |
| Levels reached over the year | 423 | 423 — unchanged |

Nothing about their progress changed; the session simply stopped being trimmed
for them. The new dominant cost of the model is **inaction**: over an honest year
of three sessions a week from zero, someone who never touches a handle finishes
at level 34 with a 65-minute session, and someone who pulls it whenever the
number passes 45 finishes at level 28 with a 51-minute one — three sets given up
across the year. That is a choice the person now makes instead of the app, which
is the point of the wave, but it is a real price and it belongs here rather than
in a footnote.

Two more prices, both named with a number rather than left to be discovered:

- **At the floor of the scale, honest answers stop moving the plan.** Someone on
  level 0 answering "tough" every time sees the same plan for **124 appearances**
  (checked out to 200 sessions). Before the wave the worst blocking state cleared
  in 25. This is the direct consequence of declaring level 0 the bottom: below
  the bottom there is nowhere to go, and taking a set off down to the floor of
  two is the one step left.
- **The pull-up branch still drops to its floor** when a descent changes the unit
  from reps to seconds, because the library has no rung between the bar hang and
  negative pull-ups. Adding one requires changing how a level maps to a
  variation, which would have made this wave's parity unprovable, so it is the
  next wave's job. The gap is measured: at the tier boundary, level 7 gives 117
  seconds under load and level 8 gives 45.

**Guided blocks: the run-in doubles.** Five seconds to change posture was a rush
if the next position means walking to a wall or getting down onto the floor
(issue #83, reported from a real workout). The run-in before every position is
now **ten seconds**, fifteen where you have to travel, and the reserve for both
blocks grows from 8:00 to 9:00 to pay for it — 245 + 295 = 540 seconds into 540,
which is exact and asserted from the app's own constants rather than from the
spec's numbers. Both blocks now also **ask before they start**, saying how many
positions and roughly how many minutes, instead of dropping you into a countdown.

**"Went differently" belongs to the set you tapped it on — the rest of it.** A
number below the plan carries forward to the sets after it, and a number above
the plan stays on its own. Entering 40 on the first set of a planned 39 used to
tell the engine you did 40 three times on the strength of one; now it is
40/39/39. Everything at or below the plan is bit-for-bit what it was, swept
across every exercise × every set × every value.

**Everything else is deliberately identical, and that is the claim this wave is
checked against.** Against v2.25, on the axis's zero: the plan is bit-for-bit
equal across 96 cells, the shared state fields are equal after a session, and a
year of levels comes out within ±0.0 % on four different answering styles. The
one number that moved on purpose is the announced duration — **exactly one
minute** longer everywhere, which is the longer run-in above.

**Housekeeping.** 653 automated tests: 264 core + 334 app + 55 UI. The verifier
went from 638,696 property checks to **443,415** — fewer mechanisms, fewer
things to check — and the golden fixture from 28 scenarios to 24. The JS↔Swift
differential test was rewritten from trajectories to **12,300 isolated calls**
over 820 pre-states, and found the porting mistake a trajectory test had missed.
The engine itself is 2,664 lines where it was 3,142, with 16 state fields where
it had 23. `accept.js` — twelve checks that a wave kept the promises it was built
on — joins the verifier as a gate every release must run; `TESTPLAN.md` says what
each check asserts and why it is there. Saved files written before this wave open
untouched: the removed fields decode away, and the journal keeps showing the pain
reports it recorded, because a record that loses a fact is a record that lies
about the past.

### Engine v2.25.0 — the sets handle (issues #149, #150, #151)

The engine had no way to say *the same exercise, but less of it*. A level picks
the variation and the dose together, and at the floor of a block the dose is
already the lowest that variation has — so the only way down was to change the
exercise, and the top of the tier below is heavier than the bottom of the one
you are standing on. One root, and a whole class of "the plan had to go lighter
and went heavier instead" grew out of it. Measured on v2.24 across the whole
lattice, 10 movements × 48 levels:

| What the person did | Where the plan got **heavier** for it |
|---|---|
| Came back after a 7–13 day break | 48 cells of 480, worst ×6.50 |
| Tapped "it hurt here" | 24 — and nothing got lighter |
| Answered "tough" honestly, every session | all **48 levels** — the movement locked for good |
| Tapped "I was ill" | 40 |

Each of the four is **zero** in v2.25. What made that possible is a second axis:
sets. The level still chooses the variation and the dose per set; the new handle
takes **sets off the same exercise** — same variation, same dose, same unit and
sides — so a descent finally has somewhere to go that is comparable to where it
came from. 3→2 sets is −33.3 %, 4→3 is −25.0 %, 5→4 is −20.0 %, and no
measurement crosses a variation to say so.

**Do no harm.**

- **Pain takes sets, not levels.** Reporting "it hurt here" no longer moves your
  level at all. The first report of an episode lands the movement on 2 sets, a
  second on the live episode on 1. The depth deliberately does not read your
  history: a second tap two years and two hundred clean sessions later must not
  turn 5×15 per side into 1×15 — minus 80 % for one honest tap is a price that
  buys silence.
- **"I was ill" takes a share, not a set.** The lens now halves the band,
  rounding up — −33 % at L24, −50 % at L36, −40 % at L44. The old fixed one set
  gave the least to whoever was carrying the most: after flu, someone on a band
  of five was still looking at four sets of shrimp squats per leg.
- **A descent is checked, not promised.** Every plan is verified after it is
  built: if your position has not gone up and the work has, sets come off until
  it has not. Moving the session-length handle yourself is the one thing that
  lifts that cap, and only for one transition — your own decision outranks an
  old showing.
- **The plan is remembered when it reaches your eyes.** Until now the engine
  only wrote down a workout you finished, so a plan you looked at and did not
  train was invisible to it — and the next one could beat it by up to ×1.47, in
  16–22 % of "opened it, skipped a week, opened it again" on the 30- and
  35-minute settings. Today tells the engine what it showed. That was the last
  accepted gap of this wave, and it is closed.
- **A descent that changes the unit lands by time under load.** Going from reps
  to seconds on the bar picks the highest rung of the tier below whose time
  under load is no greater than what you are doing now — the one quantity that
  is defined for both. Where even the bottom rung is dearer, the branch lands on
  its floor and loses its level: safety outranks the number until the library
  gains the rung that is missing (×1.44 before, ×0.74 now).

**Keep the habit.**

- **A pain episode ends.** The rest and the "has it passed" countdown now run in
  **parallel** — they answer different questions, and running them one after the
  other meant no appearance was ever clean enough to close the episode. On
  v2.24 that was 480 cells of 480 where the episode never closed at all. It now
  closes on the 6th appearance at every one of the 48 levels, full volume is
  back on the 31st appearance instead of the 48th, and three reports cost 20
  appearances rather than 38 — under three workouts a week, 6.7 weeks instead of
  12.7.
- **Pain memory fades after 90 days, not 14.** A long break is exactly what
  someone in pain takes, so the old threshold made "this is worth showing to a
  professional" unreachable for the very person it was written for. The rest
  ladder — 3 → 6 → 12 appearances — reads how often this movement has hurt in
  your whole history, not whether an episode is open.

**Improve results.**

- **Volume comes back slowly, and the dose keeps moving.** At most one set
  returns per session, and the next no sooner than two appearances later. While
  that hold is ticking, growth goes into the dose instead. The axes are not the
  same size: a dose step is ×1.033 median and ×1.08 at worst, a returned set is
  ×1.500 median and ×2.00 at worst. §32 already refused a 50 % jump in dose on
  the ACSM's 2–10 % guidance; the hold makes the volume axis behave the same
  way, by letting the dose catch up between set returns.
- **A quiet decay steps down instead of dropping a level.** A break walks the
  same ladder the growth walks, rung by rung — the "not harder" gate failed 47
  transitions of 470 under the old whole-level step, 18 of them inside a single
  block, all of it happening before you have tapped anything.

Also in the app: two sentences in the exercise card, in all seven shipping
languages, saying why the plan is showing fewer sets and when one comes back —
no notification, no card, nothing to dismiss. And the line suggesting a
specialist now hangs on how many times a movement has hurt rather than on an
unbroken run of reports, which the 3 / 6 / 12 rest exists to break: nobody it
was written for used to reach it.

Rejected on the way, with numbers: **a share-based time budget**, where every
movement independently fits its own slice. Its promised "by construction"
invariant held only *inside* a band of sets, and a whole-level descent crosses
bands — 1,504 violations of 11,520 — while costing 8.7–21.0 minutes of thrown
budget and leaving only three distinguishable positions on a 15–95 minute
handle.

verify2: 638,696 checks, 0 failures (was 531,947). Golden: 28 scenarios and 331
steps, up from 22 and 272, with six new scenarios — pain sets, block-floor
decay, illness bands, the pull-bar unit change, the budget repair and the week
window. Of the 272 old steps 129 are bit-for-bit on the v2.24 key set and seven
whole scenarios are untouched; every one of the 143 that changed traces to a
named v2.25 decision, and the fixture now carries the growth window and the
six new fields in every scenario rather than gating them by scenario shape.
Port: 323 tests, 0 failures, GoldenTests bit-for-bit, plus a JS↔Swift
differential test over 10,000 trajectories. App: 343 tests, 0 failures.

### "Went differently" belongs to the set you tapped it on (issue #158)

The number you enter mid-workout is about the set you are standing in, and
the app recorded it for the whole exercise. Tap it on the last set of 3×15,
enter 10, and the engine was handed "10" — a full shortfall: level 7 down to
2, plus a tick toward a deload, although two of the three sets had been done
exactly on plan. A hold stopped early took the same path with no tap at all:
releasing at 30 s of a 39 s plank in the third set was recorded as 30 seconds
three times over. The one-set-short case was the worst of it — a single rep
missing on the last set cost a level and a streak tick where the honest
answer was a step forward.

- **Each set carries its own number.** A fact is written against the set
  under way; the sets already behind keep what they ran at. A number entered
  mid-exercise still carries forward to the sets that follow — that is what
  the screen shows and what a hold then counts down, so it really is what
  those sets ran at. Everything landing back on the plan is nothing said at
  all, exactly as correcting a number back to the plan always did.
- **The engine is told the volume you did.** The sets collapse to their mean,
  snapped to the step the movement is prescribed in: 15 / 15 / 10 reports 13
  and lands on level 5 instead of 2; 39 / 39 / 30 seconds reports 36 and
  lands on 6 instead of 4. One set a single rep short now costs no level at
  all — the mean lands within a step of the plan, the movement stands down
  and the session rating speaks for it, so an "on plan" tap ends at level 8
  with the failure streak reset where before it was level 6 and a tick
  toward an unearned deload.
- **A shortfall is never reported as meeting the plan.** Landing exactly on
  the plan says two things to the engine at once — take the "on plan" step,
  and confirm that a movement resting after a pain report has recovered
  (spec §18.1 and §21.2). A near miss rounded up onto the plan would make
  both claims on a session that fell short: it would promote out of a freeze
  the athlete who missed a rep, while the one who hit every rep reports
  nothing and never escapes it. So a mean that only reaches the plan by
  rounding reports nothing instead, and the rating decides.
- **The sets are shown as they ran.** The rating screen and the history row
  print "15 · 15 · 10" where the sets differed, and the single number where
  they did not — spoken as a plain list to VoiceOver, so nothing is shown to
  one reader and withheld from another.

The engine is untouched: its contract is still one honest number per movement
per session (spec §5), and the collapse happens in the app. Journals and
interrupted-workout snapshots written by earlier builds decode as they always
did — a single stored number simply means every set ran at it.

### A workout fits into 45 minutes unless you say otherwise (issue #136)

Dredfit never stopped making your workout longer. Train honestly three times a
week for two years and a session reaches 98 minutes — nearly five hours a week
of what was meant to be general fitness at home. There has been a handle for
this since 1.10, and it shipped switched off: it protected the people who went
looking for it in Settings and nobody else.

- **45 minutes is now the starting point.** It is not a compromise number: 45
  is the shortest budget at which all six movements still fit at every level,
  so it costs no progress whatsoever. Two years of the same honest training,
  measured with the budget and without it, ends on identical levels in all ten
  movements — only the clock differs: 98 minutes a session becomes 45, and 284
  minutes a week becomes 129.
- **Any answer you give is yours to keep.** Pick a length — including "no
  limit" — and that is what you get from then on, on this launch and every one
  after. The default only ever applies to someone who has not answered.
- **Starting your levels over no longer resets the clock.** Resetting progress
  used to hand back "no limit", a setting you never touched, from a screen
  about starting the levels again.
- If you have been using Dredfit already, one line on Today says the default
  arrived and where to change it. It goes away when you tap it and does not
  come back.

### Engine v2.24.0 — shorter workouts stop overshooting (issues #136, #147)

Two changes underneath the default above, and one to what the app calls a day.

- **A short workout gives up one set at a time.** Trimming used to cap every
  movement at once — all six to four sets, then all six to three — and the
  step between those rungs was wider than the miss it was closing. A 45-minute
  budget produced a 30-minute workout: you asked for three quarters of an hour
  and got half of one, with the missing quarter buying nothing. Now the plan
  gives up the single most expensive set, checks, and repeats. The worst
  shortfall across the top half of the scale falls from 36% to 6.9%, and the
  average from 20% to 2.9%.
- **The clock never takes a movement out of your session.** It takes sets, down
  to two, and stops there — six movements at two sets each is the shortest
  workout Dredfit will build. The trade is deliberate: a set costs you nothing
  in progress, a missing movement costs all of it. One consequence, said
  plainly: at the 20-minute setting, high up the scale, six movements on two
  sets each run past 20 minutes. That rung is a target now, not a promise. 35
  and 45 still fit everywhere.
- **Two sets is a floor nothing can go under.** Sets are trimmed by two
  different rules — the clock, and the balance rule that stops the push
  outrunning the pull — and until now neither knew the other existed. They
  share one floor.
- **A day is a day.** Dredfit counted whole 24-hour periods, so a workout at
  23:00 on Monday and another at 01:00 on Tuesday were "the same day", while a
  clock change or a flight invented a day out of nothing. Everything that reads
  a gap — the quiet decay after a week away, the comeback card, your own
  rhythm, the rest suggestion — now counts calendar days in your timezone, the
  way you count them. None of the thresholds moved.

Also on the How it works screen: an eleventh card, on running or swimming
alongside your strength work and why a couple of hours between the two is
worth arranging when you can.

verify2: 531,947 checks, 0 failures (was 133,929). Golden: 22 scenarios, 257
steps — all 249 existing steps bit-for-bit, plus a new time_budget scenario.
Port: 309 tests, 0 failures, GoldenTests bit-for-bit.

### Engine v2.23.0 — "tough" steps back the way it came (issue #149)

Saying a session was tough could hand you five times the work. A movement went
down a whole level, and a level down often crosses the boundary between two
variations — landing not at the easy end of the one below but in the middle of
it, where the dose starts higher. The plank on a longer lever went from 3×10 s
to 3×31 s. The hinge went from 3×4 on one leg to 3×12 across both. You said it
was hard, and the plan grew. The "no harder" check that has guarded honest
numbers since v2.14 never saw any of it: it stands on the path where you type
what you did, and the rating had no gate at all.

- **"Tough" gives back exactly what the last step up added.** One set's worth,
  the same rung the growth event climbed, walked backwards: 9-9-8 becomes
  9-8-8 becomes 3×8. The variation, the sets and the unit stay where they are,
  so the plan cannot get heavier — not because something checks it, but
  because there is no way there.
- **On the bottom rung of a variation the plan stands.** There is nothing
  lighter to ask for inside a movement you already do at its smallest dose,
  and changing the movement is not what a session rating is for — that belongs
  to a pain report and to the deload.
- **Three tough sessions in a row are a different statement.** They still
  change the movement: the deload takes the plan a variation down, and for the
  first time that roll-back goes through the same "no harder" check as
  everything else. It used to be the one descent with no check at all, and it
  could land you on more work than you started with — from 3×10 s onto 3×31 s,
  the very jump this release closes elsewhere. Now it lands on the smallest
  dose of the easier variation, exactly where a second pain report lands.
- **An impossible plan still comes down.** The guarantee is measured in the
  step the regulator now takes: from level 20, seven descent events to reach a
  manageable average, against a ceiling of eleven. What holds it is the
  deload — on the bottom rung the plan stands, but the count of tough sessions
  keeps running, and every third appearance drops the movement a variation.
- **Typing what you actually did is untouched.** An exact number is a claim
  about a dose, not about fatigue, and it still moves the plan by levels,
  under the check it has always had. Nothing on that path moved by a bit.

Three consequences, all measured and all accepted. On the bottom rung of a
variation two taps of "tough" change nothing you can see and the third does —
the price of never swapping your movement out on a single tap. A movement that
is rarely the one the rating aims at can park one level higher than before,
where the step down would have crossed into a harder variation anyway. And the
aim has become stickier: because a step down usually leaves the level where it
was, the tallest movement stays the aim instead of handing it on, so a run of
hard sessions concentrates on one movement rather than smearing across six —
the healthy movements average 18.0 of a capacity of 20 against 16.9 before,
six of the eight sit exactly at capacity, and the one that gives way gives way
further.

Levels are not recalculated and the state file needs no migration.

### Engine v2.22.0 — one set at a time, and goodbye to "hold this level" (issues #150, #151)

Getting harder meant every set at once. One step of a level added its dose to
all three sets, so a single growth event was a median of 11 % more work and up
to 25 % on reps — 3×4 becoming 3×5 is a quarter more of the hardest variation
you own, for saying "on plan". The owner's own log shows what that costs: the
row hovered around its ceiling for twelve sessions, five times overshooting by
two levels and falling back. The plan could not settle where the trainee
actually was, because the smallest move it had was too big.

- **A step lands on one set.** 3×8 becomes 9-8-8, then 9-9-8, then 3×9 — three
  growth events to the level where there used to be one, four on the four-set
  band and five on the five-set band, so where there are more sets a level
  costs more. The worst single growth event across the whole scale is now
  8.3 % of the work on reps and 4.4 % on holds, against 25 % before. The plan
  parks on your capacity: an overshoot costs one rep in one set, not a level.
- **Every ceiling that bounds a rise now counts sets, not levels.** The
  per-movement growth cell (a "two" is two sets, not two levels), the weekly
  window and the window after a comeback all read the finer unit. That keeps
  the weekly rule exactly as free as it was for an honest three-a-week rhythm
  — three sessions are three steps, precisely the slow-tissue budget, just as
  three sessions used to be three levels — and holds a daily rhythm harder
  than before, which is the direction that rule exists for.
- **Going down still moves whole levels.** A "tough", a shortfall, a deload, a
  break and the load coming off after pain all take a level and clear the
  part-built one. The asymmetry is deliberate: descending one set at a time
  would stretch the guarantee that an impossible plan comes down to something
  manageable in about eleven sessions into thirty.
- **The top rung of a variation never mixes.** Where the next step means a new
  variation, a new set band or a new unit, the step goes whole — two different
  exercises can never share one slot in the plan.
- **The plan shows it.** A movement mid-step reads "9-8-8" on Today, on the
  workout screen and in the history, and the work screen names what the set in
  front of you asks for. Two sessions in three now change something visible
  where before the level simply stood still.

**"Hold this level" is gone.** It was the third channel for "tough", added in
v2.6 for the case where a movement is at your ceiling and you need longer
there. In 24 sessions of real use it was tapped zero times, and it never
reached anyone else: it shipped behind the engine version that is in the App
Store. The case it served is the one the sub-step now handles without being
asked — the plan settles on your capacity by itself. So the button, the
"just hard" answer to the weak-link question, and the section of "How it
works" that explained them are all removed, and the rest after a pain report
has a single entrance again. Nothing to migrate: the request was never stored,
only passed, and a rest it armed before the update expires on its own schedule.

Levels are not recalculated and the state file needs no migration: a save
written before this decodes with no part-built steps, and its plan is
bit-for-bit the plan the previous version drew. Two accepted consequences,
both measured: with a pull-up bar on a strictly alternating easy/hard rhythm
the branch that only ever meets hard sessions now sits at the bottom of the
scale rather than one level up — a two-second difference in the hang — and on
a run of failing sessions the healthy movements stand a little lower than
before, because a "tough" takes a whole level while getting it back takes
three steps.

### Engine v2.21.0 — hold steps go relative (issue #149)

Every step up in a hold was the same five seconds, wherever you stood. At the
bottom of the hardest tier that is a plan of 10 s becoming 15 — half again as
much work for one step, and the ceiling allows two in a session, so 10 could
become 25 in a fortnight. No training source writes progress that way; they
write it as a share of what you are already doing, and 2–10 % is the number
they use. At the other end the same five seconds barely moved anything: a
55-second plank going to 60 is a rounding error.

- **A step is now about a tenth of the dose you are on.** Holds climb
  20-22-24-26-29-32-35-39 seconds on the first tier and 10-11-12-13-14-15-17-19
  on the fourth, instead of a flat +5 everywhere. The worst single step on the
  whole scale is now 15 %, against 50 % before; the hardest tier costs 20 % for
  two steps where it used to cost 50 % for one. Reps are untouched — not a
  single number moves there.
- **The top of every tier is shorter.** The longest hold on the first tier is
  39 seconds rather than 55, and on the fourth 19 rather than 45. The starts
  are exactly where they were: what changed is how fast the plan walks up from
  them, not where it begins.
- **Entering a fourth set no longer doubles the static work.** The bands used
  to start at 25 s measured against the old ladder; against the new one that
  was a 75 % jump for a single level. They start at 20 and 24 now, so the dose
  per set carries straight over — 19 seconds becomes 20 — and the work grows
  only by the set that was added.
- **Seconds are entered one at a time.** "Went differently" used to snap a hold
  to the nearest five seconds, which matched the old step. On a relative ladder
  it does not: three honest seconds short of the plan snapped a whole cell away
  and cost five steps instead of one. The range you can report, 5 to 90
  seconds, is unchanged.
- **A number just over the plan still counts as meeting it.** The window is one
  real step wide wherever you stand — two seconds low on the scale, four at the
  top of the first tier — so an honest 21 seconds against a 20-second plan
  reads as the plan met, exactly as it has since v2.14.

Levels are numbers and are not recalculated: holds simply grow by about 10 % a
step instead of a fixed five seconds, and the upper steps of every static
movement are shorter than they were.

### Engine v2.20.0 — a pain episode ends without numbers too (issue #150)

One tap of "this hurt" could cost you a movement for good. The rest it arms
runs out after three appearances, and then the movement waits — it stays in
the plan, at its lightest dose, and never grows again until you log a number
at or above the plan. That is fine if you log numbers. This app is built for
one question a day, answered with one finger, and for that person the way out
did not exist. Measured on a tap-only run: one report on the squat, then
nothing but "on plan" taps — 125 appearances of the squat later it is exactly
where it landed, while the movement beside it in the same rotation has gone
the full length of the scale. Not a slower result — no result, for as long as
the app is used.

- **Appearances without pain now confirm too.** Three clean appearances after
  the rest is served close the episode and the movement starts moving again.
  Clean means it was trained and you said nothing hard about it: an "it was
  tough" session or a number below the plan leaves the count where it stands,
  so the way back is three sessions that actually went fine, not three
  sessions. A tap-only trainee is out of an episode in seven appearances —
  about three weeks at three workouts a week — instead of never.
- **A number is still the fast way.** Logging at or above the plan closes the
  episode on the spot and moves the level in the same session, exactly as
  before; nothing on that path changed. The slow way closes the episode but
  leaves the step for the next appearance — a number is direct evidence about
  the load, three quiet weeks are not, and an extra appearance without growth
  is cheaper than a tendon.
- **Saying it hurts again still costs what it cost.** A second report while
  the episode is open takes the second step down, doubles the rest, and starts
  the count again from the new figure — six clean appearances instead of
  three. From the third report on, the level holds, as before.
- **A skip is not an appearance and a hold is not a confirmation.** Skipping
  the movement leaves the count untouched; asking to hold the level puts it
  back under a rest. Breaks, silent decay and the "I was sick" lens all leave
  the count alone — the lens spends it exactly as it spends the rest, so being
  ill neither helps nor hurts the way back.

States written by earlier builds need no migration: an episode already open
gets a full confirmation window rather than closing on its first appearance.

### Engine v2.19.0 — a descent never adds load (issue #149)

Saying "this hurt" could hand you more work than before you said it. The
report dropped the movement a whole tier, and where the easier tier is a
one-sided movement the volume went *up*: sliding leg curls at 3×4 — twelve
reps — became single-leg deadlifts at 3×5 a leg, thirty. Two and a half times
the work, in a movement you had never done, for a tap that meant the opposite.

- **Taking the load off happens in two steps now.** The first report keeps the
  movement you know and puts it at the lightest dose that movement has —
  swept over every pattern and every level, it never asks for more work than
  the plan it replaces. Only a second report, while the joint is still
  complaining, changes the movement itself. From the third on the level holds
  and only the rest keeps doubling, 3 → 6 → 12 appearances, as before. So one
  tap can no longer cost you a variation, and the way down to an easier one is
  still there when you actually need it — you just have to say it twice.
- **A descent is measured the way you feel it.** Work now counts both sides of
  a one-sided movement, and a step down may no longer trade a set away to buy
  reps: 3×8 is not an easier answer than 4×6, whatever the totals say.
- **Two workouts in one day no longer freeze progress for good.** The weekly
  growth ceiling ages by real elapsed time, down to the hour, instead of whole
  days rounded off. Training twice a day used to report a gap of zero, so the
  week never turned over and its growth budget was spent once and never
  renewed — measured over 120 sessions, levels stopped at a total of 48 where
  a once-a-day rhythm reached 423. The same 120 sessions now reach 336, with
  the weekly ceiling still doing its job. A once-a-day rhythm is unchanged to
  the level.

Nothing else about the pain channel moved: the rest is still counted in
appearances, the freeze still expires into waiting rather than growth, and
only an honest number at or above the plan confirms recovery. States written
by earlier builds are read as they are — an episode already open takes its
second step on the next report.

### Engine v2.18.0 — the rung the push-up ladder was missing (issue #131)

Of the forty steps in the exercise library, exactly one asked for a new
*skill* rather than more strength: pike push-ups straight into a wall
handstand, entered by kicking up at nearly full bodyweight — with nothing on
the sheet about how to get in, and nothing about how to get out. Someone whose
ceiling is fifteen pike push-ups met a plan of five handstand reps and stopped
there for good. Honest logging made it worse than standing still: reporting
what actually happened walked the level back *down*.

- **A step between them.** Feet-elevated pike push-ups — feet on a chair or a
  low bed — take tier 3, and the wall handstand moves up to tier 4. It is the
  same movement as the pike, only steeper, and it can be left at any moment by
  stepping down. The chest-to-wall variation leaves the library: it needed the
  same entry and stood even higher.
- **Getting in and getting out are now part of the handstand.** Walk up the
  wall instead of kicking; walk back down to finish. And if a rep has to be
  abandoned halfway, turn the head to one side and step over — never collapse
  straight down.
- **Measured on a trainee with a fifteen-rep ceiling, over sixty sessions:**
  someone logging honest facts used to slide to 8–16 and now holds 20–21;
  someone who only taps the button was stuck at 14–16 and now holds 19–21. The
  point is not the five levels. It is that the climb now ends at the limit of
  their strength, in a movement they can actually perform.
- **Nothing changes for anyone already up the ladder.** The level number
  stays exactly as it was, so the movement at that number is easier than the
  one they finished with — never harder. Sets, reps and the scale itself are
  untouched.

### Engine v2.17.0 — you decide how long a workout is (issues #136, #129, #142, #144)

How long a session takes was something the model told you, not something you
could tell the model. The shortest plan anywhere on the scale was 31 minutes;
honest progress pushed it past 45 minutes by the 37th workout and past 75 by
the 67th; and "Short on time?" bottomed out at 20 minutes — the fifteen-minute
window a parent with a toddler actually has did not exist at any level. The
cost of the habit grew in proportion to how well you kept it.

- **A session length you choose.** Settings now offer 20, 35 or 45 minutes, or
  no limit — which stays the default, so nothing changes for anyone who does
  not open the setting. A shorter budget drops sets first and movements only
  after, never below three, and never touches your levels: the same progress
  per session, in less time. The rungs are measured, not picked — 20 is the
  shortest length that still trains three movements at every level, 45 is where
  all six always fit.
- **Entering a new set band no longer halves the work.** Crossing into four or
  five sets used to reset the reps to the bottom of the hardest tier, cutting
  the actual work by half to two-thirds while the session got *longer* — a
  45-second plank became "hold it for 10". Bands now start at their own dose.
- **Hard movements get a real rest.** A tier-4 movement at three sets — pistol
  squats, archer rows, wall handstand work — rested a minute, where the
  evidence for trained people on hard variations says two. It now rests 90
  seconds, the honest step that keeps the ladder going one way.
- **Training every day no longer outruns your tendons.** Twenty-eight daily
  workouts used to put full pull-ups in the plan — the per-session growth caps
  were simply multiplied by the number of days. A weekly ceiling now applies to
  the slow-adapting movements, and coming back from a long break opens ten
  sessions where growth is gentle. Costs an honest two-or-three-times-a-week
  trainee almost nothing: answering "on plan" it costs nothing at all — the
  plans are identical level by level — and answering "easy" every single time
  it costs three levels of pull over three months, against ten to eleven for
  the daily case it exists to catch.
- **A collapse found while measuring all this:** answering honestly with more
  reps than a *trimmed* plan asked for could drop a resting movement fifteen
  levels. Fixed, and the fix ships here.

### Engine v2.16.0 — the push plan stops flickering (issues #141, #145, #148)

With a pull-up bar the pull slot alternates between two movements, and the
rule that keeps the push from running ahead of the pull was reading whichever
one happened to be in today's session. Once the two drifted apart, the push
plan flipped between 5×4 and 3×6 every single session — a visible change with
no cause shown for it. The gate now reads the weaker of the two branches, so
the plan is steady and still holds the line it exists to hold.

- **A measured decision, not a fix.** The audit also asked that the credit
  pause stop parking a branch under an alternating rhythm. Four rules were
  measured; the only ones that unlock it also break the protection the pause
  exists for — a plan that runs to level 43 for someone who can hold 6. From
  the inside the two situations look identical, so the protection stays, and
  the spec now carries the real numbers instead of a promise it never kept.
- **Coverage the audit found missing** is now pinned: the gate with no bar
  (the one mutation that survived the whole verifier — and no bar is the
  common case), the discomfort → credit-pause path that existed only as a
  safety guard, the session's composition on a corrupt counter, and a skip
  combined with an exact number.
- **The spec stops contradicting the code** in four places the audit listed,
  including a pseudocode box that promised the opposite of what runs.

### Engine v2.15.0 — the aim finally reaches the weak link (issues #137, #130, #135)

When one movement is beyond you and the rest is fine, the app used to take it
out on everything except that movement. The rule picked whatever stood
*highest* in the session as the thing to ease off — and a weak link is by
definition the lowest one, so across 62 failing appearances it was never once
chosen. The movements that were fine kept getting easier instead. Meanwhile a
first session logged with inflated numbers could put half the body on a level
it could not hold, and unwinding that took about a month and six deloads.

- **The movement that keeps failing is the one that eases off.** Each movement
  now carries a short memory of its own last four appearances, and the one
  that keeps landing in tough sessions steps down twice as fast — the weak
  link settles at a workable level in 13 appearances instead of 31, while the
  healthy movements stay at 19.4 of 20 instead of sliding to 15.5.
- **One bragged session is a claim about the day, not about the body.** When
  three or more movements calibrate from zero at once, they land a tier lower
  than a single honest calibration would — the overconfident first week now
  costs zero deloads instead of six, and the levels settle right at what the
  trainee can actually do.
- **The app asks about the movement it keeps seeing.** If "tough" keeps
  landing on the same exercise and you never say why, Today carries one quiet
  line — *tough sessions keep landing on this movement* — with three answers:
  it hurts (rests it, the same path as the button during a workout), just hard
  (pauses its growth, load unchanged), or it's fine. Asked once per session,
  never while that movement is already resting. Without it, someone with a
  sore shoulder who only taps "tough" loses the entire programme in nine
  weeks; the model cannot tell that apart on its own.

### Engine v2.14.0 — honest facts are never scored worse (issues #139, #140, #138)

Logging what you actually did is the engine's main input, and in three places
it was punished. Hold a plank for 21 seconds when the plan said 20 and the
model moved nothing — while stopping at exactly 20 earned a step up. Beat a
plan the app itself had trimmed (the pull is behind, so the push shows fewer
sets) and the level went *down* and counted toward a deload. And an honest
zero on the upper third of the scale handed back a plan with **half again as
many reps** of the same movement — say zero, get more. All three come from
the same place: rung arithmetic done in coordinates the reported number does
not live in. The 2026-08-16 audit found them; a full sweep then showed the
third one was not a band-only quirk but 194 broken cells out of 480.

- **"You met the plan" is a window, not a point.** Seconds are stored in
  five-second steps, so anything from the plan up to the next step now counts
  as meeting it. Reps are unchanged — their step is one, so the window is the
  old exact match.
- **A trimmed plan is still your plan.** A reported number is now read against
  the movement's true set band, never the one the gate shortened for display.
  Beating a gated plan climbs exactly as it would have without the gate, and
  never feeds the deload counter.
- **Going down never asks for more.** A descent lands on the nearest level
  that is not heavier than what you were just given; falling below a tier's
  floor drops you to an easier variation instead of adding reps to the one you
  could not finish — the way to say "this movement is beyond me", which the
  model had no way to hear. Growth is untouched, and the familiar descent
  (47 → 36 → 28 → 16 → 8 → 0) still converges.

Verified across the whole scale: the level is now monotone in the number you
report, for every pattern and every level.

### Engine v2.13.0 — a corrupt save file cannot break the plan (issues #132, #146)

The model promised that "the plan is valid even with garbage in the state",
and that promise held on most paths and quietly failed on the rest. A level
of 999 in a hand-edited or corrupted save file survived loading and was read
as *the level you were at* — so every honest session counted as a shortfall,
the failure streak grew on success, and the app handed out an unearned
deload; a comeback from that state landed at 98 on a scale that ends at 47.
Worse, a counter near the integer limit crashed the app on every single plan
— a loop the store's own quarantine could never catch, because the file had
loaded just fine. The 2026-08-16 audit found both classes; this closes them.

- **Every entry point heals its input first.** All six engine functions now
  sanitize the state they are handed, exactly as the reference always did on
  the way out: levels back inside the scale, counters and runs to whole
  non-negative numbers, sparse maps to live entries only. The valid domain is
  untouched — the golden fixture is bit-for-bit identical, all 233 steps.
- **The gap between workouts is an input too.** A nonsense gap used to write
  nonsense into every level, and the next save "healed" it to zero — a total
  wipe of the user's progress; a nonsense gap could also slip past both ends
  of the silent-decay window and take a level anyway. Now anything that is
  not a real number of days simply does nothing.
- **No arithmetic edge can take the app down.** Counters, gaps and reported
  facts carry a technical ceiling far beyond any real history (a million
  sessions is 2700 years of daily training), so nothing overflows and nothing
  traps. The two implementations were compared on 2,272 corrupt-state cases
  across all six functions: zero divergences, zero crashes.
- **The journal is an input too.** The engine's own snapshots come back out of
  the save file and go straight into arithmetic — the retrospective subtracts
  a stored level from the current one, the week summary subtracts two totals,
  the Health export re-estimates a duration from stored exercises — and in
  Swift those operations crash on a corrupt number rather than shrugging it
  off. Every number the journal holds is now clamped to the range it can
  mean, and the day-gap maths saturates instead of trapping on a nonsense
  date. The valid domain never notices.

### A steady rhythm is not a break (issues #134, #147)

The model was written for one-off breaks, but the product itself promotes a
weekly cadence — and then treated every one of those weeks as a lapse. An
honest once-a-Sunday trainee lost a level to the silent decay every single
week: over two years of never missing a workout the average level drained
to 0.7 while a six-day twin climbed to 47. At a fortnight's cadence the
comeback card reappeared on every session forever, and its primary button
was the harmful answer. The 2026-08-16 audit called this the worst finding
of the keep-the-habit rung: the app punished exactly the person who kept
the habit.

- **Your own rhythm is recognized and respected.** A break that lands
  within ±1 day of any of the last three gaps between workouts is the
  trainee's cadence, not a lapse: the silent decay stands down and the
  comeback card stays away — the plan simply waits as it was. There is no
  upper cap: a consistent every-three-weeks ritual is a rhythm too. Real
  one-off breaks still land outside the window and are treated exactly as
  before, and a skipped decay leaves no stamp — if the same break outgrows
  the rhythm, it decays honestly after all. Opening the app mid-cycle — a
  reminder tapped on day 7 of a 10-day cadence — is not a break either: a
  silence that has not yet outgrown the rhythm neither decays nor summons
  the card, and that window comes only from gaps that actually repeat, so
  one long vacation does not shield the next absence. Since a rhythm break
  has no card, the quiet "I was sick" offer stays on Today for it. Two
  years of honest weekly training now ends at the same ceiling as daily
  twins instead of at zero, and the card shows at most once per genuinely
  new break. The engine is untouched: the contract governs when the app
  layer calls its two time functions (spec §23).
- **A day is now twenty-four hours of your life, not a wall-clock label.**
  The gap between workouts counts whole elapsed days — so a shift worker
  whose 6.0-day ritual drifts across midnight (23:00 one week, 01:00 the
  next) no longer collects phantom decays (13 per 26 sessions before, zero
  now), rounding can only ever understate a break, and DST or a timezone
  trip stop being edge cases entirely (spec §7).

Nothing changes for anyone whose training simply happens on daytime hours
at irregular intervals: decay zones, comeback maths and every stamp behave
exactly as they did.

### Engine v2.12.0 — a comeback lands no heavier than your last workout (issues #126, #133)

The comeback level was monotone in the break — the dose was not. Dropping
across a variation boundary kept the rung, which landed on the TOP of the
easier variation: three weeks away from level 18 met thirteen rows where
seven used to be — 1.86× the work of the last completed session. The window
of 56–179 days had no landing ceiling at all (90 days of illness still
offered tier-4 archer rows), the 180/365 ceilings were themselves tier tops,
and a run of "come back once, vanish a month" was infeasible six times in a
row. The 2026-08-16 audit measured all of it; this wave makes the first
session after any break carry no more than the last one before it.

- **Crossing down lands on the same dose.** An easier variation at the reps
  you actually had — not the easier variation's hardest rung. Verified across
  all 9,118 (level × break) pairs: zero landings heavier than the session
  before the break (the old rule violated 3,609 of them).
- **The landing ceilings are a ladder of floors.** 56 days caps the landing
  at the bottom of tier 4, 77 at tier 3's floor, 119 at tier 2's, a year is
  a clean slate. Every ceiling is the bottom of its range, so a ceiling
  landing is soft by construction — and the old 179 → 180 two-tier cliff is
  gone.
- **Returning again and again digs deeper.** Comebacks with no completed
  workout between them drop one extra level each — the plan now slides
  faster than fitness decays, so even the sixth attempt at returning meets
  a session you can actually do.
- **"I was sick" is one tap.** A flu shorter than a week used to be
  invisible. The new tap makes the next six workouts one variation easier
  without touching your levels — a recovery fortnight, exactly the clinical
  minimum-load window. Facts and ratings conclude nothing while it runs
  (illness is a time for neither growth nor verdicts), pain reports still
  work — safety outranks the gentle mode — and the lens survives breaks.
- Spec §22, 22,483 property checks (was 19,972); an eighteenth golden
  scenario walks a double return, the whole life of the lens and a clean
  slate at a year. State files decode unchanged — both new fields are
  additive.

### Engine v2.11.0 — pain takes the load off and asks before growth resumes (issues #124, #125)

Reporting pain used to freeze a movement for three appearances — at its full
load. The plan kept offering the same pistol squats to the same complaining
knee, and when the freeze quietly ran out (about a week and a half at three
workouts a week) growth resumed into the sore joint with no questions asked —
against tissue-recovery timelines measured in months. The 2026-08-16 audit
confirmed it as the one place the app could physically harm; the spec had
already written the rule this wave finally enforces: take the load off,
don't trim it.

- **A pain report now unloads the movement.** The level lands at the bottom
  of the previous variation — an easier movement for the joint, not fewer
  reps of the one that hurts. The shortfall streak resets with it: the old
  variation's history has nothing to say about the new one.
- **The rest ends with a question, not a timer.** A pain freeze expires into
  waiting: taps keep the level parked indefinitely, and growth resumes only
  after a logged number at or above the plan — proof, not optimism. The
  confirming number itself takes the first step, through the ordinary
  per-session ceiling. A held level (the "I need longer here" request) still
  expires into growth as before — a request is not an injury.
- **Saying it again buys more rest.** A repeat report doubles the assignment
  — 3, then 6, then 12 appearances, about a month at the ceiling — and never
  drops the level twice. The care line that suggests a specialist from the
  third report is untouched.
- **The cross-credit respects the rest.** With a bar, training one pull
  branch no longer grows the other while that other is frozen or waiting —
  the audit caught a hang climbing from 35 to 55 seconds during the "rest"
  of an injured shoulder. A hold request never shortens a pain rest either.
- Spec §21, 19,972 property checks (was 17,848) — the freeze lifecycle,
  the ladder, the confirmation gate and the credit gate swept across the
  level lattice; a seventeenth golden scenario walks two overlapping pain
  episodes through a break, a pin and a confirmation. State files decode
  unchanged: the episode field is additive, like every field before it.

### Engine v2.10.0 — the pull keeps up with the push when you have a bar (issue #90)

With a bar enabled the pull's fixed slot alternates between the row and the
vertical branch, and each branch kept its own count — so each climbed at half
the slot's speed while both push movements climbed at full speed. The push
therefore reached the 4- and 5-set bands 13 to 16 workouts earlier, and in
those windows it did four sets against the pull's three. Measured over 32
weeks: 22 weeks out of 94 sat below the 0.7 pull/push balance the model is
built on, the worst at 0.56, up to five weeks in a row. Without a bar this
never happened.

- **Training one pull moves the other.** The step the slot earns is repeated
  to the branch that was not in today's workout, capped by that branch's own
  growth ceiling. Both rows and pull-ups develop the same lats and biceps, and
  the slot is trained every workout either way — so it now progresses at the
  speed it always did without a bar, rather than half of it.
- **The push never shows more sets than the pull of the same workout.** Only
  the plan is clamped: the push level keeps growing, history and Progress show
  it honestly, and the sets come back the moment the pull reaches the band.
- Two things this also fixes, both invisible until now: with an alternating
  "harder/easier" rhythm the vertical branch used to land in the same rating
  forever and never left zero, and with a four-workout rhythm the row lagged
  the same way. Both branches now keep pace.
- **And it stops when you say the movement is hard.** The credit lands on the
  workouts a branch is not in — the ones you have no way to answer — so a
  branch whose last appearance you reported as harder than usual earns no
  credit until an appearance goes by without that. Without it the plan climbed
  away from what you could actually do and never came back; with it it parks
  one step above your current ceiling, exactly where every other movement
  parks. Reporting pain, holding the level, or logging a number below the plan
  all count as the same signal.
- Pull-ups join the row's growth ceiling at variations 2 and 3 — one step per
  workout. The #76 wave had left the bar branch alone precisely because it
  appeared half as often; the credit removes that premise, so the frequency
  argument now applies to it too.
- Spec §20, 17,848 property checks (was 14,733) — the balance envelope is now
  swept across seven rating rhythms and both bar settings instead of one, and
  the volume side of it counts time under load, so an isometric hang stops
  reading as zero. A sixteenth golden scenario; no migration, state files
  decode unchanged.

### Engine v2.9.0 — "harder than usual" stops punishing the movements that were fine (issue #91)

One tap used to hand one delta to all six movements of the workout, and
pattern membership repeats on a cycle of eight — so any rhythm in the taps
landed on that cycle unevenly. Over 48 workouts of identical behaviour the
model spread the movements 24 levels apart, starting the same rhythm one
session later flipped which ones won by 25, and on the cells that only grow
one step at a time (calves everywhere, the pull from its second variation)
+1 and −1 cancelled into a standstill: calves never left zero, the pull
parked at the tier-2 boundary for good.

- **"Harder than usual" now goes where you pointed.** If the workout carried
  a per-movement signal — an exact number below the plan, "Hold this level",
  "Something hurt" — that movement takes the step down and the other five
  simply hold. Nothing about the tap changed, and no new question is asked:
  the app already sends all three.
- **When nothing was named, one movement comes down** — the hardest-looking
  one, at the top of its scale — and the rest hold their level. Holding is
  not a shortfall, so a deload no longer accumulates on movements that were
  never the problem.
- **Say it twice in a row and it is heard as being about the plan.** The
  third "harder than usual" in a row with nothing named goes back to moving
  the whole workout, so a plan that is too hard everywhere still comes down
  as fast as before. Naming a movement never counts toward that run.
- Measured against the reference on a 96-workout horizon: seven movements
  that can hold the same load now end within 19–21 of each other instead of
  1–21, the calves climb, the pull keeps moving, and honest progression is
  unchanged (the same 18, 23 and 32 workouts to an average level of 20).
  Spec §19, 14,733 property checks (was 14,029), a fifteenth golden scenario;
  state files written before this decode unchanged.

### Hold this level (issue #75, closes #77, #78) — built here, withdrawn here

**Withdrawn before release by engine v2.22.** The feature below shipped to
no one: it was added in this cycle and removed in it, so 1.10.0 contains
neither the action nor the `pinned` input behind it. The reason is in the
v2.22 entry — the sub-step does the same job without asking anyone to make a
decision mid-workout, and the boxed journal showed zero uses across the
24 sessions the input existed for. A state file that recorded a held level
decodes without it and plans exactly as it did before. The description is
kept because the engine version numbers and the golden scenarios it names
are part of this release's history, not because the button exists.

- A new **Hold this level** action on the exercise screen, beside "Something
  hurt": the movement keeps today's plan and is trained as usual, but stops
  getting harder for its next three appearances. Unlike a pain report the
  workout still counts — the rating applies one-directionally, an exact
  number can still take the level *down*, and no deload can fire on top of a
  hold. A second tap in the same workout changes your mind.
- Nothing visible changes in the plan when you ask, so the confirmation
  carries the meaning: the caption under the big number reads "level held"
  and the action flips to a **Holding** pill. The rating screen lists held
  movements under **HELD** with their horizon, history marks them "held",
  and Today's quiet line — "Not getting harder", with the per-movement
  counter — now covers both ways into the rest without claiming anyone is
  resting.
- Engine v2.6: a `pinned` input as the second, milder entrance to the same
  freeze — spec §16, 9,887 property checks (was 9,367), a twelfth golden
  scenario, and the identity that ties the three inputs together:
  discomfort ≡ pinned + skipped. A repeat request refreshes the rest;
  breaks still never clear it; old state files decode unchanged.
- A held movement counts as performed everywhere a skipped one does not:
  the debut badge, the estimated duration, the cool-down and milestones.
  "How it works" gains a tenth section, and the site's card about the
  resting mechanic now names the second way in — in all seven languages.

### The pull climbs one step at a time from the second variation (issue #76)

A behaviour change, not a fix. The pull's fixed slot puts it in every
workout — eight appearances for every rotating pattern's five — so at
identical feedback it climbed 1.6× faster than any other movement in the
model. New growth-ceiling cells hold it to one step per session at
variations 2 and 3, the inverted rows, where the elbow and the shoulder
first carry a real fraction of bodyweight.

- What goes away is only the collateral double step — the session-wide
  "easy" that handed the highest-frequency pattern +2 on a signal that was
  not about it. "On plan" is never capped, so the pull still moves every
  session; athletes mid-progression will see it climb the middle
  variations more slowly. Pull-ups are untouched: with the bar on the
  slot alternates and the horizontal row drops below the rotating
  average, so the frequency argument does not apply there.
- Spec §15.3 now records the frequency argument alongside the tissue one,
  and a new invariant pins the progression-rate spread across patterns —
  9,908 property checks (was 9,887). Golden fixtures move by design; the
  diff is classified with zero unexplained shifts.
- "How it works" stops enumerating who is capped and names the principle
  instead — the tissue doing the work sets the pace — in all seven
  languages.

### Warm-up and cool-down: positions you walk to get a longer transition (issue #83)

Five seconds is enough to start marching where you already stand; it is
not enough to get up off a lying twist and walk to a wall. The "Get
ready" transition of issue #52 splits in two: the base five seconds, and
ten for a position that changes the starting position or needs a support
— cat-cow in the warm-up; every floor and wall position in the cool-down,
while forward fold, the lat stretch and the wrists stay standing at the
base length.

- The flag travels with the position, not its slot, because the cool-down
  set is composed per session. The side-switch pause and the way back in
  from a pause keep the base length: nobody changes support mid-position,
  and Resume is tapped by someone already back in place.
- The supplement is five seconds and not six because the budget is hard:
  the engine reserves 8:00 for both blocks, and the worst composition —
  every supplemented position drawn, every side-switch played — now fills
  those minutes to the second. No estimate moves; the engine and
  `golden.json` are untouched. The site's card names the two lengths in
  all seven languages.

### Engine v2.7.0 — the do-no-harm gate (issues #88, #89, #92, #97)

The first remediation wave: the audit's two findings on the P0 boundary
and the two mechanisms behind them.
Spec §17; 13,390 property checks (was 9,908); a thirteenth golden scenario
`long_break`; scenarios 1–12 move only in the fail-streak snapshots of
their decay steps — levels and exercises are untouched everywhere.

- **Calibration stops at the neighboring tier** (#88). An honest fact
  entered from zero used to teleport the plan across the scale:
  `{squat: 30}` straight to a tier-3 pistol squat, `{calf: 40}` to level
  32 past the very ceiling that exists because the Achilles remodels over
  months. Calibration is still stronger than the per-session cap, but its
  result is now bounded by the neighboring tier's ceiling (level 15 from
  zero); slow-tissue patterns — the calf — land no higher than tier 1.
- **Long breaks land where the body actually is** (#89). The comeback
  drop was capped at −8 regardless of level: a year away still landed a
  former ceiling user in tier 4, and 140+ days of rest produced MORE
  first-session volume than 90 (the rung survived the set-band change).
  Past the table's edge there are now landing ceilings — half a year
  lands no higher than tier 2, a year no higher than tier 1 — and
  crossing a set band snaps the rung to the band floor. The landing level
  is monotonic in the gap, verified across the whole scale, and peeking
  mid-break still costs exactly nothing.
- **A pause no longer counts against you** (#97). The silent decay
  (7–13 days) now resets the underperformance streak like the comeback
  does: a streak of 2, a 13-day pause and one honest "less" used to ride
  into a deload (−5 total) while a 14-day break cost −3.
- **Garbage cannot poison the state** (#92). A non-numeric fact is
  ignored (the pattern falls back to the session rating); NaN, fractions
  and negatives in a state file heal on the next engine call; the
  generated plan is well-formed even from a dirty state. All 75,122 fuzz
  violations in the audit reduced to this one cause. The Swift port is
  type-immune already — the reference now matches it.

### Quiet lines for a pain trend and a run of training days (issues #100, #98)

Two sentences, both derived from the journal on every render — nothing is
persisted, nothing blocks, nothing turns red, and no count is ever
presented as an achievement.

- **A pain trend finally gets an answer** (#100). A repeat "Something
  hurt" used to refresh the rest and say nothing more — six painful
  appearances in a row produced the same plan. Today's "Not getting
  harder" block now adds one sentence when a movement has hurt its last
  two appearances in a row, pointing at the existing ways down ("Went
  differently" numbers, "Hold this level"); from the third the sentence
  says instead that pain that stays is a reason to see a specialist. The
  streak counts appearances, like the freeze does; one clean appearance
  takes the line down the same day.
- **A rest offer before the fourth day in a row** (#98). Nothing observed
  actual frequency: seven days straight was invisible. When starting
  today's workout would make it at least the fourth consecutive training
  day, Today carries one quiet line offering a rest day. The Start button
  and "Train anyway" are untouched, and the line never appears once today
  is trained. The engine half of the same question is settled with it: time
  reaches the model only as the gap since the last workout, from seven days
  up, so frequency stays an app-layer matter and nothing about the plan
  changes when you train two days running.
- Three new strings in all seven languages; engine and `golden.json`
  byte-identical.

### The care note grows a checklist and an explicit acknowledgement (issue #101)

The audit called the population boundary thin: three lines on the last
onboarding card, skippable. A screening questionnaire is out by a standing
product decision — so the note grows instead, as statements to read, not
questions to answer.

- The care card now names the contraindications — a heart condition or
  chest pain under load, treated or high blood pressure, dizziness or
  fainting, a joint injury that flares under load, pregnancy or recent
  childbirth → talk to a doctor first — and keeps "sharp pain always means
  stop". Same quiet typography; more content, same register.
- Its button reads **I understand — start**, and Skip on the earlier
  cards now jumps *to* the care card instead of past it: one extra tap
  for a skipper, zero questions asked, and no way to complete the
  onboarding without the checklist on screen. One tolerant timestamp
  records the acknowledgement; nothing else is stored or gated on it.
- Existing users see nothing — the stop rule already lives in "How it
  works". Strings in all seven languages; engine and fixtures untouched.

### The golden fixture names the reference that generated it (issue #104)

The reference contour deliberately lives outside this repository — which
made "commit ↔ reference" an unprovable claim: on audit day the shipped
fixture was already unreproducible by the reference at hand, and nothing
could prove why. The link is now a committed fact.

- A provenance manifest ships next to the fixture: the generator string
  plus sha256 hashes of the four contour files and of `golden.json`
  itself. `ManifestTests` recomputes the bundled fixture's hash — a
  fixture changed without provenance fails CI, not a reviewer's memory.
- `scripts/update_reference_manifest.py` rewrites the manifest as step
  4bis of the reference protocol, right after regeneration; `--check`
  verifies the working tree before an engine PR. Like the fixture, the
  manifest is never edited by hand.

### Engine v2.8.0 — the polish wave (issues #96, #102, #94)

Spec §18; 13,987 property checks (was 13,390); a fourteenth golden
scenario `discomfort_pinned`; of the old scenarios only `ceiling` and
`long_break` move, and only in their per-set rest and duration fields —
levels, streaks and counters are untouched everywhere.

- **An exact fact equal to the plan now steps like "on plan"** (#96).
  `levelFromActual` is the encoding's exact inverse, so the diligent
  logger — exact numbers every session — never progressed, while a tap
  moved. A fact equal to the plan's load now gives the same +1 the tap
  gives, zero included: doing the first plan exactly is progress too. The
  comparison is against the plan's load, not the inverted level, so
  "below plan at zero" still calibrates to zero. A fact still outranks
  the rating, and a freeze or a hold still clamps growth.
- **The rest between sets follows the set band** (#102). Sixty seconds
  was a constant across the whole scale — including the 4–5-set bands of
  tier 4, where a ceiling session is ~110 shrimp squats with one-minute
  pauses against literature that gives trained users two to three
  minutes. Now 60/90/120 s by band; the per-exercise `restSetSec` field
  already feeds the timer, so no app change. The ceiling session grows
  deliberately to ~85 min; the ≤80-minute checks are re-pinned to ≤90,
  not loosened.
- **discomfort ∧ pinned on one pattern is now specified** (#94): the
  discomfort absorbs the pin — the session is annulled, the rest is
  armed, the pin adds nothing. Behavior is unchanged; the rule, the
  verifier asserts and the golden scenario now exist, so the port can no
  longer legally diverge. `discomfort ≡ pinned + skipped` keeps holding.

### The verifier closes its own audit holes, and the spec stops lying (issues #95, #105, #106)

No engine behavior changes and a byte-identical fixture — this wave hardens
the harness that guards the other waves. 14,029 property checks (was
13,987).

- **The surviving mutants are dead** (#95). The freeze is now asserted on
  a rotating movement — a pattern absent from a session spends nothing,
  and the rest expires on its third *appearance*, not its third session
  (the mutant that survived the audit's whole run). The four duration
  constants are pinned by value, with two exact session durations — 33.0
  minutes at the start, 84.9 at the ceiling — that move if any of them
  drifts. A pre-bar legacy state now runs through the full API in one
  block: same session, same feedback, same comeback as explicit defaults.
  And the 40 variation identities are pinned by name in a locale-proof
  Swift test — golden deliberately carries no names, so a reorder inside
  a tier used to pass every test while silently rewriting journal
  history.
- **Edge-input contracts are written down and aligned** (#106). Spec §7
  is rewritten from the stale "3 functions, 11 numbers" to the real five
  functions and their contracts: what throws (an invalid rating — nothing
  else), what clamps, and what a repeated submission does. The reference
  adopts the port's replay guard — feeding the same feedback twice used
  to double the growth in JS while Swift ignored it; now both are a
  silent no-op, asserted on both sides.
- **The spec text catches up with the shipped engine** (#105): the
  pre-v2.3 encoding in the engine's own header, the unreachable
  "tier 3 × 15" example, the dead `repMin`/`holdMin` knobs, the stale
  duration claim of §12.1, and the "≈1.25:1 in favor of pulls" arithmetic
  that was never true — replaced with the real 8:10 appearance ratio and
  the ≥ 0.7 set balance the verifier actually holds.

### The tones grow a voice of their own (issues #84, #186)

The three workout tones were bare sines at full scale: harsh on a phone
speaker, easy to lose under music, and overloaded — "go" meant a start,
the end of a hold and the end of the whole workout alike, while the
milestone screen said nothing. The "Minimal+" set keeps the language —
C major, a fifth up to start — and gives it a body, a rhythm of its own
and three new words.

- Every note is now an additive pair (fundamental plus a soft octave
  harmonic) under an exponential decay: warmth instead of a beep, and
  enough overtone to survive over music. Peaks sit below full scale on a
  strict loudness hierarchy — the frequent is quiet, the rare is bright:
  tick, then switch, then go, then the finale, then the milestone.
- **Every ending is announced, whatever ended it** — a set logged by
  tap, a hold run down to zero, a hold stopped early, a warm-up move, a
  cool-down stretch. Each closes on **done**: top-down C7 → G6,
  "release", with its own `.rigid` haptic, instead of a go that said
  "start" a beat too early. The cool-down closes the workout with a
  **finale** that completes the go's motif by the octave, and an earned
  milestone opens with a major arpeggio crowned by its own echo — the
  first sound that screen has ever had. Everything that started with a go
  still starts with a go, and everything silent stays silent: a pause,
  extra rest, a hold abandoned inside the mis-tap window, and every skip
  — skipping is not finishing, and the cool-down's skip stays a tap
  rather than a fanfare.
- **Switching sides is a rhythm, not a melody.** Two taps on one note,
  75 ms apart against the 95–110 ms of the melodic pairs. Eyes closed
  halfway through a stretch, an inverted go only ever said "a pair of
  notes happened" and left the listener to work out which pair; nothing
  else in the set is two attacks on one pitch.
- The reminder notification rings in the app's own voice: the same motif
  slowed and softened, generated on demand into `Library/Sounds` (no
  audio asset ships in the app), falling back to the system sound if the
  file cannot be written. It follows the system's notification-sound
  setting, as notifications do; the in-app toggle keeps governing the
  workout tones.
- All seven sounds remain code — reviewable, deterministic, and pinned by
  tests: exact durations and peak targets, the loudness hierarchy, the
  rise of the go, the fall of the done, the flat double tap of the switch
  measured off its own envelope, and byte-for-byte reproducibility. The
  engine is untouched.

### The mark's third ring rejoins the palette (brand-colour audit, 2026-08-12)

The 1.6.0 contrast pass retired `#D9D9DB` from `Theme`: a ring that means
"a workout is planned here" is meaningful graphics, and 1.41:1 is not a ring
anyone sees. The icon, the favicon and the site's own logo kept the retired
grey — at favicon size the mark read as two dots, not three.

- The third circle is `ink3 #A7A9AD` (2.35:1) everywhere it is drawn:
  `final_light.svg` and the 1024 app icon, `apple-touch-icon.png`, the
  favicon and the header/footer marks `sitegen` emits, and `og.png`. The
  dark variant's ring moves off an invented `#8E8F94` to `#98999E` — the
  dark counterpart of `ink2` that `WidgetTheme` already defines. The tinted
  variant is unchanged: iOS builds a luminance map from it.
- `AccentColor` was an empty colorset while the build asked for it by name,
  so every surface outside `RootView`'s `.tint(Theme.ink)` — the share
  sheet, system alerts, the widget gallery — fell back to the system blue.
  It now carries `ink #111214`, the tint the app had already chosen.
- `og.png` shipped tagged Generic RGB instead of sRGB: right in a
  colour-managed browser, `#E0430E` anywhere a preview renderer drops the
  profile, which is most of them. Re-encoded in sRGB — the accent is
  `#E8590C` in the pixels now, not only in intent.
- The pages gain `<meta name="theme-color">`. App Store screenshots, the
  landing's CSS tokens and every colour in the Swift sources were checked
  against `Theme` in the same pass and needed no change.

### One palette, one source: the tokens move into the asset catalog (issue #116)

The design audit called the forced-light theme a debt and the widget's
hand-kept copy of the palette its cheapest symptom: two lists of the same
ten colours, drifting apart one hotfix at a time.

- The brand colours live in `Design/Brand.xcassets` now — one colorset per
  token, a light and a dark value each, compiled into the app and the
  widget extension alike. `Theme` stays the façade code reads; no app view
  changed a line. `WidgetTheme` is gone — the widget speaks `Theme` too.
- A `bg` token joins the palette: the light scheme kept the background
  implicit (system white), and in dark it is the ground every other token
  is measured against.
- The widget's dark ground moves from its private `#1C1C1E` onto the
  shared `bg`, and the Live Activity stops painting its own background:
  the lock screen supplies the material, so the card follows the system
  look instead of flashing white on a dark lock screen. The countdown
  stays accent, `.secondary` in the expanded island stays deliberate.
- Four dark values are new — `bg #090A0C`, `cardBG #1E1F23`, `accentSoft
  #3A2013`, and `accentText`, which equals the accent in the dark scheme
  on purpose: `#E8590C` reads 5.5:1 on the dark ground where the light
  scheme's `#B44504` drops unreadable. `bg` and `cardBG` sit one step off
  the first candidates: the floors ink3-on-bg ≥ 3:1 and cardBG-on-bg
  ≥ 1.2:1 only clear at these values.
- A palette test resolves every token in both appearances, pins the values
  against the table in `Theme.swift` and re-derives the WCAG floors. The
  share card pins its own light environment — an exported image must not
  follow the viewer's scheme, and a dark-scheme render is proven
  pixel-identical by test.
- The app itself stays light by design. The full dark theme remains the
  owner's call; after this wave its price is translating the views and
  removing one `preferredColorScheme(.light)`.

### The app follows the system appearance (issues #118, #119)

The owner's call arrived the same day: the pin comes out. The app now
renders in whichever scheme the system is in — no theme picker, no new
strings, the system setting is the setting.

- `preferredColorScheme(.light)` is gone. The tab screens sit on one
  explicit `bg` ground under the TabView; the workout cover, onboarding
  and every sheet paint the same token instead of the implicit system
  white; plain-list rows go clear so the ground shows through.
- Labels over ink-filled shapes — the primary buttons, the technique step
  numbers, the calendar's done cell and its "Completed today" card, the
  OK capsule — switch from `.white` to the `bg` token: on the ink fill
  the label must flip with the scheme, or dark mode paints white on
  near-white. White survives only over the scheme-stable accent and
  inside the share card, which stays a light export by design (pinned,
  pixel-tested).
- The `AccentColor` global tint gains its dark counterpart, so system
  surfaces tinted by it — alerts, the share sheet — follow the ink.
- Increased Contrast gets real values (issue #119): every token carries
  high-contrast variants for both schemes, floors one tier up (`ink2`
  ≥ 7:1 on `bg`, decorative ≥ 4.5:1, quiet graphics ≥ 1.5:1, cards
  ≥ 1.3:1; the one documented exception is ink2-on-cardBG at ≥ 5.5:1,
  keeping the ink hierarchy and the card separation both alive). The
  palette test now resolves all four appearances and pins every value
  and every floor.

### Fixes

- Silent decay now fires on a cold launch too (issue #93). The 7–13-day
  blind-zone decay used to run only on a scene-phase transition, which a
  cold launch never produces — the most ordinary comeback ("return after
  8 days, open the app, train") ran the whole session on pre-break levels.
  The activation sequence now lives in one store seam, `activate()`,
  called from both `onAppear` and the `.active` transition, with a
  cold-start regression test.
- Importing an unrelated backup no longer hides its workouts from Apple
  Health (issue #103). The import used to keep this device's high-water
  export mark and stamp every foreign record beneath it "already
  exported" — those workouts silently never reached Health, with no way
  back. Journals now count as the same lineage only when they share a
  record identity (session number + date); an unrelated journal keeps its
  own mark. The legacy mark→flags migration runs only on flag-free files,
  which also stops a reload from stamping a post-reset session 1 under
  the old mark. Restoring an older backup of your own journal keeps
  today's guarantee: nothing re-exports.

## 1.9.0

The largest release the project has shipped, and the first to reach the App
Store since 1.8.0: three versions' worth of waves in one submission. The
regulator gains the dimension it never had — how fast a movement is allowed to
climb — and an answer for "my joint hurt" that is not "tough". Both guided
blocks gain a pause and a run-in before every position. German, French and
Italian join, so the app speaks seven languages. And the screens stop
promising more than the engine can deliver. The engine steps to v2.5, verified
against the reference at 9,367 property checks; the state format and the
journal format are untouched, so there are no migrations.

### Engine safety wave: growth ceiling and discomfort (issue #38, closes #64–#67)

- The regulator gains a dimension it never had: how fast a movement is allowed
  to climb. The single `+2` ceiling becomes a table by movement and variation,
  because tissue is not uniform — calves climb one step per workout at every
  variation (everything loads the Achilles), the vertical push from the wall
  handstand up, and every movement on its fourth variation, where the archer
  variants and the set bands live. Everything else keeps two. The cap is the
  only dial that acts before an overload rather than after it.
- "Tough" no longer has to stand for both "my muscles gave out" and "my joint
  hurts". A new **Something hurt** action on the exercise screen — one tap, no
  dialog, its own line next to the skip — ends that exercise and rests the
  movement: it keeps its place in the plan at the same level and stops
  climbing for its next three appearances. A level can still go *down* while
  it rests, and no deload can fire on top of the rest.
- Today carries a quiet line while a movement rests ("Resting for now: …"),
  the rating screen lists it under **Discomfort** rather than **Skipped**, and
  the calendar's history row says "hurt". A ninth "How it works" section
  explains what the report does and repeats the stop rule.
- Reporting survives everything a skip survives: process death mid-workout,
  the resume card, and a break — neither the silent decay nor the comeback
  clears a rest, on purpose. State files written before this decode unchanged.
- Engine v2.5.0: reference spec §15, 9,367 property checks, and a new golden
  scenario for the freeze. The ceiling table lives in the spec and the
  verifier compares it against the shipped one cell by cell, so the two cannot
  drift apart silently. Strings complete in all seven languages.

### Screen honesty pass (issue #73)

- The rating screen stops promising a multiple. "Easy, could do more" said
  progress comes twice as fast and the completed state repeated it, which the
  growth ceiling made untrue in v2.5: a session built from fourth variations
  climbs exactly like "on plan". Both captions now promise a direction and no
  size, because the size is knowable only after the answer is applied.
- The freeze says how long it lasts. A resting movement carries its own
  counter on Today — "3 more times" — read from the engine's own
  `freezeRemaining`, which the screen had never asked. It counts appearances
  of that movement rather than workouts, and the wording drops the claim of
  rest so it stays true for the second, milder entrance being added in #75.
- The rating states its scope once. The banner under the heading and the
  summary card said the same thing, under a comment demanding the two never
  contradict each other; the count moves into the card header, where the
  itemisation right below already answers "which ones".
- Rest can be extended, not only cut short. "+15 s" sits beside "Skip rest",
  both outlined and of equal weight, repeatable to twice the planned rest and
  greying out in place at the cap. Someone who is not recovered used to have
  the choice of standing at an expired timer or starting a set they would not
  finish — and the engine reads the second as "tough", so this protects the
  regulator's input rather than comfort.
- A break owns its cost. The silent decay lands between two journal entries
  while the chart draws one point per entry, so the drop appeared inside a
  completed workout — deliberate quiet reading as an accusation. Gaps of a
  week or more now carry a band behind the line with their length inside it,
  and one line under the chart. That line names a cost only where the levels
  fell across the gap *and* the first workout back cannot account for the drop
  itself — neither by its rating nor by a number entered in it. Anything less
  strict would put the mistake this wave removes from the rating screen back
  on the chart.
- Two lines earn their removal: "Last time you chose" re-weighted three cards
  that are meant to be equal, and the weekly summary gave its space to the
  chart. The load caption under the big number stops printing the number
  again.

### Warm-up and cool-down: a "Get ready" transition before each position (issue #52)

- Both guided blocks used to start every position cold: the 30 seconds of a
  warm-up move and the timer of a cool-down stretch began the instant the
  previous one ended, while you were still getting off the floor, reading the
  next name or looking for the wall. The first seconds of the interval went
  into moving house, not into moving — and for a beginner that reads as "I
  can't keep up" rather than "the timer starts too early".
- Every position is now preceded by a five-second "Get ready: <move>" — the
  first one included, because you have just pressed Start and are still
  standing by the phone. It names what is coming, opens its technique sheet
  like the position itself does, runs the usual 3-2-1 into the go that starts
  the movement, and carries the same two escapes (this position, the whole
  block). "I'm ready" starts the position at once: the transition is a floor
  on the pause between positions, never a wait.
- The go-tone moved to where the movement actually starts. A position now
  ends silently and the transition speaks with its own 3-2-1 — two gos five
  seconds apart would have said nothing twice. The falling "switch sides"
  tone keeps its one meaning.
- The pattern already half-existed: the side-switch pause of 1.8.2 counts a
  transition inside a position, this one counts the transition between them.
  Same five seconds, same wall clock, same survival of a locked screen; a
  backgrounded block still jumps whole stages instead of stretching itself.
- No estimate moves. The engine reserves 8 minutes for the two blocks
  (`warmupMin` 5 + `cooldownMin` 3); with the transitions they spend 210 s on
  the warm-up and 220–235 s on the cool-down — 430–445 s of the reserved 480.
  The number on "Today" keeps promising at least what the flow delivers, and
  the engine, `estimatedTotalMin` and the golden fixtures are untouched.
- VoiceOver reads the transition as one phrase, "Get ready: Cat-cow". At the
  accessibility text sizes a three-line position name plus the countdown no
  longer fits the screen, so the block's content scrolls and its escapes stay
  pinned — the running move and stretch screens gained the same treatment.
- Strings in every shipping language. "I'm ready" is translated by sense —
  «Начать» / "Empezar" / "Começar" / "Commencer" / "Inizia" — because "ready"
  takes a gendered adjective in Russian, Spanish, Portuguese and French; only
  German keeps the adjective, where "Bereit" has no gender to take.

### Warm-up and cool-down: a pause for the guided blocks (issue #61)

- The guided blocks are the only part of a workout that runs strictly on
  timers. Working sets are self-paced, and a rest timer that kept counting
  while you answered the door merely granted extra rest — but in the warm-up
  and the cool-down the block kept marching through positions without you.
  The only two options were to let it run past, so the flow pretended you did
  positions you didn't, or to throw the whole block away. The honest move —
  pausing — did not exist, and this app is built for people training at home,
  where the doorbell, the kettle and a child are normal.
- Every timed screen of both blocks now carries a **Pause**: the position
  countdowns, the "Get ready" transitions, the "Switch sides" pause. Paused,
  the countdown stops on the second it showed, the number dims, the unit under
  it says so, and every tone ahead of it goes quiet. Like every other timer in
  the app the pause is wall-clock based — with no deadline left to run out, a
  locked screen or a backgrounded app changes nothing.
- **Resume** counts you back in rather than dropping you mid-position: five
  seconds naming the position, the same 3-2-1 into the go a "Get ready" plays,
  and then the interval continues from the seconds it froze on — never from
  the top, never a position later. The two transitions are the exception —
  "Get ready" and "Switch sides" already are ways back in, each with its own
  signal still ahead of it, so they simply carry on.
- The pattern already half-existed, twice. Opening a position's technique
  sheet freezes the countdown (reading is not stretching), and the "Get ready"
  beat is a screen where the flow already knows how to stand still. This
  promotes that hidden freeze to a control you can find. Where the two meet,
  the user's pause wins: closing the mini-sheet never restarts a block that
  was stopped on purpose.
- Nothing about the numbers moves. The pause is user-initiated, so
  `estimatedTotalMin` keeps promising what an uninterrupted flow delivers, and
  the duration written to Health stays the wall-clock truth of the session.
  Working sets and their rest timers are untouched — they are self-paced by
  design. The engine and the golden fixtures are untouched.
- VoiceOver announces "Paused" and "Resumed", and the state is readable under
  the countdown. Strings in every shipping language.

### Localization: German (issue #63)

- German joins English, Russian, Spanish and Brazilian Portuguese, complete —
  every key across the four String Catalogs: the 40-exercise
  library with its technique steps and common mistakes, the 15 warm-up and
  cool-down position sheets, the "In real life" lines, onboarding, "How it
  works", milestones, the anniversary retrospective, the widgets and the
  Health permission strings.
- The register is du — lowercase, calm, and gender-free: the athlete is never
  named by a gendered noun. The terminology keeps the app's three concepts as
  disjoint in German as everywhere else — Variante (which exercise, 1 of 4),
  Stufe (one unit of level change), Level (the number itself) — and prefers
  the words German home training actually uses: Kniebeuge, Liegestütze,
  Klimmzüge, Ausfallschritte, with Plank kept English because that is what
  German says. A bare "Pause" only ever means the seconds between sets; a
  longer absence is a Trainingspause, and a deload an Entlastung.
- No code changed for the language: the one locale-sensitive label ("on
  Monday") already had a default path that German's uniform "am + weekday"
  fits, so the catalog carries "am %@" and the switch in
  `nextTrainingDateLabel` stays three cases long. The engine and the golden
  fixtures are untouched.
- The marketing site ships the same five languages: dredfit.com/de (landing
  and privacy policy), with hreflang alternates and sitemap entries on every
  page. Nine German store screenshots join the set, captured through the
  standard pipeline.

### Localization: French and Italian (issue #69)

- French and Italian join the shipping languages, each complete across the four
  String Catalogs: the 40-exercise library with its technique steps and common
  mistakes, the 15 warm-up and cool-down position sheets, the "In real life"
  lines, onboarding, "How it works", milestones, the anniversary retrospective,
  the widgets and the Health permission strings. Seven languages now.
- Both address the reader as *tu*, and neither ever genders them: French leans
  on impersonal turns ("C'est fait") rather than a masculine "Prêt", and
  Italian on `avere` participles ("hai fatto") rather than an *essere* one.
  Buttons follow each platform convention — French infinitives ("Commencer"),
  Italian second-person imperatives ("Inizia").
- The app's three-way distinction survives translation intact in both: French
  *variante · cran · niveau*, Italian *variante · gradino · livello*, with the
  words for a technique step kept clear of them (*étape*, *passaggio*). The
  rest cluster is likewise disjoint — French *repos · jour de repos · coupure ·
  allègement*, Italian *recupero · giorno di riposo · pausa · scarico* — so a
  sixty-second rest never reads like a fortnight away from training.
- French typography is honoured rather than approximated: narrow no-break
  spaces before `? ! ;`, a no-break space before `:`, typographic apostrophes,
  and never an elision against a placeholder.
- No code changed for either language: both take the same default branch of
  `nextTrainingDateLabel` that German uses, with the weekday label carried in
  the catalogs ("le %@" in French; the bare day in Italian, whose article is
  gendered). The engine and the golden fixtures are untouched.
- dredfit.com ships /fr and /it — landing and privacy policy — with hreflang
  alternates and sitemap entries across all seven locales, and nine store
  screenshots per language through the standard pipeline.

### Localization audit across the seven languages

- French and Italian stop bending the grammar of the exercise they name. A
  participle after the placeholder cannot agree with "Pompes" or "Flessioni",
  so the skipped and unfinished labels now carry their own noun — "Pompes,
  exercice ignoré", "Flessioni, esercizio saltato" — instead of a masculine
  ending glued to a feminine name.
- Nothing addresses the reader by gender any more. The Russian privacy page
  drops the formal "вы" that it alone still used, the "you export it yourself"
  lines lose their masculine "сам" / "tú mismo" / "você mesmo", and six Spanish
  and Portuguese starting positions turn from "Acostado boca arriba" into the
  imperative the rest of the library already used.
- Terminology reconnects to the glossary: Brazilian "Deload" becomes
  "Descarga", the wall handstand goes back to the name the exercise library
  gives it in each language — the Spanish copy had picked up "el pino", a
  Spain-only word — and German "Equipment" becomes the "Zubehör" the site was
  already using.
- The English source loses its one piece of gym jargon: "kipping doesn't count"
  is now "using momentum doesn't count", and the Russian, Spanish and
  Portuguese calques go with it.
- The site says what to tap. "Tap it during the workout" had no antecedent on a
  page that shows no button, so every language now names the control, and the
  German "Ein Tipp" (a hint) becomes "Ein Fingertipp" (a tap). Typographic
  quotes replace the straight ones left in English, Spanish and Portuguese, and
  the landing page gains the card for the discomfort feature.
- The glossary records the decisions that let the drift happen: a row for the
  wall handstand, the French and Italian placeholder rule, "ты" for Russian
  legal copy, and gym jargon banned in the English source too.

### Widget: the longest exercise names fit the large size again

- On the large home-screen widget in Russian the longest name in the catalog
  — «Птица-собака» (удержание) — ended in an ellipsis. The plan row carries
  the load in the long form the snapshot writes ("3×20 сек на сторону"),
  which left the name short of the width it needs. The name now shrinks a
  little instead of truncating, the way every other line of the widget
  already does — and an ellipsis is the worst of the two, because sibling
  variations differ at the end of the name. Brazilian Portuguese already fit;
  English is nowhere near the edge.

### Widget: it stops asking to be refreshed once its snapshot runs out

- The app writes the widget two weeks of days; the widget asked for its next
  timeline "after the last one". Once only today was left, that moment had
  already passed by the time the timeline arrived, so the widget re-asked
  immediately, got the same expired answer, and spent the day's whole refresh
  budget on it — which is exactly the budget a real change needs the moment
  the app is opened again. It now asks again after midnight instead. Reachable
  after two weeks without opening the app, which is a break the app already
  models rather than an accident.
- The same budget went on the one-off Apple Health backfill: exporting a year
  of history poked the widget once per workout, for content none of those
  exports can change.

### Cool-down: the "swap sides" steps say something useful now

- "Chest and shoulders at the wall" and "Wrists and forearms" still had
  "Swap arms — or hands — halfway through" as their third technique step,
  left over from when the user did the counting. Since 1.8.2 the app counts
  both sides itself, so the line only repeated the timer. Both now carry a
  technique line like the other four one-sided stretches: keep the shoulder
  down and away from the ear, and pull the wrist only to a stretch. In every
  shipping language.

### Calendar: the footer names the month you are looking at

- Paged back to June, the card under the grid still read "This month" over
  June's count — a sentence about August stating June's number. It now names
  the month on screen whenever that is not the current one.

### Site

- dredfit.com stops advertising the public TestFlight link (issue #72). It sat
  in the hero line under the download button and again in the footer, on the
  landing and the privacy page alike, in all seven languages — an advertised
  entry point that has to stay correct, with a build expiring every 90 days
  and a beta review to keep passing, next to an App Store button that keeps
  the same promise better and has been the real call to action since 1.8.0.
  Internal TestFlight distribution is untouched, and testers already invited
  keep their builds.

### Housekeeping

- One more finding from the review that produced the widget and calendar fixes
  above: the go-tone could sound over a "Get ready" screen. A long absence —
  a locked phone, a backgrounded app — crosses several stage boundaries at
  once, so the boundary that opened the run and the stage the countdown
  actually landed on are two different things. Choosing the signal from the
  first alone announced a movement over the name of one that had not started;
  both blocks read the landing too now.
- The technique button on a position screen carries an accessibility
  identifier. It was the one control the tests drive that had none, so it was
  addressed by its English label, and a localized run could not open the
  technique sheet at all.
- 284 → 343 automated tests. The engine's new ceiling table is compared
  against the reference cell by cell, so the shipped one and the spec cannot
  drift apart in silence; the rest covers the discomfort report surviving
  process death and a break, the freeze horizon counting appearances rather
  than workouts, rest extended to its cap, the gap band under the progress
  chart and the single line that may accompany it, both guided blocks pausing
  and resuming, and the get-ready transition as a floor on the pause between
  positions rather than a wait.
- The nightly UI job's retry flags fire for the first time since it was split
  out of the release gate: `-retry-tests-on-failure` had never once produced a
  second iteration, so a flake cost a red run rather than a retry. Two races
  in the suite itself went with it — a hold countdown that expired under its
  own Stop tap, and a transition the tests had five real seconds to find and
  tap.
- Every comment in the app, the engine, the widget and the tests was read and
  reduced to what an edit would break without, and the repository's counters
  match the code again: README's three test layers, TESTPLAN's header, and the
  pull-request checklist, which still asked for three translations when six
  ship.

## 1.8.2

A fix release for the cool-down: the two stretches that told you to swap
sides now have the app counting them, like the other four already did. No new
features; the engine, the state format and the journal format are untouched,
so there are no migrations.

### Cool-down

- "Chest and shoulders at the wall" and "Wrists and forearms" ran as a single
  30-second countdown while their own technique steps said to swap arms —
  or hands — halfway through. They were the two positions where the app knew
  the stretch was two-sided and still handed the count back to the user: no
  "15 s per side" line on screen, no five-second switch pause, no falling tone
  to move on. Both are counted now: 15 seconds a side with the pause between
  them, exactly like the hip flexors that open the block.
- Why they were missed: the per-side flag was introduced with the cool-down
  itself, when it only decided whether to print the "15 s per side" hint, and
  the counted switch was later built on the same flag without re-reading which
  positions are actually one-sided. A unit test then pinned the old
  classification under the name "unilateral positions only", so the mismatch
  looked deliberate.
- The block is a little longer as a result: never under 3:10, up to 3:25 when
  three of the session-mapped stretches are one-sided too. The reserved
  cool-down minutes in the engine's estimate are unchanged — the pauses ride
  on top, inside the "≈" every duration carries.

### Housekeeping

- 283 → 284 automated tests. The new one is a guard rather than a regression
  test for this bug: it asserts that no position the app treats as bilateral
  tells the user to swap sides, so a step text and its flag cannot drift apart
  again the way these two did.

## 1.8.1

A small fix release: a widget that keeps asking for fresh data instead of
sitting on a timeline dated in the past, and a documentation pass that makes
the repository describe the app it actually ships. No new features; the
engine, the state format and the journal format are untouched, so there are
no migrations.

### Widgets

- The fallback timeline entry — the one used when the App Group snapshot is
  missing or cannot be decoded, which is the state a widget added before the
  app's first launch is in — was a stored `static let` built with `.now`.
  A stored static is initialised once per process, so its date froze at the
  first access and every later timeline request in the same extension process
  received an entry already dated in the past, asking WidgetKit to refresh a
  timeline that had expired before it was handed over. The entry is computed
  now and carries the time it was actually built.

### Housekeeping

- The countdown tones clamp their sample conversion into `Int16` range.
  Nothing changes for the three tones that ship — every sample was already in
  range — but the tones are generated inside a `static let`, so raising an
  amplitude past 1.0 would have trapped at the first countdown of a workout
  rather than at the edit that caused it.
- Documentation caught up with the code. README still described the v2.2 level
  encoding (`reps = 8 + L % 8`, a ceiling of 5 × 15) although per-tier floors
  landed in v2.3 — it is `repStart[tier] + L % 8` with floors 8/6/5/4, so the
  ceiling is 5 × 11 — and still counted the reference cycle at 4,150 checks
  and 133 steps across 9 scenarios instead of 8,009 / 143 / 10. The app
  section predated 1.8.0: no short version, no cool-down, no side-switch
  pause, and widgets described as home-screen only. TESTPLAN promised 24
  reminders "with the default rest day" after the default became two days
  (a 28-day window holds 20) and still expected six "How it works" sections
  where there are eight. Four files pointed at `instructions/GIT_FLOW.md`,
  which does not exist; `.github/WORKFLOWS.md` now carries the local UI-run
  procedure itself and the workflow comments point there.
- 281 → 283 automated tests. Neither code fix earns one — the widget one is a
  static-initialisation timing issue whose regression test would pass or fail
  depending on the order tests run in, and the clamp is a no-op for every
  amplitude the app ships. The two new tests are the release smoke instead:
  the S1–S7 block of TESTPLAN, which was walked by hand before every release
  and never changed between them, is now a suite that walks it in English and
  in Russian. Running the full test plan before cutting a release covers that
  block by itself. The walk that drives a workout to the rating moved into one
  shared driver at the same time: it existed in a single copy, and the release
  smoke needed the same steps — two copies of it would drift, and the last
  time this walk drifted it cost the nightly six red runs.

## 1.8.0

A feature release that makes the workout whole: the cool-down the estimates
always promised, a short version for the days there is no time, technique
help on every warm-up and cool-down position, a counted side switch, and
honest guidance on weekly rest. Around the session, Progress learned to draw
the journey, the widget grew into every size, and the milestone card shows
where you started. The engine steps to v2.4 — a silent level decay for
7–13-day breaks, verified against the reference and recorded as golden
scenario 10; the state format and the journal format are untouched, so there
are no migrations.

### Widget: every timeline day speaks from its own date

- The "Next workout today / tomorrow" line was computed once when the app
  wrote the snapshot and copied into all fourteen timeline entries, so a
  rest-day entry rendered days after the app was last opened could claim
  "Next workout today". The app now precomputes the label for every day —
  localization, including the Russian accusative and the pt-BR weekday
  gender, stays app-side — and each widget entry reads its own word.
- "This week" on the large family is stamped with the Monday it tallies
  and no longer shows on next-week entries, where last week's numbers
  would read as the current week's.
- The timeline mapping and the widget's word choices are under unit tests
  now: the widget sources compile into DredfitTests, and the Live Activity
  contract moved to ActivityShared.swift so app and test types never twin.

### Localization audit: ru / es-419 / pt-BR pass over all four catalogs

- Russian athlete-facing strings no longer assume a male user: the three
  feedback buttons («Готово», «Легко, могу больше», «Тяжело, получилось
  меньше»), the stop line and the onboarding copy now use gender-free
  forms — the previous masculine past tense read as a male self-description
  under a female user's finger.
- es-419 is now actually Latin American: Apple-lexicon UI terms (Agregar,
  Respaldo, Configuración, Restablecer, Calificar), gym terms (pantorrilla,
  parada de manos, flexión pike, enfriamiento) and «Omitir» for the whole
  skip family; peninsular forms (hacia delante, todo el rato, gemelos,
  tumbado, sustituir) are gone. Status labels with a substituted exercise
  name switched to invariable phrasings («%@, quedó fuera») because the
  old participles broke on feminine names.
- pt-BR: the same invariable status fix («Prancha, ficou de fora» instead
  of the ungrammatical «Prancha, pulado»), «alguns passos» instead of the
  «um par de passos» calque, Deload kept in English, the barra fixa family
  completed (negativa/parcial), suspensão instead of the noun «pendurada».
- Counts decline correctly now: the exercises number in "≈ %lld min ·
  %lld exercises" got plural forms via a substitution bound to the second
  argument (all four languages, app and widget catalogs), the rest
  countdown got its missing English singular, and the big-number caption
  agrees with the number above it («1 повтор / 3 повтора / 12 повторов»)
  instead of a frozen genitive.
- The "on %@" weekday phrase moved into code: Russian accusative
  («в среду», «во вторник») replaces the old prefix heuristic that
  produced «в среда», and pt-BR now picks no/na by weekday gender.
- Four English source cues were reworded where the source itself was
  flawed (hollow shape, active hang, the Y-T-W rep definition, the
  2-second hold ambiguity) — catalog keys and Library.swift renamed
  together, translations already matched the intended reading.
- The ru Health privacy description no longer promises more than the
  English source ("nothing else is shared", not "shared nowhere").

### Engine v2.4: silent level decay for 7–13 day gaps (issue #37)

- The comeback only starts at 14 days, leaving the 7–13 day zone blind —
  the most common real-life break length (vacation, work trip, a cold) met
  an overestimated plan on the single most churn-prone session. Now a
  quiet −1 lands on every pattern when the gap enters that zone: no card,
  no UI, applied once per break on scene activation, clamped at 0.
  `failStreak` and `counter` are deliberately untouched.
- The two drops never stack (spec §14.2): if the silent −1 already hit the
  break, a later comeback weakens by one — the break's total is exactly
  the table value, and whoever peeked at the app mid-break is never
  punished harder than whoever stayed away. The comeback card shows the
  weakened remainder.
- Full reference cycle: spec addendum §14, reference implementation,
  verify 8 009 checks / 0 failures (was 4 150 — most of the growth is the
  exhaustive non-stacking sweep over all 48 levels), golden scenario 10
  `silent_decay` including the "decay → tough → no premature deload"
  branch. The nine existing golden scenarios reproduce bit-exact.

### Technique mini-sheets for warm-up and cool-down positions (issue #34)

- Every one of the 15 positions (6 warm-up moves, 9 cool-down pool) now
  opens a reduced technique sheet from a "technique" affordance under its
  name: the position name, a block capsule ("cool-down · 15 s per side"),
  2–3 numbered steps and "Got it". For a beginner "Lat stretch with
  support" was an empty label — and the context is harsher than for
  exercises: a countdown is running, there is no time to look anything up.
- The position countdown freezes while the sheet is open and resumes from
  the same second on close — reading is not stretching. A deliberate
  divergence from the rest-phase sheet, where the timer keeps ticking.
- The steps carry the safety the names could not: no bouncing, no pushing
  into pain, unroll the spine to come up. ~40 new keys in all four
  languages; when position schematics arrive, the steps stay as captions.
- Engine and golden fixtures untouched; the warm-up block moved out of the
  flow view into its own model (Warmup.swift) on the way.

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

### The level curve on the share card (issue #24)

- The milestone card now draws the level curve — the total level after every
  workout, oldest first — above its footer, the same line the Progress chart
  draws. The curve takes only the room the headline leaves behind, capped so
  it never becomes the point of the card, and gives up its place entirely
  when the words need it.
- Fewer than two journal snapshots — no curve: a first-workout card stays
  exactly what it was. Still no body metrics and no names on the card.
- A workout that unlocks several variations now names every one of them in
  the headline, not just the first row on screen; the render and the
  share-sheet preview read the same line, so the two can never drift apart.

### The widget widens to medium, large and the lock screen (issue #23)

- One widget family became six. The medium spends its extra width on the week
  strip — spanning the whole card instead of crowding into a corner — and
  carries the total level in its header; the large lists the next workout's
  plan and closes with the week's tally; the lock screen gets all three
  accessories: a single glyph for the only at-a-glance question, a two-line
  rectangle, and an inline line.

### A design pass over Progress, Today, Rating and Calendar (issues #21, #22)

- Progress fits one screen: the pattern rows became a single legible list,
  and the chart projects the total level — or, when a row is picked, that
  pattern's own line built from the journal's snapshots — over a sparse
  first/middle/last date axis. The duplicate chips row is gone: it was the
  same list of patterns twice.
- A row's small print about where its level is heading shows only while that
  pattern is the one on the chart — detail on demand instead of eight rows of
  it at once. The chart title holds still when a pattern is picked, and the
  total level keeps to one row.
- Today marks a variation debut with an inline "new variation" pill at the
  end of the exercise name — a tier crossing swaps the exercise itself, the
  most meaningful event in the system — and quietly links the "how it works"
  explainer for everyone who skipped onboarding.
- The rating's consequence lines speak workout language — "on plan — the next
  asks a little more", "easy — progressing twice as fast" — instead of
  "+1 step / +2 steps", and "Finish now" says plainly that it keeps what is
  done and marks the rest skipped. The calendar's planned days open the
  next-workout preview.

### Site

- The landing dropped its "app is still in English" hedges: es and pt-BR
  have shipped complete since 1.7.0, so the note is gone and the technique
  card says "in your language" on all four locales.

### Housekeeping

- The RU catalog calls inverted rows «Тяга под опорой» again across all
  surfaces — «под опорой» pinpoints the body position (lying under the
  table) that the replacement name had blurred; the RU landing mockup
  follows (issue #19).
- The skip-all UI test asserts the rating summary's "Skipped" header plus
  all six rows via their accessibility labels — what VoiceOver actually
  reads — instead of the per-row word the rating redesign removed (issue #32).
- 198 → 281 automated tests: the variation-debut badge, the share card's
  headline and curve, the widget's timeline mapping and per-day words, the
  short workout's picks and the rotation anchor, cool-down composition and
  its honest edges, the side-switch pause, the position technique sheets,
  the silent decay and its non-stacking sweep against the comeback, and the
  rest-day defaults. The README table now counts what the runners actually
  execute, layer by layer.

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
