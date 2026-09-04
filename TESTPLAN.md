# Dredfit — manual QA checklist

Automated coverage (657 tests: 70 core + 513 app units + 74 UI tests, all confirmed green — the UI run is a single `** TEST SUCCEEDED **`, no `Failing tests:`, zero relaunches, so its own closing tally is trustworthy) is described in [README.md](README.md#testing). This document covers what a simulator or a device has to be driven by hand to confirm: system integrations, wall-clock behavior, locale passes, and anything that only misbehaves on a real screen.

**How to use.** Run the *Release smoke* block before every release. Run *Full pass* when the engine, persistence or an integration changed. Device-only rows cannot pass on a simulator and are marked ⌚. Record anything that fails in the [Issue registry](#issue-registry) at the bottom rather than fixing it silently.

**Reset between runs.** Delete the app from the simulator (long-press → Remove App) — this clears Application Support, the App Group container, HealthKit authorization and notification permissions in one go. Launching with the `--uitest-reset` argument clears state but *not* system permissions.

Legend: ✅ pass · ❌ fail (log it) · ➖ not applicable this run · ⌚ device only

---

## Release smoke (run every release)

**Automated since 1.8.1** — `DredfitUITests/ReleaseSmokeTests.swift` walks
these rows, and it is in the test plan, so the full local run at stage Э6 of
the release regulation already covers this block. To run it alone:

```sh
xcodebuild test -project Dredfit.xcodeproj -scheme Dredfit \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:DredfitUITests/ReleaseSmokeTests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Each row is an XCTest activity carrying its own id, so a failure names the row
("S3: the next-workout card is missing") without needing translation back to
this table. Two things in the table stay human: the ⌚ device-only rows
elsewhere in this plan, and the "no clipped labels" half of S7 — a judgement
about pixels, not about strings. Walk those on a device before submitting.

| # | Check | Expected |
|---|---|---|
| S1 | Cold start on a fresh install | Opens on **Today** with "Workout 1", **≈ 24–32 min**, 6 exercises, one **Start** button with nothing to agree to first, and an **"Easier"** handle on each movement row. Both minutes are engine arithmetic, not decoration — the full plan and the same plan on the sets floor: read them from the reference when they move, never off the screen |
| S2 | Full workout: Start → warm-up (opens on its "Get ready" transition) → 6 exercises → cool-down → rating | Rating screen appears; tapping an option returns to Today in the done state |
| S3 | Today after completion | Checkmark, "Workout 1 completed", a rating caption, and a **Next** card (no Start button) |
| S4 | Relaunch the app | Still in the done state — the record survived the restart |
| S5 | Calendar tab | Today is filled and tappable; the history sheet lists what was done |
| S6 | Progress tab | Total level > 0, one chart point, per-pattern bars drawn |
| S7 | Switch to Russian and repeat S1–S3 | No English leaks, no clipped labels |
| S8 | Skip three exercises, **answer** the fourth with a number, then finish the workout | The answered exercise reaches the journal as **work**, not as a fourth skip, and the history row prints the number. Re-marked for engine v2.26 (spec §37.0): the row was **Something hurt** and asserted the word "hurt" in the history — the pain channel is gone, and what replaced it as the honest channel is the number |
| S9 | An exercise the plan shows mid-step, e.g. "9-8-8" on Today | The workout screen asks 9 on the first set and 8 on the rest, and its caption names the number of the set in front of you; the history row prints the same "9-8-8". Re-marked for engine v2.22 (spec §33): the row was **Hold this level**, and that input is cancelled — the case it served is what the sub-step now handles by itself |

---

## Full pass

### 1. Workout flow

| # | Check | Expected |
|---|---|---|
| 1.1 | Tap an exercise row on Today before starting | Technique sheet opens; the workout does **not** start |
| 1.2 | Tap **Start** | Full-screen flow opens on **WARM-UP**, on the first move's "Get ready" transition (§34); the screen does not auto-lock for the whole workout |
| 1.3 | Let the warm-up run | 6 × (5 s transition + 30 s move) = 3:30. At 3-2-1 a tick sound + light haptic; at 0 a two-tone rise + success haptic starting the move; dots advance |
| 1.3a | ⌚ Play music, run a countdown to 0 | The 3-2-1 ticks and the finale are clearly audible over the music at typical media volume; the music keeps playing (mixed, not paused) |
| 1.3b | ⌚ Silent switch on | Signals are silent — haptics only. Same with **Sounds** off in settings |
| 1.4 | Tap **Skip warm-up** | The *entire* warm-up block ends (not just the current move) and exercise 1 appears |
| 1.4a | Tap **Skip this move** during the warm-up | Only the current move is skipped — the next one starts with its own transition; on the last move it ends the warm-up |
| 1.5 | Work screen layout | Header "1 / 6" and 6 capsules; exercise name; **technique** button; big planned number; "reps" (or "reps per side"); set dots; "set 1 of 3" |
| 1.6 | Tap **technique** during work | Sheet opens for the current exercise; it does not swap if the phase changes underneath |
| 1.7 | Tap **Done** on a non-final set | Rest starts at 60 s |
| 1.8 | Rest screen | "REST", a ring counting down from 60, "Next up" + next label, a **technique** button for the *next* exercise, and two outlined controls of equal weight: **+15 s** and **Skip rest** |
| 1.9 | Complete all sets of all 6 exercises | Flow reaches the rating screen |
| 1.10 | Tap **Exit** with progress on the clock (a set done, an actual entered, or mid-rest) | Confirmation dialog: **Finish now** / **Discard workout** (destructive) / **Cancel** |
| 1.10a | Choose **Finish now** | Remaining exercises are marked skipped, the rating screen opens; after rating, the workout is recorded. The exercise cut mid-way reads "not finished", fully untouched ones read "skipped" |
| 1.10b | Choose **Discard workout** | Returns to Today; nothing is recorded and no resume card appears later |
| 1.10c | Choose **Cancel** | Back in the workout exactly where it was |
| 1.10d | Tap **Exit** during the warm-up or on the very first set with nothing done | Leaves quietly — no dialog, nothing to protect |

### 2. Rest ring and backgrounding

| # | Check | Expected |
|---|---|---|
| 2.1 | Start a rest, lock the phone ~20 s, unlock | The countdown reflects real elapsed time — it does not resume where it paused |
| 2.2 | Start a rest, background the app ~20 s, return | Same: wall-clock accurate |
| 2.3 | Let a rest run to 0 in the foreground | Advances to the next set/exercise with the 3-2-1 signals |
| 2.4 | Background the app across a rest's end, then return | The flow has advanced correctly, not stalled at 0 |
| 2.5 | Tap **+15 s** during a rest | The number jumps by 15 and keeps counting down; the ring's arc shrinks to match the new total rather than running past full |
| 2.6 | Tap **+15 s** repeatedly | Allowed up to twice the rest this transition planned (60 s → four taps). At the cap the button greys out **in place** — the row does not jump |
| 2.7 | Extend, then lock the phone ~20 s | Wall-clock accurate against the *extended* end; the Live Activity on the lock screen counts to the new end, not the old one |
| 2.8 | Extend inside the last 3 seconds | The 3-2-1 signals play again on the new way down — they are not spent for the rest of the phase |
| 2.9 | Extend, then kill the app and reopen | Resuming returns to the rest with the extended time, not the planned one |
| 2.10 | **+15 s** with VoiceOver | Reads as a phrase ("Add 15 seconds of rest"), not as "plus fifteen ess" |

### 3. Hold timer (static exercises)

Reach a hold exercise — plank (core · plank) appears in the rotation; with the bar on, "Bar hang" is a hold at tier 1.

Re-marked for the hands-free wave: the hold screen has ONE start, and it buys
the whole exercise. **Start hold** still exists, but only where a set has to be
re-armed on its own — a Stop inside the mis-tap grace, and the probe set.

| # | Check | Expected |
|---|---|---|
| 3.1 | Tap **Start exercise** | Countdown runs down from the planned seconds. The screen before the tap says how many sets and how long the rest between them, and promises the exercise runs itself |
| 3.1a | Do not touch the phone again | Every set after the first begins when its rest ends, on the rest's own go — **no second count-in and no second signal** (R32). The rest counts its own last three seconds down; the minute between sets is the minute it says |
| 3.1b | Cut a rest short with **Skip rest** | THAT set is counted in — five seconds, the beat every start tap earns. A tap is somebody saying they are ready, and the hold must not land under the thumb that skipped |
| 3.1c | On the rest between two sets of a hold, tap **Pause** | The ring freezes, the number dims and reads **Paused**, and the set does NOT start while it is frozen — leave it a minute and check. **Resume** hands the clock back, and a rest resumed with a second left still gives five before the hold begins. The same rest on an exercise of REPS offers no pause: nothing there starts without you |
| 3.2 | Let it finish on a set that is **not** the movement's last | 3-2-1 signals, then the two-tone finale, and the rest begins automatically — no tap between the effort and the recovery. The movement comes back, so there is nothing to correct here |
| 3.2a | Let it finish on the movement's **last** set | The same finale at the moment the effort stops — and then the screen **stays**. The seconds held stand under a **Held** caption, **Went differently** is live again, and the primary button reads **Done**. The set is logged, and the flow moves on, on that tap. Nothing about this movement comes back, so this is the only moment its seconds can be corrected |
| 3.2b | While a hold runs, read the primary button | It says **Stop · N s** — N being what the tap would record right now, updating each second. Inside the first three seconds it says plain **Stop**: that tap cancels the set and stores nothing |
| 3.3 | **Stop the hold early** | The recorded actual is the seconds held LESS a three-second reach allowance (the tap lands after the effort stopped), snapped to the **1 s** grid and clamped to 5…90 s — exactly the figure the button named. The set then behaves as 3.2 / 3.2a for its position. Re-marked 30.08.2026: the row said "nearest multiple of 5", which the engine stopped doing in v2.21 — `SetFacts.snap` steps by one for both units (see 4.2) |
| 3.4 | Verify 3.3 on the rating screen | The summary shows "actual N", N being the seconds actually held |
| 3.5 | A per-side hold | Side one runs, then a 5 s "Switch sides" pause opens with its own falling tone, then the second side **starts itself** on the usual go, marked "second side"; the recorded actual is the **smaller** of the two sides |
| 3.6 | Before the effort, on a hold | **Went differently** is not on the screen at all, and neither is the first-workout hint that names it — nothing is entered about a set nobody has performed. The screen for sets of **reps** is unchanged, button for button |
| 3.6a | While a hold is counting down | **Skip this set** and **Skip exercise** are hidden and unresponsive |
| 3.7 | On the last set, after the hold ends, tap **Went differently** | The number the hold just recorded opens in the stepper; confirming replaces it and **Done** logs the corrected one. Before 30.08.2026 the flow left the screen in the same frame the number was produced in, and nothing about that movement ever came back |
| 3.8 | The same screen, before **Done** | **Skip this set** and the exercise escape are unresponsive: the set was performed, and its number is on screen |
| 3.9 | Kill the app on that screen and relaunch | **Continue the workout?** comes back on the same set with the recorded seconds standing. A hold never restores mid-count, so the set is offered again rather than resumed |
| 3.10 | A per-side hold as the movement's **last** set | The switch pause and the second side run exactly as in 3.5, and it is the finished SET — both sides behind it — that is handed back, with the smaller of the two sides on screen |

### 4. Adjusting and skipping

| # | Check | Expected |
|---|---|---|
| 4.1 | **Went differently** on a reps exercise | Inline stepper opens: −/value/+ and **OK**; steps by 1 within 0…30 |
| 4.2 | Same on a hold exercise | Steps by 1 within 5…90; value shows a trailing "s". Re-marked for engine v2.21 (spec §32.6): the hold ladder is relative, so a five-second grid could express only 13 of the scale's 48 rungs |
| 4.3 | Enter a value **equal to the plan** and confirm | The override is dropped entirely — the rating screen shows no adjustment for it |
| 4.4 | Enter a different value and finish the workout | Rating screen summary shows "actual N" in accent; history later shows the same |
| 4.5 | **Skip exercise** | Asks first — **Skip this exercise?**, with the sentence that says what is lost. **Keep going** leaves everything standing; **Skip the exercise** advances and marks it skipped. The button is **not red**: what the tap destroys is the numbers entered for the movement, which the sentence names, while the movement itself keeps its plan — a destructive role would argue with the message above it (owner, 31.08.2026) |
| 4.5a | **Skip this set** / **Skip remaining sets** | Both ask too, each in its own words. **Keep going** on either must leave the set, the minutes left and any number already entered exactly as they were |
| 4.5c | All three questions, side by side | Identical shape: title, the sentence, **Keep going**, **Skip**. The confirm button is the same short word in all of them **on purpose** — an alert lays its two actions out side by side only while both titles fit on one line, so per-kind labels made two controls of equal weight stack differently (in Russian "Пропустить этот подход" fit and "Пропустить это упражнение" did not). Check it in **de** and **ru** too, and at the largest accessibility size |
| 4.5b | Tap **outside** any of the three questions | Nothing happens. An alert has no anchor and swallows the tap, so the question stands until a button answers it — which is the whole point: these three controls are 44 pt targets 18 pt under the button that logs the set, and a workout has no undo |
| 4.6 | Record an actual, then skip the same exercise | The actual is discarded — a skip wins; only "skipped" is shown |
| 4.7 | Skip an exercise, complete the workout, check Progress | That pattern's level is **unchanged** (skips are neutral) |
| 4.8 | Open history for that day | The skipped exercise shows the grey "skipped" label |

### 5. Rating screen

| # | Check | Expected |
|---|---|---|
| 5.1 | Layout | "Workout N" kicker, "How did it go?", subtitle "One tap — the next workout adapts" |
| 5.2 | Three options | "Tough, did less" / "On plan" / "Easy, could do more" — **equal visual weight** (no filled card), captions "next workout eases off" / "the next one asks a little more" / "the next one asks as much more as each movement allows" — **no caption promises a multiple**: since v2.5 the growth ceiling makes "twice" false on fourth-variation work |
| 5.3 | No adjustments made | No summary card is shown — and no scope chip anywhere on the screen: the count lives in the card header now, so with nothing to show there is nothing to say |
| 5.4 | With adjustments/skips | The scope is stated **once**, in the card header: "Your rating applies to N of M" (N excludes skips **and** adjusted exercises). No chip under the title. Below it the lists label themselves: "DISCOMFORT" and "SKIPPED" over their rows, adjusted rows sitting directly under the header. Skipped rows are dimmed names with **no** per-row word; the one exception is the "Finish now" exercise, whose row reads "not finished". VoiceOver still reads every row with its state. The footer "These keep their level either way." appears only when something **was** set aside |
| 5.5 | Tap any option | Submits immediately — the card *is* the button; returns to Today |
| 5.6 | Choose "On plan" and check Progress next session | Each non-skipped pattern rose by exactly 1 level |

### 6. Rest days

| # | Check | Expected |
|---|---|---|
| 6.1 | Settings → **REST DAYS**, fresh install | Monday, **Wednesday and Friday** highlighted — four workouts a week, the rhythm both captions name; captions "Highlighted days are rest days" and "2–3 rest days a week is the recommended rhythm". An install upgrading from a file without the key keeps Sunday only (issue #36) |
| 6.2 | Chip order | Starts at the locale's first weekday (Monday for ru and de, Sunday for en-US) |
| 6.3 | Select a second rest day | Both highlighted; Calendar marks both |
| 6.4 | Try to select a **7th** rest day | Refused — six is the maximum |
| 6.5 | Calendar rendering on a rest day | A soft filled circle, clearly distinct from an out-of-month day; the legend lists **rest** |
| 6.6 | **Today** screen on a rest day | Reads "Rest day" with the next workout date and a recovery line; **no Start button**. "Train anyway" opens the normal flow |
| 6.7 | Complete a workout, then check the "Next" card | Skips over rest days when naming the next training day ("tomorrow", "on Wednesday") |

### 7. Reminders

| # | Check | Expected |
|---|---|---|
| 7.1 | Enable **Reminder** | iOS permission prompt appears (alert + sound, no badge) |
| 7.2 | Deny the permission | The toggle flips back **off** — it reflects the system's answer |
| 7.3 | Allow, then keep the default rest days | A 28-day window of **one-shot** notifications, one per training date (**16** with the three default rest days — 28 days less four Mondays, four Wednesdays and four Fridays); none on rest days. The window refills every time the app becomes active |
| 7.4 | Change **Time** | Every pending slot moves to the new time |
| 7.5 | Add a rest day while the reminder is on | That weekday's dates disappear from the window |
| 7.6 | Disable the reminder | All pending reminders are removed |
| 7.7 | Complete today's workout **before** the reminder time | No notification that day; tomorrow's slot stays |
| 7.8 | ⌚ Wait for a scheduled fire | Notification titled "Dredfit", body "Today's workout is ready" |

### 8. Backup export / import

| # | Check | Expected |
|---|---|---|
| 8.1 | Do 2–3 workouts with adjustments and skips | History populated |
| 8.2 | Settings → **Export history** | Share sheet offers a JSON file; save it to Files |
| 8.3 | Inspect the JSON | Three top-level keys: `engineState`, `records`, `settings` |
| 8.4 | Delete the app, reinstall, **Import history** | Confirmation "Replace history?" with **Replace** (destructive) / **Cancel** |
| 8.5 | Confirm the import | History, levels, settings and rest days are all restored exactly |
| 8.6 | Cancel instead | Nothing changes |
| 8.7 | Import a non-Dredfit JSON file | "Couldn't read this file." — existing data is untouched |
| 8.8 | Import a backup taken before Health was enabled | The Health high-water mark does not move backwards (no re-export) |

### 9. Pull-up bar module

| # | Check | Expected |
|---|---|---|
| 9.1 | Settings → **EQUIPMENT** → enable **Pull-up bar** | Caption: "Every other workout swaps the row for a vertical pull" |
| 9.2 | Look at the next workout, then the one after | The pull slot **alternates**: floor pull, then vertical pull, and so on |
| 9.3 | Technique for a bar exercise | Opens correctly for Bar hang / Negative pull-up / Partial pull-up / Pull-up |
| 9.4 | Train the bar branch a few sessions | Its level rises independently of the floor pull's level |
| 9.5 | Progress tab | A "Vertical pull" level row appears; tapping it projects the bar branch in the chart |
| 9.6 | Turn the bar back **off** | Sessions return to floor pull only; the Vertical pull row **stays visible** because progress exists; its level is preserved |
| 9.7 | Re-enable the bar | Resumes at the preserved level, not from zero |

### 10. Apple Health ⌚

Simulator HealthKit is unreliable; run this on a device. Rows 10.13 and 10.14
need a paired Apple Watch to mean anything.

| # | Check | Expected |
|---|---|---|
| 10.1 | Settings → **HEALTH** → enable | Permission sheet asks to **write** workouts and active energy, and to **read** weight, height, date of birth, sex, resting energy and workouts; each purpose string says what it is for |
| 10.2 | With existing history, on enabling | Offered a backfill; choosing "Only new ones" exports nothing historical |
| 10.3 | Complete a workout | It appears in the Health app as *Functional Strength Training* with the real duration |
| 10.4 | Run a backfill with history present | Each past workout appears **once** |
| 10.5 | Run the backfill **again** | **No duplicates** are created |
| 10.6 | Turn Health off, complete a workout, turn it on again | The workout done while off is not silently lost — it backfills, and still no duplicates |
| 10.7 | Deny the Health permission | The toggle reflects the denial; nothing is written |
| 10.8 | With a weight already recorded in Health, enable the toggle | The **Body weight** row fills itself in — nothing to type — and says **Taken from Health, and kept up to date**; it no longer opens an editor |
| 10.9 | Type a weight, disable Health, enable it again | Health wins: the row shows the **recorded** weight, not the typed one. The phone has one owner, and their weight lives in Health — the field is for the case Health cannot answer |
| 10.9a | Weigh yourself again in Health, then background Dredfit and reopen it | The row shows the **new** number. It is re-read on every activation, not copied once when the toggle went on |
| 10.9b | Restore a backup taken on another phone | The weight travels, but the row is **editable** again and drops the "Taken from Health" line until this device's Health answers for itself |
| 10.10 | With **no** weight in Health (or the read refused): clear the weight (empty field → Save), complete a workout | The row is editable, clearing it works, the workout still reaches Health with **no** calories, and the row under it says why |
| 10.11 | With a weight set, complete a workout | The entry carries active energy — **80–115 kcal** for a 35-minute session at 80 kg, and 60–210 across the whole span of plans. Never a four-digit number. The band is the model replayed over all 282 plans in `golden.json`, not a guess: the median session is 33 min and 84 kcal, so a wider band would pass a broken build |
| 10.12 | The Move ring for that day | Rises by that amount, once |
| 10.13 | Record the same session on an Apple Watch too ⌚ | The Dredfit entry appears **without** calories, and the day's active energy counts the watch's figure once |
| 10.14 | Turn on **Leave calories out**, complete a workout | No calories, whatever Health happens to contain. The switch is the one way to say it for **either** reason its caption names — a watch recording the same session, or simply not wanting an estimate |
| 10.14a | With a weight in Health, try to switch calories off by clearing the weight | Not possible, and that is the point: the row is read-only while Health supplies the number. **Leave calories out** is where that answer lives now |
| 10.15 | Refuse the **read** permissions, complete a workout | Calories are still written — the app cannot tell a refusal from an empty Health — and 10.14 is the way out |
| 10.16 | Backfill with history and a weight set | Past days gain calories as well, and each past workout still appears once |
| 10.17 | Pause mid-workout for ten minutes, then finish | The duration in Health grows by the pause; the calories do not — they are priced from the plan |
| 10.18 | Decline **both** the warm-up and the cool-down, complete the workout ⌚ | The calories come out roughly a quarter lower than the same plan with both blocks done (≈82 vs ≈107 kcal on a 35-minute plan at 80 kg). The flow's stamping of the two blocks is reachable only through the view — **no automated test covers it**, so this row is the only guard |
| 10.19 | Start the warm-up, then tap "Skip warm-up" halfway | Charged for the part that ran: the figure lands between 10.18's and a full session's |
| 10.20 | Skip every exercise, then finish the workout | The entry appears in Health with its duration and **no calories at all** — nothing was performed |

### 11. Live Activity ⌚

| # | Check | Expected |
|---|---|---|
| 11.1 | Start a workout, reach a rest, lock the phone | Lock screen shows the Dredfit activity: next exercise + a live countdown |
| 11.2 | Watch the countdown on the lock screen | Counts down in real time (rendered by the system) |
| 11.3 | Dynamic Island (iPhone 14 Pro and later) | Compact shows a training glyph + countdown; expanded shows the next exercise |
| 11.4 | Finish the workout | The activity disappears immediately |
| 11.5 | Exit mid-workout | The activity disappears |
| 11.6 | Force-quit the app during a rest | The card dims once stale; the next cold launch of the app removes it entirely (no zombie card until the system cap) |
| 11.7 | Start a second workout right after a first | Exactly one activity is present, not two |

### 12. Widgets and lock-screen accessories

The snapshot contract is unit-tested on every run (the snapshot URL is injected, so these no longer skip on unsigned/CI runs): `testWidgetSnapshotMirrorsWeekStatuses`, `testWidgetSnapshotCarriesTheStepsWeekAndPlan`, `testWidgetSnapshotFromAnOlderBuildStillDecodes` and `testWidgetSnapshotWeekFromBeforeTheScaleChangeStillDecodes`. What these manual checks still own is the WidgetKit side: timeline rendering, reload timing, the real App Group container, and everything that only misbehaves on a real screen.

| # | Check | Expected |
|---|---|---|
| 12.1 | Add the small **Today's status** widget | Renders without a placeholder |
| 12.2 | Before today's workout | "Workout N" with an accent dot |
| 12.3 | After completing today's workout | "Done ✓" — and it updates without opening the app again |
| 12.4 | On a rest day | "Rest day" in muted ink |
| 12.5 | Change rest days in settings | The widget reflects the change |
| 12.6 | Leave the device overnight past midnight | The widget flips to the new day's status **without** the app being launched |
| 12.7 | Add the **medium** widget | Status on the left; on the right the total level and a Monday–Sunday strip |
| 12.8 | Compare the strip with the Calendar tab | Same marks for the same days: filled = done, quiet fill = rest, outline = planned, accent ring = today |
| 12.9 | A training day earlier this week that was missed | Blank in the strip — no ring, no fill, nothing that reads as a reproach |
| 12.10 | Add the **large** widget on a training day | The plan of today's session: 6 rows, name and load; a weekly summary line at the bottom |
| 12.11 | The large widget once today is done, or on a rest day | The plan is labelled "Next: Workout N · \<when\>" so it cannot be read as today's |
| 12.12 | A deload week on the large widget | The summary shows a **negative** level delta, not a hidden or clamped one |
| 12.13 | Add all three lock-screen accessories | Circular: a glyph only — figure / checkmark / moon. Rectangular: "Today", the headline, minutes and exercise count. Inline: the headline (plus ≈ minutes on a training day) |
| 12.14 | Glance at the circular accessory on a rest day vs a training day | The two silhouettes are told apart without reading |
| 12.15 | ⌚ Every family in **dark mode** | Background and ink follow the system; no white tile among dark widgets |
| 12.16 | ⌚ Live Activity on the lock screen in dark mode | The card is dark, not a white flash; the countdown stays accent and readable |
| 12.17 | Install over the previous version without opening the app | The widget keeps rendering from the old snapshot instead of blanking (new fields decode as absent) |
| 12.18 | Long-press the widget on the home screen and tap each entry of the size row | App icon, small, medium and large are all offered; tapping small, medium or large converts the widget in place and it redraws in that layout — not a silent no-op |
| 12.19 | The same three conversions by dragging the corner handle in edit mode | The same result as the menu: no size is reachable one way and not the other |
| 12.20 | Add **Today's status** straight from the gallery at each of the three home sizes | Three size pages under the widget; each one adds at the size on screen |
| 12.21 | The large widget in Russian, Brazilian Portuguese and German, on a session carrying the longest names — "Bird dog (hold)", whose load prints per side; German compounds ("Einbeiniges rumänisches Kreuzheben") are the new length crown | Every plan row keeps its whole name: it shrinks a little rather than ending in an ellipsis. The weekly summary line stays on one line |
| 12.22 | ⌚ Flip the system appearance mid-workout — widget on the home screen, a rest counting down on the lock screen | The app, the widget and the Live Activity all redraw in the new scheme without relaunching anything; the countdown stays accent; the workout state is untouched |

A conversion that seems to do nothing is a page question before it is a widget
question: check the page has room for the larger footprint, and re-run §12.18
on a page that does — see I-11.

### 13. Date rollover and edge cases

| # | Check | Expected |
|---|---|---|
| 13.1 | Complete a workout, then move the clock past midnight | Today returns to the plan state offering the next workout |
| 13.2 | Cold-start the app on a day already completed | Opens on **Today** in its completed state (the calendar keeps its "Completed today" card one tap away) |
| 13.3 | Cold-start on a day not yet completed | Opens on **Today** with the plan |
| 13.4 | Complete a workout at 23:59, check the calendar at 00:01 | The record sits on the day it was performed |
| 13.5 | Change the device timezone, reopen | No duplicated or missing calendar days |
| 13.6 | Kill the app mid-workout and relaunch | No partial record is written; Today offers **Continue the workout?** (see §24) |

### 14. Localization (run the whole Full pass in en and ru; spot-pass the other locales)

| # | Check | Expected |
|---|---|---|
| 14.1 | Every screen in **English** | No missing keys, no raw identifiers |
| 14.2 | Every screen in **Russian** | Complete translation; exercise names and all technique text translated |
| 14.3 | Russian typography | Uses `е`, never `ё` (a deliberate project convention) |
| 14.4 | Next-training-day label in Russian | Correct preposition: "во вторник", "в среду" |
| 14.5 | Calendar weekday order per locale | Russian and German start Monday |
| 14.6 | Notification, widget and Live Activity text | Localized too — not just the main app |
| 14.7 | Long Russian labels | Nothing clipped or truncated mid-word |
| 14.8 | Key screens in **German** (Today, workout, rating, Progress, settings) | Complete translation; du always lowercase mid-sentence, no gendered noun for the athlete; next-training label reads "am Montag" |
| 14.9 | Long German compounds ("Einbeiniges rumänisches Kreuzheben", "Handstand-Liegestütze mit Brust zur Wand") | Nothing clipped or truncated mid-word on plan rows, sheets and the widget |
| 14.10 | Key screens in **French** | Complete translation, tu throughout, nothing describing the reader with a gendered participle; next-training label reads "le mardi" |
| 14.11 | French punctuation on screen | A no-break space before `:` and a narrow one before `? ! ;` — the mark never starts a line on its own, and never sits flush against the word |
| 14.12 | Key screens in **Italian** | Complete translation, tu throughout, buttons in the imperative ("Inizia", "Salta"); next-training label is the bare weekday, with no gendered article |
| 14.13 | The longest names in both ("Élévation de mollet à une jambe sur une marche", "Sollevamenti sulle punte a una gamba sullo scalino") | Nothing clipped or truncated mid-word on plan rows, sheets and the widget — these two are the longest in the library |

### 15. Progress, calendar, history

| # | Check | Expected |
|---|---|---|
| 15.1 | Progress header | Total level, beside it "level" / "N workouts". No weekly summary line — the space belongs to the chart |
| 15.1a | Header at a four-digit total, in Russian (1.8.0) | The number stays on **one** line — never broken mid-digit ("1 27" / "0"); the caption stays on two lines |
| 15.1b | Header share button | A round icon (the word does not fit beside the number in Russian), centred on the height of the number's line |
| 15.1c | Header at an accessibility type size | The caption drops under the number instead of pushing the row off either edge; the share glyph stays inside its ring |
| 15.3 | Chart projection | Tapping a pattern row tints it and plots that pattern only; the kicker over the chart names the projection ("PUSH — PUSH-UP"); "Show all" resets to the total — no chips row |
| 15.3a | Chart x-axis | Two–three sparse date labels (first / middle / last workout); no label before the second workout |
| 15.3b | Per-pattern bars | One line per pattern: name, bar with white ticks at band boundaries, level. No per-row detail in the all-patterns view |
| 15.3d | Select a pattern (1.8.0) | Only the selected row grows a detail line under it — the current variation and its position ("Push-up · 2/4") on the left, "next in N" (or "+1 set in N" at tier 4, nothing at the ceiling) on the right; the tint covers both lines |
| 15.3e | Back to all patterns | The detail line disappears — from the view hierarchy, not merely off-screen |
| 15.3c | Selecting a pattern, in Russian (1.8.0) | The kicker and the chart under it **do not move**: the title stays on one line (shrinking, then truncating) and "Show all" keeps its place even while hidden |
| 15.3f | A history with a gap of 7 days or more | A grey band spans the gap behind the line, with the duration inside it ("9 days"); a narrow band keeps the band and drops the label. No gaps means no band and no reserved space |
| 15.3g | The line under the chart | States the longest break and its length. It adds "The plan met you lower." **only** where the level fell across that gap *and* the first workout back cannot explain the drop itself — neither rated "Tough, did less" nor carrying an entered number. Otherwise it says the break and stops. Several gaps add "Others are marked too." |
| 15.3h | Come back after 2+ weeks, decline "Start easier", then rate the session **tough** | The band is drawn, the line names the break — and does **not** say the plan met you lower: nothing decayed, the rating took that step |
| 15.3i | Same, but rate **on plan** and enter a smaller number on one exercise | Same again in that movement's projection: the drop is the entered number, not the break |
| 15.3j | The same history in a per-pattern projection | The bands sit in the same places — gaps are calendar facts — while the causal half is computed for that pattern |
| 15.4 | History of an on-plan workout | Exercises with planned volumes and no "actual" annotations |
| 15.5 | History of an adjusted workout | "actual N" in accent on the adjusted rows only |
| 15.6 | History footer | "Total level after: N" |
| 15.7 | A very old record with no exercise snapshot | "No details saved for this workout." rather than an empty list or a crash |

### 16. Accessibility and display

| # | Check | Expected |
|---|---|---|
| 16.1 | Dynamic Type at the largest accessibility size | Every screen usable, nothing clipped. The rep counter, rest countdown, total level and completion tick grow to a cap; the rest ring grows with its countdown |
| 16.2 | VoiceOver through the workout flow | Every control is reachable and announced meaningfully |
| 16.3 | Dark mode / light mode, every screen of the full pass | The app follows the system: every surface sits on the token ground (`bg`), no white flash survives in dark, ink-filled buttons flip their label with the scheme, sheets carry the token background |
| 16.3a | Increased Contrast on, in **both** schemes | The palette steps up: labels and hairlines strengthen visibly (the high-contrast token variants), nothing disappears or clips |
| 16.4 | Smallest supported device (iPhone SE) | Nothing clipped |
| 16.5 | Reduce Motion enabled | No motion sickness triggers |

### 17. First run and the explainer (1.4)

| # | Check | Expected |
|---|---|---|
| 17.1 | Delete the app, reinstall, launch | Opens on the onboarding: "Training at home. No questionnaires." |
| 17.2 | Page through all three cards, tap **Start** | Lands on Today with the workout plan |
| 17.3 | Relaunch | The onboarding does **not** come back |
| 17.4 | Reinstall, tap **Skip** on card 1 | Lands on Today; a relaunch does not show it again |
| 17.5 | Install over existing history (upgrade from 1.3) | No onboarding — it is for a genuinely fresh install only |
| 17.6 | Settings → first row → **How it works** | **Eleven** numbered sections under "Eleven things worth knowing about the regulator."; the count in the subtitle matches the sections below it — a stale count here has shipped twice (I-7, I-13) — and the numbers agree with the engine (±1/+2, three shortfalls → −3, five of eight rotations) |
| 17.7 | Same screen in Russian | Fully translated, no English left, no `ё` |

### 18. Milestones (1.4)

| # | Check | Expected |
|---|---|---|
| 18.1 | Finish a workout that crosses a tier on some pattern | One screen, "NEW STEP", the name of the **newly unlocked** exercise, "<pattern> · step N of 4" |
| 18.2 | Finish an ordinary workout | No milestone screen — straight back to Today |
| 18.3 | Finish a workout rated **less** | No milestone screen (a step down is never announced) |
| 18.4 | Finish the 10th workout | "WORKOUT #10" with "10 workouts behind you" |
| 18.5 | A workout that both tiers up and hits a jubilee | Both on one screen, tier-up above the jubilee |
| 18.6 | Cross from level 31 to 32 | "Now 4 sets" rather than a tier-up |
| 18.7 | Skip an exercise that would otherwise have tiered up | No milestone for it — a skip changes nothing |
| 18.8 | **Done** on the milestone screen | Returns to Today with the workout recorded |

### 19. Share card (1.4)

| # | Check | Expected |
|---|---|---|
| 19.1 | **Share** on a milestone screen → save the image | PNG, exactly 1080×1350 |
| 19.2 | Inspect the card | Wordmark, accent rule, milestone line, date without a time, `dredfit.com`. **No** body metrics, weight, photo or name |
| 19.3 | Progress tab → share icon | Card reads "N workouts · level M" — the same one word the header uses |
| 19.4 | Progress tab on a fresh install | No share icon (nothing to show yet) |
| 19.5 | Aeroplane mode | Card still renders — generation is entirely local |
| 19.6 | Card in Russian | Correct plural forms ("10 тренировок", "4 подхода" vs "5 подходов") |
| 19.7 | Share a milestone screen with several unlocks (1.8.0) | The card names **every** unlocked variation, comma-separated, not only the first row |
| 19.8 | The same in Russian, with the longest names, on a calibration workout | The headline steps down in size; the date and `dredfit.com` stay on the card |
| 19.9 | Inspect the ground | Flat ink, exactly as before — the app owns no gradients and the card must not either |
| 19.10 | Share from Progress with a few workouts behind you | A plain accent line runs across the bottom: no fill under it, no shading |
| 19.11 | Compare the curve with the Progress chart | The same drawing: straight segments, a dot on the latest session, and a scale that starts at zero — the card must not steepen the line the app draws flat |
| 19.12 | Share a milestone, then finish another workout and re-share the same milestone screen | The milestone card's curve stops at the workout that earned it |
| 19.13 | Share after the very first workout | No curve at all — one session is a dot, not a history. The card falls back to the earlier layout |
| 19.14 | A deload week where the total did not move | The curve renders as a flat line, not missing and not a division-by-zero artefact |
| 19.15 | The longest Russian headline again | The curve steps aside entirely rather than pushing `dredfit.com` off the card |

### 20. Review request (1.4)

| # | Check | Expected |
|---|---|---|
| 20.1 | Milestone screen closed with fewer than 5 workouts | No review prompt |
| 20.2 | Milestone after a session rated **less** | No review prompt |
| 20.3 | Milestone, ≥5 workouts, not rated less, never asked before | System review prompt may appear (iOS may still suppress it) |
| 20.4 | Trigger the conditions again the next day | No second prompt — the 60-day floor is recorded even if iOS showed nothing |
| 20.5 | Settings → About → **Rate in App Store** | Opens the App Store review sheet for id6791739610 |
| 20.6 | Settings → About → **Recommend Dredfit** | System share sheet with the App Store link |

### 21. Calibration on the first workout (1.5)

| # | Check | Expected |
|---|---|---|
| 21.1 | Fresh install → first workout → rating screen | A hint under the rating: open the list and enter what you actually did |
| 21.2 | Enter 20 against a plan of 8, rate "on plan" | That pattern jumps to level 12 immediately, not to 2 |
| 21.3 | Second workout, enter an enormous number on the same pattern | Level moves by exactly +2 — the cap is back |
| 21.4 | Enter 5 against a plan of 8 on the first workout | Level stays 0; no deload builds up from it |
| 21.5 | Enter a number and skip that same exercise | The skip wins; level unchanged |
| 21.6 | Hint after any workout but the first | Not shown |

### 22. Comeback after a break (1.5)

| # | Check | Expected |
|---|---|---|
| 22.1 | Last workout 13 days ago | No card |
| 22.2 | Last workout 20 days ago | "Welcome back" card above Start |
| 22.3 | Tap **Start easier** | Plan drops two steps; card gone; nothing new in the journal |
| 22.4 | Tap **Leave as it was** | Plan unchanged; card gone |
| 22.5 | Relaunch after either answer | Card does not return |
| 22.6 | Complete a workout, then wait another 14+ days | Card is offered again — a new break is a new question |
| 22.7 | Last workout 200 days ago | Card also offers **Start from scratch**, behind a confirmation |
| 22.8 | Confirm Start from scratch | Levels reset; history kept; pull-up bar setting kept |
| 22.9 | First hard session after a comeback | A plain −1, no deload — the streak was reset |

### 23. Softer tier changes (1.5)

| # | Check | Expected |
|---|---|---|
| 23.1 | Cross from level 7 to 8 on any pattern | New variation asks for 6 reps, not 8 |
| 23.2 | Reach a tier-3 exercise (pistol squat, level 16) | 5 per side |
| 23.3 | Reach a tier-4 exercise (level 24) | 4 per side |
| 23.4 | Levels 0–7 on any pattern | 8 to 15 reps; holds walk the tier-1 ladder 20-22-24-26-29-32-35-39 s (engine v2.21, spec §32.1 — the step is ~10% of the dose, not a flat five seconds) |
| 23.5 | Adjust an actual on a tier-2+ exercise | Placeholder shows the planned number from the session, not a hardcoded 8 |

### 24. Interrupted workout and resume (design-audit wave)

Simulate process death by swipe-killing the app from the app switcher (or `terminate` in a debugger). The snapshot is written on every phase transition.

| # | Check | Expected |
|---|---|---|
| 24.1 | Kill during a **rest**, relaunch within minutes, tap **Continue** | The flow reopens **inside the same countdown** (wall-clock accurate), then advances normally |
| 24.2 | Kill during a rest, wait until the rest would be long over, **Continue** | Lands on the **work screen of the set the rest was leading into** — the finished set is not replayed |
| 24.3 | Kill on a **work** screen mid-set | Resumes at that exercise and set; a hold that was counting simply starts the set over |
| 24.4 | Kill on the **rating screen**, relaunch, **Continue** | Card says the workout is done and only the rating is left; Continue opens the **rating screen** (not the last set); actuals and skips are intact |
| 24.5 | Tap **Start over** on the resume card | A fresh session starts from the warm-up; the old snapshot is gone for good |
| 24.6 | Kill right after the warm-up with the first set untouched | **No resume card** — plain Start (with its warm-up); "continue nothing" is never offered |
| 24.7 | Relaunch more than **3 hours** after the interruption | No resume card — a different training occasion, not an interrupted one |
| 24.8 | Interrupt a workout, toggle the **pull-up bar** in settings, return to Today | No resume card — the session would regenerate with different exercises, and the snapshot must not resume into them |
| 24.9 | Interrupt a workout, accept a **comeback** offer (if present), return | Same: no resume card once the plan regenerated differently |
| 24.10 | Complete the workout normally (or discard via Exit) | No resume card afterwards, ever |
| 24.11 | Rate a resumed workout | Exactly **one** record in the journal; actuals and skips from before the kill are in it |
| 24.12 | Resume card in Russian | «Продолжить тренировку?», позиция упражнения, «Продолжить» / «Начать заново» — no English leaks |

### 25. Calendar day states (design-audit wave)

| # | Check | Expected |
|---|---|---|
| 25.1 | A **past** training day with no workout | A plain dimmed number — **no ring, no mark**; VoiceOver reads just the date |
| 25.2 | A **future** training day | The grey "planned" ring |
| 25.3 | A rest day (any past or future) | The soft filled circle, visible both in the grid and as the 13 pt legend dot |
| 25.4 | The legend | completed · planned · rest · today — every dot distinguishable on a real screen at normal brightness |
| 25.5 | Tap the **next** training day (today's ring before the workout, or the next planned ring after it) | NextWorkoutSheet opens — same preview as the Today done-card; no Start button. Other planned days stay inert |

### 26. Design-review wave

| # | Check | Expected |
|---|---|---|
| 26.1 | Today header | "Why this plan?" link next to "≈ N min · N exercises"; tapping opens "How it works", "Got it" dismisses |
| 26.2 | A workout whose plan first shows a harder variation | That row carries a small "new variation" pill; the pill is not separately tappable — the row still opens technique |
| 26.3 | The badge after a deload and re-climb | Returning to a variation already performed does **not** re-badge it |
| 26.4 | Badge across languages | «новая вариация» / "nueva variación" / "nova variação" / "neue Variante" / "nouvelle variante" / "nuova variante" — no clipping next to long exercise names |
| 26.5 | Badge on the longest names (pt-BR "Flexão em parada de mão de frente para a parede", it "Sollevamenti sulle punte a una gamba sullo scalino", fr "Élévation de mollet à une jambe sur une marche") | The pill trails the name inline and wraps with it as a unit; the name wraps — **no ellipsis**; the load stays on the first line |
| 26.6 | Progress fits one screen | No chips row; header stats + chart + all 9 rows (10 with the bar branch) visible together on a 6.1" screen at default type, spaced apart rather than stacked flush |
| 26.6a | Pattern names in every language (1.8.0) | Each name holds one line — the widest are "Горизонтальный жим" and "Empurrão horizontal"; a wrapped name would cost the row its air |
| 26.7 | Progress row selection | Tap a row → accentSoft tint + chart re-projects + kicker reads "PATTERN — VARIATION"; a second tap on the same row or "Show all" (accentText) resets to the total; VoiceOver reports the selected trait |
| 26.8 | Selection tint at the edges | The tint reaches ≈8 pt into both gutters with **rounded** corners — no flat-cut edges |

### 27. Life-benefit line (issue #25)

| # | Check | Expected |
|---|---|---|
| 27.1 | Open any technique sheet | An "IN LIFE" section below the mistakes with one line in secondary ink; present for **every** exercise, including bar-module ones |
| 27.2 | Technique sheet for Pistol squat, Push-up, Pull-up, Chest-to-wall handstand push-up | The **override** line, not the movement's base line |
| 27.3 | Technique sheet for a non-override variation of the same movements (e.g. Knee push-up, Shrimp squat) | The movement's **base** line |
| 27.4 | Milestone "New variation" | The life line under "<pattern> · variation N of 4"; override → base rule as above |
| 27.5 | "Now N sets" and jubilee milestones | **No** life line — abilities belong to variations, not to volume or habit |
| 27.6 | All seven languages (with §14) | Lines read naturally, informal register in es/pt-BR/de/fr/it, no "ё" in RU; nothing clips on the sheet or the milestone at default type |
| 27.7 | Largest accessibility type | Both surfaces wrap without truncation; the sheet scrolls to keep "Got it" reachable |

### 28. Jubilee retrospective (1.8.0, issue #26)

| # | Check | Expected |
|---|---|---|
| 28.1 | Reach an anniversary (workout 10, 25, 50…) with an old snapshot in the journal | Under "WORKOUT #N": "Then: <variation> · S×R — Now: <variation> · S×R" plus "N weeks/months since your first workout" |
| 28.2 | The movement named | The one with the **largest level gain** since the first snapshot; sets/reps match what the engine would prescribe at those levels (incl. hold movements as "S×R s") |
| 28.3 | Fresh install reaching workout 10 with no growth (rate "less" throughout) | Jubilee shows **without** the retrospective — never a zero or negative comparison |
| 28.4 | Journal imported from a pre-1.1 backup (no levelsAfter anywhere) | Jubilee as before, no crash, no empty "Then:" |
| 28.5 | **Share** on an anniversary | The card carries the same two lines under the date; the curve yields space rather than pushing the footer off |
| 28.6 | Non-anniversary milestone share | Card unchanged — no retrospective lines |
| 28.7 | All seven languages | "Тогда/Сейчас", "Antes/Ahora", "Antes/Agora", "Damals/Jetzt", "Avant/Maintenant", "Prima/Ora"; week/month plurals correct (RU: неделя/недели/недель) |

### 29. Short workout (1.8.0, issue #27)

> **This whole section is void from v2.27:** the short workout was removed — no picking three of six movements, no rotation anchor to guarantee they cycle. Kept as the history of what the app used to promise; a green row here would mean the mechanism came back. See §46.

| # | Check | Expected |
|---|---|---|
| 29.1 | Today, a training day | Under the duration, beside the sets handle: **"Fewer movements · 3 of 6 · ≈ N min"**; N is noticeably below the full estimate above. It is a handle on the plan, not a second start button |
| 29.2 | Tap it, then **Start** | The line above becomes "≈ N min · 3 exercises" and the handle turns into **"All movements back"**; the workout then runs the warm-up as usual, then "1 / 3" and three capsules — the same exercises, same numbers, as the plan above showed |
| 29.3 | The three chosen | The pull slot (or **Bar hang**/pull-up branch with the bar on), the rotation anchor, and the lowest-level of the rest |
| 29.4 | Finish and rate | Rating screen lists the untouched three under their own **SKIPPED** header — dimmed names, no per-row word, no "ADJUSTED" when nothing was adjusted; scope chip reads "applies to 3 of 6" |
| 29.5 | Progress after it | The three trained moved; the three skipped are **unchanged**; the workout counter advanced by one |
| 29.6 | History for that day | Six exercises, three marked skipped |
| 29.7 | Kill the app mid-short (swipe up) and relaunch | "Continue the workout?" says "exercise N of **3**"; Continue resumes the **short** flow, not the full six |
| 29.8 | "Start over" from that card | The full session, warm-up included — starting over is not starting short |
| 29.9 | Next training day | Today opens on the full session by default; the short version is again only an offer, with no mention of last time |
| 29.10 | Eight short workouts in a row | Every movement appears at least once across them (the anchor guarantees it) |
| 29.11 | All seven languages | The button fits on one line at default type; es/pt/de/fr/it do not clip ("Peu de temps ? Version courte · ≈ N min") |

### 30. Cool-down (1.8.0, issue #28)

| # | Check | Expected |
|---|---|---|
| 30.1 | Complete the last exercise's last set | "COOL-DOWN" header, six dots, a 5 s "Get ready" transition (§34) and then "Hip flexor stretch" with a 15 s countdown and "15 s per side" hint |
| 30.2 | The six positions | Hip flexors → chest and shoulders → three from the session's movements (dedup'd, session order) → rest pose last; no duplicates |
| 30.3 | The mapped three | Match what was performed: fold for squat/hinge, lats for pulls, wrists for pushes, twist for core, calf at the wall, seated glute for lunges |
| 30.4 | Let it run | 6 × 30 s of stretching = the reserved 3:00, plus a 5 s side-switch pause per unilateral position and a 5 s transition per position (§34). Hip flexors and chest-and-shoulders are always among the six and both run per side, so the block is never shorter than 3:40; with three per-side positions among the mapped three it reaches 3:55. All of it sits inside the "≈" every estimate carries; the rating follows |
| 30.5 | "Skip this move" / "Skip cool-down" | One position or the whole block; either way the rating still comes and the workout records exactly as before |
| 30.6 | "Finish now" from mid-workout | **No** cool-down — whoever cut the workout short is out of time by definition |
| 30.7 | Skip all six exercises | No cool-down either — nothing was trained, nothing to stretch |
| 30.8 | Short workout | Cool-down composed from the **three performed** movements only |
| 30.9 | Kill the app during the cool-down, relaunch, Continue | Lands on the rating screen — the work is behind, nobody returns to finish a stretch |
| 30.10 | Health duration | The workout's recorded duration includes the cool-down time |
| 30.11 | Background mid-position, return after a while | The countdown reflects real elapsed time and jumps over positions it already covered |
| 30.12 | All seven languages | Position names and hints read naturally; nothing clips |

### 31. Side-switch pause (issue #35)

| # | Check | Expected |
|---|---|---|
| 31.1 | A unilateral cool-down position (hip flexors is first, chest and shoulders second) | 15 s first side → "Switch sides" in accent with a 5→1 countdown → 15 s marked "second side"; bilateral positions (forward fold, lats, rest pose) still run one 30 s countdown. Every position whose steps say to swap must be counted by the app — chest and wrists were not, until 1.8.2 (I-10) |
| 31.2 | Listen at each boundary | The pause opens with a **falling** two-tone (the go inverted) — audibly distinct from the rising go that starts the second side and the next position; 3-2-1 ticks precede the end of each side, none inside the pause |
| 31.3 | A per-side hold (bird dog / side plank) | After side one the same pause runs and the second side starts itself — no tap; **Stop**, **Went differently** and **Skip exercise** are unavailable during the pause |
| 31.4 | Stop the second side within the first ~3 s | Mis-tap grace: the countdown cancels and **Start hold** returns for the second side, first side's result intact |
| 31.5 | Kill the app during a hold's pause, relaunch, Continue | The set starts over from side one — holds are never restored mid-count; during the cool-down's pause it restores to the rating as before |
| 31.6 | All seven languages | "Switch sides" reads naturally (Cambia de lado · Troque de lado · Смени сторону · Seitenwechsel · Change de côté · Cambia lato); nothing clips |

### 32. Position technique mini-sheets (issue #34)

| # | Check | Expected |
|---|---|---|
| 32.1 | Every warm-up move and cool-down position | A **technique** affordance under the name; the mini-sheet opens with the name, a block capsule ("warm-up · 30 s" / "cool-down · 30 s" / "cool-down · 15 s per side"), 2–3 numbered steps and **Got it** — all 15 positions |
| 32.2 | The countdown while the sheet is open | **Frozen** — the number does not move; closing the sheet resumes from the same second. A deliberate divergence from the rest-phase sheet, where the timer keeps ticking |
| 32.3 | Open during a side-switch pause (issue #35) | The 5→1 pause countdown freezes too and resumes on close |
| 32.4 | Signals under the sheet | No ticks or go while frozen — the countdown is simply not running |
| 32.5 | es / pt-BR / de / large Dynamic Type | Long strings wrap inside the sheet (scrolls at the biggest accessibility sizes); nothing clips or overlaps |
| 32.6 | The work and rest screens | Their technique button still opens the full exercise sheet — with the timer ticking on rest, as before |

### 33. Silent decay for 7–13 day gaps (engine v2.4, issue #37)

| # | Check | Expected |
|---|---|---|
| 33.1 | Last workout **7**–13 days ago, open the app | Every level silently −1 (Progress bars, Today's plan) — no card, no message; levels at 0 stay at 0. Day 7 is the boundary the engine actually uses (`gapDays >= 7`), so run it there, not only in the middle of the zone |
| 33.2 | Reopen the app during the same break | No further drop — one decay per break; the stamp survives relaunches |
| 33.3 | Last workout 6 days ago / 14+ days ago | No silent decay: below the zone nothing happens; at 14+ the comeback card owns the break as before |
| 33.4 | Break crosses both zones (opened at day 8–13, returned at 14+) | The comeback card shows the **weakened** drop (table − 1); accepting lands exactly where a plain comeback would — peeking mid-break never costs extra |
| 33.5 | First workout after a decayed break rated "tough" | Regular −1 on top; **no** deload from the old streak alone — the streak grows as usual |
| 33.6 | Complete a workout, then a new 8-day break | The new break decays independently — the old stamp went stale with the new workout |

### 34. "Get ready" transition (issue #52)

| # | Check | Expected |
|---|---|---|
| 34.1 | Tap **Start** | The warm-up opens on **GET READY** + "Marching in place", a 5 s countdown, the block dots, **technique**, **Skip this move**, **I'm ready** and **Skip warm-up** — never mid-move |
| 34.2 | Let it run out | 3-2-1 ticks, then the rising go, and the move starts at 30 s. The position itself now ends **silently** — the go belongs to the moment a movement starts, not to the moment one finishes |
| 34.3 | Tap **I'm ready** | The move starts at once; the transition is a floor on the pause between positions, never a wait |
| 34.4 | **Skip this move** during a transition | Skips the position it was announcing and lands on the next position's transition; on the last one it ends the block |
| 34.5 | Complete the last exercise's last set | The cool-down opens the same way — a transition before "Hip flexor stretch", then the 15 s first side |
| 34.6 | Every cool-down position | Preceded by its own transition, the per-side ones included: transition → 15 s → "Switch sides" 5 s → 15 s → next transition |
| 34.7 | Total block length | Warm-up 6 × (5 + 30) = 3:30; cool-down 6 × 5 on top of its 3:10–3:25 = 3:40–3:55. Both inside the 8 minutes the estimate reserves (`warmupMin` 5 + `cooldownMin` 3) — the number on Today is unchanged, and must stay unchanged |
| 34.8 | Lock the phone mid-transition, return after a while | The countdown reflects real elapsed time and jumps whole stages — a long absence lands on a transition or a position boundary, never mid-glyph |
| 34.9 | **technique** during a transition | The mini-sheet opens for the upcoming position and freezes its countdown, exactly as it does while a position runs |
| 34.10 | VoiceOver on a transition | Reads one phrase — "Get ready: Cat-cow" — not the kicker and the name separately |
| 34.11 | All seven languages | «Приготовься» / "Prepárate" / "Prepare-se" / "Mach dich bereit" / "Prépare-toi" / "Preparati" over the name; the button reads «Начать» / "Empezar" / "Começar" / "Starten" / "Commencer" / "Inizia" (translated by sense — "ready" is a gendered adjective in most of them) |
| 34.12 | es / pt-BR / de / fr / it at the largest accessibility sizes | The longest names ("Chest and shoulders at the wall", "Pecho y hombros en la pared", "Brust und Schultern an der Wand", "Poitrine et épaules au mur", "Petto e spalle al muro") wrap to three lines and the block's content **scrolls**; **I'm ready** and the block skip stay pinned and fully tappable. Applies to the running move and stretch screens too |

### 35. Pause of the guided blocks (issue #61)

| # | Check | Expected |
|---|---|---|
| 35.1 | **Pause** on a running warm-up move | The countdown stops on the second it showed, the number dims, the unit under it becomes "Paused", and the control reads **Resume** |
| 35.2 | Wait a minute, watching | Nothing moves and nothing sounds — no ticks, no go, no advance to the next position |
| 35.3 | **Resume** | A 5 s "Get ready" naming the same move, with the usual 3-2-1 and go, then the move **continues from the seconds it stopped on** — never from 30, never a position later |
| 35.4 | Pause a "Get ready" transition | It freezes the same way, and **I'm ready** steps aside — there is nothing to start early. **Resume** gives the transition straight back with no second lead-in: a transition already is one |
| 35.5 | Pause the "Switch sides" 5 s of a per-side stretch | Freezes; resuming carries the pause on from where it stopped and hands over to the second side on its own single go. No lead-in here either — two gos seconds apart is what §34.2 exists to prevent |
| 35.6 | Pause a cool-down stretch, then **Skip this move** / **Skip cool-down** | Both escapes work from a paused screen and leave the pause behind — the next position runs normally |
| 35.7 | Lock the phone while paused, return after several minutes | Still paused on the same second. A pause has no deadline to run out, so time away costs nothing |
| 35.8 | Background the app while paused, return | Same — and the block does **not** jump stages the way an unpaused absence does |
| 35.9 | **technique** while paused | The mini-sheet opens; closing it leaves the block **paused**. The user's pause outranks the sheet's own freeze — the two never fight |
| 35.10 | Pause, then **technique**, then **Resume** while the sheet is closed | The way back in runs once, from the seconds that were frozen |
| 35.11 | Kill the app while paused mid-warm-up | Nothing to resume: the warm-up writes no snapshot by design, and Today offers no "Continue" card for a workout with nothing done |
| 35.12 | Kill the app while paused mid-cool-down | Restores onto the rating screen, exactly as an unpaused cool-down does (§4 of the spec) |
| 35.13 | Working sets and rest | Unchanged — no pause control on the work screen or the rest ring. They are self-paced by design, and an over-run rest only grants extra rest |
| 35.14 | Estimate on Today, and the duration written to Health | Unchanged by pausing: "≈ N min" promises an uninterrupted flow, and Health still gets the wall-clock truth of the session |
| 35.15 | VoiceOver | The control reads "Pause" / "Resume"; toggling announces "Paused" / "Resumed", and the state is also readable under the countdown |
| 35.16 | All seven languages | «Пауза» / "Pausar" / "Pausar" / "Pausieren" / "Pause" / "Pausa" and «Продолжить» / "Continuar" / "Continuar" / "Fortsetzen" / "Reprendre" / "Riprendi"; the state reads «На паузе» / "En pausa" / "Em pausa" / "Pausiert" / "En pause" / "In pausa" |
| 35.17 | es / pt-BR / de / fr / it at the largest accessibility sizes | The control keeps its own line under the countdown, the content scrolls as in §34.12, and both footer escapes stay pinned |
| 35.18 | Pause and leave the phone alone (device only) | The screen dims and locks on the system Auto-Lock as usual — the workout stops holding it open, because a held block is the one state where the app knows nobody is training. Resuming, skipping or leaving the block puts the hold back |

### 36. Discomfort and the growth ceiling (engine v2.5, issues #38 / #64–#67)

> **Rows 36.1–36.13 and 36.17–36.20 are void from v2.26** — everything about the discomfort input: the action, its rating row, the resting block on Today, its VoiceOver, its seven-language strings, its state field, and the section count on "How it works". **What still stands is the growth ceiling — 36.14–36.16** — which was the other half of the #38 wave and is untouched. Voided rows are kept as the history of what the app used to promise; a green result on one of them means the mechanism came back. See §44.

| # | Check | Expected |
|---|---|---|
| 36.1 | **Something hurt** on the exercise screen | Its own line under **Went differently** / **Skip exercise**, visually distinct from both. One tap, no confirmation dialog — the exercise ends and the flow moves to the next one, exactly as a skip does |
| 36.2 | The rating screen afterwards | The exercise is listed under **DISCOMFORT** with "resting" — not under **SKIPPED**. The card header counts it out of the rating ("Your rating applies to 5 of 6") |
| 36.3 | Level and streak of the reported pattern | Unchanged by that workout, whichever rating is given — the report behaves as a skip for the session |
| 36.4 | Today, while the pattern rests | A quiet block under the plan: "Not getting harder", then one row per movement — its name and an accent pill with the horizon ("Y-T-W raises ⟦3 more times⟧"). A fact, not a warning — no icon, no colour alarm. It names the exercise the way the list above it does, only while the movement is in today's plan, and counts **appearances of the movement**, never weeks. A second report refreshes that one counter while the others keep counting down |
| 36.5 | The next three workouts containing that movement | It is still in the plan at the same level and does not climb, whatever the rating; the line disappears by itself once the third one is done |
| 36.6 | "Tough" on a resting movement | The level still steps **down** — honesty is never overridden — and no deload fires while it rests, even from a streak of two |
| 36.7 | An exact number ("Went differently") on a resting movement | Below the plan it lands as usual; above it the level does not move |
| 36.8 | Report the same movement again while it rests | The rest starts over from three appearances |
| 36.9 | Skip a resting movement | The skip costs it nothing: the rest does not tick down on a workout where the movement was not trained |
| 36.10 | A break (7–13 days, or 14+ with the comeback card) during a rest | Levels drop as they always did; the rest is **not** cleared by the break |
| 36.11 | Calendar history of a workout with a report | The row reads "hurt" (accent), never "skipped" |
| 36.12 | Kill the app after reporting, reopen | "Continue the workout?" comes back with the report still in place — it is progress like a skip or an actual |
| 36.13 | "How it works" | Nine sections now; §8 is "Something hurt" and explains the rest and the stop rule. §2 says the level climbs at most two steps — one for calves, the wall handstand and every fourth variation |
| 36.14 | Growth speed after the ceiling (calves) | "Easy, could do more" on calves moves the level **one** step, not two — at every variation. Same for the vertical push from its third variation up, and for every movement on its fourth |
| 36.15 | Growth speed elsewhere | Unchanged: two steps for "easy", one for "on plan", and an exact number still calibrates from zero without any cap |
| 36.16 | Sets bands (levels 32–47) | One step per workout there too — they are the fourth variation by encoding |
| 36.17 | VoiceOver | The action reads "Something hurt" with a hint about what it does; the rating row announces "Pull, hurt — resting"; Today's line is read as one sentence |
| 36.18 | All seven languages | «Здесь болело» / "Algo me dolió" / "Algo doeu" / „Etwas tat weh" / « Ça a fait mal » / "Ha fatto male"; the rest line reads «Пока на отдыхе: …» / "En reposo por ahora: …" / "Em repouso por ora: …" / „Vorerst in Erholung: …" / « Au repos pour l’instant : … » / "A riposo per ora: …" |
| 36.19 | es / pt-BR / de / fr / it at the largest accessibility sizes | The three action labels keep their two lines without overlapping the primary button; Today's rest line wraps rather than truncating |
| 36.20 | An old state file (no rest recorded) | Opens with nothing resting — the field is additive and its absence means "nothing frozen" |

---

### 37. The two-step pain unload (engine v2.19, spec §30.6, issue #124)

> **This whole section is void from v2.26:** the pain channel was removed. Kept as the history of what the app used to promise; a green row here would mean the mechanism came back. See §44.

Reporting pain now **takes load off** instead of only freezing the movement. Two reports, two steps; the third and later ones only lengthen the rest.

| # | Check | Expected |
|---|---|---|
| 37.1 | **Something hurt** on a movement standing in the middle of its variation | The next workout offers the **same movement** at the **smallest dose of that variation** — the name does not change, the numbers drop to the bottom rung of the tier. Nothing about the plan gets harder |
| 37.2 | Rest horizon after the first report | Three appearances, exactly as before (§36.4) |
| 37.3 | A second report on the same movement while the episode is live | Now the **variation itself** changes — one step easier — and the rest doubles to six appearances |
| 37.4 | A third and a fourth report | The level no longer moves; the rest doubles to twelve and then stops there. The movement never disappears from the plan |
| 37.5 | A first report on a movement already at the bottom of tier 1 | Accepted without a level change — there is nothing below; the rest still starts |
| 37.6 | The reported movement across the whole scale | Never harder after a report than before it, at any level — the first step stays inside the variation by construction |
| 37.7 | An episode opened before the update (rest recorded, level already dropped) | The next report gives the **second** step. Nothing to migrate; the direction of the error is the safe one |
| 37.8 | "Tough" or a low number on a resting movement | Still steps the level down — honesty is never overridden by the rest |

### 38. Closing a pain episode without numbers (engine v2.20, spec §31, issue #124)

> **This whole section is void from v2.26:** there is no episode to close. See §44.

The fast path (type a number) is unchanged. The new one is for people who never type numbers.

| # | Check | Expected |
|---|---|---|
| 38.1 | After a report, do the movement and rate the workout **on plan**, entering no numbers | Each such appearance counts down the confirmation quietly. Nothing new appears on screen |
| 38.2 | Keep tapping only | Growth resumes by itself. Worst path from one report: the rest, then the same number of clean appearances, then one more — seven appearances in all, roughly two to four weeks at ordinary cadences |
| 38.3 | An exact number at or above the plan | Closes the episode **immediately** and grows in the same workout — the number is direct evidence, the countdown is not |
| 38.4 | A workout rated **tough**, or a number below the plan, during the countdown | Not a clean appearance: the countdown stands still and the level still goes down |
| 38.5 | Skip the movement during the countdown | The countdown does not tick — a workout where the movement was not trained costs it nothing |
| 38.6 | Report pain again during the countdown | The countdown restarts from the new, longer rest — the path to closing lengthens with the rest |
| 38.7 | A break (silent decay, comeback, or the illness lens) mid-countdown | The countdown survives the break unchanged, exactly as the rest does |
| 38.8 | An episode opened before the update | Gets the **full** confirmation window, not an immediate close on the first appearance |

### 39. Hold ladders and the one-second corridor (engine v2.21, spec §32, issues #139, #142)

Holds moved from a fixed five-second step to per-tier ladders, and the number pad follows.

| # | Check | Expected |
|---|---|---|
| 39.1 | **Went differently** on a hold | The corridor steps by **one second**, not five. Any whole second in range can be entered |
| 39.2 | Enter exactly the planned seconds | Counts as the plan met and moves the position up |
| 39.3 | Enter one to four seconds **above** the plan | Never scores worse than entering the plan exactly — the old five-second bucket that swallowed a +1 is gone |
| 39.4 | Enter one second **below** the plan | Costs one rung, never a jump of several |
| 39.5 | Hold plans across the whole scale | Every rung is reachable by an entered number — no rung exists that the pad cannot express |
| 39.6 | Entering a hold after an upgrade from 1.9 | Old states land on the nearest rung of the new ladder, **downwards**; nothing jumps up on first launch |

### 40. Sub-steps: the plan parks on your capacity (engine v2.22, spec §33, issues #150, #151)

> **Read this section in v3 vocabulary (§40 of the spec, §47 here).** The mechanism
> survives — a step of growth still lands on one set — but the words "level", "tier"
> and "sets band" name things the engine no longer has. Read "a whole level" as "a
> whole step along the ladder". **Row 40.4 has lost its referent**: there is no tier
> top, and what happens at the top of a variation's grid is now a probe (§47.6–47.8).
> Rows 40.7 and 40.8 assert an absence and still stand.

Growth used to move a whole level at a time. Now it adds one set's worth first, so the plan stops overshooting what the body can do.

| # | Check | Expected |
|---|---|---|
| 40.1 | Rate a workout **on plan** at a level with three sets | The next plan shows an uneven row — e.g. **11-10-10** — one set carrying the extra rep, not all three |
| 40.2 | Keep going on plan | The row fills set by set (11-10-10 → 11-11-10 → 11-11-11) and only then becomes the next whole level |
| 40.3 | The **Done** button and the number pad against an uneven row | The plan the app asks for is the row it shows; entering exactly the shown minimum counts as the plan met and keeps the position moving |
| 40.4 | The top rung of a tier or a sets band | No uneven row there — growth moves a whole level. Two different exercises never appear in one slot |
| 40.5 | "Easy, could do more" | Moves at most the same number of sub-steps the ceiling allows for that movement — calves and the vertical push still climb slower |
| 40.6 | Any step **down** (tough, a low number, a break, a pain report) | Clears the uneven row — the extra sets belonged to a dose that no longer applies |
| 40.7 | **Hold this level** in Settings and on the rating screen | **Gone entirely.** No control, no stored flag, no leftover string in any of the seven languages |
| 40.8 | A state file written by 1.9 with "hold this level" set | Opens without it and plans exactly as 1.9 did — the field is dropped, nothing else moves |

### 41. "Tough" steps back the way it came (engine v2.23, spec §34, issue #149)

> **Still true in v3, in v3 vocabulary.** "Tough" steps back one step along the ladder
> and 41.4 is the load-bearing row. What changed underneath: a descent that runs out of
> dose now takes a **set** off, down to the floor of two, instead of landing on a tier
> floor — those do not exist. Where a descent does cross into the variation below, the
> landing comes from your journal and is capped so it is not more work (§48.1).

| # | Check | Expected |
|---|---|---|
| 41.1 | Rate a workout **tough** | The movement steps back **one position along the path it grew** — one sub-step, not a whole level, and never a different variation |
| 41.2 | "Tough" at the bottom of a variation | Still does something: it is never a dead tap |
| 41.3 | Two "tough" ratings in a row, then a third | The deload fires through the same gate — the plan after it is never heavier than the plan before |
| 41.4 | The plan after any "tough" | Never asks for more total work than the plan that was just called tough, on any movement, at any level |

### 42. The 45-minute default and calendar days (v2.24, spec §35, issues #136, #147)

> **Rows 42.1–42.3 are void from v2.26** — there is no session length in Settings and no default to explain. The calendar-day rows below them stand. See §44.

| # | Check | Expected |
|---|---|---|
| 42.1 | **Session length** in Settings | Four rungs — 20 min, 35 min, 45 min, No limit — with **45 min** selected on a fresh install |
| 42.2 | An install upgraded from 1.9 that never chose a length | Gets 45 as well, plus a one-off line explaining it. Once closed, the line does not come back |
| 42.3 | Choose **No limit** | Recorded as a choice: the default never reapplies to that install, on this or any later launch |
| 42.4 | Workout length at 45 minutes, at levels 32–47 | Sessions land at or under 45 minutes; the shortfall under the target is small and even, never a saw between long and short workouts |
| 42.5 | What the budget cuts | **Sets only, never movements** — all six movements are always present, each with at least two sets. Levels do not change |
| 42.6 | The 20-minute rung | A target, not a promise: most plans run a little past it once every movement is already at two sets. Nothing is dropped to make it fit |
| 42.7 | **Reset progress** | Keeps the chosen session length, like the pull-up bar setting |
| 42.8 | Two workouts on the same calendar day | Counts as zero days apart for the decay, the comeback card, the cadence line and the rest suggestion — no phantom day |
| 42.9 | A workout at 23:00 and the next at 01:00 | **One** day apart, not zero — the count is midnights in the local zone, not elapsed hours |
| 42.10 | Fly across time zones, or change the clock, between two workouts | No phantom day in either direction; the gap never goes negative |
| 42.11 | The autumn and spring clock-change days | The 25-hour and 23-hour days both count as one day |

### 43. The sets handle (engine v2.25, spec §36, issues #149, #150, #151)

> **Also read in v3 vocabulary.** The sets axis survives; the framing below — "the only
> way down was the level, which also picks the variation and the dose" — describes the
> problem v3.0 removed at the root. The four "a person could get a heavier plan"
> counts are measured on the 0–47 lattice and **do not reproduce** on this engine; they
> are kept as the history of what was fixed, not as numbers to re-verify.

> **Rows 43.1–43.7 and 43.12 are void from v2.26** — the pain depth ladder, the illness lens and the 35-minute rung. 43.8–43.11 stand and are the load-bearing half of this section. See §44.

The engine gained a way to say *the same exercise, but less of it*. Until v2.25
the only way down was the level, which also picks the variation and the dose, so
a descent off the floor of a block had to change the exercise — and the top of
the tier below is heavier than the bottom of the one you are on. Four things a
person could do and get a **heavier** plan for it are all zero now: a 7–13 day
break (48 cells of 480, worst ×6.50), "it hurt here" (24), honest "tough" every
session (all 48 levels locked forever), and "I was ill" (40).

| # | Check | Expected |
|---|---|---|
| 43.1 | Report **"it hurt here"** on a movement | The **same** exercise comes back with **fewer sets** — same variation, same dose per set, same unit and sides. The level does not move |
| 43.2 | First report of a **new** episode, at any point in your history | Lands on **2 sets** — always, whether it is your first tap ever or your tenth. Depth does not read history: a second tap two years and two hundred clean sessions later must not turn 5×15 per side into 1×15 |
| 43.3 | Second report while the episode is still live · third and later | 1 set. The rest between appearances doubles **3 → 6 → 12**, and that ladder reads how many times this movement has hurt **in your whole history**, not the current episode |
| 43.4 | Keep training the movement after a pain report | Two counters run **in parallel**, not one after the other — "how long to rest" and "has it passed". The episode closes on the **6th** appearance at every level, and full volume is back on the 31st, not the 48th |
| 43.5 | Recover and keep going | At most **one set** comes back per session, and the next no sooner than **2 appearances** later. While that hold is ticking, growth goes into the **dose**, not into another set |
| 43.6 | Tap **"I was ill"** | The plan drops to half the band, rounded up (−33 % at L24, −50 % at L36, −40 % at L44) — never below the two-set floor, and never above what pain has already taken. If the plan is already on the floor, the lens gives nothing: that is deliberate, not a bug |
| 43.7 | Let the illness lens run out | The plan returns **exactly** to the last ordinary showing, never heavier. The lens is a view — it does not overwrite what the engine remembers |
| 43.8 | Anything that lowers your position (a break, "tough", a pain report) | The next plan is **not heavier** than the one you last saw at that position. The single exception is moving the **session-length handle** yourself: that lifts the cap for one transition, because your own decision outranks the old showing |
| 43.9 | On the pull-up bar, a descent that changes the **unit** (reps → seconds) | Lands by **time under load**, not by the number — the highest rung of the target tier whose time is no greater than what you are doing now. If even the bottom rung is dearer, it lands on the branch floor and the branch loses its level. Known and accepted: safety outranks the level until the library gains the missing rung |
| 43.10 | A save file written by 1.9 or earlier (no `cut`, no `painSeen`, no `setsHold`) | Opens, and the plan is **bit-for-bit** what v2.24 built. Every new field is sparse — a zero is never stored — and all of them survive a break |
| 43.11 | Open the app, look at the plan, **do not train**, come back a week later | The new plan is not heavier than the one you saw. v2.25 records the plan when it reaches your eyes, not only when you finish a workout |
| 43.12 | The **35-minute** rung with every movement on the floor | Known: 27 of 768 cells run up to 2.5 minutes over. 45 fits everywhere without a caveat |

### 44. The handles, and what the app stopped asking (engine v2.26, spec §37, issues #184, #99)

> **The handles stand; the floor numbers below do not.** "Level 0 … about 34 minutes,
> and about 25 minutes at the shortest" was measured on the 0–47 library. On the shipped
> v3 library a clean start is about **31 minutes**, and about **23** cut to the sets
> floor from inside the workout. The declared entry boundary in spec §37.1 and the App
> Store listing still carry the old pair — see I-17.

A wave of removal. The pain channel and the time budget are gone, and two handles
take their place — on the **plan**, not inside the workout, so pressing one
redraws the plan and the announced duration together. Level 0 becomes a declared
floor rather than a hole: three sets of eight in the gentlest variation of six
movements, about 34 minutes, and about 25 minutes at the shortest the app can
build at all. Nothing below it exists.

**Rows this wave voids, so nobody walks them looking for a button that is gone.**
§36.1–§36.13 and §36.17–§36.20 (everything about the discomfort input; the growth
ceiling of §36.14–§36.16 stands), §37 and §38 entirely (the two-step unload and
closing an episode), §42.1–§42.3 (Session length in Settings and its one-off notice), and
§43.1–§43.7 plus §43.12 (the pain depth ladder, the illness lens, the 35-minute
rung). They stay in the file as the history of what the app used to promise —
a row silently deleted is a row nobody can check was deliberate — but a red
result on any of them means the mechanism came back, not that the app is broken.
What survives from §43 is §43.8 (a descent is never heavier), §43.9 (a unit
change lands by time under load), §43.10 (an old save file opens unchanged) and
§43.11 (the plan is remembered when it reaches your eyes).

| # | Check | Expected |
|---|---|---|
| 44.1 | The plan on Today, any level above the floor | Each movement row carries **"Easier"** and **"Fewer"**; a movement with a set already off also carries **"More"**. Under the duration sit the two session handles, each naming the axis it moves: **"Fewer sets in every movement · 37 → 26 min"** — both numbers, before you agree — and **"Fewer movements · 3 of 6 · ≈ N min"** |
| 44.2 | Tap **Easier** on a movement | The **name and the dose of what you will get** are on the button before you press it, and after the tap the movement is in a genuinely different variation — never the same exercise with smaller numbers. The announced duration redraws in the same beat |
| 44.3 | Tap **Fewer** down as far as it goes | Stops at **two sets**. There is no third tap and no disabled-looking button that does nothing — when the floor is reached the control is gone |
| 44.4 | Tap **Fewer sets in every movement**, then **All sets back** | Fewer only ever shortens; All sets back restores every set on every movement and then disappears, because with nothing cut there is nothing to restore |
| 44.4a | Pull BOTH handles | They compose and the screen says so by arithmetic: the plan line counts what Start will run (3 movements at the cut set count), and the sets handle prices itself inside those three rather than inside the full six |
| 44.5 | A movement at level 0 with two sets | Both handles are **absent**, and the weak-link prompt stays silent. This is §37.1 from the app's side: at the declared bottom there is nothing to offer, and a button that cannot work is worse than no button |
| 44.6 | Level 0, answer **"tough"** many workouts running | The plan does not move — for **124 appearances** if you keep going. Known, accepted and named: below the declared floor there is nowhere to descend. What the app must not do is pretend otherwise |
| 44.7 | Start a workout | The **warm-up asks first** — "6 positions · about 5 min", with start and skip — instead of dropping you into a countdown. Same for the cool-down after the last exercise |
| 44.8 | The run-in before each guided position | **Ten seconds**, and **fifteen** where the position means walking to a wall or getting down onto the floor. Time the worst warm-up and the worst cool-down: neither block may exceed the 9:00 the plan reserves for the two of them |
| 44.9 | **Went differently** with a number **below** the plan on set 1 of 3 | Carries forward: 8/8/8 for a planned 9. A number **above** the plan stays on its own set — 40 on set 1 of a planned 39 reads 40/39/39, not 40/40/40 |
| 44.10 | Enter a number above the plan | One soft note per exercise — "do the plan, save your maximum for the last set" — which does not block the entry and does not promise the engine will do anything with the order. It will not: 12-8-8 and 8-8-12 reach the engine as the same number |
| 44.11 | Settings | **No session length row.** Nothing offers 15, 20, 35 or 45 minutes, and nothing explains a default that no longer exists |
| 44.12 | Anywhere in the workout or on the rating screen | **No "Something hurt"**, no discomfort section, no "I was ill" offer, no "see a specialist" line. The warning that sharp pain means stop **remains** — in the care note and on "How it works". What was removed is a state machine, not the warning |
| 44.13 | A save file written before this wave, carrying a pain episode and a chosen session length | Opens, and the plan is what the current engine builds — the removed fields decode away silently. The **journal keeps showing the pain reports it recorded**: a record that loses a fact is a record that lies about the past |
| 44.14 | "How it works", section 8 | Titled **"Too much today"**, and it describes the two handles. If it still says "Something hurt", the screen is older than the app |
| 44.15 | The announced duration of workout 1 on a fresh install | **≈ 34 min** — one minute more than v2.25, which is the longer run-in of §44.8 and the only number this wave moved on purpose. Drift here blocks a release: it is the engine's own arithmetic, read from the reference, not copied off the screen |

### 45. Reachable, readable, and spoken with a scale (design re-review R16–R20)

No engine in this one — five app-layer defects the design re-review found,
four of which a test could not have caught because they are about *reaching*
and *hearing* rather than about what the plan says.

| # | Check | Expected |
|---|---|---|
| 45.1 | Progress, a history with a break of two weeks or more | The **"N days"** label on the grey band is legible against it, in **light, dark and both Increased Contrast variants**. The arithmetic, against the band's own fill (hairline at 55 % over bg): **4.55 : 1** light, **5.99** light HC, **5.94** dark, **6.54** dark HC. Before the wave it was 2.16 and 2.57 — below the 4.5 : 1 floor the wave that drew the band set for itself |
| 45.2 | The same label, at the largest Dynamic Type sizes | Grows with the setting — it is the one chart label that is not a frozen axis mark. A band too narrow to hold it draws with **no label at all** rather than a label lying across the line it explains. The width fractions are 0.155 and 0.33, a tenth above what they were, because the label went from 10 pt to 11 |
| 45.3 | Today with a **"new variation"** badge, then switch light ↔ dark in Control Centre | The pill **repaints in the same beat as the rest of the screen**. It is a bitmap, so this is the one thing on Today that can lag a theme change; a light pill on a dark card means the cache lost its appearance key. Same check with Increased Contrast |
| 45.4 | Every screen of the workout flow: **Exit**, **technique** | Answer to a tap anywhere in a **44 pt** band, not just on the glyphs. Tap deliberately high and low. The header grows about 26 pt for it and the work screen's number sits about 20 pt lower — the exercise name and the primary button do not move |
| 45.5 | Today: **Easier**, **Fewer sets**, **More sets**, and the two session handles | The same 44 pt. A plan row is about 29.5 pt taller for it, so an iPhone SE shows three of six exercises where it showed four — the list already scrolled at six, and this is the accepted price |
| 45.6 | Today: tap the **empty strip of a plan row**, beside a handle | **Nothing changes.** Not the announced duration, not the number of handles. This was a real defect: one such tap took a set off and the plan went 35 min to 33. Tapping the card itself still opens the technique sheet |
| 45.7 | Calendar, any month | `buttons["day-15"]` matches **exactly one** element. Cells of the neighbouring months carry no identifier at all, so they cannot answer to a number that belongs to the month on screen |
| 45.8 | VoiceOver on Progress | A row reads **"Squat, variation N of M, selected"** — the number with the scale the bar draws it against. Selected, the variation and the next milestone follow; the level is not said twice. (Row rewritten from the pre-v3 level scale — see I-18) |
| 45.9 | VoiceOver on the work screen | The big number and its unit arrive as **one element**: "8 reps per side", not "8" and then "reps per side". During a hold the same element **counts down** rather than freezing at the number the hold started on |
| 45.10 | Dynamic Type XL and the accessibility sizes: Today, work, rest, Progress | Progress scrolls and stays whole. Today's plan rows and the flow's controls keep their labels. **Two known failures, both older than this wave and identical on the previous release — see I-15:** at accessibility sizes Today's two session handles overlap each other and the line above them, and the work screen, which has no scroll view, pushes its header and exercise name off the top |


---

### 46. The decision moves inside the workout (engine v2.27, spec §38)

The last two mechanisms that asked the person to decide BEFORE the workout are
gone: the short version, which picked three of six movements for them, and the
session-wide "fewer sets in every movement". What replaces both is a skip on
the **work screen** — one set, or the rest of a movement — plus two numbers
that follow the decision instead of predicting it: a **range** on Today and
what is **left** of the session on the work screen.

This also makes §37.1 checkable for the first time. The short version lived
outside the engine and delivered **20.5 min** against an announced 24.8; with
it gone, no level on the scale can be squeezed under the announced floor.

**Rows this wave voids, so nobody walks them looking for a button that is
gone.** §29 entirely (the short workout) and §30.8 with it; §44.1, §44.3,
§44.4, §44.4a and §44.14 (the two session handles, the per-movement "Fewer" /
"More", and the explainer section that described them); §44.15 (the announced
duration is a range now — see 46.1); §45.5 and §45.6 as far as they name the
removed controls — the 44 pt claim and the empty-strip tap still hold for the
one handle that is left. §43.8's exception clause ("moving the session-length
handle yourself lifts the cap for one transition") has nothing to move any
more. They stay in the file as the history of what the app used to promise.

| # | Check | Expected |
|---|---|---|
| 46.1 | Today, a training day, fresh install | The plan line is a **range**: "≈ 24–32 min · 6 exercises" (31.5/24.3 on the 3.4.0 reference — §41.12 put a minute on every announced duration, matching `ReleaseSmokeTests.swift`'s "about 24 to 32 minutes · 6 exercises") — the full plan and the shortest the session can be made from inside it. Nothing under it to agree to; each movement row carries **"Easier"** and nothing else |
| 46.2 | The same, once the plan is on the sets floor | A plan already on the sets floor shows **one** number, not a range of one. (This row is written in the pre-v3 level scale — "L34"/"L47" no longer exist; see I-18) |
| 46.3 | The work screen | Under the button that logs the set: **"Went differently"**, **"Skip this set"**, and one exercise-level escape. Never two controls that would do the same thing |
| 46.4 | Tap **Skip this set** | Straight to the next set — **no rest** on the way, because nothing was done to recover from. The header's **"≈ N min left"** drops in the same beat |
| 46.5 | Two sets of a four-set movement behind, then look at the escape | It reads **"Skip remaining sets"**. With nothing behind it, it reads **"Skip exercise"** — the difference is real: the first is the movement trained short, the second is a movement not trained |
| 46.6 | A movement showing **two sets** (the floor), or two of four already skipped | **"Skip this set" is absent.** The only way out is "Skip exercise". §38.2 rule 2: below the floor there is nothing to record, and doing it quietly as something else is what the rule prevents |
| 46.7 | Skip one set of a movement, finish, rate **on plan** | The **next** plan for that movement has one set fewer — 3×4 becomes 2×4 at L24, 5×8 becomes 4×8 at L40. The order matters and is the engine's to keep: a cut written before the rating is eaten by the set the rating hands back |
| 46.8 | Skip a set on a movement already on the floor, finish, rate | The movement's **level does not move at all** — no tier lost. It reaches the engine as a skipped exercise, never as a dose of 0, which would cost eight levels at L24 |
| 46.9 | Kill the app mid-workout after skipping sets, relaunch, **Continue** | The skips are still counted: finish and the next plan is short by exactly what was skipped |
| 46.10 | History for a workout with skipped sets | The record keeps them. Nothing on screen has to show them yet — the journal is the only place §38.6's "has the skip become the dominant price" can ever be answered from |
| 46.11 | "How it works" | Section 7 says a skipped **set** is not a skipped exercise; section 8 says the answer is an easier variation or a set skipped **while you are doing it**, and that nothing has to be decided in advance. If either still offers a handle on the plan, the screen is older than the app |
| 46.12 | All seven languages | The three actions fit under the button without truncating — they drop to two rows and then to three as the labels grow. "≈ N min left" and the range fit on Today at default type |
| 46.13 | VoiceOver on Today | The plan line is read as a range — "about 26 to 34 minutes" — not as two numbers |
| 46.14 | Dynamic Type XL and the accessibility sizes, work screen | Known, and **worse than before this wave — see I-15**: the column still has no scroll view, and it now carries one more line (the time left) and one more control. At the accessibility sizes the top of the screen is pushed off it |

### 47. The measured ladder (engine v3.0, spec §40)

The engine stopped predicting. A position is no longer one number but **a
variation and a dose**, and nothing can be assigned that has not already been
shown. The whole 0–47 scale, its tiers, its per-tier rep ladders and its tier
floors are gone — so is any screen word that named them. Walk this section on a
**fresh install** unless a row says otherwise.

| # | Check | Expected |
|---|---|---|
| 47.1 | Fresh install → Today | Every one of the six movements reads **3 × 4** (or 3 × 15 s for a hold). The line above says about **31 minutes** for the full plan and about **23** for the shortest it can be cut to from inside |
| 47.2 | Settings → **How it works** → first section | Titled **"Variation and dose"** — two facts per movement, not one number. No section anywhere in the sheet says "level", "tier" or "band" |
| 47.3 | Progress, after one workout | The big number is captioned **"total steps"**, never "total level". Each pattern's bar is measured along **its own** ladder — its own denominator, a tick where each variation begins — and VoiceOver reads "*variation N of M*", not a bare number |
| 47.4 | Progress, on a state that trained before this wave | The pre-wave workouts say they have **no number on this scale** rather than being drawn at some invented height. The chart does not connect across the gap as if it were continuous |
| 47.5 | Rate **on plan** twice at 3 × 8 | The row goes uneven one set at a time — 9-8-8, then 9-9-8, then 3 × 9. The same behaviour §40 describes, in the new vocabulary |
| 47.6 | Reach the top of a variation's grid (15 reps / 45 s), then start the workout | The **last working set is replaced** by one set of the next variation, labelled as a try, target **4 reps** (15 s). It is a replacement, not an addition: the minutes on Today do **not** go up for it |
| 47.7 | Do 4 or more on that probe set | Next workout opens that movement in the **next variation at 3 × 4**. A variation-debut badge fires, and the technique sheet shows the new movement |
| 47.8 | Do fewer than 4, or skip the probe | Nothing moves. Under the number: **"We'll stay with the current variation."** The working sets you did still count, no set is taken away, and the probe comes round again next time |
| 47.9 | Answer **tough** at the very bottom of a variation's grid | The plan takes a **set** off rather than dropping you a variation — down to the floor of two, never to a "tier floor", which no longer exists |
| 47.10 | Pull the **easier variation** handle on any movement | It always lands on a *different* variation, and the plan it lands on is never more work than the one you were doing — including per-side movements, where the same number is twice the work (see §48.1) |
| 47.11 | Bar on, `pull_bar` at the top of the hang | The hang → negative-pull-up boundary is crossed **only** by a probe. There is no descent, comeback or handle that walks across it by comparing seconds to reps |
| 47.12 | Every movement's technique sheet, in each of the seven languages | All **59** positions carry a name, three numbered steps and two mistakes. No position shows a raw key, an empty line, or the English string on a translated device |
| 47.13 | Warm-up and cool-down | Six positions each, drawn from pools of nine. The warm-up still runs **245 s**. Y-T-W, bird-dog and the single-leg Romanian deadlift appear in the **warm-up**, not among the strength movements |
| 47.14 | A state file written by a pre-v3 build (see §48.5) | Opens with your movements, doses, rotation and bar answer carried across, and a card on Today saying what happened — **once** |

### 48. Measuring honestly (engine v3.1, spec §41)

Eight defects a full audit of v3.0 found, all fixed. Each row here is a defect
that shipped, so a green row means the fix is still in place.

| # | Check | Expected |
|---|---|---|
| 48.1 | **Easier variation** on a movement whose neighbour below is trained one side at a time (sliding leg curls → single-leg glute bridge) | The plan you land on is **not more work**. The old behaviour kept the remembered number and doubled the work with the sides — 3 × 15 became 3 × 15 *per leg*. Where nothing lighter exists in the library the landing may still rise; those boundaries are a closed, named list in the spec, not a surprise |
| 48.2 | A probe set of **reps**, finished by tapping **Done** rather than typing a number | Counts as done, at the target it asked for. Before this, only holds recorded themselves, so a rep probe finished by tapping recorded nothing and the ladder never moved |
| 48.3 | An uneven plan (8-7-7) done in full, then Progress → history | The journal shows what you actually did, not the plan's top set. A number that appears in none of your sets must never appear here |
| 48.4 | Train on a **regular** long cycle — every ten days, many times | The plan is not eased as if each gap were a break. A steady rhythm is read as a rhythm; the engine now decides that from your last **eight** intervals |
| 48.5 | Update over a build older than v3 with a real history | Movements, doses, rotation and the pull-up-bar answer are all carried across — nobody is started over. Holds that used to sit below the shortest hold the app offers come **up** to it. The journal, settings and history are untouched, and the explainer for typing your own numbers is not swallowed by a non-empty journal |
| 48.6 | `python3 scripts/check_engine_gates.py` | All five gates run **and print their clean line**. A gate that dies before its first check must fail the runner, not pass silently — three of six once did exactly that |

### 49. The count-in, and "easy" earned (app, 26.08.2026)

| # | Check | Expected |
|---|---|---|
| 49.1 | Tap **I'm ready** on any position of the warm-up or cool-down | Five seconds of count-in before the position's clock starts. Nothing jumps under the thumb that just tapped |
| 49.2 | Tap **Start hold** on a static exercise | The same five seconds first. On a hold this is preparation time that always existed — it used to be spent before the tap and came off the number the engine measures |
| 49.3 | During any count-in | The escapes are **hidden, not removed** — nothing new appears under your thumb, and the controls come back when the clock starts. A transition's count-in can only shorten what is already running, never extend the block |
| 49.4 | Finish a workout in full, then the rating screen | All three cards live, **"Easy, could do more"** among them |
| 49.5 | Skip a set, skip a movement, or type a number below the plan, then the rating screen | The **"Easy, could do more"** card is dimmed, with one line under the three saying why. The same sentence is the card's VoiceOver hint — "dimmed" alone is a riddle |
| 49.6 | The same screen, **"Hard, did less"** and **"On plan"** | Always live, in every state. Honesty downward is never gated |
| 49.7 | Any technique card | Three steps in **numbered filled circles**, two mistakes marked **✕**. The two groups are never one undifferentiated bullet list |
| 49.8 | Table rows → setup step | Says what to do when the edge cuts into the fingers (a folded towel). A grip that hurts ends the set before the back does |
| 49.9 | French, anywhere with `: ; ! ?` or guillemets | Non-breaking space before `:`, narrow non-breaking space before `; ! ?` and inside `« »`, typographic apostrophe `’` throughout. **No gate checks this** — it is a read-through |
| 49.10 | Progress chart axis, each language | Says **steps** in that language. It said the retired word "level", which VoiceOver read aloud |


### 50. Hands-free holds (app, R23–R29)

The wave is app-only: the engine diff is empty and `golden.json` is untouched.
Sets of **reps** are untouched too — walk one exercise of each and compare.

| # | Check | Expected |
|---|---|---|
| 50.1 | Reach a hold exercise | One primary control, reading **Start exercise**. Under the set dots: how many sets and how long the rest between them. Above the button: a promise that the exercise runs itself and you can put the phone down |
| 50.2 | Tap it once and put the phone down | The whole exercise runs: count-in, hold, finale, rest, and the next set begins on the rest's own go. The phone is not touched again until the movement's last set hands itself back |
| 50.3 | Time the rest between two sets | It is the planned rest and nothing more, and the start is announced ONCE. Re-marked by R32: this row used to require fifteen seconds of "travel" after the rest, with a second 3-2-1 and a second go — a minute of rest ran a minute and a quarter, and the same set was announced twice. The five-second count-in a TAP earns is unchanged (3.1b) |
| 50.4 | Read the primary button during a hold | **Stop · N s**, N updating every second, and N is exactly what the tap records. Inside the first three seconds it reads plain **Stop** — that tap cancels the set and stores nothing |
| 50.5 | Stop a hold past the grace, then check the number | Three seconds lower than the clock showed. The tap lands after the effort stopped — the walk to the phone is not training |
| 50.6 | The hold screen before any effort | No **Went differently**, and no reserved gap where it stood. On the movement's LAST set, once the hold is behind, it is live again: nothing about that movement comes back |
| 50.7 | The same walk on an exercise of **reps** | Identical to before the wave — **Done**, **Went differently**, and the first-workout hint about entering more than planned |
| 50.8 | Skip a set or the exercise mid-run, then reach the next hold | The next exercise asks again: one tap buys one exercise, never the next one |
| 50.9 | A per-side hold | Both sides of every set run themselves, exactly as in 3.5, and the auto-run carries the sets between them |
| 50.10 | A probe set that is a hold | Waits for a tap of its own (**Start hold**). It is one set of a movement nobody has done, possibly in another unit |
| 50.11 | Every new string in each of the seven languages | Reads naturally and does not clip: **Start exercise**, **Stop · N s**, the sets-and-rest line, the promise. `python3 scripts/check_localization.py` is green |
| 50.12 | On the hold screen before the effort, tap **Set the time** | The stepper opens on the number the clock would use. Raising it sets what EVERY set of this exercise counts down from; lowering it is an ordinary answer too, and the label does not call it a failure |
| 50.13 | Declare more than the plan and let the exercise run untouched | Every set runs the declared time, and every card on the summary carries it, compared against the PLAN (not against what was declared) |
| 50.14 | Declare more, then Stop one set short of it | That set records what was held, less the reach allowance, and is marked **≈**. The sets AFTER it run what that set showed, capped by the declaration — aiming at 60 and managing 50 does not put 60 back on the clock |
| 50.15 | Declare a time on a **per-side** hold | Both sides run from it and the set records the smaller of the two, as always. This is the case a clock running past the plan could never have served: the smaller side caps the number, so nothing after the plan could raise it |
| 50.13a | Declare a time, then **Skip this set** on a set that is not the last | The sets after it still run the declared time, and any "≈" already earned in this movement is still on its card. A skipped set is a departure from a SET; the declaration belongs to the movement |
| 50.13b | Declare a time, run the movement out, and reach the NEXT hold movement | Its clock is on its own plan — the plank's 20 s must not set the side plank's, whose plan is 15. Check the number on the intro screen, or open **Set the time** and read where the stepper opens |
| 50.15a | Kill the app after declaring and relaunch | **Continue the workout?** comes back with the declared time still on the clock. Coming back to the plan's number would undo the decision without saying so |
| 50.16 | The screen after the last set of any hold movement | Every set as a card, the movement's name above them, the plan below, and a line saying these are the numbers the next plan starts from. No escapes — the movement is behind |
| 50.17 | Tap the card of set **one** and change its number | Only that card changes. Sets two and three keep what they ran at. Before this screen there was no writer that could do that: the work screen's writer clears the sets after the one it records |
| 50.18 | Correct every card back onto the plan | The exercise reports nothing at all and the session rating governs it, exactly as correcting a single number back to the plan always did |
| 50.19 | An UNEVEN plan (9-8-8) on a hold | The plan is printed on each card ("set 2 · planned 8") and the "planned N s each" line is absent — "each" would be false |
| 50.20 | Five sets, Dynamic Type XL and an accessibility size, on the smallest screen | The cards reflow to two rows and then to a column, and the screen scrolls. No number is clipped: a number that cannot be read is a number that cannot be corrected |
| 50.21 | VoiceOver on the summary and the running hold | A card reads "set 2, approximately 48 seconds, planned 55" — one sentence with the comparison in it. The Stop button reads "Stop, records 60 seconds". **Set the time** carries a hint saying what it governs and that Stop ends a set early |
| 50.22 | Skip a set of a hold, then finish the movement | **Known limitation, walk it and log what you see.** The summary prints a card for every set, including the skipped one, at the number in force for it — the app keeps skips as a COUNT per movement, not as indices (`SetFacts.Skips`), so it cannot tell which card that was. The number shown is the one the next plan starts from, which is what the line under the cards says, and the card is correctable like any other. Deliberately not fixed in this wave: per-index skips are a change to what the flow records, not to what a screen draws |

### 51. The easier variation moves into the technique sheet (app, R30)

App-only: the engine diff is empty and `golden.json` is untouched. What moved is
where the handle is CALLED from — it still goes through `Engine.easierVariation`.
Walk it seeded above the first variation (`--uitest-long-session` reaches every
ladder's top), because on a fresh install there is nothing below any movement and
the block is absent by design.

| # | Check | Expected |
|---|---|---|
| 51.1 | Today, with six movements in the plan | Six rows, six movements, and nothing under any of them. No accent line, no second control |
| 51.2 | The line above **Start** | One grey sentence saying a row opens the technique, and that the version one step below is in there |
| 51.3 | Open any technique sheet, close it, return to Today | The line is gone. Kill the app and relaunch: still gone — it is spent by the first visit, from ANY of the three doors, not by the plan row in particular |
| 51.4 | Tap a plan row | The sheet opens on that movement, and under the variation tag — before the technique steps, without scrolling — a block naming the movement one rung below and its dose |
| 51.5 | Tap **Switch** | It asks first: "Switch to <name>?", with what the step costs, and the two answers **Keep going** / **Switch**. Nothing has changed yet |
| 51.6 | Answer **Keep going** | The sheet stays on the movement it was describing, and the plan row behind it is unchanged |
| 51.7 | Answer **Switch** | The sheet redraws in place onto the new movement — name, tag, technique, mistakes, "in life" — with no blink of a re-presented sheet, and the block now offers the rung below THAT one. Close it: the plan row carries the new movement and the announced duration has moved with it |
| 51.8 | Keep switching to the first variation | The block disappears rather than standing disabled: there is nothing below the bottom rung |
| 51.9 | Tap the descriptive part of the block, and drag from it to scroll | Neither changes the plan. Only the capsule acts |
| 51.10 | Inside a workout: the ⓘ on the work screen, and the one on the rest screen | The sheet opens with technique, mistakes and "in life" as always, and carries **no** block. The session is fixed at Start; a switch taken here would move the state under a plan already in flight, and the rating at the end lands on both at once — measured on the engine, squat v6 3×15 switched to v5 and rated "on plan" writes 15 into the journal of v5 where the person had shown 4, and a probe passed later in the same session promotes straight past the rung just chosen |
| 51.11 | The next-workout preview (the card after a finished workout) | No block either. It is a look at a future session, not a decision about one |
| 51.12 | An exercise that carries a probe, on Today and in the next-workout sheet | Under the row: *Then a probe: one set of <movement> · <dose>*. The number on the right counts the WORKING sets only — the probe replaces the last of them — so without this line a three-set plan whose third set is a probe read "2 × 15" and said nothing about the set standing after it, while the announced duration counted it |
| 51.13 | An exercise with no probe | No such line. And on a movement that has both a returned set and a probe, two lines, not one sentence |
| 51.14 | Dynamic Type XL and an accessibility size, smallest screen | The capsule drops below the text instead of shrinking; the name wraps; nothing is clipped |
| 51.15 | VoiceOver on the block | One sentence — "One step below: Bar hang, 3×20 sec, holds instead of reps" — and the button reads "Switch to Bar hang", naming the movement out of context |
| 51.16 | All seven languages | The kicker, the capsule, the unit note, the alert's title and body, and the line on Today read naturally and do not clip. `python3 scripts/check_localization.py` is green |
| 51.17 | On the pull-up ladder, a step from the negatives down to a hang | The dose line says the unit changes ("holds instead of reps"). Nowhere else in the library does it, and nowhere else may it say so |


### 52. History remembers the probe (app, R31)

App-only; the engine diff is empty. Needs a workout whose plan carried a probe —
a movement at the ceiling of its variation with the journal to match (§40.4) —
walked to the rating, then opened from the calendar.

| # | Check | Expected |
|---|---|---|
| 52.1 | Finish a workout whose last set of some movement was a probe, doing the probe | Calendar → that day: under the movement, *Probe: <movement> · <number> — passed*. The number is what the probe set recorded, in the PROBE's unit — seconds where the rung below counts reps |
| 52.2 | The same, with a number below the probe's target | *— not this time*. The same words the work screen gives an unresolved probe; nothing scolds |
| 52.3 | Skip the probe set and finish the workout | The line still names the probe and reads *— not this time*: the app cannot tell a skipped probe from an older record, and this sentence is true of both |
| 52.4 | A movement with no probe in that session | No line at all. The row is exactly what it was |
| 52.5 | A workout recorded before this wave (an existing journal) | The line appears with the verdict and WITHOUT a number — the outcome is read off the position the session ended on, which every v3 record carries. Nothing is invented |
| 52.6 | Export the backup, read `dredfit-state.json` | The record carries a `probes` key only when a probe actually reported a number. A session where none did carries no key — a zero would read as "did the probe and showed nothing" |
| 52.7 | All seven languages, and a language switch after the fact | The line reads naturally, and the movement's name follows the switch like the name above it. `python3 scripts/check_localization.py` is green |

### 53. The warm-up counts the switch (app + engine §41.12)

Four moves of the pool have a halfway boundary their own steps name: two are
unilateral (single-leg Romanian deadlift, bird dog) and two are circles that
reverse (arm circles, hip circles). Arm circles are in EVERY composition, so any
session shows this; the unilateral pair needs one of sessions 2–5. Torso
rotations and cat-cow alternate continuously and must stay one countdown.

| # | Check | Expected |
|---|---|---|
| 53.1 | A unilateral warm-up move | 15 s first side → **"Switch sides"** in accent with a 5→1 countdown → 15 s marked **"second side"** → the next transition |
| 53.2 | A circle (arm circles, hip circles) | The same 15 + 5 + 15 with the same tones, and DIFFERENT words: **"Switch direction"**, then **"the other way"**, and "15 s each way" before the switch. Nothing on these screens says "side" |
| 53.3 | Torso rotations, cat-cow, marching, half squats, Y-T-W | One 30 s countdown, no line above it, no switch tone. They alternate continuously — there is no single moment to announce |
| 53.4 | Listen at each boundary | The pause opens with the **falling** two-tone and the second half starts on the rising go — the cool-down's signals exactly (31.2). 3-2-1 ticks precede the end of each half and **none** sound inside the pause |
| 53.5 | The technique sheet of each kind | The capsule reads **"warm-up · 15 s per side"** for the unilateral pair, **"warm-up · 15 s each way"** for the circles, and "warm-up · 30 s" for the rest. Opening it freezes the countdown mid-pause too |
| 53.6 | Pause during the switch, then Resume | Freezes and carries the pause on from where it stopped, handing over to the second half on its own single go — no lead-in, for the reason 35.5 gives about the cool-down twin |
| 53.7 | Lock the phone across a whole split move | The block lands where the wall clock says. Nothing sounds a switch that is already over: the tone belongs to what is on screen |
| 53.8 | The warm-up offer screen | "6 positions · about 5 min", and the block does not overrun what it promised (255 s with two pauses, 260 with three) |
| 53.9 | All seven languages | "Switch sides" / "second side" / "15 s per side" and "Switch direction" / "the other way" / "15 s each way" read naturally and stay distinct; nothing clips |
| 53.10 | Today, on a fresh install | The plan line is **one minute longer than 2.1.0** — ≈ 24–32 min. The reserve for the two blocks grew to 10:00 to pay for the switch pause, and the price is on every announced duration |


## Engine gates before a release

Not a manual row — the five automated gates a release runs from `reference/`,
recorded here because "clean" is not the same word for each of them. The middle
column is machine-read by `scripts/check_engine_gates.py`, which runs every row
and fails on any gate that did not print its line. The full definition, and the
residues that are known and named, live in phase 0 item 3 of
`instructions/CORE_AUDIT.md` — a working document that is deliberately not in
the repository, like `reference/` itself.

| Command | Must print | Clean means |
|---|---|---|
| `python3 scripts/update_reference_manifest.py --check` | `OK:` | the local `reference/` really is the one that produced the fixture. It is not versioned, so it goes stale silently |
| `node verify2.js` | `провалов: 0` | every block of the verifier — 74 772 checks on engine 3.3.0 |
| `node accept.js` | `ПРИЁМКА ЧИСТА` | not one `ПРОВАЛ` line across the twenty wave-acceptance blocks below. It is the wave's own gate: every wave replaces the copy in `reference/` with the one written for it |
| `node passcheck_v3.js` | `Провалов всего: 0` | П1 and П2 both PASS — the two passability claims of §40, that every variation can be reached and that entering one never lengthens the session |
| `node audit_static.js` | `НОВЫХ СРАБАТЫВАНИЙ НЕТ` | no new hit of the "fix applied to one branch of two" class |

What `audit_static.js` compares is **not the number but the absence of new
lines** against the previous run. The cell counts move every wave — the sweep
walks a lattice that grows — and chasing a particular figure hides a regression
as well as a red run does.

`audit_local.js` and `audit_local2.js` are **no longer gates**, and are gone
from this list rather than left in it red. Their sweeps — set floors, the
consistency of the "easier" handle, the week window, reachability — became
blocks 8, 9, 17, 18 and 25 of `verify2.js` in the v3.0 wave, and keeping the
scripts alive beside the verifier would have been a second copy of the same
rules: the thing an audit calls a finding, not a check. Three of their checks
had no twin, and the v3.1 wave put all three inside `verify2` rather than
resurrecting the scripts:

| Was | Is |
|---|---|
| `audit_local` H1 — the descent invariant on every path × the whole grid | block 13, extended to descents that **cross a variation boundary**. The old block excluded exactly that case, which is how the boundary defect of the 26.08.2026 audit lived through it |
| `audit_local2` S4 — the balance envelope on seven rhythms, sliding six-session window | block 6, restored to §20.4's shape. It had regressed to one rhythm and a 24-session sum |
| `audit_local2` S1 — long random stress with a fixed seed | block 29, seed `20260826`. Every other v3 sweep is deterministic by construction, so nothing else covers the classes only randomness reaches |

### Why the gates have a runner

    python3 scripts/check_engine_gates.py            # locally, before a release
    python3 scripts/check_engine_gates.py --contract # what CI can do

Three of the six gates this section used to list **did not run at all** on
engine 3.0.0: they called `state.levels` and `decodeLevel`, exports that wave
had removed, and died before their first check. Nothing went red, because a
gate that is never run is indistinguishable from a gate that passed — and a
gate named in a tracked checklist is worse than no gate, because it reads as
done. It was the second wave in a row with that exact failure; v2.27 lost two
of six the same way, and the rule written down after it ("a wave that removes
an export must look for it in every gate") did not survive the next wave. So it
stopped being a rule to remember.

The runner reads the table above, so adding a row is what makes a gate run, and
a row nobody can run fails instead of reading as done. **Running the gates is a
LOCAL gate, not a CI one** — a real limit, not an oversight: `reference/` is
gitignored and never checked out on a runner, so CI has nothing to execute.
What CI checks is the contract — that the table still parses, and that every
row names both a command and the line that means clean.

### What `accept.js` checks, and why each check is there

`verify2.js` proves the engine obeys the spec. `accept.js` proves a *wave* kept
the promises it was built on — every check below was put there by a defect that
shipped, or by a decision the owner made and would otherwise have to take on
trust. It is deterministic, self-contained and takes seconds, and it calls the
engine's **exported** predicates rather than keeping its own copies of them
(rule 16 of the audit protocol), so a rule and its check cannot drift apart.

Twenty blocks. The `Пn` numbers are the ones they carried in the v2.27
acceptance and keep them on purpose, so a block can be traced back to the
defect that created it; the `Иn` and `Фn` blocks arrived with v3. There is no
П13 any more — the roll-call it performed is now an `EXPECTED` list plus a
`process.on('exit')` hook, which also catches a script that dies before the
last block instead of printing "no failures" and reading as a pass.

| Check | What it asserts | Why it is a gate |
|---|---|---|
| П1 | On the honest "that was tough" path a movement never drops below two working sets — every pattern × every position × every cut, 25 taps deep | The set floor is the last thing between the engine and a one-set plan. v2.25 could reach the floor by two mechanisms at once, and the second did not know about the first |
| П2 | Every plan is well-formed: sets within floor and max, a positive dose, a display string, six movements | Cheap, and it catches the whole class of "the handle produced a plan nobody can read" |
| П3a/b | A set never comes back while the person is answering "tough" or skipping | The set is returned by growing strength, not by a timer. Invisible unless swept |
| П3c | When a set does come back, the volume jump is at most ×1.50 | The first set back used to be +100 % by construction (a gap §36.10 п. 5 named and priced). The floor moving 1 → 2 is what bought the ×1.50, and this is what keeps it bought |
| П4 | The "give me an easier variation" handle always changes the variation, and the position it lands on satisfies the engine's own `noHarder` | A handle that answers with the same exercise is a lie on a button. The second half is new in v3.1: the handle used to land in the journal unconditionally, which on a per-side neighbour doubled the work |
| П5a/b | `generateSession` is deterministic, and state survives a JSON round-trip | The fixture, the port and the whole audit apparatus stand on both. One field that does not survive `JSON.parse` turns golden into a coin toss |
| П6 | No path of descent returns a position heavier than the one it left | The 20.08 audit found "descent never adds load" checked on two of six paths, while the other four produced transitions the exported predicate refused |
| П7 | An honest year moves the position — Σ posOrd, plus where `squat` lands and what the session costs in minutes | Progress is what a safety wave is most likely to quietly destroy. The numbers are printed; what is asserted is only that the sum is above zero, because there is no right figure |
| П9 | Skipping sets never digs below the floor of two | The handle this used to check is gone; the promise now belongs to the skip inside the workout, one movement at a time (§38.2 rule 3) |
| П11 | "Tough" never makes the next shown plan heavier — including on top of an active cut | The composition question. Each mechanism was fine alone in v2.25; the P0s came from the pairs |
| П12 | A growth event never lightens the plan | The mirror of П11, and the one a sub-step is most likely to break: growth costs one rep in one set, so the arithmetic that spends it has two ways to round |
| И1 | The ladder's density is at most ×1.50 between neighbouring variations — recomputed independently from `LIBRARY`, not read from the engine | §40.9's first invariant. Computing it from the same table the engine uses would assert the table against itself |
| И3 | A probe that was not completed does not move the position | The probe is the only entry into a new variation (§40.4), so a failed one that still moved something would promote people through movements they cannot do |
| И6 | Feeding the same feedback twice is a no-op | `applySilentDecay` is deliberately not idempotent and is keyed on `comebackDecidedFor`; everything else must be, or a retried write moves the person twice |
| Ф1 | No transition anywhere raises the load by more than ×1.50 | The absolute ceiling on a single step, independent of which mechanism produced it |
| Ф2 | After "tough", the next plan is not heavier — asked of the engine's own `noHarder` predicate | The 26.08.2026 audit proved by mutation that this had been TAUTOLOGICAL: the predicate compared the plan against itself, and breaking the rule produced zero failures. It now compares against the journal |
| Ф2w | The same, measured as work weighted by `w` rather than by reps | Reps are not comparable across a variation change (§30.4), so the honest second opinion is a weighted one |
| Ф3 | A descent that crosses a variation boundary does not raise time under load — with the three structurally impossible boundaries named as a closed list | The headline defect of the 26.08.2026 audit: the landing rose on 49 boundaries out of 49, worst ×11.25. `hinge 4`, `hinge 7` and `pull_bar 3` stay accepted gaps (§41.6 item 1) and are listed by name, so a fourth cannot appear quietly |

Two things this table deliberately does not claim. Ф1 and П12 are bounded by
what the engine already accepted rather than by zero, so they detect a
*regression* and not a defect that was already priced. And the parity blocks of
v2.27 — П8, П10, П4b — are gone with the baseline they compared against: v3
rewrote the encoding, so there is no cell-for-cell twin of the old engine to
compare with, and a block that cannot be computed is removed rather than left
asserting nothing.

---


## Issue registry

Log every failure found while running this plan. Keep entries until they ship fixed.

| ID | Found | Area | Description | Severity | Status |
|---|---|---|---|---|---|
| I-1 | 2026-07-18 | Workout flow | **Exit** during a workout discards the session with no confirmation — an accidental tap loses all progress | medium | **fixed in the design-audit wave** — confirmation dialog with a "Finish now" path (§1.10), plus mid-workout snapshots make even a kill recoverable (§24) |
| I-2 | 2026-07-18 | Today | Today did not render a rest-day state; only the Calendar and widget marked rest days | low | **fixed in 1.4.0** — Today shows a rest state with a "Train anyway" escape hatch (§6.6) |
| I-3 | 2026-07-18 | Accessibility | Text sizing was hardcoded via `.font(.system(size:))` throughout, so it did not scale with Dynamic Type at all | medium | **fixed in 1.4.0** — 88 call sites moved to `dredfitFont`; display numbers scale to a cap (§16) |
| I-4 | 2026-07-18 | Calendar | Rest days rendered identically to out-of-month days (dimmed number, no shape, no legend entry) | low | **fixed in 1.4.0** — soft fill plus a legend entry (§6.5) |
| I-5 | 2026-07-18 | UI tests / CI | 6 of 16 UI tests fail on GitHub runners with `No matches found for … "Skip rest" IN identifiers`, while the same suite passes 16/16 locally. Timing flakiness under runner load, not a product defect — the rest phase advances before the tap lands. Survives the workflow's 3 retries | medium | **fixed by PR #14 (2026-07-23)** — a DEBUG-only `--uitest-fast` hook collapses rest to ~1 s, and `completeWorkout` drives only the stable **Done** / **Start hold** controls, never the auto-vanishing **Skip rest**, confirming each tap with `waitForNonExistence`. Verified 2026-08-01 against the nightly history: the last run carrying this signature was 2026-07-23 03:40, hours before the fix landed. Of the eight nightlies since, the two reds have unrelated causes — a runner-side `XC_kAXXCAttributeFocusedApplications` timeout (07-26) and one stale assertion fixed the same morning by PR #32 (07-29) — and the last three are clean 38/38 with zero individual failures, so no retry is masking anything |
| I-6 | 2026-07-24 | Workout flow | `testMilestoneScreenListsEverythingEarned` intermittently hangs mid-workout: the app stops responding (neither **Done** nor **Start hold** is present, the rating never arrives) and XCTest kills it — "Test crashed with signal term". Failed twice on a busy machine at `99704ef` and on the 1.7.1 branch, passed on a quiet one, and did not reproduce at `dc67b20` — the commit before the audible countdown. Suspect: audio playback on the main actor stalling under simulator load | medium | **not reproducing since 2026-07-23** — watched, not declared fixed. The nightly never showed the hang signature (`signal term`) at all; what CI did show for this test was `did not reach the rating screen`, which is the I-5 root cause and went away with PR #14. Nine nightlies since, the last three clean 38/38. Kept on the register because a load-dependent heisenbug cannot be proven gone: if it recurs, sample the app while it is stuck rather than re-running |
| I-7 | 2026-07-30 | How it works | The subtitle still read "Seven things worth knowing about the regulator." after the "Weekly rhythm" section made it eight — caught by the 1.8.0 store-frame recapture of s8 | low | **fixed in the 1.8.0 wave** — key renamed to "Eight things…", all four languages updated |
| I-8 | 2026-07-30 | Widget tests | `WidgetTimelineTests` word assertions compared SwiftUI `Text` values — equality of two Texts with identical words is nondeterministic (localized-storage identity, not content): green bare, 12 failures under `-testPlan` + `-test-iterations`, then pass-pass-fail across three identical bare runs | medium | **fixed in the 1.8.0 wave** — `headline`/`subline`/`nextPlanText` return resolved `String(localized:)`, tests compare strings; full plan then green 281/0 |
| I-9 | 2026-08-01 | Widgets | `TodayEntry.empty` — the timeline's fallback when the App Group snapshot is missing or undecodable — was a stored `static let` built with `.now`. A stored static initialises once per process, so the date froze at first access and every later timeline request in the same extension process got an entry already dated in the past, handing WidgetKit a timeline expired on arrival under `policy: .atEnd`. Found by code review, not by this plan | low | **fixed in the 1.8.1 wave** — the entry is computed, so it carries the time it was built. Not covered by a new test: an assertion on freshness passes or fails depending on when the static was first touched in the test process, so it would not reliably fail on the old code. The device-side check is §12.1–12.6 |
| I-10 | 2026-08-01 | Cool-down | "Chest and shoulders at the wall" and "Wrists and forearms" ran as one 30 s countdown with no side switch, while their own technique steps said "Swap arms / hands halfway through" — the two positions the app knew were two-sided and still left the user to count. The `perSide` flag was set in the cool-down wave (#33), when it only chose whether to show the "15 s per side" hint; the counted 15 + 5 + 15 switch (#35) was later built on the same flag without re-auditing which positions are unilateral, and a unit test pinned the old classification under the name "unilateral positions only" | medium | **fixed in the 1.8.2 wave** — both flagged `perSide`, so they get the hint, the pause, the switch tone and the "second side" marker like the other four. A new test asserts no bilateral position asks the user to swap sides, so the two cannot drift apart again |
| I-11 | 2026-08-03 | Widgets | Reported (#55, iPhone, iOS 26.5.2, App Store 1.8.0 (11)): the medium and large entries of the home-screen size row do nothing — the widget stays small, nothing redraws, no placeholder, no error. The page it was reported from was close to full | low | **not reproducible on iOS 26.5** — on an iPhone 17 simulator with room on the page, the size row converts the widget through all three home sizes (168×191 → 353×191 → 353×391) and each layout renders; the gallery offers the same three sizes and adds at any of them; the extension neither crashes nor is jetsammed while doing it. Nothing to fix in `supportedFamilies` — all six families have shipped since #23, tag `v1.8.0` included. The plan gains §12.18–12.21 so the resize path is covered from here on, and the page-space check is the first thing to rule out. What the acceptance check did find is the ru truncation fixed alongside it (below) |
| I-12 | 2026-08-03 | Widgets | Found running §12.21 for I-11: on the large widget in Russian the longest catalog name ended in an ellipsis — «Птица-собака» (удер… — because the plan row carries the load in the long form the snapshot writes ("3×20 сек на сторону"), leaving the name short of the width it needs. Brazilian Portuguese fits; English is nowhere near the edge | low | **fixed in the #55 wave** — the name shrinks like every other line of the widget (`minimumScaleFactor(0.8)`) instead of truncating, which also matters because sibling variations differ at the *end* of the name. Verified on the simulator in all three locales |
| I-13 | 2026-08-07 | Store screenshots | Frame s8 was captioned "Eight plain facts about how the plan moves" in all seven languages, while the screen inside the frame has read "Nine things worth knowing about the regulator" since the discomfort section was added in the #38 wave. The caption lives in `appstore/tools/compose.py`, not in a String Catalog, so no localization gate could see it — the frame contradicted itself in every locale | low | **fixed in the 1.9.0 wave** — all seven captions now say nine, and the full recapture reissued the frames. Exactly the I-7 failure mode (a count in prose going stale when a section is added) and caught the same way: by recapturing rather than by a test. The standing mitigation is unchanged — any release that adds a "How it works" section must re-read the s8 caption |

| I-14 | 2026-08-23 | Progress | Found by the UI suite, which is **red on `develop`** for this one cause: `testProgressReflectsCompletedWorkout` ("0" is not equal to "12" — the total level after "easy" should be 12) and `ReleaseSmokeTests.testReleaseSmokeEnglish` row S5 ("the history sheet must list the level the workout ended on"). Since v2.22 the first growth steps do not land in the **level** at all — they land in the **sub-step**: one honest "easy" on a fresh install moves all six worked patterns by 2 sub-steps each, and every level stays 0. The Progress screen and the history sheet both read levels, so a person who has just trained and been told the plan will grow is shown a screen that says nothing happened. The tests are not stale markup — they assert the right amount of progress (12 is exactly the sub-step total) against a screen that cannot see it | medium | **open — the screen is the question, not the test.** Verified on `chore/close-v2.25` (develop + docs only), each test run alone: both still fail with the signatures above. Deliberately not fixed inside the closing wave: what Progress should show for a sub-step is a product decision (a fractional level, a second axis, or a different sentence), not a markup change. Backlog: "Прогресс не видит под-ступени". **Closed by engine v3.0 (2026-08-26 reconciliation).** The product decision the entry was waiting for was taken by the wave that removed the level: Progress now measures a pattern along its own ladder, and the ordinal it draws (`Engine.totalProgress` → `posOrd`) counts the sub-step — `ordInVar` ends `+ pos.sub`. The screen the entry says "cannot see it" can see it. The two UI tests were re-marked to the new vocabulary in the same wave and are not evidence either way; **§47.3 and §47.5 are the replacement checks** and they are unwalked — this is closed on the code, not on a run |
| I-15 | 2026-08-24 | Today, Workout flow | Found running §45.10 for the design re-review wave, and **not caused by it — the frames are pixel-identical to the previous release**. At the accessibility Dynamic Type sizes (checked at `accessibility-extra-extra-extra-large` on an iPhone SE) two things on the app's first and busiest screens come apart. On **Today**, the two session handles are drawn on top of each other and on top of the "≈ N min · N exercises" line above them — three sentences in one place, none of them readable. On the **work screen** the column has no `ScrollView`, so once the type outgrows the height the header, the exercise name and the "technique" affordance are simply pushed off the top of the screen; what is left starts mid-number. Neither is a truncation the layout chose — both are content the layout never accounted for | medium | **half closed by removal, half open and now larger.** The Today half is gone with the controls: v2.27 removed both session handles, so there are no long sentences left to overlap the line above them. The work screen half stands, and this wave adds to it — one more line in the header ("≈ N min left") and a third action under the button, on a column that still has no `ScrollView`. The fix is the same layout decision it always was: scroll, or drop the elements the screen can afford to lose. Deliberately not taken inside a §38 diff, for the reason it was not taken inside the accessibility one — a layout decision hidden in a feature wave is a decision nobody reviewed. **Still open at 2026-08-26, and larger again:** the count-in wave puts a fifth thing in the same column (§49.1–49.3) on a screen that still has no `ScrollView`. Unchanged as a decision — it wants its own wave, not a corner of someone else's |
| I-16 | 2026-08-26 | How it works | Found reconciling the docs with the shipped app, **not by a test — nothing pins either half**. `HowItWorksView.swift` has **twelve** sections while its subtitle still reads "Eleven things worth knowing about the regulator." — the third occurrence of the exact failure mode logged as I-7 and I-13 (a count in prose going stale when a section is added). Worse, the section v3.0 added, "Trying the next movement", was given `id: 12` but placed tenth in the array, and `id` *is* the number drawn in the circle — so the visible numbering reads **1 2 3 4 5 6 7 8 9 12 10 11**. The UI test that opens the sheet asserts seven section titles exist and never counts or orders them | low | **closed by code (2.0.0, verified 2026-08-28).** `HowItWorksView.swift` now has `Section(id: 1…12)` declared in that literal order — the numbering defect is gone. The subtitle reads "Twelve things worth knowing about the regulator." — the stale-count defect is gone too. `appstore/tools/compose.py`'s s8 caption says Twelve/Двенадцать/Doce/Doze/Zwölf/Douze/Dodici across all seven languages, so the frame does not contradict the screen. Both halves of the original defect (subtitle count, and id-vs-array-order) are closed; still no test pins either — the standing mitigation from I-13 remains a read-through, not a gate |
| I-17 | 2026-08-26 | Spec, store listing | Found reconciling the docs with the shipped engine. Spec §37.1 declares the app's entry boundary as **24.8 min** (full 34.0 at the bottom of the scale), measured on the v2.27 library at level 0. On the shipped v3 library a clean start is **30.5 min** full and **23.3 min** cut to the sets floor from inside the workout — measured against the reference, `sessionMinutes(generateSession(initState()))`. The declared floor moved and nothing re-measured it; the app's own onboarding string already says "about 31 minutes", so the app and the spec now disagree | medium | **half closed by this release, half still open.** The 30.5 / 23.3 pair was re-measured against the shipped 3.3.0 reference on 2026-08-28 (6 movements, `var=1, sets=3, dose=4`, i.e. 3×4 entry) and confirmed — no longer a v3.0-era estimate. The store-listing half's replacement, `appstore/release_texts_2.0.0.md` (1009 lines, "Prepared 2026-08-28"), shipped with 2.0.0; its 2.1.0 successor is `appstore/release_texts_2.1.0.md` (1139 lines), and the 2.0.0 file is due for removal at the end of this wave — **closed.** §37.1 itself still declares the stale v2.27 pair; that is a spec edit nobody has made, and remains open |
| I-18 | 2026-08-28 | Progress, VoiceOver | Found by Skeptic #6 (numbers vs. runs). Two live, non-annulled rows in this plan were still written in the pre-v3 level scale (0-47), which the v3.0 wave removed: §45.8 said **"Squat, level 18 of 47, selected"**, and §46.2 said **"≈ 31-55 min" and "≈ 40-94 min" "at L34 and L47"**. `ProgressScreen.swift:524` reads **"variation N of M"**, not a level out of 47 — the described screen does not exist, so neither row is a check that can pass | low | **closed by rewrite (2026-08-28).** §45.8 now reads "variation N of M"; §46.2 now names the state ("once the plan is on the sets floor") instead of level numbers that no longer exist. Same failure class as I-16/I-17: prose in the pre-v3 vocabulary, not caught by any gate |
| I-19 | 2026-08-28 | Store frames, it | Found by Skeptic #2 reading the recaptured frames as images. `appstore/screenshots/it/s8.png` shows **"Com'era:"** with a straight apostrophe (U+0027) next to the button **"Lascia com'era"** with a typographic one (U+2019), in the same screen. The Italian catalog carries **22 strings with a straight apostrophe**; French was brought to the ’ rule in an earlier wave and Italian was never done. No gate sees it: `check_localization.py` checks that a key is translated, not how it is punctuated | low | **open — deliberately deferred by the owner (2026-08-28).** Not introduced by this wave, and the cost is not the 22 strings: editing any `.xcstrings` invalidates the frame set, and the seven locales had just been shot from one build. Fixing one apostrophe here would mean re-shooting part of a set that took two full capture runs to get right. A later wave closes all 22 at once and recaptures once |
| I-20 | 2026-08-28 | Store frames, rest screen | Found by Skeptic #2, twice, on two independent capture runs. The `s9` (`rest_`) frame catches the countdown digit **inside** `.contentTransition(.numericText)` (`FlowChrome+Rest.swift:99`): the second digit measures 187-209 px of ink against 118-121 px for a single glyph, i.e. two overlaid characters. Which locales are hit is random per run — `es`/`pt-BR` the first time, `ru`/`pt-BR`/`de`/`fr` the second. The driver does `Thread.sleep(16)` then `snap()` (`StoreScreenshots.swift.reference:279-280`), so the shot has no phase relative to the tick | low | **closed by owner decision (2026-08-28): a digit blurred mid-flip is not a defect, and such a frame is accepted.** Recorded so a later skeptic does not re-raise it as a blocker. If it is ever reopened, the fix belongs in the driver, not the app: align the shot to the middle of a tick, or assert the digit is stable before `snap()`. Nothing in CI looks at frame pixels — `compose.py` measures caption width only |
| I-21 | 2026-09-01 | Accessibility, Design tokens | Found by extending `BrandPaletteTests` while adding the exercise summary, **not by any gate — the pair had none**. `accentText` on `accentSoft` measures **4.20:1 in the dark scheme**, under the 4.5 that small text needs. It is the pair the probe badge and the out-of-order-maximum note are drawn in, both shipped, and the only thing standing behind it was a comment on the maximum note saying that `accent` itself comes to 2.91:1 on that fill — true, and about a different colour. The floors list gates `ink`-on-`accentSoft` and `accentText`-on-`bg`; the product of the two was never asked | medium | **open — reported, not fixed here.** The new screen avoids it: every card of the exercise summary uses `ink` on the accented fill, which is gated at 4.5 dark and 7 in Increased Contrast, and says "above plan" in words on the caption so the fill is never the only signal. Fixing the pair itself means moving a token, which is the owner's decision and invalidates the whole store screenshot set — a decision hidden inside a feature wave is a decision nobody reviewed (the I-15 reasoning). The measurement is pinned by `testTheAccentedPillIsPinnedWhereItActuallyStands` so it cannot drift further without a red test |
| I-22 | 2026-09-02 | UI tests / CI | The nightly has gone red on six of the last eight runs, each time on a DIFFERENT test, and two of those failures were not assertions at all (`Failed to get list of active applications: Timed out fetching `XC_kAXXCAttributeFocusedApplications``, 01.09; `point.x != INFINITY`, 31.08). The run of 02.09 failed one test, `testBarWorkoutFlowsToRating`, on a bare `XCTAssertTrue(rating.waitForExistence(timeout: 3))` with no message — so the whole report was "XCTAssertTrue failed". Not a product defect: the same test passes locally at 130.2 / 129.3 / 129.6 / 130.5 s across four runs, three of them full-suite. The job takes 1h7m for 74 tests, and the failing assertion is the tightest deadline in the longest walk | medium | **half fixed 02.09.2026, half open.** `skipExercises` used to spin against the cool-down's own question until its wall-clock deadline expired — `limit: 6` on a session of six with one exercise already behind burned seventy seconds doing nothing — so the walk ran out of budget before it ran out of exercises. It now returns as soon as that question is up (it is the caller's to answer), and the per-exercise budget went 15 s → 30 s. Measured: `testBarWorkoutFlowsToRating` 130.5 s → 60.5 s — seventy of its hundred and thirty seconds were that spin. And the assertion itself was one of FIVE waits for the rating screen written at `timeout: 3`, two of which the nightly has now lost (`testBarWorkoutFlowsToRating` 02.09, `testCooldownRunsBetweenLastExerciseAndRating` 31.08 — and again on the local full run of 02.09, at 76.5 s). The rating is the screen a whole workout ends on and every wait for it stands at the end of a chain of taps, so all four short ones went to 15 s and the two that carried no message got one. **What is not fixed is the runner itself:** at 1h7m the suite is at the edge of what one job can do, and the relaunch it takes on a failure is also what makes the closing `Executed N tests, with 0 failures` omit the failure. Sharding the suite across two or three jobs is the standing proposal, and it is a CI decision rather than a test fix |
| I-23 | 2026-09-02 | UI tests / CI | `testCooldownRunsBetweenLastExerciseAndRating` failed 02.09 not on an app defect: the cool-down chain itself did not change this wave, but a single unconfirmed tap on `skip-cooldown` inside a `fullScreenCover` was LOST — the 02.09 failure synthesized the tap at (201,792), dead center of the live button, and the block simply played out all seven positions afterward, so the test read a screen it never asked the app to leave | medium | **fixed.** `skipCooldownBlock()` (`DredfitUITests/WorkoutDriver.swift`) now confirms the tap by waiting for the button's disappearance, retries once, and caps the wait at ≤ 9 s against the block's ~17 s natural end — the cap IS the check: at 20 s the test would go green on the block merely finishing on its own and would stop testing the skip at all. Proved by mutation: breaking the tap delivery reproduces a red at 87.3 s; three ordinary runs stayed green at 82.1 / 79.0 / 78.8 s |
| I-24 | 2026-09-02 | Progress chart, Store frames | Found by sweeping App Store capture frames against the live screens: the progress chart's axis dropped its last date label — Charts discards a tick that does not fit rather than repositioning it, so the rightmost date silently vanished | medium | **fixed, this wave (commit 4501479).** Pinned by `DredfitTests/ProgressChartAxisTests.swift`, which was red on the prior code and stays red on three independent mutations of the axis logic. No gate had ever looked at chart axis content before this test existed |
| I-25 | 2026-09-02 | Technique sheet, l10n (de) | Found by the same App Store frame sweep: `.lowercased()` in the technique sheet's pattern capsule broke the capitalization of all ten German pattern names — a defect that only shows up in a correctly-populated catalog at runtime, so no static localization gate could have caught it | medium | **fixed, this wave (commit 4501479).** No gate watches rendered capsule casing; recorded so the class (`.lowercased()`/`.uppercased()` applied to a localized noun) is named for the next sweep |
| I-26 | 2026-09-02 | Store capture tooling | Operational, not a product defect. `appstore/tools/seed.py` writes into the app's container and its seed only takes if the simulator is already BOOTED, with no rebinary between seed and run; a `simctl shutdown all` plus a fresh build ahead of this wave's capture wiped the seed silently — 28 of 42 capture methods failed on "seeded Today should show a plan", while seven `today_` frames were written anyway against an unseeded plan, i.e. a partial set that would have looked plausible enough to ship. Separately, `assertLanguage` flaked ("app did not come up in de: no 'Fortschritt' tab") and survived three retries on one method although the app does come up in that locale, confirmed by a direct run with a screenshot | low | **seed half fixed 03.09.2026, language half open.** `seed.py` no longer writes blind: it refuses a device that is not `Booted` and an app that is not installed, each by name instead of a `SimError 405` traceback, and it plants a marker in `Library/Caches` whose absence is proof that the container was wiped rather than a guess about it. `seed.py <udid> --check` tells the two failures apart — a seed that never survived, and a test that walked the wrong way — for the price of a second instead of a capture run. The order that makes the seed hold (install, then seed, then run; one throwaway method after any rebuild) is written into `appstore/tools/README.md` and the release regulation, because it was never a preference. All six paths exercised, wipe detection included. **What stays open is the `assertLanguage` flake:** "app did not come up in de: no 'Fortschritt' tab" survived three retries on one method while the app demonstrably comes up in that locale — confirmed by a direct `simctl launch` and a screenshot showing the tab. That is a harness timing question, unrelated to the seed, and it still costs a retry per capture run |
| I-27 | 2026-09-04 | Warm-up | The same class as I-10, in the other block, and wider than it first looked. FOUR moves have a halfway boundary named by their own steps — the single-leg Romanian deadlift and the bird dog ("one side at a time"), and the two circles whose step 2 says "switch direction halfway" — and the warm-up ran each of them as one 30 s countdown with no switch. The person either spent thirty seconds on one side (in one direction) or changed on their own count. The cool-down has counted the switch since #35 and the work screen since the hold wave; the warm-up was never re-audited when §40.1 moved movements into it out of the strength ladders. The circles were missed a second time inside this very wave — the first pass fixed only the two unilateral moves, because "unilateral" was read off the shape of the movement instead of off the steps | medium | **fixed, this wave.** All four run 15 + 5 + 15 with the switch tone and the marker, and the WORDS follow what is switched: sides for the two unilateral moves, direction for the two circles, with a technique capsule to match. Torso rotations and cat-cow stay whole — they alternate continuously, so there is no moment to announce. The pauses cost 15 s in the dearest composition, which the reserve of §37.7а had no room for, so `warmupMin` went 5 → 6 through the reference chain and every announced duration grew by a minute — priced out loud, as in §37.7а. `BlockReserveTests` pins the blocks against the reserve, `GetReadyTests` pins the classification by id (all three kinds, so a move cannot quietly change camp), and `SplitStageWords` exists as a type precisely so a test can assert that a circle is never told to switch sides |
| I-28 | 2026-09-04 | Workout flow, holds | Two defects in the hands-free hold run (R23), both found by the owner walking a real workout. (1) The rest between sets ran its full minute, sounded its go, and was then followed by a SECOND window of fifteen seconds with its own 3-2-1 and its own go before the set started: a minute of rest actually took a minute and a quarter, the start of one set was announced twice, and those seconds are counted by no estimate anywhere — `restSetSec` is what the engine budgets between sets. The window was deliberate (a set the run opens was "priced as travel"), which is why no gate caught it: a UI test asserted it as the intended behaviour. (2) That same rest could not be PAUSED. It is the one screen of the work phase whose clock acts on its own, so it was also the only place where stepping away cost a set — the guided blocks have had a pause since #61, and the work screen never needed one until one tap started buying a whole exercise | medium | **both fixed, this wave.** The rest is now the lead-in: its own 3-2-1 ends on the go that starts the hold, exactly as the side-switch pause has always started the second side. A rest cut short by Skip still earns the tap's five seconds, and that asymmetry is a rule with a test on each half. The rest of a run offers **Pause**/**Resume** through the same `BlockPause` state both blocks use, with a floor on what it resumes into so nobody is dropped into a plank two seconds after walking back in; a paused rest is persisted as the rest it will be when the pause ends, because a nil end date would read back as "no rest was running" and hand the person the set they had just finished. `HoldFactsTests` and `BlockPauseTests` pin the two rules; three UI tests walk them |
**Severity.** *high* — data loss, crash, or a broken core flow · *medium* — a feature misbehaves but there is a way around it · *low* — cosmetic or a rare edge case.
