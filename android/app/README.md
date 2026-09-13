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
│   │   workout/     Warmup, GetReady, Cooldown, BlockPause, SessionAhead,
│   │                SetFacts, Retrospective, Milestones, LifeBenefit
│   │   journal/     Journal, V2EngineState, Backup
│   │   health/      Health Connect — write-only, like HealthStore + EnergyEstimate
│   │   reminders/   NotificationScheduling, ReminderSound
│   │   signals/     CountdownSounds, WorkoutSignals — synthesised, no media files
│   │   widgets/     Glance: TodayStatusWidget, TodayProvider, WidgetSnapshot
│   │                (the two-week snapshot is rewritten after every persisted
│   │                change; the widget never computes rest days itself)
│   │   ui/          theme/ (tokens, dredfitFont, the 44 dp target), RootScreen,
│   │                today/, workout/, progress/, settings/, technique/
│   └── res/
│       values/, values-de/, values-es/, values-fr/, values-it/,
│       values-b+pt+BR/, values-ru/
│                    strings_core.xml, strings_app.xml, strings_widgets.xml —
│                    GENERATED from the String Catalogs, one file per source
│                    catalog so a key's provenance is visible from the file name
│       drawable/, mipmap-*/
├── test/kotlin/com/dredfit/         the counterpart of ios/DredfitTests
└── androidTest/kotlin/com/dredfit/  the counterpart of ios/DredfitUITests
    AccessibilityId.kt   the same names as `enum AX` on iOS — testTag equals
                         accessibilityIdentifier, so one screenshot pipeline
                         serves both stores
    WorkoutDriver.kt     ONE walk through the flow; a second copy would drift
```
