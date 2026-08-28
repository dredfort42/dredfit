# Screenshot pipeline

Four steps, all repeatable for any release: seed → capture → compose → remove
the driver. Nothing here is run by CI; the whole pipeline is a local, manual
operation whose only gate is the eye of the person running it.

The composition of the ten slots is NOT a constant. It is decided per release
by `release-frames` and approved by the owner BEFORE the capture — capture is
the most expensive operation of the cycle. The authoritative table lives in
`instructions/RELEASE_PROMPT.md` (Э3); this file only says how to run it.

## 1. Seed the app state

The marketing screens run on a real app with a planted history. With the app
installed on the simulator (any earlier test run does this):

```bash
python3 seed.py <udid> A   # counter 11 → Today, How it works, set, dial, rest, rating
python3 seed.py <udid> B   # counter 34, 667 steps in total → Progress
python3 seed.py <udid> C   # counter 11, push_h parked on its dose ceiling → the probe
python3 seed.py <udid> D   # counter 14, hinge alone in a four-set band → the skip
```

| seed | feeds | why it is a seed and not a launch flag |
|---|---|---|
| A | `testSeeded*`, `testRating*` | a trained-but-ordinary history |
| B | `testProgress*` | enough sessions for the chart to have a shape |
| C | `testProbe*` | the probe is a POSITION (§40.4), and a planted file is exactly what states one |
| D | `testSkip*` | `--uitest-long-session` gives every ladder four sets and a 67-minute session; the listing promises 30.5 |
| — | `testComeback*` | no seeding: `--uitest-comeback` owns the date arithmetic a file cannot state |

**The driver carries no `--uitest-*` flag of its own, and must never gain one.**
The live set of those flags is ten and every one of them is passed by a test of
the suite; this file is not part of the suite, so a flag added for it would be
a flag no suite run can keep honest. What the driver needs is a STATE, and
`seed.py` plants states.

`seed.py` also owns the `counter`, and that is not a convenience: which six
movements a session is made of, and in what order, is a pure function of it.
Both new seeds need a NAMED movement to be the FIRST exercise, because each
route walks one exercise and stops. Change a counter and the frame changes
movement with no warning anywhere.

**Re-seed before every capture that runs a workout, not just between the
groups.** Since 1.6.0 the flow snapshots its position, and `testRating*` stops
on the rating screen without answering — so it leaves an unfinished workout
behind. The next launch then opens Today on "Continue the workout?" instead of
the Start button the capture waits for, and the run fails. Re-seeding rewrites
the state file and clears the snapshot with it.

## 2. Capture raw screens

Drop `StoreScreenshots.swift.reference` into `DredfitUITests/` as
`StoreScreenshots.swift` (synchronized groups pick it up automatically), then:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TEST_RUNNER_SCREENSHOT_DIR=/path/to/raw xcodebuild test \
  -project Dredfit.xcodeproj -scheme Dredfit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  -only-testing:DredfitUITests/StoreScreenshots/testSeededRussian \
  -parallel-testing-enabled NO
