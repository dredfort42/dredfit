# Dredfit — manual QA checklist

Automated coverage (653 tests: core invariants, golden parity, app units, UI flow) is described in [README.md](README.md#testing). This document covers what a simulator or a device has to be driven by hand to confirm: system integrations, wall-clock behavior, locale passes, and anything that only misbehaves on a real screen.

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
| S1 | Cold start on a fresh install | Opens on **Today** with "Workout 1", **≈ 26–34 min**, 6 exercises, one **Start** button with nothing to agree to first, and an **"Easier"** handle on each movement row. Both minutes are engine arithmetic, not decoration — the full plan and the same plan on the sets floor: read them from the reference when they move, never off the screen |
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

| # | Check | Expected |
|---|---|---|
| 3.1 | Tap **Start hold** | Countdown runs down from the planned seconds |
| 3.2 | Let it finish | 3-2-1 signals, then the two-tone finale; rest begins automatically |
| 3.3 | **Stop the hold early** | The recorded actual is rounded to the **nearest multiple of 5** and clamped to 5…90 s |
| 3.4 | Verify 3.3 on the rating screen | The summary shows "actual N" where N is a multiple of 5 |
| 3.5 | A per-side hold | Side one runs, then a 5 s "Switch sides" pause opens with its own falling tone, then the second side **starts itself** on the usual go, marked "second side"; the recorded actual is the **smaller** of the two sides |
| 3.6 | While a hold is counting down | **Went differently** and **Skip exercise** are hidden and unresponsive |

### 4. Adjusting and skipping

| # | Check | Expected |
|---|---|---|
| 4.1 | **Went differently** on a reps exercise | Inline stepper opens: −/value/+ and **OK**; steps by 1 within 0…30 |
| 4.2 | Same on a hold exercise | Steps by 1 within 5…90; value shows a trailing "s". Re-marked for engine v2.21 (spec §32.6): the hold ladder is relative, so a five-second grid could express only 13 of the scale's 48 rungs |
| 4.3 | Enter a value **equal to the plan** and confirm | The override is dropped entirely — the rating screen shows no adjustment for it |
| 4.4 | Enter a different value and finish the workout | Rating screen summary shows "actual N" in accent; history later shows the same |
| 4.5 | **Skip exercise** | The flow advances; that exercise is marked skipped |
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
| 6.1 | Settings → **REST DAYS**, fresh install | Sunday **and Wednesday** highlighted (issue #36); captions "Highlighted days are rest days" and "2–3 rest days a week is the recommended rhythm". An install upgrading from a file without the key keeps Sunday only |
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
| 7.3 | Allow, then keep the default rest days | A 28-day window of **one-shot** notifications, one per training date (**20** with the two default rest days — 28 days less four Sundays and four Wednesdays); none on rest days. The window refills every time the app becomes active |
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

### 10. Apple Health ⌚ (write-only)

Simulator HealthKit is unreliable; run this on a device.

| # | Check | Expected |
|---|---|---|
| 10.1 | Settings → **HEALTH** → enable | Permission sheet asks only to **write** workouts; purpose string mentions nothing is read |
| 10.2 | With existing history, on enabling | Offered a backfill; choosing "Only new ones" exports nothing historical |
| 10.3 | Complete a workout | It appears in the Health app as *Functional Strength Training* with the real duration |
| 10.4 | Run a backfill with history present | Each past workout appears **once** |
| 10.5 | Run the backfill **again** | **No duplicates** are created |
| 10.6 | Turn Health off, complete a workout, turn it on again | The workout done while off is not silently lost — it backfills, and still no duplicates |
| 10.7 | Deny the Health permission | The toggle reflects the denial; nothing is written |

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

The snapshot contract is unit-tested on every run (the snapshot URL is injected, so these no longer skip on unsigned/CI runs): `testWidgetSnapshotMirrorsWeekStatuses`, `testWidgetSnapshotCarriesTheLevelWeekAndPlan` and `testWidgetSnapshotFromAnOlderBuildStillDecodes`. What these manual checks still own is the WidgetKit side: timeline rendering, reload timing, the real App Group container, and everything that only misbehaves on a real screen.

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
| 45.8 | VoiceOver on Progress | A row reads **"Squat, level 18 of 47, selected"** — the number with the scale the bar draws it against. Selected, the variation and the next milestone follow; the level is not said twice |
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
| 46.1 | Today, a training day, fresh install | The plan line is a **range**: "≈ 26–34 min · 6 exercises" — the full plan and the shortest the session can be made from inside it. Nothing under it to agree to; each movement row carries **"Easier"** and nothing else |
| 46.2 | The same at L34 and L47 | "≈ 31–55 min" and "≈ 40–94 min". A plan already on the sets floor shows **one** number, not a range of one |
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

## Engine gates before a release

Not a manual row — the six automated gates a release runs from `reference/`,
recorded here because "clean" is not the same word for each of them. The full
definition, and the residues that are known and named, live in phase 0 item 3 of
`instructions/CORE_AUDIT.md` — a working document that is deliberately not in the
repository, like `reference/` itself.

| Command | Clean means |
|---|---|
| `python3 scripts/update_reference_manifest.py --check` | `OK` — the local `reference/` really is the one that produced the fixture. It is not versioned, so it goes stale silently |
| `node verify2.js` | 0 failures |
| `node accept.js` | "ПРИЁМКА ЧИСТА" and not one `ПРОВАЛ` line — the twelve wave-acceptance checks below |
| `node audit_static.js` | "НОВЫХ СРАБАТЫВАНИЙ НЕТ" — no new hit of the "fix applied to one branch of two" class |
| `node audit_local.js` | "ЛОКАЛЬНЫЙ ПЕРЕБОР ЧИСТ" — H1–H8 without failures |
| `node audit_local2.js` | S2–S6 without failures; S1 reports **zero** invariant violations and **one** cell parked at the set floor — the named residue of item 46. A second at-floor cell, or any violation off the floor, is a finding |

What is compared is **not the number but the absence of new lines** against the
previous run. The cell counts move every wave — the sweep walks a lattice that
grows — and chasing a particular figure hides a regression as well as a red run
does.

### What `accept.js` checks, and why each check is there

`verify2.js` proves the engine obeys the spec. `accept.js` proves a *wave* kept
the promises it was built on — every check below was put there by a defect that
shipped, or by a decision the owner made and would otherwise have to take on
trust. It is deterministic, self-contained and takes seconds; the only thing it
needs from outside is the previous engine, `adaptive_engine.v2.25-baseline.js`,
which lives in `reference/model-v2.26/` (point `DREDFIT_V225` at another copy to
compare against a different baseline). Twelve numbered checks, seventeen
assertions — П7 prints a number and asserts nothing on purpose.

| Check | What it asserts | Why it is a gate |
|---|---|---|
| П1 | On the honest "that was tough" path a movement never drops below two sets — every pattern × every level × every cut, 25 taps deep | The set floor is the last thing between the engine and a one-set plan. v2.25 could reach the floor by two different mechanisms at once, and the second one did not know about the first |
| П2 | Every plan is well-formed: sets within floor and max, a positive dose, a display string, six movements | Cheap, and it catches a whole class of "the handle produced a plan nobody can read" |
| П3a/b | A set never comes back while the person is answering "tough" or skipping | The set is returned by growing strength, not by a timer. This is the promise the wave replaced the time budget with, and it is invisible unless swept |
| П3c | When a set does come back, the volume jump is at most ×1.50 | The first set back used to be +100 % by construction (a gap §36.10 п. 5 named and priced). The floor moving 1 → 2 is what bought the ×1.50, and this is the assertion that keeps it bought |
| П4 | The "give me an easier variation" handle always changes the variation — 400 cells, zero of them staying inside their tier | A handle that answers with the same exercise is a lie on a button. Descending inside a tier is the engine's own job, not the handle's |
| П4b | Time under load after that handle stays inside the accepted ×2.50 | §30.4 says reps are not comparable across a variation change, so the honest gate is the accepted bound of §36.10 п. 1, not zero. Named, not silently tolerated |
| П5a/b | `generateSession` is deterministic, and state survives a JSON round-trip | The fixture, the port and the whole audit apparatus stand on both. A single field that does not survive `JSON.parse` turns golden into a coin toss |
| П6 | `descendNoHarder` never returns a position the engine's own `noHarder` predicate rejects | The 20.08 audit found "descent never adds load" checked on two of six paths, while the other four produced transitions the exported predicate refused. This asserts the predicate against itself |
| П7 | *Informational:* the sum of levels over an honest year, and where `squat` lands | Progress is what a safety wave is most likely to quietly destroy. It is printed, not asserted, because there is no right number — П10 does the asserting |
| П8a/b/c | Against the v2.25 engine, on the axis's zero: the plan is bit-for-bit equal (96 cells), the shared state fields are equal after a session, and the announced duration grew by **exactly** one minute | This is the wave's parity claim, and the reason a refactor can be told from a change. The one minute is §37.7а — the longer run-in before every guided position — and it is asserted as a number so it cannot creep |
| П9 | The sets handle only ever shortens, and stops at the floor | A handle that could lengthen a session, or dig below two sets, is worse than no handle |
| П10 | A year of levels stays within ±1 % of v2.25 across four answering styles | Removing two mechanisms must not cost progress. ±1 % is the tolerance; the run gives ±0.0 % on all four |
| П11 | "Tough" never makes the next shown plan heavier — including on top of an active cut | The composition question. Each mechanism was fine alone in v2.25; the P0s came from the pairs |
| П12 | The wave added no new cell where a growth event lightens the plan — parity with v2.25, not an absolute | Absolute is unreachable and saying otherwise would be a false guarantee: at a band start the per-set dose resets lower while the set count grows (v2.21, deliberately), and across a variation the measure is invalid at all. So the assertion is that the count did not move: 6 before, 6 after, all at L31/L39 |

Two things this table deliberately does not claim. П4b and П12 are bounded by
what v2.25 already accepted, so they detect a *regression*, not a defect that was
already priced. And П8 compares plans, not durations — the duration moved by
design, which is why it gets its own line and its own exact number.

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

| I-14 | 2026-08-23 | Progress | Found by the UI suite, which is **red on `develop`** for this one cause: `testProgressReflectsCompletedWorkout` ("0" is not equal to "12" — the total level after "easy" should be 12) and `ReleaseSmokeTests.testReleaseSmokeEnglish` row S5 ("the history sheet must list the level the workout ended on"). Since v2.22 the first growth steps do not land in the **level** at all — they land in the **sub-step**: one honest "easy" on a fresh install moves all six worked patterns by 2 sub-steps each, and every level stays 0. The Progress screen and the history sheet both read levels, so a person who has just trained and been told the plan will grow is shown a screen that says nothing happened. The tests are not stale markup — they assert the right amount of progress (12 is exactly the sub-step total) against a screen that cannot see it | medium | **open — the screen is the question, not the test.** Verified on `chore/close-v2.25` (develop + docs only), each test run alone: both still fail with the signatures above. Deliberately not fixed inside the closing wave: what Progress should show for a sub-step is a product decision (a fractional level, a second axis, or a different sentence), not a markup change. Backlog: "Прогресс не видит под-ступени" |
| I-15 | 2026-08-24 | Today, Workout flow | Found running §45.10 for the design re-review wave, and **not caused by it — the frames are pixel-identical to the previous release**. At the accessibility Dynamic Type sizes (checked at `accessibility-extra-extra-extra-large` on an iPhone SE) two things on the app's first and busiest screens come apart. On **Today**, the two session handles are drawn on top of each other and on top of the "≈ N min · N exercises" line above them — three sentences in one place, none of them readable. On the **work screen** the column has no `ScrollView`, so once the type outgrows the height the header, the exercise name and the "technique" affordance are simply pushed off the top of the screen; what is left starts mid-number. Neither is a truncation the layout chose — both are content the layout never accounted for | medium | **half closed by removal, half open and now larger.** The Today half is gone with the controls: v2.27 removed both session handles, so there are no long sentences left to overlap the line above them. The work screen half stands, and this wave adds to it — one more line in the header ("≈ N min left") and a third action under the button, on a column that still has no `ScrollView`. The fix is the same layout decision it always was: scroll, or drop the elements the screen can afford to lose. Deliberately not taken inside a §38 diff, for the reason it was not taken inside the accessibility one — a layout decision hidden in a feature wave is a decision nobody reviewed |

**Severity.** *high* — data loss, crash, or a broken core flow · *medium* — a feature misbehaves but there is a way around it · *low* — cosmetic or a rare edge case.
