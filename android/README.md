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
- **Health Connect is write-only**, the same promise HealthKit keeps on iOS.
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
- Health Connect stays write-only here, the same promise HealthKit keeps on
  iOS. So its permissions will not qualify, and
  `HIGH_SAMPLING_RATE_SENSORS` stays the prerequisite.

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
- **Never asked again**, whatever the answer. The mark is a file in
  `noBackupFilesDir`, because a permission belongs to the device.
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
