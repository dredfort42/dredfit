# android/core

The Kotlin port of `ios/DredfitCore` — the engine as pure functions. A plain
`kotlin("jvm")` module with **no Android plugin**, so `./gradlew :core:test`
runs on any machine without an emulator, the way `swift test` does for the
Swift package, and the CI job for it can run on ubuntu in seconds.

```text
core/
├── build.gradle.kts     test resources point at
│                        ../../ios/DredfitCore/Tests/DredfitCoreTests/Fixtures
│                        — golden.json and reference-manifest.json, the one copy
└── src/
    ├── main/kotlin/com/dredfit/core/
    │   Breaks.kt          the only file that sees a date
    │   Descent.kt, Dose.kt, Engine.kt, Feedback.kt, Handles.kt, Session.kt,
    │   SubStep.kt, WarmupTechnique.kt, MigrationV2.kt
    │   EngineState.kt     decodeLenient, the sanitizer, and a serializer that
    │                      reads the iOS shape (unkeyed [Pattern: Int])
    │   Library.kt, LibraryLegs.kt, LibraryPull.kt, LibraryPush.kt
    │                      (a `+` in a Kotlin file name does not survive)
    │   SetsHandle.kt      no default arguments, for the same reason as Swift
    └── test/kotlin/com/dredfit/core/
        GoldenFixture.kt, GoldenTest.kt, EngineTest.kt, EngineV3Test.kt,
        DescentSweepTest.kt, LibraryPinTest.kt, ManifestTest.kt
                           — the seven names of DredfitCoreTests, one to one
```

The first test to write is `GoldenTest`: it reads the fixture and fails on the
first scenario, so the port starts from a red test rather than a blank file.
Plausible-but-different is a failing test here too, not a judgment call.
