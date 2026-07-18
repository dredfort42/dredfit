# Dredfit — manual QA checklist

Automated coverage (81 tests: core invariants, golden parity, app units, UI flow) is described in [README.md](README.md#testing). This document covers what a simulator or a device has to be driven by hand to confirm: system integrations, wall-clock behavior, locale passes, and anything that only misbehaves on a real screen.

**How to use.** Run the *Release smoke* block before every release. Run *Full pass* when the engine, persistence or an integration changed. Device-only rows cannot pass on a simulator and are marked ⌚. Record anything that fails in the [Issue registry](#issue-registry) at the bottom rather than fixing it silently.

**Reset between runs.** Delete the app from the simulator (long-press → Remove App) — this clears Application Support, the App Group container, HealthKit authorization and notification permissions in one go. Launching with the `--uitest-reset` argument clears state but *not* system permissions.

Legend: ✅ pass · ❌ fail (log it) · ➖ not applicable this run · ⌚ device only

---

## Release smoke (run every release)

| # | Check | Expected |
|---|---|---|
| S1 | Cold start on a fresh install | Opens on **Today** with "Workout 1", ≈33 min, 6 exercises, a **Start** button |
| S2 | Full workout: Start → warm-up → 6 exercises → rating | Rating screen appears; tapping an option returns to Today in the done state |
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
| 1.2 | Tap **Start** | Full-screen flow opens on **WARM-UP**; the screen does not auto-lock for the whole workout |
| 1.3 | Let the warm-up run | 6 moves × 30 s. At 3-2-1 a tick sound + light haptic; at 0 a lower tone + success haptic; dots advance; total 3 min |
| 1.4 | Tap **Skip warm-up** | The *entire* warm-up block ends (not just the current move) and exercise 1 appears |
| 1.5 | Work screen layout | Header "1 / 6" and 6 capsules; exercise name; **technique** button; big planned number; "reps" (or "reps per side"); set dots; "set 1 of 3" |
| 1.6 | Tap **technique** during work | Sheet opens for the current exercise; it does not swap if the phase changes underneath |
| 1.7 | Tap **Done** on a non-final set | Rest starts at 60 s |
| 1.8 | Rest screen | "REST", a ring counting down from 60, "Next up" + next label, a **technique** button for the *next* exercise, **Skip rest** |
| 1.9 | Complete all sets of all 6 exercises | Flow reaches the rating screen |
| 1.10 | Tap **Exit** mid-workout | Returns to Today; **nothing is recorded** — the session is discarded (there is no confirmation dialog; see [I-1](#issue-registry)) |

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
| 3.2 | Let it finish | 3-2-1 signals, then completion tone; rest begins automatically |
| 3.3 | **Stop the hold early** | The recorded actual is rounded to the **nearest multiple of 5** and clamped to 5…90 s |
| 3.4 | Verify 3.3 on the rating screen | The summary shows "actual N" where N is a multiple of 5 |
| 3.5 | A per-side hold | Two countdowns run; the second is marked "second side"; the recorded actual is the **smaller** of the two sides |
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
| 5.2 | Three options | "Tough, did less" / "On plan" (highlighted) / "Easy, could do more" with captions −1 / +1 / +2 |
| 5.3 | No adjustments made | No summary card is shown |
| 5.4 | With adjustments/skips | "Adjusted" card lists them; footer "Your rating applies to the rest" |
| 5.5 | Tap any option | Submits immediately — the card *is* the button; returns to Today |
| 5.6 | Choose "On plan" and check Progress next session | Each non-skipped pattern rose by exactly 1 level |

### 6. Rest days

| # | Check | Expected |
|---|---|---|
| 6.1 | Settings → **REST DAYS**, default | Sunday only is highlighted; caption "Highlighted days are rest days" |
| 6.2 | Chip order | Starts at the locale's first weekday (Monday for ru, Sunday for en-US) |
| 6.3 | Select a second rest day | Both highlighted; Calendar marks both |
| 6.4 | Try to select a **7th** rest day | Refused — six is the maximum |
| 6.5 | Calendar rendering on a rest day | A plain dimmed number with **no shape** — rest days carry no mark and no legend entry, so they look the same as days outside the month. Confirm this is intended ([I-4](#issue-registry)) |
| 6.6 | **Today** screen on a rest day | Today shows the normal plan — it does **not** render a rest-day state. Confirm this is intended ([I-2](#issue-registry)) |
| 6.7 | Complete a workout, then check the "Next" card | Skips over rest days when naming the next training day ("tomorrow", "on Wednesday") |

### 7. Reminders

| # | Check | Expected |
|---|---|---|
| 7.1 | Enable **Reminder** | iOS permission prompt appears (alert + sound, no badge) |
| 7.2 | Deny the permission | The toggle flips back **off** — it reflects the system's answer |
| 7.3 | Allow, then keep the default rest day | Exactly **6** notifications scheduled (one per non-rest weekday) |
| 7.4 | Change **Time** | Reminders reschedule to the new time |
| 7.5 | Add a rest day while the reminder is on | That weekday's reminder disappears |
| 7.6 | Disable the reminder | All pending reminders are removed |
| 7.7 | ⌚ Wait for a scheduled fire | Notification titled "Dredfit", body "Today's workout is ready" |

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
| 9.5 | Progress tab | A "Vertical pull" chip and level bar appear |
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
| 11.6 | Force-quit the app during a rest | The activity goes stale on its own — no zombie card left on the lock screen |
| 11.7 | Start a second workout right after a first | Exactly one activity is present, not two |

### 12. Home-screen widget

The automated snapshot test (`testWidgetSnapshotMirrorsWeekStatuses`) skips itself whenever there is no App Group container — which is the case for any unsigned test run, including CI. These manual checks are therefore the only real coverage the widget gets.

| # | Check | Expected |
|---|---|---|
| 12.1 | Add the small **Today's status** widget | Renders without a placeholder |
| 12.2 | Before today's workout | "Workout N" with an accent dot |
| 12.3 | After completing today's workout | "Done ✓" — and it updates without opening the app again |
| 12.4 | On a rest day | "Rest day" in muted ink |
| 12.5 | Change rest days in settings | The widget reflects the change |
| 12.6 | Leave the device overnight past midnight | The widget flips to the new day's status **without** the app being launched |

### 13. Date rollover and edge cases

| # | Check | Expected |
|---|---|---|
| 13.1 | Complete a workout, then move the clock past midnight | Today returns to the plan state offering the next workout |
| 13.2 | Cold-start the app on a day already completed | Opens on the **Calendar** tab, not Today |
| 13.3 | Cold-start on a day not yet completed | Opens on **Today** |
| 13.4 | Complete a workout at 23:59, check the calendar at 00:01 | The record sits on the day it was performed |
| 13.5 | Change the device timezone, reopen | No duplicated or missing calendar days |
| 13.6 | Kill the app mid-workout and relaunch | No partial record is written; Today still offers the workout |

### 14. Localization (run the whole Full pass in both locales)

| # | Check | Expected |
|---|---|---|
| 14.1 | Every screen in **English** | No missing keys, no raw identifiers |
| 14.2 | Every screen in **Russian** | Complete translation; exercise names and all technique text translated |
| 14.3 | Russian typography | Uses `е`, never `ё` (a deliberate project convention) |
| 14.4 | Next-training-day label in Russian | Correct preposition: "во вторник", "в среду" |
| 14.5 | Calendar weekday order per locale | Russian starts Monday |
| 14.6 | Notification, widget and Live Activity text | Localized too — not just the main app |
| 14.7 | Long Russian labels | Nothing clipped or truncated mid-word |

### 15. Progress, calendar, history

| # | Check | Expected |
|---|---|---|
| 15.1 | Progress header | Total level, "N workouts", and "This week · N workouts · +D levels" |
| 15.2 | A week containing a deload | The weekly delta honestly shows a **minus** |
| 15.3 | Chart pattern chips | Selecting one plots that pattern only; "All" plots the total |
| 15.4 | History of an on-plan workout | Exercises with planned volumes and no "actual" annotations |
| 15.5 | History of an adjusted workout | "actual N" in accent on the adjusted rows only |
| 15.6 | History footer | "Total level after: N" |
| 15.7 | A very old record with no exercise snapshot | "No details saved for this workout." rather than an empty list or a crash |

### 16. Accessibility and display

| # | Check | Expected |
|---|---|---|
| 16.1 | Dynamic Type at the largest accessibility size | All screens remain usable; nothing overlaps unreadably (known gaps — see [I-3](#issue-registry)) |
| 16.2 | VoiceOver through the workout flow | Every control is reachable and announced meaningfully |
| 16.3 | Dark mode / light mode | Both render correctly |
| 16.4 | Smallest supported device (iPhone SE) | Nothing clipped |
| 16.5 | Reduce Motion enabled | No motion sickness triggers |

---

## Issue registry

Log every failure found while running this plan. Keep entries until they ship fixed.

| ID | Found | Area | Description | Severity | Status |
|---|---|---|---|---|---|
| I-1 | 2026-07-18 | Workout flow | **Exit** during a workout discards the session with no confirmation — an accidental tap loses all progress | medium | open — backlog item 4 |
| I-2 | 2026-07-18 | Today | Today does not render a rest-day state; only the Calendar and widget mark rest days. Product decision or gap — needs a call | low | open — needs owner decision |
| I-3 | 2026-07-18 | Accessibility | Text sizing is hardcoded via `.font(.system(size:))` throughout, so it does not scale with Dynamic Type at all; no `dynamicTypeSize` caps exist | medium | open — scheduled for v1.4 accessibility audit |
| I-4 | 2026-07-18 | Calendar | Rest days render identically to out-of-month days (dimmed number, no shape, no legend entry), so a configured rest day is not actually visible in the grid | low | open — needs owner decision |

**Severity.** *high* — data loss, crash, or a broken core flow · *medium* — a feature misbehaves but there is a way around it · *low* — cosmetic or a rare edge case.