```

**One test METHOD per invocation — the `-only-testing:` line above names one on
purpose.** It used to name the whole class, two paragraphs above the sentence
telling you not to, and a class-wide run is what produced the 2.0.0 language
defect below: 42 methods in one runner process, each relaunching the app in a
different language.

`TEST_RUNNER_` env vars must be in xcodebuild's environment, not build
settings. The six methods are `testSeeded* / testProgress* / testProbe* /
testSkip* / testRating* / testComeback*`, each × the seven shipping languages
(English, Russian, Spanish, Portuguese, German, French, Italian) — 42 tests
producing 70 raws. Raws are suffixed by locale tag and `compose.py` writes each
to its own folder. iPhone 17 Pro Max gives the store's 6.9" size (1320×2868).

**Run one test method per `xcodebuild` invocation** on a pre-booted simulator,
and between them terminate the app and pause before re-seeding:

```bash
xcrun simctl terminate <udid> com.dredfit.Dredfit; sleep 3
python3 seed.py <udid> A
```

Seeding immediately after `xcodebuild` returns is a race the 1.9.0 recapture
lost four times out of seven: the app is still flushing its own state as the
seed is written, so the next launch opens on a workout in progress and the
capture fails at "no Start on Today". Terminating first makes it deterministic.

**Scout one locale before paying for seven.** `seed.py <udid> A` then
`-only-testing:DredfitUITests/StoreScreenshots/testSeededEnglish`. It is the
longest single route (Today, How it works, and five screens of the workout), so
a driver that survives it survives the rest. Every control on the route is
addressed by `accessibilityIdentifier`, never by a localized title: XCUITest
matches the identifier first and only falls back to the label when none is set,
so once the app pinned `start-workout`, `exercise-done`, `skip-rest` and the
rest, every query for "Start" / "Начать" stopped resolving and the run died on
its first assert. A recapture that starts failing on assert one is almost
always this, or its twin: the workout opens on the warm-up OFFER
(`warmup-intro-skip`), and `skip-warmup` belongs to the block behind it.

## 3. Compose framed images

`RAW_DIR=/path/to/raw python3 compose.py` (needs Pillow). Captions live at the
bottom of the file: ten frames × seven languages = **70 lines of `jobs`**, and
the script asserts that count, that a raw's locale tag matches the folder it is
written to, and that every locale carries s1…s10.

Style constants at the top were measured from the 1.3.0 set (`en/s1.png`):
Helvetica Bold 106 headline, Helvetica 43 subtitle, frame (26,26,28) radius
166, background gradient (246,245,242)→(237,235,230). Two-line headlines shift
the whole device down by 117 px, as in the original set. The simulator status
bar is painted over with the app's own top background before the rounded mask,
so no time/battery ever shows.

**"A frame without a fresh raw keeps its last set" is a trap as often as a
convenience.** It makes a partial recapture cheap, and it also leaves a removed
mechanism advertised in the store, or — after a slot reorder — every remaining
frame sitting under someone else's caption. That is why a slot that changes
meaning changes its RAW NAME too, and why a set whose numbering moved is
deleted rather than overwritten in place: an empty folder is honest, a
half-renumbered one is not.

Captions are checked by NOTHING. `scripts/check_localization.py` and the
required `Localization` job walk String Catalogs only; an English phrase that
reaches the German storefront fails no run. Lines still marked `TODO-i18n` in
`compose.py` are waiting on a translator and must not ship.

One thing about a caption IS checked, since 2.0.0: **its width.** `compose.py`
centres a line on the 1320 px canvas and silently CLIPS whatever falls outside,
and the frame around it still looks finished — so seven captions shipped for
review with a first letter, a final letter or a whole first word cut off, and
the eye that reviewed the set read the sentence it expected instead of the one
on the canvas. The script now measures every line with its own fonts and its
own centring, and refuses to compose anything at all if a line leaves less than
8 px of background on either side. It also prints a `tight:` note under 24 px,
which is advice, not a failure — the approved set contains a 1302 px line
(`es/s3`), and a gate that fails work the owner has signed off is a gate people
learn to bypass.

The fix for a clipped line is never a smaller font. A **subtitle** is always one
line, so only the wording can give. A **headline** has a second tool — a break
into two lines — but that break is a composition decision: two lines push the
whole device down 117 px, so it is placed where the PHRASE divides (subject |
predicate, or on the comma of a French dislocation), never merely where the
pixels ran out.

## The trap that cost 2.0.0 its first review: the wrong language in the frame

Ten of the seventy 2.0.0 frames were English screens filed under a foreign
locale — six `s5`, three `s2`, one `s7` — and one more (`ru/s1`) was an English
screen with a Russian *region*, dated "FRIDAY 28 AUGUST" in day-month order.
Two independent mechanisms, both now closed in `launch(_:_:)`:

**The argument domain pairs tokens, and `--uitest-*` flags shift the pairing.**
`NSUserDefaults` reads `-key value` left to right, so `["--uitest-reset"] +
["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]` pairs `-uitest-reset` with
`-AppleLanguages`, drops `(ru)` on the floor as a token that is not a key, and
then pairs `-AppleLocale` with `ru_RU` perfectly. Region arrives, language does
not — which is exactly what `ru/s1` shows. An ODD number of flags in front of
the locale pair is all it takes. The locale arguments therefore go FIRST now,
where nothing a caller passes can shift them.

**`-AppleLanguages` is read once, at process start.** A `launch()` that lands on
an app still alive from the previous test method keeps THAT method's language.
`terminate()` only requests the kill and returns — the same asynchrony this file
already documents for seeding, which the 1.9.0 recapture lost four times out of
seven. `launch(_:_:)` now terminates, waits for `.notRunning`, and only then
launches.

**And the reason it shipped rather than went red: the driver could not see it.**
Every control on every route is addressed by `accessibilityIdentifier`, and an
identifier is the same word in all seven languages — so an app in English walked
the Russian route to the end and wrote `skip_ru.png` with every assert green.
Nothing downstream looks either: `compose.py` trusts the tag in the filename and
the required `Localization` check walks String Catalogs. The one route that
could not fail this way was `testProgress*`, and only by accident — it taps the
tab by its localized title, so a wrong language made it go red instead of lying,
which is why `s6` is the one slot with no bad frame in the set.

`launch(_:_:)` now ends in `assertLanguage`, the file's single deliberate
localized assert: the Progress tab must read the locale's word, **and** must not
read the English "Progress". Both halves are needed — the positive one alone
passes on any fallback that happens to render the same string. Keep it to that
one tab title: it is the only localized surface `L` carries, and widening it
would hand a reworded caption the power to break the capture of six locales.

## 4. Remove the driver

```bash
rm DredfitUITests/StoreScreenshots.swift
```

It is not part of the suite and must not be left behind: it is slow, it depends
on a hand-planted state file, and a nightly run that picks it up goes red for a
reason that has nothing to do with the app.
