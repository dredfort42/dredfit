# android/app

The Compose app — the counterpart of `ios/Dredfit`, `ios/DredfitWidgets` and
`ios/Shared` in one module. Package `com.dredfit`, application id
`com.dredfit.dredfit` (iOS ships as `com.dredfit.Dredfit`).

```text
app/src/
├── main/
│   ├── AndroidManifest.xml
│   ├── kotlin/com/dredfit/
│   │   DredfitApp.kt
│   │   store/       AppStore.kt plus AppStoreCadence.kt, AppStoreCalendar.kt …
│   │                — the iOS rule "extensions only read, every mutating
│   │                decision stays in AppStore" becomes a compiler rule here:
│   │                an extension function cannot touch private state
│   │   workout/     the flow without its screens: WorkoutSession and its
│   │                WorkoutSession<Part>.kt extensions, Countdown, GuidedBlock,
│   │                Warmup, GetReady, Cooldown, BlockPause, SessionAhead,
│   │                SetFacts, Retrospective, Milestones, LifeBenefit — plain
│   │                Kotlin on an injected clock; what it says is `Words`
│   │                (key + args, resolved by `ui/L10n.kt`), what it plays
│   │                goes through `WorkoutSignalling` (WorkoutSignals.kt), what
│   │                the ongoing notification shows through
│   │                `WorkoutActivityDriving`
│   │   journal/     Journal, V2EngineState (the backup itself is
│   │                store/AppStoreBackup.kt, after AppStore+Backup.swift)
│   │   health/      Health Connect — write-only, like HealthStore + EnergyEstimate
│   │   reminders/   NotificationScheduling, ReminderSound
│   │   signals/     CountdownSounds and the device half of WorkoutSignals —
│   │                synthesised, no media files
│   │   widgets/     Glance: TodayStatusWidget, TodayProvider, WidgetSnapshot
│   │                (the two-week snapshot is rewritten after every persisted
│   │                change; the widget never computes rest days itself)
│   │   l10n/        CoreStrings, AppStrings, WidgetStrings — GENERATED key →
│   │                resource-id lookups, so code calls `tr("English key")`
│   │   ui/          theme/ (tokens, dredfitFont, the 44 dp target), RootScreen,
│   │                today/, workout/, progress/, settings/, technique/
│   └── res/
│       values/, values-de/, values-es/, values-fr/, values-it/,
│       values-b+pt+BR/, values-ru/
│                    strings_core.xml, strings_app.xml, strings_widgets.xml —
│                    GENERATED from the String Catalogs, one file per source
│                    catalog so a key's provenance is visible from the file name;
                    resource name = <catalog>_<slug of the key, 40>_<sha1[:8]>
│       drawable/, mipmap-*/
├── test/kotlin/com/dredfit/         the counterpart of ios/DredfitTests
└── androidTest/kotlin/com/dredfit/  the counterpart of ios/DredfitUITests
    AccessibilityId.kt   the same names as `enum AX` on iOS — testTag equals
                         accessibilityIdentifier, so one screenshot pipeline
                         serves both stores
    WorkoutDriver.kt     ONE walk through the flow; a second copy would drift
```
