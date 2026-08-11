# Changelog

## 1.11.0

The post-audit wave: a multi-agent audit of the engine and its golden
contour (2026-08-11) confirmed 51 findings; this release works through
them wave by wave.

### Engine v2.7.0 — the do-no-harm gate (issues #88, #89, #92, #97)

The two findings on the P0 boundary and the two mechanisms behind them.
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
  is trained.
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

## 1.10.0

"Tough" used to hide three different facts. The v2.5 safety wave separated
two of them — muscles giving out, a joint complaining — and this release
gives the third its own channel: *this movement is at my ceiling and I need
longer here*. Not an injury, not a bad session, and until now it had no way
to be said. The engine steps to v2.6, verified against the reference at 9,908
property checks; no new state field, so the state and journal formats are
untouched and there are no migrations.

### Hold this level (issue #75, closes #77, #78)

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
