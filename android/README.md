# android/

The Android port of Dredfit. Empty today except for these notes; the Kotlin
scaffold arrives as its own PR. The layout is fixed here first so the scaffold
has something to match and so the root `.gitignore` already carries the Android
rules (`.gradle/`, `local.properties`, `*.jks`, `*.keystore`) before the first
Gradle file lands.

The Android side lives on `develop` beside `ios/`, never on a long-lived
platform branch: the repo squash-merges, and the one thing tying the two ports
together — `ios/DredfitCore/Tests/DredfitCoreTests/Fixtures/golden.json` — is
on `develop`. A branch that lived for months would fall behind that fixture
silently, which is the defect class the reference chain exists to catch.

## What goes here

```text
android/
├── CLAUDE.md          the guide for agents — gitignored by the root pattern,
│                      like the root CLAUDE.md; picked up when work touches
│                      files under android/
├── settings.gradle.kts, build.gradle.kts, gradle.properties, gradlew
├── gradle/            wrapper + libs.versions.toml (the one version catalog)
├── core/              the Kotlin port of DredfitCore — see core/README.md
├── app/               the Compose app, widgets included — see app/README.md
└── tools/             swift-backup-probe: the iOS app's own persistence code
                       on the command line, writing the fixtures the
                       cross-platform tests compare against
```

Not here, deliberately:

- **No copy of `golden.json`.** `core` reads the Swift package's fixture
  through `../../ios/DredfitCore/Tests/DredfitCoreTests/Fixtures`; the
  manifest guards one file, and a copy is exactly what it must not allow.
- **No `widgets/` module.** Isolating an extension into its own process is an
  iOS constraint; on Android the Glance widget is a receiver inside `app`.
- **No `shared/` module.** The App Group is iOS; the two-week widget snapshot
  is a class in `app`, and the rule that the widget never computes rest days
  itself comes along unchanged.
- **No `res/raw/` for sounds.** The iOS app synthesises its countdown and
  reminder sounds in code and tracks no media file; do the same.
- **No second CHANGELOG, TESTPLAN or glossary.** One of each at the root; the
  Android side gets sections, not files.

## Rules that transfer from `ios/`

- **The judge is `golden.json`, not the Swift port.** The reference is
  `reference/adaptive_engine.js`; where Kotlin and Swift disagree, the fixture
  decides. Otherwise the Kotlin port inherits every defect of the Swift one.
- **The wire format must read iOS JSON**: `[Pattern: Int]` is encoded as an
  unkeyed array, new fields are optional with a default, and the journal
  decodes record by record. Backup export/import is the bridge from iOS to
  Android, and it works only if both sides read the same file.
- **No third-party SDKs, no network calls, no analytics** — the root README's
  promise — with ONE exception the owner approved on 09.10.2026: **Play
  In-App Review** (`com.google.android.play:review`, which brings
  play-services-basement, play-services-tasks and Play core-common with it).
  Why: it is the only way to ask for a Play rating inside the app — the twin
  of iOS's StoreKit `requestReview`, which iOS has from the OS — and the ask
  follows the iOS rule exactly (after a milestone, from the fifth workout,
  never after "hard", at most once in 60 days). It adds no permission: the
  manifest still has no INTERNET, because the card is drawn and sent by the
  Play Store app, not by Dredfit. What a person types there (stars, review)
  goes to Google Play; Google's own data-safety table for the library lists
  it as user-entered rating and review, used to post the review. Nothing
  else from Play Core or Play services is to be added on the strength of
  this exception.
- **Health Connect reads and writes what HealthKit does on iOS**: it writes the
  workout and its energy, and reads weight, height, date of birth, sex,
  resting energy and workouts for the energy estimate (owner decision,
  09.10.2026; it lands with phase 3d).
- **User-facing text follows `instructions/GLOSSARY.md`** in all seven
  languages; `res/values*/strings_*.xml` are generated from the String
  Catalogs by `scripts/export_android_strings.py`, one file per source
  catalog, never edited by hand — so both localization gates cover Android
  without a second source of truth.
- **File names one-to-one with Swift** (`Breaks.swift` ↔ `Breaks.kt`): after
  the port, a diff on the Swift side must point at the Kotlin file without a
  search. That is the maintenance mechanism, as important as the fixture.
