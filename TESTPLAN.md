# Dredfit — manual QA checklist

Automated coverage (284 tests: core invariants, golden parity, app units, UI flow) is described in [README.md](README.md#testing). This document covers what a simulator or a device has to be driven by hand to confirm: system integrations, wall-clock behavior, locale passes, and anything that only misbehaves on a real screen.

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
| S1 | Cold start on a fresh install | Opens on **Today** with "Workout 1", ≈33 min, 6 exercises, a **Start** button with the short-version offer under it |
| S2 | Full workout: Start → warm-up (opens on its "Get ready" transition) → 6 exercises → cool-down → rating | Rating screen appears; tapping an option returns to Today in the done state |
| S3 | Today after completion | Checkmark, "Workout 1 completed", a rating caption, and a **Next** card (no Start button) |
| S4 | Relaunch the app | Still in the done state — the record survived the restart |
| S5 | Calendar tab | Today is filled and tappable; the history sheet lists what was done |
| S6 | Progress tab | Total level > 0, one chart point, per-pattern bars drawn |
| S7 | Switch to Russian and repeat S1–S3 | No English leaks, no clipped labels |

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
| 1.8 | Rest screen | "REST", a ring counting down from 60, "Next up" + next label, a **technique** button for the *next* exercise, **Skip rest** |
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
| 4.2 | Same on a hold exercise | Steps by 5 within 5…90; value shows a trailing "s" |
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
| 5.2 | Three options | "Tough, did less" / "On plan" / "Easy, could do more" — **equal visual weight** (no filled card), captions "next workout eases off" / "the next one asks a little more" / "progress comes twice as fast" |
| 5.3 | No adjustments made | No summary card and no scope chip are shown |
| 5.4 | With adjustments/skips | With skips a scope chip under the title: "Applies to N of M — … stays put" (N excludes skips **and** adjusted exercises). The summary card labels its lists separately: "ADJUSTED" only over adjusted rows, "SKIPPED" only over skipped rows. Skipped rows are dimmed names with **no** per-row word (the header says it once); the one exception is the "Finish now" exercise, whose row reads "not finished" — it differs from the header. VoiceOver still reads every row with its state. The "Your rating applies to the rest" footer appears only when nothing was skipped |
| 5.4a | Second and later workouts | "Last time you chose: <previous rating>" in small print under the cards; absent on the very first workout |
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
| 15.1 | Progress header | Total level, beside it "level" / "N workouts", and "This week · N workouts · +D levels" |
| 15.1a | Header at a four-digit total, in Russian (1.8.0) | The number stays on **one** line — never broken mid-digit ("1 27" / "0"); the caption stays on two lines |
| 15.1b | Header share button | A round icon (the word does not fit beside the number in Russian), centred on the height of the number's line |
| 15.1c | Header at an accessibility type size | The caption drops under the number instead of pushing the row off either edge; the share glyph stays inside its ring |
| 15.2 | A week containing a deload | The weekly delta honestly shows a **minus** |
| 15.3 | Chart projection | Tapping a pattern row tints it and plots that pattern only; the kicker over the chart names the projection ("PUSH — PUSH-UP"); "Show all" resets to the total — no chips row |
| 15.3a | Chart x-axis | Two–three sparse date labels (first / middle / last workout); no label before the second workout |
| 15.3b | Per-pattern bars | One line per pattern: name, bar with white ticks at band boundaries, level. No per-row detail in the all-patterns view |
| 15.3d | Select a pattern (1.8.0) | Only the selected row grows a detail line under it — the current variation and its position ("Push-up · 2/4") on the left, "next in N" (or "+1 set in N" at tier 4, nothing at the ceiling) on the right; the tint covers both lines |
| 15.3e | Back to all patterns | The detail line disappears — from the view hierarchy, not merely off-screen |
| 15.3c | Selecting a pattern, in Russian (1.8.0) | The kicker and the chart under it **do not move**: the title stays on one line (shrinking, then truncating) and "Show all" keeps its place even while hidden |
| 15.4 | History of an on-plan workout | Exercises with planned volumes and no "actual" annotations |
| 15.5 | History of an adjusted workout | "actual N" in accent on the adjusted rows only |
| 15.6 | History footer | "Total level after: N" |
| 15.7 | A very old record with no exercise snapshot | "No details saved for this workout." rather than an empty list or a crash |

### 16. Accessibility and display

| # | Check | Expected |
|---|---|---|
| 16.1 | Dynamic Type at the largest accessibility size | Every screen usable, nothing clipped. The rep counter, rest countdown, total level and completion tick grow to a cap; the rest ring grows with its countdown |
| 16.2 | VoiceOver through the workout flow | Every control is reachable and announced meaningfully |
| 16.3 | Dark mode / light mode | Both render correctly |
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
| 17.6 | Settings → first row → **How it works** | **Eight** numbered sections under "Eight things worth knowing about the regulator."; the numbers agree with the engine (±1/+2, three shortfalls → −3, five of eight rotations) |
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
| 23.4 | Levels 0–7 on any pattern | Identical to 1.4 — 8 to 15 reps, 20 to 55 s |
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
| 29.1 | Today, a training day | Under **Start**, a secondary line: "Short on time? Short version · ≈ N min"; N is noticeably below the full estimate above |
| 29.2 | Tap it | Warm-up as usual, then "1 / 3" and three capsules — the same exercises, same numbers, as the plan above showed |
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

**Severity.** *high* — data loss, crash, or a broken core flow · *medium* — a feature misbehaves but there is a way around it · *low* — cosmetic or a rare edge case.
