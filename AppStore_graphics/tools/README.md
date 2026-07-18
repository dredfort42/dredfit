# Screenshot pipeline

Two steps, both repeatable for any release.

## 1. Capture raw screens

Drop `StoreScreenshots.swift.reference` into `DredfitUITests/` as
`StoreScreenshots.swift` (synchronized groups pick it up automatically), then:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TEST_RUNNER_SCREENSHOT_DIR=/path/to/raw xcodebuild test \
  -project Dredfit.xcodeproj -scheme Dredfit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  -only-testing:DredfitUITests/StoreScreenshots \
  -parallel-testing-enabled NO
```

`TEST_RUNNER_` env vars must be in xcodebuild's environment, not build
settings. iPhone 17 Pro Max gives the store's 6.9" size (1320×2868). Delete
the .swift file afterwards — it is not part of the suite.

## 2. Compose framed images

Edit paths/captions at the bottom of `compose.py`, then `python3 compose.py`
(needs Pillow). Style constants at the top were measured from the 1.3.0 set
(`en/s1.png`): Helvetica Bold 106 headline, Helvetica 43 subtitle, frame
(26,26,28) radius 166, background gradient (246,245,242)→(237,235,230).
The simulator status bar is painted over with the app's own top background
before the rounded mask, so no time/battery ever shows.