- **PRs target `develop`**, Conventional Commits titles, one wave per PR. The
  Android CI job stays non-required until the app ships; when it becomes
  required, filter paths at the job level, not the workflow level — a
  workflow-level `paths:` filter leaves a required check pending on every PR
  that does not touch `android/`, and blocks the merge.

## Where Android departs from iOS: the workout off screen

On iOS a workout lives on screen. The app declares no background mode, so a
locked phone suspends it: no tone, no haptic. The flow is *left*
(`sceneLeft`), and the time away is cut from the duration. What runs on is
the Live Activity's countdown, drawn by the system. Android keeps one thing
more going: a countdown's 3-2-1 still sounds with the phone face down or
another app on top. Everything the workout records stays iOS's (owner
decision, 09.10.2026). Three parts do that
(`app/src/main/kotlin/com/dredfit/`):

- **The ongoing notification** (`ongoing/OngoingNotification.kt`) shows what
  the Live Activity shows. The rules are in `workout/RestLiveActivity.kt`.
  - **Title:** in bold, the exercise, or what the rest leads into.
  - **Detail line:** "Next up", "set 2 of 3", "Paused".
  - **Countdown:** a system chronometer to the end of a rest or a hold, only
    while that end is ahead. A countdown left past its end is redrawn
    without it, because iOS's timer stops at zero and Android's would count
    below it.
  - **Actions:** none, because the iOS tile has none. A tap opens the app on
    the flow.
  - **When it goes:** where the iOS tile goes — on the rating, after Finish
    now, and when the flow closes.
  - **Channel:** importance DEFAULT, with no sound and no vibration. A LOW
    channel counts as "silent", and the system may keep a silent
    notification off the lock screen, where the iOS tile lives.
- **A foreground service of type `health`** carries the notification for
  exactly the life of the tile. Without it, Android caches the process once
  it leaves the screen, and from Android 14 freezes it within seconds.
- **The beat** (`workout/WorkoutBeat.kt`) belongs to the flow, not to the
  screen.
  - **Leaving:** off screen it keeps running only while the notification is
    up. Leaving the screen is still leaving: `sceneLeft` is stamped on every
    stop, and the time away is charged as on iOS.
  - **A countdown that runs out while you are away** waits at its end, with
    no go and no next stage, until you come back. The first tick on return
    reads the real overshoot, which is the tick a resumed iOS app runs. So
    every rule iOS applies to an absence holds here unchanged: a hands-free
    run dropped past 4 s, a guided block frozen, the count-in a late rest
    earns, the time away.
  - **Wake lock:** a partial wake lock is held only while a countdown is
    heading for an end the beat may still reach. Waiting for a tap, or
    waiting at an end with you away, holds nothing.

Swiping the app from Recents does not end the workout: the notification stays
and a tap brings the flow back. On Android 14+ the notification itself can be
swiped away; the service runs on, and the next phase change posts the
notification again.

### Why `health`

