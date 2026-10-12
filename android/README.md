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
                       cross-platform tests compare against;
                       build-release.sh: the signed bundle for Google Play
                       ("Releasing" below)
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
- **Health Connect reads and writes what HealthKit does on iOS** (owner
  decision, 09.10.2026): it writes the workout and its active energy, and
  reads weight, resting energy and workouts for the energy estimate. Height,
  date of birth and sex are not read: Health Connect has no record for the
  last two, and without an age the height cannot change the estimate. The
  `connect-client` library is Google's AndroidX; it brings Guava and a
  protobuf runtime, and no permission, no network ("Health Connect" below).
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

**Health Connect does not replace it.** Checked on that page on
09.10.2026:

- The only Health Connect permissions it lists are READ permissions:
  `READ_HEART_RATE`, `READ_SKIN_TEMPERATURE` and `READ_OXYGEN_SATURATION`,
  plus `READ_HEALTH_DATA_IN_BACKGROUND` in the background note.
- No WRITE permission is listed; `WRITE_EXERCISE` appears nowhere on the
  page.
- The types the app reads from Health Connect (weight, resting energy,
  workouts — see "Health Connect" below) are not on that list either. So its
  permissions do not qualify, and `HIGH_SAMPLING_RATE_SENSORS` stays the
  prerequisite.

