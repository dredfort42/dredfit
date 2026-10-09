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
locked phone suspends it: no tone, no haptic, the flow is *left*
(`sceneLeft`) and the time away is cut from the duration. What runs on is the
Live Activity's countdown, drawn by the system. Android keeps the workout
itself going instead, so the 3-2-1 of a rest still sounds with the phone face
down or another app on top. Three parts do that
(`app/src/main/kotlin/com/dredfit/`):

- **The ongoing notification** (`ongoing/OngoingNotification.kt`) shows what
  the Live Activity shows (`workout/RestLiveActivity.kt` holds the rules). The
  bold title is the exercise, or what the rest leads into. The small line is
  the detail ("Next up", "set 2 of 3", "Paused"). A system chronometer counts
  down to the end of a rest or a hold, and only while that end is in the
  future. It has no actions, because the iOS tile has none. A tap opens the
  app on the flow. The notification goes away where the iOS tile does: on the
  rating, after Finish now, and when the flow closes.
- **A foreground service of type `health`** carries the notification for
  exactly the life of the tile. Without it, Android caches the process once it
  leaves the screen, and from Android 14 freezes it within seconds.
- **The beat** (`workout/WorkoutBeat.kt`) belongs to the flow, not to the
  screen. It runs while the flow is on screen OR the notification holds it.
  Only losing both counts as leaving, and only then is the absence stamped as
  on iOS. A partial wake lock is held only while a countdown runs. Waiting for
  a tap holds nothing, because a tap only comes with the screen on.

### Why `health`

The [service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
for targetSdk 34+, weighed:

- **`health`** — the documented type for "long-running use cases to support
  apps in the fitness category such as exercise trackers". It needs
  `FOREGROUND_SERVICE_HEALTH` plus one runtime prerequisite. Of the listed
  prerequisites, `HIGH_SAMPLING_RATE_SENSORS` is the one granted at install
  with no prompt. The others are `ACTIVITY_RECOGNITION`, `BODY_SENSORS`
  and `READ_HEART_RATE`, each a runtime prompt for data the app never reads.
  The app reads no sensor. The service always starts from the activity, in
  front, so the while-in-use limits on the sensor permissions never apply
  here. Health has no time limit.
- **`specialUse`** is only for uses that no other type covers. Play reviews
  its free-form justification, and an exercise tracker is covered by
  `health`.
- **`shortService`** has a hard cap of about 3 minutes, but a workout runs 20
  to 40.
- **`mediaPlayback`** is "continue audio or video playback". The countdown
  tones are signals, not media, and the declaration would not survive review.

Play Console: from target 34, every type in use is declared under **Policy >
App content > Foreground service permissions**. For `health` that means
describing the use: the workout's notification while a session is in
progress. Whether the form also wants a demo video was not checked here.

### POST_NOTIFICATIONS (Android 13+)

iOS asks nothing, because a Live Activity needs no permission. Android asks
when a workout starts, which is the
[in-context moment](https://developer.android.com/develop/ui/views/notifications/notification-permission)
the notification is for. The workout never waits for the answer. If the user
refuses, only the shade changes. The service, the beat and every signal run
the same (`NotificationDeniedTest`), and Android lists the workout in Task
Manager instead of the drawer. Android caps the asking itself: after a
second "Don't allow" a runtime permission's dialog no longer shows.

### A workout left running for hours (battery, Doze)

- **The CPU.** The wake lock is held only while a countdown runs (a rest, a
  hold, a guided block). Every countdown ends within minutes: a rest is
  capped at twice its plan, and a hold run ends on its summary. The flow then
  waits for a tap and holds nothing, so the device suspends and Doze applies
  as usual. A one-hour timeout on the lock is a backstop, not the release.
  Android vitals flags 2 h of
  [partial wake locks](https://developer.android.com/google/play/vitals/excessive-wakelock)
  in 24 h. A workout stays far below that because the lock is released
  between countdowns.
- **The service.** The service ends by the settlement's own rule
  (`settleAbandonedWorkout`). Once 12 hours have passed with no snapshot
  written (`WorkoutSessionStore.isForgotten`), the beat ends the
  notification. From then on, leaving the screen counts as leaving, as on
  iOS. The flow keeps its snapshot, and coming back to it still works. While
  the CPU sleeps, the beat cannot run either, so the check happens on the
  device's next wake. That is the moment someone could see the notification.
- **Doze and Battery Saver** do not stop a foreground service. Battery Saver
  mutes `USAGE_TOUCH` vibrations whether the app is in front or not.
- **Process death** (low memory, Task Manager's Stop) takes the service, the
  notification and the lock with the process. The service is not sticky, so
  the snapshot and Today's "Continue the workout?" bring the workout back,
  and nothing restarts on its own.
