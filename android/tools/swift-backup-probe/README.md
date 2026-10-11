# swift-backup-probe

The iOS app's own persistence code, run from the command line, so the Android
port can be checked against what Swift actually writes and reads. A backup is
the bridge between the two ports: it only works if both sides read the same
file the same way.

`Sources/SwiftBackupProbe/` holds **symlinks** to the app's Codable sources —
`AppSettings.swift`, `Journal.swift`, `AppStore+PersistedState.swift`,
`V2EngineState.swift`, `SetFacts.swift` in `ios/Dredfit/` — never copies, and
the package depends on `ios/DredfitCore` by relative path. `AppShims.swift`
holds the only stand-ins, none of them a persisted type: a `Pattern` alias
(macOS SwiftUI exports a `Pattern` of its own, and `SetFacts.swift` imports
SwiftUI), and an `AppStore`, a `Theme` and a `dredfitFont` that the trailing
`extension AppStore` in `AppSettings.swift` and the `SetFactsLabel` view in
`SetFacts.swift` name. Nothing in the probe calls them; they trap if reached.

## Regenerate the fixtures

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer android/tools/swift-backup-probe/regenerate.sh
```

Writes, with `SWIFT_DETERMINISTIC_HASHING=1` so a rerun gives the same bytes:

| File | What |
|---|---|
| `android/core/src/test/resources/swift/sessions.json` | `[Session]`: the initial plan, the bar plan, the first uneven plan (`loads`) and the first plan with a `probe` of a run |
| `android/app/src/test/resources/ios/ios-backup.json` | `AppData` exactly as `exportURL` writes it — six workouts through the engine, every optional record field and every settings key set |
| `android/app/src/test/resources/ios/ios-state-pending.json` | the same with a `pendingWorkout` carrying every snapshot field — the state file's shape |
| `…/ios/ios-backup.swift-decoded.json` | what Swift reads back out of the backup, re-encoded with sorted keys, plus its decode flags |
| `…/ios/ios-state-pending.swift-roundtrip.json` | Swift's decode → encode of the pending state |

`CrossPlatformBackupTest` and `SessionJsonTest` compare against them.

## Check that an Android export reads on iOS

`CrossPlatformBackupTest` writes the Android export to
`android/app/build/cross-platform/android-backup.json`. Then:

```sh
cd android && ./gradlew :app:testDebugUnitTest --tests 'com.dredfit.CrossPlatformBackupTest'
cd tools/swift-backup-probe && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run -c release SwiftBackupProbe decode ../../app/build/cross-platform/android-backup.json
```

It prints `{"ok":true,…}` with `droppedRecordCount` 0 and the three flags
false when Swift reads the whole file; `{"ok":false,"error":…}` otherwise.
The other commands: `sessions <out>`, `backup <out> <pending-out>`,
`decode-session <in>`, `roundtrip <in> <out>`.