Play Console: from target 34, every type in use is declared under **Policy >
App content > Foreground service permissions**. For `health` that means
describing the use: the workout's notification while a session is in
progress. The form also asks, per type, for a link to a video of the feature
being started in the app (Play Console Help, "Understanding foreground service
and full-screen intent requirements", read 11.10.2026); the answers and what to
film are drafted in `store/playstore/policy.md`.

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

Two alarms, both allowed in Doze (`reminders/SystemNotificationScheduler.kt`,
the rule in `reminders/ExactAlarm.kt`, owner decision 12.10.2026):

- **Exact, where the phone allows it.** `setExactAndAllowWhileIdle()`, on
  the minute. Android 10–11 allow it to every app. Android 12+ allow it while
  "Alarms & reminders" (`SCHEDULE_EXACT_ALARM`) is on for Dredfit: granted at
  install on 12–13,
  [off for a fresh install](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)
  from 14, and revocable on every version.
- **Inexact, otherwise.** `setAndAllowWhileIdle()`, which the
  [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule)
  page names for a "user-specified action that should happen after a specific
  time (even if system in idle state)". It never fires early, but Android 12+
  fires it "within one hour of the supplied trigger time": `dumpsys alarm`
  shows `window=+1h0m0s0ms`. On the idle emulator it posted 69 s after its
  minute (`ReminderTest.theAlarmItselfPostsTheReminder`), but on the owner's
  Galaxy A16 (Android 16), unfrozen and exempt from battery optimisation, a
  14:00 reminder posted at 15:00:00.4, the very end of its window
  (12.10.2026). That hour is why the exact alarm exists.
- **The hint.** While the reminder is on and its alarm would be the inexact
  one, Settings says under it: "To have the reminder arrive on time rather
  than up to an hour late, allow Dredfit to set alarms and reminders." The
  row under it, "Allow alarms and reminders", opens that permission's page
  for Dredfit (`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`). The hint is read again
  on every resume, so it goes on the return once the switch is on.
- **The switch, either way.** Turned on, the system sends
  `SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`, and the rebuild receiver
  below draws the window again with exact alarms — no return to the app
  needed (`ReminderExactAlarmTest`). Turned off, the system stops the app and
  cancels its exact alarms (seen on the API 37 emulator: the process died on
  the revocation); the next open draws the inexact window. Until that open
  there is no reminder.
- **Never on the wrong day.** An alarm that comes late across midnight is
  dropped (`ReminderScheduler.stillItsDay`): "Today's workout is ready" at
  00:20 would speak of a day that may be a rest day. The new day has its
  own slot, if it is a training day.

Weighed and left:

- **`USE_EXACT_ALARM`.** Exact with no person's yes, but limited to
  alarm-clock and calendar apps.
- **`setWindow`.** Its window is at least 10 minutes from Android 12. It is
  not allowed in Doze, so in deep Doze it waits for a maintenance window,
  which can be hours away.
- **WorkManager.** Work runs when the system batches it, deferred by the
  app's standby bucket. For an app opened every few days that can be hours
  late, and it would add a dependency.

**What an alarm loses, and how it comes back.** An alarm is an instant and
dies with a reboot. An iOS calendar trigger is a wall time that the system
keeps. So `ReminderRescheduleReceiver` rebuilds the window from the store on
five broadcasts:

- `BOOT_COMPLETED`
- `TIME_SET`
- `TIMEZONE_CHANGED` (09:00 moves with the zone, as an iOS trigger does)
- `MY_PACKAGE_REPLACED`
- `SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` (the window turns exact)

The rebuild is idempotent: it removes every id and adds the window again.
`RECEIVE_BOOT_COMPLETED` is a normal permission, granted at install.

A Force stop in the system settings also clears the alarms. The next open of
the app draws them again.

### Samsung holds the reminder back

Checked on the owner's Galaxy A16 (SM-A165F, Android 16) on 10.10.2026:

- **The app is frozen.** About two minutes after Dredfit leaves the screen,
  Samsung's app freezer (Freecess) freezes it. Logcat:
  `FreecessController: FZ : com.dredfit.dredfit … reason: LEV` (the
  package before it became `app.dredfit`).
- **The alarm waits for the screen.** The reminder's alarm is then deferred
  ("Deferring alarm … due to freecess"). It is sent only when the screen is
  woken (`UFZ … CancelPolicy`, "Sending alarms blocked by MARsFreecess"). A
  19:25 reminder arrived at 19:35, the moment the screen was turned on.
- **Unrestricted fixes it.** With Dredfit set to "Unrestricted" in its
  battery settings, `dumpsys deviceidle whitelist` lists
  `User,com.dredfit.dredfit`. Nothing was frozen, and a 19:48 reminder fired
  at 19:53 with the screen off.

So Settings shows a line under the reminder (owner decision, 10.10.2026):
"So the reminder arrives on its own, without waiting for you to pick up the
phone, let Dredfit run without battery restrictions." It promises the
reminder without the screen, not the minute: the minute is the exact
alarm's (above).
A row under it, "Open phone settings", leads to the place to
change it. Both show only when all three hold (`reminders/BatteryHint.kt`):

- the reminder is on;
- `PowerManager.isIgnoringBatteryOptimizations` is false for the app;
- `Build.MANUFACTURER` is Samsung.

How the hint behaves:

- **Not on stock Android.** Doze lets `setAndAllowWhileIdle` through (above),
  so a Pixel shows nothing.
- **No other make, yet.** [dontkillmyapp.com](https://dontkillmyapp.com/)
  ranks Huawei, Xiaomi and OnePlus worse than Samsung, and OPPO, vivo and
  realme lower down. No phone of theirs was checked. Their own switches may
  not be what `isIgnoringBatteryOptimizations` reads: Xiaomi's page there
  names Autostart, the app's battery saver and a lock in Recents. On such a
  phone the hint could stay after the person did what it asks. Each make
  waits for a phone of that make.
- **Samsung below Android 16 is not checked.** The app runs from Android 10.
  Whether an older One UI's battery page sets the same exemption was not
  checked.
- **Where the row goes.** `ACTION_APPLICATION_DETAILS_SETTINGS` opens the
  app's own page in the phone's settings. On the A16 that page's Battery row
  holds Unrestricted. On the API 37 emulator the page opens, and its "App
  battery usage" row leads to "Allow background usage". No public intent
  opens the battery row itself.
  - `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` asks in a dialog, but Play
    restricts it, and it is not used.
  - `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` opens a list of every app
    on the phone (API 37 emulator), Dredfit to be found in it. It is only the
    fallback.
  - **Not checked on a Samsung:** that the intent lands on that page under
    One UI on Android 16. The owner found the setting there by hand.
- **When it goes.** Settings reads the exemption again on every resume. A
  person who comes back from the phone's settings with Unrestricted set no
  longer sees the line (`ReminderBatteryHintTest`).

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
(`content://app.dredfit.share/sounds/…`), because the system cannot
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

The reminder adds two permissions. `RECEIVE_BOOT_COMPLETED` is a normal
one. `SCHEDULE_EXACT_ALARM` is special access the person grants; whether the
Console asks for a declaration for it was not checked
(`store/playstore/policy.md`). `POST_NOTIFICATIONS` was already declared for
the ongoing notification.

The battery hint adds nothing either: it reads the exemption and opens a
settings page, and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is not declared.

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
| large: kicker, status, the next plan line, the plan list, the week line | 4×4 and up (`LARGE`, 250×340) |
| accessoryCircular, Rectangular, Inline | none |

- **One widget, not three.** The Android picker offers one entry per
  provider. The widget resizes, and the three layouts are drawn up front
  (`SizeMode.Responsive`). The launcher picks a layout by the size the person
  gives the widget, so a resize needs no app process. The default is the
  medium: at the size a widget is most often given, it shows the most of
  what iOS shows.
- **Breakpoints.** They follow what each layout needs. The large's six plan
  rows, headline and week line take about 312 dp at the default font size;
  the threshold leaves room for a larger one. Text is in sp, so it follows
  the person's font size, where iOS's home-screen sizes are fixed points: at
  the largest font sizes the last row can be cut.
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
a restored phone must not show a day that is not its own. It is synced
before the rename, as the state file is.

`WidgetCenter.publish` drops a snapshot equal to the last one: most writes (a
plan shown, a setting) change nothing the widget shows. A fresh process's
first snapshot is compared with the file, so a cold start redraws nothing
that is already on the home screen.

**No widget service.** TV, Automotive and some ARC builds lack
`android.software.app_widgets`, and `AppWidgetManager.getInstance` returns
null there. Nothing is written or drawn, as iOS degrades on a nil App Group
URL.

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
  (Android 14+) takes the second column; it is read at each draw, and a
  change redraws the widget while the process lives (it is not a
  configuration change, so DredfitApp listens for it). On Android
  10–11 Glance resolves day/night itself when it draws: a live process
  redraws on the change (`DredfitApp.onConfigurationChanged`); a dead one
  shows the new mode at the next draw.
- **Language.** The widget's own catalog first, as iOS's extension reads its
  own: "steps" in ru is «ступеней» on the widget and «ступени» in the app.
  A new system language redraws it (LOCALE_CHANGED, Glance's receiver). So
  does a per-app language changed while the process lives, which no
  broadcast announces (`onConfigurationChanged`).
- **Tap.** Opens the app as it was left, as on iOS, whose widget sets no
  `widgetURL` (owner decision, 11.10.2026): a workout in flight stays in
  front, Settings stays open. Glance gives every click intent a unique data
  URI, and an intent unlike the task's root intent stacks a second
  MainActivity instead of bringing the task back. So the tap starts
  `OpenAppActivity`: invisible, in no task of the app's. It moves the app's
  existing task to the front as it stands, whatever started that task (the
  launcher, a reminder). With no task, it launches the app as the icon does.
- **Picker preview.**
  - Android 15+: the generated preview is the person's own day, set once
    per process (the system allows about two an hour).
  - Android 10–14, and 15+ before the app has set one: `previewImage`
    (`res/drawable-nodpi/widget_preview_image.png`, 919×447, 21 KB). It
    shows the medium on a neutral week, light, in English (owner decision,
    11.10.2026). There is no `previewLayout`, because from Android 12 it
    would win over the image.

### Battery and permissions

- **No wakeups.** No periodic update, and the midnight alarm is non-wakeup.
- **A redraw only when the snapshot changes,** plus one at midnight. Each
  redraw is one short WorkManager job (Glance's session).
- **WorkManager starts on demand.** Glance runs its sessions on WorkManager
  2.7.1. Its startup initializer would open its database in every process,
  including for the many who never place the widget. The manifest removes
  the initializer, and DredfitApp is its `Configuration.Provider`.
- **Permissions.** None added. WorkManager declares `ACCESS_NETWORK_STATE`
  for work that waits on a network. Glance's work never does, so the
  manifest removes it.

## Health Connect

iOS's Apple Health integration (`HealthStore.swift`, `HealthExporter.swift`,
`EnergyEstimate.swift`, `AppStore+Health.swift`, the Settings group) is ported
to Health Connect (`app/…/health/`, `store/AppStoreHealth.kt`,
`workout/EnergyEstimate.kt`, `ui/settings/SettingsHealthSection.kt`). The rules
are iOS's: the switch follows the workout permission, a record is flagged
exported only after Health Connect confirms the save, the backfill runs in
journal order and stops at the first failure, the weight follows the later
statement, and a calorie is left out rather than guessed.

### What is written and read

| iOS (HealthKit) | Android (Health Connect) | Permission |
| --- | --- | --- |
| `HKWorkout`, `.functionalStrengthTraining`, device `.local()` | `ExerciseSessionRecord`, `EXERCISE_TYPE_CALISTHENICS`, recording method "actively recorded", device phone + make + model | `WRITE_EXERCISE` |
| `activeEnergyBurned` sample over the workout | `ActiveCaloriesBurnedRecord` over the same interval (no `TotalCaloriesBurnedRecord`: iOS writes active energy only) | `WRITE_ACTIVE_CALORIES_BURNED` |
| `HKMetadataKeyExternalUUID` = journal id | `clientRecordId` = journal id, on both records | — |
| `HKMetadataKeyAlgorithmVersion` = model revision | the calories' `clientRecordVersion` = model revision (the session's is 0) | — |
| read `bodyMass` (newest sample) | read `WeightRecord` (newest by time) | `READ_WEIGHT` |
| read `basalEnergyBurned` (sum over the interval) | `BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL` over the interval — only when a rate was recorded at or before its end | `READ_BASAL_METABOLIC_RATE` |
| read workouts of other apps (bundle id ≠ ours) | `ExerciseSessionRecord`s whose `dataOrigin` package ≠ ours | `READ_EXERCISE` |
| read `height`, `dateOfBirth`, `biologicalSex` | not read | — |

**Why calisthenics.** HealthKit has no calisthenics type; Apple's
`functionalStrengthTraining` is the one it defines for free weights and body
weight. Health Connect has both, and its own table of exercise names
(`ExerciseSessionRecord.EXERCISE_TYPE_STRING_TO_INT_MAP`, connect-client
1.1.0) files squat, lunge, plank, crunch and burpee under `CALISTHENICS` and
keeps `STRENGTH_TRAINING` for barbells, dumbbells and machines.

**Height, date of birth, sex.** Health Connect has no date-of-birth and no sex
record. iOS treats a missing one as absent and adds no field for it: the
resting ladder's middle rung (Mifflin–St Jeor) needs the height AND the age,
and an absent sex takes the mean of the two equations. Without an age that
rung can never be reached, so the height could not change a single number —
and asking for a permission whose data cannot change a number is what Play's
Health Connect declaration exists to refuse. The ladder on Android is
therefore: a recorded resting rate, else one standard MET
(`aPartialProfileDoesNotReachTheFormula` is every Android phone).

**Resting energy that nobody recorded.** With no `BasalMetabolicRateRecord`
anywhere, Health Connect's `BASAL_CALORIES_TOTAL` still answers — 1534.5
kcal/day with no weight either, a figure worked out from the newest weight
otherwise (API 37) — and names no app in either case, with or without a real
rate. A figure nobody recorded is not this person's resting energy: the app
reads the total only when a rate was recorded at or before the interval's end
(`restingEnergyIsReadOnlyWhereARateWasRecorded`).

**One record per workout.** iOS looks its own workout up by its external id
before saving. Health Connect does it in the write: a record with the same
`clientRecordId` replaces the one there when its `clientRecordVersion` is the
same or higher, and is ignored when lower (probed on API 37). So the export
re-saves a record whose flag was lost and never adds a copy. The session and
its calories go in ONE `insertRecords` call — one transaction — and the
calories ride only when their write is granted, or the session would fail with
them.

**Other apps' workouts.** HealthKit's predicate finds every workout that
overlaps a window; Health Connect's time filter matches a session by its START
(API 37: a session begun before the window and ending inside it is not
returned). The sweep reads sessions that began up to a day before the export's
window and decides the overlap itself; our own are filtered out by package, or
the first export would switch its own calories off forever.

**Reads Health Connect limits.** Without `READ_HEALTH_DATA_HISTORY` an app
reads other apps' data only from 30 days before it was first granted a
permission — older records are left out of the answer, without an error
(probed on API 37; Health Connect's screen says so). Not requested: a weigh-in
older than that is not adopted (the field stays as it was), and a backfill of
older workouts cannot see another app's recording of them (calories written,
as on iOS when the workout read is refused). Google's guide allows reads in
the foreground; the export starts on screen, from the rating. A read that
fails (the app left for the background mid-backfill — not probed here) leaves
that run with what it has, as a refused read does on iOS: the stored weight,
the standard resting rate, no other app's workout to check against.

### Availability, permission, the policy link

- **Android 14+** has Health Connect in the system. A work profile or a device
  without the service is `SDK_UNAVAILABLE`: the Settings group is not shown at
  all, as Google's guidance for that status asks. (The library checks for a
  work profile only from 14; on 10–13 a work profile reads as "install".)
- **Android 10–13** need the Health Connect app. Without it (or with one too
  old) the status is `SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED`: the group
  shows "Install Health Connect" / "Update Health Connect", which opens its
  Google Play page (`market://details?id=com.google.android.apps.healthdata&url=healthconnect%3A%2F%2Fonboarding`,
  the web page without a Play Store), and the status is read again on every
  return to Settings. The manifest's `<queries>` lets Android 11–13 see the
  app at all.
- **The switch** asks for the five permissions through
  `PermissionController.createRequestPermissionResultContract()`, registered by
  MainActivity as the reminder's question is; the answer is read from Health
  Connect afterwards, and only `WRITE_EXERCISE` decides the switch. Each other
  type may be refused on its own and costs only its feature, as iOS's per-type
  answers do (`HealthDeniedTest` step 4: the workout saved, its calories not).
- **Re-checked, never asked**: on every return to the app (iOS's activation)
  and after an import — so also after Android's own restore onto a new phone,
  whose first launch is such a return. A write taken back in Health Connect
  turns the switch off; a Health Connect that cannot answer (IPC to another
  app on 10–13) leaves it on. Revoking a Health Connect permission kills the
  app's process on API 37, so the next launch is where that is seen.
- **The past is offered once**, after a grant, as on iOS — and the question
  is held by the store (`healthBackfillOffered`), not the screen: a Settings
  rebuilt or closed while Health Connect's screen was up must still ask, or
  the next workout would write the whole history unasked. The back gesture
  answers "Only new ones", the choice that writes nothing.
- **Two marks, one per store** (owner decision, 11.10.2026). A record's
  `healthExported` is APPLE Health's, written by an iPhone; Android reads it
  for nothing and passes it — and `healthExportedThrough` — through
  untouched, so a backup that goes back to an iPhone still says what Apple
  Health holds. Android's own mark is the record's optional
  `healthConnectExported` (written or declined here). An iPhone's backup
  therefore arrives with every workout unwritten for Health Connect and
  offered like any other. A field on the record, not a file of ids in
  `noBackupFilesDir`, because the mark must travel with the journal it
  describes: Android's own restore brings it back, so "Only new ones" stays
  answered on the next phone and nothing is offered twice, and an Android
  backup's marks are believed as iOS believes its own. Through an iPhone
  the key is lost — Swift reads past a key it does not know and leaves it
  out when it writes the file again (swift-backup-probe `roundtrip`,
  11.10.2026) — so another phone offers those workouts again and writes
  them under the same `clientRecordId`s: a replace, not a copy. The phone
  that wrote them keeps its marks through the import (same journal, same
  ids).
- **The privacy-policy link** on Health Connect's permission screen opens
  `HealthPrivacyActivity` — the `ACTION_SHOW_PERMISSIONS_RATIONALE` filter
  (Android 10–13) and the `VIEW_PERMISSION_USAGE` alias (Android 14+). It
  opens dredfit.com/privacy.html (the site's page in the app's language) in
  the browser: the app holds no INTERNET permission, so no WebView could load
  it, and a copy of a legal text in the app would drift. Without the alias,
  API 37 never shows the permission screen at all (HealthDeniedTest red).

### What the library brings

`androidx.health.connect:connect-client` 1.1.0 (Google Maven's newest stable
on 11.10.2026) brings Guava, its own protobuf runtime and
`kotlinx-coroutines-android`, and merges one component into the manifest: the
exported `HealthDataSdkService`, which the Health Connect app on Android
10–13 binds to (it accepts only that caller). It adds no permission; the
merged release manifest has no INTERNET and exactly the five Health Connect
permissions plus the `<queries>` entry.

### Play Console for Health Connect

- **Health Connect declaration** (Policy > App content > Health apps / Health
  Connect): `WRITE_EXERCISE` and `WRITE_ACTIVE_CALORIES_BURNED` — finished
  workouts and their estimated active calories written to Health Connect;
  `READ_WEIGHT` — the body weight the calorie estimate is multiplied by;
  `READ_BASAL_METABOLIC_RATE` — the resting energy subtracted from it;
  `READ_EXERCISE` — another app's recording of the same session, so its
  calories are not counted twice.
- **Data safety**: health and fitness data is read and written on the device
  only; the app transmits nothing (no INTERNET permission), so nothing is
  "collected" or "shared" in the form's sense. Android's own Auto Backup of
  the state file is the system's upload, a judgment call written out in
  `store/playstore/policy.md`.
- **Privacy policy**: Google requires the policy the Console lists to be the
  one the link shows, and to cover Health Connect data. dredfit.com's policy
  has a Health Connect section (`privacy.html#health-connect`) from
  11.10.2026, but GitHub Pages serves main's `docs/`: the text is live only
  once it reaches main. `store/playstore/policy.md` drafts every Console
  answer.

## Releasing

The procedure — branch, Play Console, tag — is in
[`.github/WORKFLOWS.md`](../.github/WORKFLOWS.md) ("Android release"). This
section is the build: version, key, shrinking.

### Version

Both numbers live in `android/gradle.properties`, nowhere else;
`app/build.gradle.kts` reads them and `scripts/check_version.py --android`
checks them (`build-release.sh` runs it before it asks for the key).

- **`dredfit.versionName`** is the product version, the x.y.z of iOS's
  `MARKETING_VERSION` in the same tree (owner decision, 11.10.2026): one
  product, one number in both stores, one CHANGELOG. An Android-only fix
  keeps it and takes the next versionCode — 2.5.0 build 2. An iOS release
  only notes an Android version that differs; it never fails on one.
- **`dredfit.versionCode`** is Google Play's counter, +1 for every bundle
  uploaded, whatever the track. A plain counter, like iOS's build number but
  its own (Xcode Cloud counts that one): Play refuses a code it has already
  seen, so every upload spends one, a replaced internal build included. A
  code derived from the version (2.5.0 → 20500) has no room for 2.5.0 build
  2, and caps each part at 99. `check_version.py --android` fails a code that
  is not above every code a tag already carries.
- **The tag** is `android-vX.Y.Z+CODE` — `android-v2.5.0+1`: the build as
  semver build metadata, which is what it is (a `-b1` suffix would read as a
  pre-release of 2.5.0). The check reads the codes from the tag names, of
  every version, not only older ones.

### Signing

The upload key is `~/keys/dredfit-release.jks` (PKCS12, alias `dredfit`). Its
password is in the macOS Keychain only (generic password, service
`dredfit-release-keystore`). A bundle uploaded to Play goes through Play App
Signing: Play re-signs what it delivers with the app-signing key chosen at
the first upload, and this key only proves the uploads are ours.

```sh
android/tools/build-release.sh
```

The script, run by the owner on his Mac:

1. refuses to run traced (`bash -x` would print the password), with
   uncommitted changes under `android/` — the tag must name what was built —
   and on anything but `origin/main` after a fetch: a squash merge discards
   a branch's own commits, and the tag must name one that stays;
2. runs `check_version.py --android` (the fetch brought every tag it
   compares the code with);
3. checks the alias without the password (a PKCS12 store lists its aliases;
   `keytool -list -v -keystore ~/keys/dredfit-release.jks </dev/null` shows
   them), then asks the Keychain for the password — macOS shows its own
   prompt;
4. builds `:app:bundleRelease` with the password in the environment of that
   one build: never echoed, never in a file, never on a command line `ps`
   shows. No Gradle daemon (it would keep the variable for hours), no
   configuration cache (it would store the signing config under
   `android/.gradle`), the Kotlin compiler in-process (its daemon outlives
   the build). Stopped (Ctrl-C, a TERM), it stops the Gradle client and
   deletes the bundle, as it does on any failure before the check below:
   nothing signed and unchecked is left to upload;
5. checks the bundle: `jarsigner -verify` (a bundle is JAR-signed; `apksigner`
   reads APKs only), and the certificate in the bundle against the key's;
6. prints the bundle's path, the version, the commit and the tag to give it,
   and the upload certificate's SHA-256, to compare with Play Console.

`DREDFIT_UPLOAD_KEYSTORE` and `DREDFIT_UPLOAD_KEY_ALIAS` override the path and
the alias. Without them `app/build.gradle.kts` defines no signing config, and
the release build is unsigned — CI's, and every other machine's.

**One trace of the password does reach the disk.** AGP feeds the store
password to its signing tasks as an input in the form of an unsalted SHA-256
(`SigningConfigDataProvider.storePasswordHash`, Guava's
`hashUnencodedChars`), and Gradle's up-to-date check keeps that input in
`android/.gradle/<gradle version>/executionHistory/executionHistory.bin`
(found there for the throwaway key, 11.10.2026). It is left there: the
upload key's password is random and kept only in the Keychain, and a SHA-256
of such a string cannot be walked back; deleting the history after every
release would only make the next build start cold. Were the password ever a
guessable one, delete that directory after the build.

Proved with a throwaway key and a stand-in for `security` (11.10.2026): the
bundle verified and carried the throwaway certificate; while the build ran,
only the Gradle client, its single-use daemon and aapt2 held the variable,
and nothing did after it — nor after a TERM mid-build, which left no bundle;
the password itself was in neither `android/.gradle` nor `app/build`. A
traced run, a dirty tree, a branch that is not `origin/main`, a wrong alias,
a Keychain that refuses and a wrong password each stop before Gradle starts.

### Shrinking (R8)

The release build is minified and its resources shrunk:

| | bundle | download (bundletool `get-size total`) |
| --- | --- | --- |
| without R8 | 12.5 MB | 11.8 MB |
| with R8 | 6.6 MB, over half of it the mapping (3.7 MB) | 2.25–2.30 MB, any ABI, API 29+ |

- **Why it is safe here.** The app reflects on none of its own classes: JSON
  is read through the tree, never by generated serializers, and strings by
  their R ids (`l10n/`). The libraries that reflect ship keep rules — Health
  Connect's protos, Glance, WorkManager, Room, Play services' basement (the
  merged list: `app/build/outputs/mapping/release/configuration.txt`).
- **Two of those rules predate R8's full mode** (AGP's default since 8.0),
  which no longer keeps a kept class's no-argument constructor.
  WorkManager 2.7.1 and its Room 2.2.5 create their database and input
  merger by reflection, so the first shrunk build never drew the widget
  ("Failed to create an instance of androidx.work.impl.WorkDatabase").
  `app/proguard-rules.pro` keeps those constructors.
- **The mapping rides in the bundle**
  (`BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map`), so
  Play Console can deobfuscate crash reports without a separate upload.
- **Baseline profiles.** The libraries' profiles (Compose and others) are
  merged into the bundle (`BUNDLE-METADATA/com.android.tools.build.profiles`).
  An app profile of its own would need a Macrobenchmark module and a device
  run; there is none yet.

**The smoke** (11.10.2026, API 37 emulator): the throwaway-signed bundle,
installed through bundletool's split APKs as Play installs them,
non-debuggable, showed "Dredfit 2.5.0 (1)" in Settings and passed:
onboarding; a whole workout — the warm-up's countdown, then skipped; every
set; the rests (one run out: its 3-2-1 and go vibrated, the others
skipped); the cool-down skipped — under the `health` foreground service with
its notification and wake lock; the rating; the
state through a force stop; history, Progress, Calendar, the share sheet;
the reminder asked for, scheduled, and posted on its own channel and sound
after a clock move; Health Connect asked for, then the workout and its
calories written; export and import of a six-workout backup; the widget
placed, drawn and tapped. Logcat showed no error from the app after the fix
above. Not covered: Play In-App Review (it needs a milestone from the fifth
workout and an install from Play — internal testing is the first place it
can be seen); the Health Connect app of Android 10–13, a separate app the
client binds to, where the system service of 14+ answered here (no shrunk
build has run below API 37); the per-app language; the ongoing
notification's tap.
