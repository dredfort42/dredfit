# Screenshot pipeline

Three steps, all repeatable for any release.

## 1. Seed the app state

The marketing screens run on a real app with a planted history. With the app
installed on the simulator (any earlier test run does this):

```bash
python3 seed.py <udid> A   # counter 11 → Today, workout flow, rating
python3 seed.py <udid> B   # counter 34, total level 158 → Progress
```

Seed A feeds `testSeeded*` and `testRating*`; seed B feeds `testProgress*`.
Milestone and comeback screens don't need seeding — they use the app's own
`--uitest-milestone` / `--uitest-comeback` launch hooks (see git history of
the reference file for those captures).

**Re-seed before every capture that runs a workout, not just between the two
groups.** Since 1.6.0 the flow snapshots its position, and `testRating*`
stops on the rating screen without answering — so it leaves an unfinished
workout behind. The next launch then opens Today on "Continue the workout?"
instead of the Start button the capture waits for, and the run fails.
Re-seeding rewrites the state file and clears the snapshot with it.

## 2. Capture raw screens

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
settings. The same run covers all four languages — testSeeded/testProgress/
testRating × English/Russian/Spanish/Portuguese; raws get `_es` and
`_pt-br` suffixes, and compose.py writes those frames to `es/` and `pt-br/`. iPhone 17 Pro Max gives the store's 6.9" size (1320×2868). Delete
the .swift file afterwards — it is not part of the suite.

## 3. Compose framed images

`RAW_DIR=/path/to/raw python3 compose.py` (needs Pillow). Frames without a
fresh raw keep their last set, so a partial recapture is just a matter of
which raws exist. Captions live at the bottom of the file. Style constants at the top were measured from the 1.3.0 set
(`en/s1.png`): Helvetica Bold 106 headline, Helvetica 43 subtitle, frame
(26,26,28) radius 166, background gradient (246,245,242)→(237,235,230).
Two-line headlines shift the whole device down by 117 px, as in the original
set. The simulator status bar is painted over with the app's own top
background before the rounded mask, so no time/battery ever shows.