The [service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
for targetSdk 34+, weighed:

- **`health`** is the documented type for "long-running use cases to support
  apps in the fitness category such as exercise trackers". It has no time
  limit. It needs `FOREGROUND_SERVICE_HEALTH` plus at least one prerequisite.
- **`specialUse`** is only for uses that no other type covers. Play reviews
  its free-form justification, and an exercise tracker is covered by
  `health`.
- **`shortService`** has a hard cap of about 3 minutes, but a workout runs 20
  to 40.
- **`mediaPlayback`** is "continue audio or video playback". The countdown
  tones are signals, not media.

**`HIGH_SAMPLING_RATE_SENSORS` is declared ONLY as the prerequisite of the
`health` service type. The app reads no sensor, at any rate.** The page lists
two ways to meet the prerequisite:

- declare `HIGH_SAMPLING_RATE_SENSORS`, which is granted at install with no
  prompt;
- hold one runtime permission from this list: `BODY_SENSORS` (API 35 and
  lower), `READ_HEART_RATE`, `READ_SKIN_TEMPERATURE`,
  `READ_OXYGEN_SATURATION`, or `ACTIVITY_RECOGNITION`.

Every runtime permission on that list would ask for data the app never reads.

**Health Connect (phase 3d) will not replace it.** Checked on that page on
09.10.2026:

- The only Health Connect permissions it lists are READ permissions:
  `READ_HEART_RATE`, `READ_SKIN_TEMPERATURE` and `READ_OXYGEN_SATURATION`,
  plus `READ_HEALTH_DATA_IN_BACKGROUND` in the background note.
- No WRITE permission is listed; `WRITE_EXERCISE` appears nowhere on the
  page.
- The types the app will read from Health Connect (weight, height, date of
  birth, sex, resting energy, workouts) are not on that list either. So its
  permissions will not qualify, and `HIGH_SAMPLING_RATE_SENSORS` stays the
  prerequisite.

Play Console: from target 34, every type in use is declared under **Policy >
App content > Foreground service permissions**. For `health` that means
describing the use: the workout's notification while a session is in
progress. Whether the form also wants a demo video was not checked here.

### POST_NOTIFICATIONS (Android 13+)

iOS asks nothing, because a Live Activity needs no permission. Android asks
**once**, as the first workout that draws a tile starts. That is the
[in-context moment](https://developer.android.com/develop/ui/views/notifications/notification-permission)
the notification is for (`ongoing/NotificationAsk.kt`, owner decision
09.10.2026).

- **Not asked:** "Rate the workout" and "Finish now" from Today open on the
  rating, which draws no tile, so they do not use up the one ask.
- **Never asked again** by a workout, whatever the answer. The mark is a
  file in `noBackupFilesDir`, because a permission belongs to the device.
  The reminder's switch is the one other door, and it asks for itself (see
  "The training reminder").
- **The workout never waits for the answer.**
- **A refusal changes only the shade.** The service, the beat and every
  signal run the same, and Android lists the workout in Task Manager instead
  of the drawer (`NotificationDeniedTest`, which also checks that the second
  start asks nothing).

### A workout left running for hours (battery, Doze)

- **The CPU.** The wake lock is held only while a countdown is running
  toward its end (a rest, a hold, a guided block).
  - **How long:** every countdown ends within minutes: a rest is capped at
    twice its plan, and a hold run ends on its summary.
  - **After that:** the flow waits for a tap, or at the countdown's end
    while you are away, and holds nothing. The device suspends and Doze
    applies as usual.
  - **Timeout:** a one-hour timeout on the lock is a backstop, not the
    release.
  - **Play vitals:** Android vitals flags 2 h of
    [partial wake locks](https://developer.android.com/google/play/vitals/excessive-wakelock)
    in 24 h. A workout stays far below that.
- **The service.** It ends at the resume window
  (`WorkoutSessionStore.resumeWindow`, 3 h with no snapshot written), the
  point past which Today no longer offers the workout as the same occasion.
  - **The flow stays:** it keeps its snapshot, and coming back to it still
    works.
  - **When the check runs:** while the CPU sleeps the beat cannot run, so
    the check happens on the device's next wake. That is the moment someone
    could see the notification.
- **Doze and Battery Saver** do not stop a foreground service. Battery Saver
  mutes `USAGE_TOUCH` vibrations whether the app is in front or not.
- **Process death** (low memory, Task Manager's Stop) takes the service, the
  notification and the lock with the process. The service is not sticky. The
  snapshot and Today's "Continue the workout?" bring the workout back, and
  nothing restarts on its own.

## The training reminder

The rule is iOS's (`ReminderScheduler.swift`), ported line for line to
`reminders/ReminderScheduler.kt`:

- **Which days.** A 28-day window of one-shot reminders, one per day the
  rule accepts: not a marked rest weekday, and not a day already trained.
  The weekdays are the marked ones, even before the first workout (no
  `restApplies` here).
- **Which time.** `reminderHour:reminderMinute` on the wall of the
  trainee's zone. A slot already past is left out, today's included.
- **When it is rebuilt.** Whole, on every change: the switch, the time, a
  rest-day toggle, a finished workout (a morning workout takes tonight's
  reminder down), every return to the app, a journal read on the second
  try, and an import. A frozen launch leaves the window alone.
- **The words.** Title "Dredfit", text "Today's workout is ready", the iOS
  catalog keys.
- **The same price as iOS.** Reminders run dry after four weeks without
  opening the app (BACKLOG №8). Android has no cap of 64 pending
  notifications, so it could roll the window on, but the two phones stay
  alike until the owner says otherwise.

### Which alarm

The [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule)
page names `setAndAllowWhileIdle()` for exactly this case: a "user-specified
action that should happen after a specific time (even if system in idle
state)". It is inexact, and it is allowed in Doze. That is what the app uses
(`reminders/SystemNotificationScheduler.kt`).

- **No permission.** No dialog, nothing for Play to review.
- **Never early.** A reminder never fires before its time.
- **Not to the minute.** Android 12+ fires such an alarm "within one hour of
  the supplied trigger time". `dumpsys alarm` shows `window=+1h0m0s0ms` for
  each reminder. On the idle emulator the real alarm posted 69 s after its
  minute (`ReminderTest.theAlarmItselfPostsTheReminder`). iOS's calendar
  trigger fires on the minute, but the iOS app promises a training day, not
  a minute: the caption says "On training days only".
- **Never on the wrong day.** An alarm that comes late across midnight is
  dropped (`ReminderScheduler.stillItsDay`): "Today's workout is ready" at
  00:20 would speak of a day that may be a rest day. The new day has its
  own slot, if it is a training day.

Weighed and left:

- **Exact alarms.** These need `SCHEDULE_EXACT_ALARM`. The permission is
  user-granted ("Alarms & reminders"). It is
  [denied by default](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)
  to fresh installs from Android 14, and it is revocable. Or they need
  `USE_EXACT_ALARM`, which is limited to alarm-clock and calendar apps. The
  page asks for exact alarms "only if a user-facing function in your app
  requires precisely-timed actions".
- **`setWindow`.** Its window is at least 10 minutes from Android 12. It is
  not allowed in Doze, so in deep Doze it waits for a maintenance window,
  which can be hours away.
- **WorkManager.** Work runs when the system batches it, deferred by the
  app's standby bucket. For an app opened every few days that can be hours
  late, and it would add a dependency.

**What an alarm loses, and how it comes back.** An alarm is an instant and
dies with a reboot. An iOS calendar trigger is a wall time that the system
keeps. So `ReminderRescheduleReceiver` rebuilds the window from the store on
four broadcasts:

- `BOOT_COMPLETED`
- `TIME_SET`
- `TIMEZONE_CHANGED` (09:00 moves with the zone, as an iOS trigger does)
- `MY_PACKAGE_REPLACED`

The rebuild is idempotent: it removes every id and adds the window again.
`RECEIVE_BOOT_COMPLETED` is a normal permission, granted at install.

A Force stop in the system settings also clears the alarms. The next open of
the app draws them again.

### The permission

iOS asks on the switch, and so does Android. Turning the reminder on IS the
request (`NotificationAsk.reminderStep`):

- **Already allowed:** the window is drawn.
- **Android 13+, not yet granted, with the activity there to ask from:**
  the system's dialog is shown, whatever the workout's door asked before.
  The answer is read from the phone, not from the dialog's result.
- **Anything else is a refusal:** below 13 with the app's notifications off,
  a reminder channel switched off, or two refusals already given (the
  system then answers without a dialog).

A refusal turns the switch back off. The note under it is iOS's:
"Notifications are off for Dredfit, so the reminder can't be set from here."
Its row, "Open notification settings", opens the app's page of notification
settings (`ACTION_APP_NOTIFICATION_SETTINGS`), its channels included.

- **On iOS** the note shows only when the switch bounces.
- **On Android** the store keeps the refusal (`reminderRefused`, not
  persisted), because an import asks too.

An imported backup keeps `reminderEnabled` as it came (owner decision,
09.10.2026). Then, as on iOS, the import turns the reminder on again, which
asks. A refusal lands in the same note, never in a switch that quietly went
off.

**Android's own restore.** `allowBackup` brings the state file back with
`reminderEnabled` as it was on the old phone. The permission may not come
with it. The first launch on the new device makes the import's re-check
(owner decision, 09.10.2026). That launch is known by a missing mark: a file
in `noBackupFilesDir`, which a backup never carries. A BackupAgent's
`onRestoreFinished` was weighed and left: it runs without the app's
Application, and a custom agent replaces auto backup's own.

A refusal also takes down any window drawn while the flag was on. iOS stops
at the switch, but here the activation draws the window before the check
runs. Alarms left behind would remind with the switch off once
notifications were allowed later.

### The sound and the channel

The tone is iOS's `SignalTone.reminder`: the go's motif, slowed and
softened. It is written once as a 16-bit mono WAV, byte for byte iOS's
`wavFile`, to `files/sounds/dredfit_reminder_v1.wav`. It is never
rewritten. The channel plays it through the FileProvider
(`content://com.dredfit.dredfit.share/sounds/…`), because the system cannot
open a file in the app's private storage by path.

A channel's sound is fixed when the channel is created. Recreating a deleted
id brings its old settings back. So the version is in both names:

- the file, `_v1`;
- the channel, `reminder-v1`.

A new tone ships as `_v2` and `reminder-v2`, and the old channel is deleted
(`ReminderChannel.stale`). If the file cannot be written, the reminder posts
on `reminder-v1-stock` with the system's sound, as iOS falls back to
`.default`. A channel of the current version that already exists is kept,
whichever kind it is (`ReminderChannel.choose`): what the person set on it,
a block included, must not be undone when the file becomes writable.

The channel is named "Reminder" (the iOS key) and carries the iOS caption as
its description. Its importance is DEFAULT: a sound and a place in the shade,
no heads-up. A tap opens Today, closes Settings if it was open, and leaves a
workout in flight where it is.

### Play Console

Nothing to declare for the reminder. It adds no exact-alarm permission. The
only new permission, `RECEIVE_BOOT_COMPLETED`, is a normal one, and
`POST_NOTIFICATIONS` was already declared for the ongoing notification.

## The home-screen widget

iOS's `DredfitWidgets` is ported to Glance (`app/…/widgets/`). The rules are
iOS's: the STORE writes a two-week snapshot after every persisted change, and
the widget only reads it. The widget never computes a rest day.

### Sizes

iOS ships three home-screen families and three lock-screen accessories.

| iOS | Android |
| --- | --- |
| small: kicker, the day's status | 2×2 and up (`TodayFamily.SMALL`, 110×110 dp) |
| medium: kicker, total steps, status, the week strip | 4 columns and ≥ 140 dp tall (`MEDIUM`, 250×140) — the default, 4×2 |
| large: kicker, status, the next plan line, the plan list, the week line | 4×4 and up (`LARGE`, 250×320) |
| accessoryCircular, Rectangular, Inline | none |

- **One widget, not three.** The Android picker offers one entry per
  provider. The widget resizes, and the three layouts are drawn up front
  (`SizeMode.Responsive`). The launcher picks a layout by the size the person
  gives the widget, so a resize needs no app process. The default is the
  medium: at the size a widget is most often given, it shows the most of
  what iOS shows.
- **Breakpoints.** They follow what each layout needs. A 4×3 stays a medium,
  because six plan rows do not fit it.
- **No lock-screen twin.** Android has no accessory families. Android 16's
  lock-screen widgets are the same home-screen widget in a hub the system
  shows while charging or docked
  ([FAQ](https://android-developers.googleblog.com/2025/03/widgets-on-lock-screen-faq.html)).
  A widget is eligible there unless it opts out with `not_keyguard`. This one
  does not opt out and draws nothing twice. A tap there asks for the unlock
  first, because MainActivity is not shown when locked. The accessories'
  own words have no surface here, so they are not ported: the length range
  line (`subline`), the spoken range, the glyph and the inline line.
- **What Glance cannot draw.** Circles and rings are tinted shape drawables.
  The lines iOS shrinks before it truncates are TextViews of our own with
  uniform autosize (`FittedLine`, `res/layout/widget_text_*.xml`): the
  headline, a plan row's name (whose HEAD goes, I-12) and the week line. In
  ru, "Тренировка 3" fits a 2×2 only shrunk.

### The snapshot

`WidgetBridge.kt` builds it from the store, in plain Kotlin: fourteen days
from the Monday of the write week. Each day carries:

- its status (workout, done, rest, unmarked);
- today's session number;
- from today on, for a day that is not a workout, the next training DATE as
  seen from that day.

The plan rows carry a name and the parts of a dose. The words are not baked
in: iOS writes "tomorrow" and "3×12 sec per side" in the app's language at
write time. Here the widget says them in the language it is drawn in, and
the store stays free of a locale. The rest days are still the store's.

**When it is written.**

- At launch, and on the journal's second read.
- After every persisted change except a workout's own snapshots
  (`update(refreshWidget = false)`), which are some 35 a session and change
  nothing the widget shows.
- When the app goes to the background (iOS's `.background`).
- On the broadcasts that move a day: a zone or clock change, a boot, an app
  update (the reminder's `ReminderRescheduleReceiver`).
- Never from a frozen journal.

**Where.** In `noBackupFilesDir`: the file is derived from the state file, and
a restored phone must not show a day that is not its own.

`WidgetCenter.publish` drops a snapshot equal to the last one: most writes (a
plan shown, a setting) change nothing the widget shows.

### Midnight

WidgetKit switches to the next day's entry on its own; Android has nothing
like it. So the snapshot is a timeline (`TodayProvider.entries`), the widget
draws the entry of the day on the wall, and a redraw is booked at the next
local midnight.

- **The alarm.** `setWindow(RTC, …)`: inexact and non-wakeup, with the
  10-minute window Android 12+ grants at least. It wakes nothing. A phone
  asleep at midnight redraws when it next wakes, which is the moment the
  widget can be seen again.
- **When it is booked.** On every draw the system asks for: a placement, a
  boot, an update, the app's own redraw, a new system language (the
  receiver's `onUpdate`). It is unbooked when the last widget goes.
- **A zone or clock change** re-books it on the new wall, through the
  reminder's receiver.
- **Two weeks without the app.** The snapshot runs out and the widget signs
  itself ("Dredfit"), as iOS's `.empty` does.

Weighed and left:

- `updatePeriodMillis`: at least 30 minutes, it wakes the phone, and it
  ignores midnight.
- `ACTION_DATE_CHANGED`: a manifest receiver never hears it, because it is
  not on the list of implicit broadcasts that are exempt.
- `set()`: an inexact alarm booked at noon may come at eight the next morning
  (its window is 75 % of the wait).
- Exact alarms: they need a permission for something no one sees.

### A session outlives its update

Glance keeps a widget's session about 45 s after its first frame and does not
run `provideGlance` again on an update. A write inside that window — the
launch's snapshot, then the decay's — would leave the widget on the first
one. So the session COLLECTS the feed (`WidgetCenter.feed`): the newest
snapshot, the day on the wall and a redraw count. Any change redraws a live
session, and a broadcast redraws the rest.

### Theme, language, tap, preview

- **Theme.** The palette's light and dark columns (`ui/theme`), as day/night
  pairs. From Android 12 the launcher picks by the SYSTEM's mode, never by the
  in-app Appearance. The Settings caption "Widgets and the Lock Screen keep
  following the system." is therefore shown, as on iOS. Increased contrast
  (Android 14+) takes the second column and is read at each draw. On Android
  10–11 Glance resolves day/night itself when it draws: a live process
  redraws on the change (`DredfitApp.onConfigurationChanged`); a dead one
  shows the new mode at the next draw.
- **Language.** The widget's own catalog first, as iOS's extension reads its
  own: "steps" in ru is «ступеней» on the widget and «ступени» in the app.
  A new system language redraws it (LOCALE_CHANGED, Glance's receiver). So
  does a per-app language changed while the process lives, which no
  broadcast announces (`onConfigurationChanged`).
- **Tap.** Opens Today (`MainActivity.ACTION_OPEN_TODAY`, the reminder's
  door). A workout in flight stays on top. iOS sets no `widgetURL`, so its
  tap opens the app wherever it was.
- **Picker preview.**
  - Android 15+: the generated preview is the person's own day, set once
    per process (the system allows about two an hour).
  - Android 12–14: `previewLayout`, a static small on a workout day.
  - Android 10–11: the app icon.

### Battery and permissions

- **No wakeups.** No periodic update, and the midnight alarm is non-wakeup.
- **A redraw only when the snapshot changes,** plus one at midnight. Each
  redraw is one short WorkManager job (Glance's session).
- **Permissions.** None added. Glance brings WorkManager 2.7.1 and DataStore.
  WorkManager declares `ACCESS_NETWORK_STATE` for work that waits on a
  network. Glance's work never does, so the manifest removes it.
