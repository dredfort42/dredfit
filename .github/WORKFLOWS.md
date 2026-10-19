# CI/CD & release automation

How the GitHub Actions in this repo fit together, what gates a merge, and the
step-by-step release procedure. All workflows live in
[`.github/workflows/`](workflows); shared helpers live in
[`scripts/`](../scripts) and [`.github/actions/`](actions).

## Workflows at a glance

| Workflow | File | Trigger | Gates a merge? | Runtime |
|---|---|---|---|---|
| **iOS** — unit tests (Core + app) + engine-gate contract | `ci.yml` | push/PR to `main`, `develop`, `release/**`, `hotfix/**` + manual | ✅ **required** | ~5–15 min |
| ↳ **Release build** — unsigned `-configuration Release`, generic iOS | `ci.yml` (`release-build`) | same | ❌ advisory (for now)† | ~10 min |
| ↳ **App unit tests in Europe/Berlin** — `TEST_RUNNER_TZ` | `ci.yml` (`app-tests-timezone`) | push to the iOS workflow's branches + manual, not PRs | ❌ advisory† | ~5–15 min |
| **Lint** — SwiftLint (container pinned to `0.65.1`) | `lint.yml` | push/PR, as iOS (no manual) | ✅ **required** | ~30 s |
| **Localization** — String Catalog completeness | `localization.yml` | same | ✅ **required** | ~10 s |
| **Android** — Kotlin engine vs `golden.json`, app unit tests, debug build, unsigned release APK and bundle | `android.yml` | push/PR as iOS, when `android/`, the fixture or a String Catalog changed + manual | ❌ not required | ~5 min |
| **iOS UI tests** | `ui-tests.yml` | nightly, only if the app or its UI tests changed + manual | ❌ non-gating | ~75–100 min |
| **CodeQL** — Swift security scan | `codeql.yml` | push to `main`/`develop` + weekly | ❌ advisory | ~15 min |
| **PR title** — Conventional Commits | `pr-title.yml` | PR | ❌ advisory | ~5 s |
| **Secret scan** — gitleaks | `gitleaks.yml` | push/PR + weekly | ❌ advisory | ~1 min |
| **Release checks** — version/changelog | `release-checks.yml` | push to `release/**`, `hotfix/**` | ❌ advisory* | ~5 s |
| **Release** — GitHub Release | `release.yml` | tag `v*` | — | ~15 s |

Names follow one pattern. A workflow is named for what it covers, in sentence
case (iOS, Android, iOS UI tests, Lint, Localization, CodeQL, Secret scan, PR
title, Release checks, Release). A job — the check name a PR shows, and the
name branch protection matches — is `Scope: subject`, unique across all
workflows: `iOS: app unit tests`, `Android: engine tests`, `Engine: gate table
contract`. A step is an imperative in sentence case (`Check out`, `Run tests`,
`Upload test results on failure`). Renaming a required job means updating
`CONTEXTS` in `scripts/setup_branch_protection.sh` and re-running it.

\* Release checks is advisory in GitHub's sense (not in the required-checks list
because it only runs on release branches), but treat a red run as a hard stop:
it means the version or changelog is wrong.

† `continue-on-error`: a failure shows red on the job but leaves the iOS run
(and its badge) green, so it never blocks a merge or a release. Read the job
itself. A manual iOS run has its own concurrency group and does not cancel a
push run on the same branch. A push to `develop` starts up to five macOS jobs
at once (both test jobs, both advisory jobs, CodeQL); on GitHub Free that is
the whole macOS allowance, so a PR's required jobs may queue behind them.

**The gate is unit tests, not UI tests.** UI tests are slow and occasionally
flaky on shared runners, so they run nightly — only when the app changed since
the last tested commit — and block nothing. Before cutting a release you run
them locally (see the release procedure below).

## The pipeline by stage

### 1. Open / update a pull request → `develop` (or `main`)
Runs and **must be green to merge**: iOS (Core + app unit tests), Lint,
Localization. Also runs (advisory): PR title, Secret scan, the iOS release build.
Branch protection
keeps the merge button disabled until the required checks pass — see
[Branch protection](#branch-protection).

### 2. Push to `develop` / `main`
Same required checks re-run on the branch head, plus CodeQL and Secret scan,
and the app unit tests once more with the test process in `Europe/Berlin`
(the runner is UTC, which hides day-boundary and DST mistakes) — on every
push to the iOS workflow's branches, `release/**` and `hotfix/**` included.
Start it on any branch with the iOS workflow's **Run workflow**.

### 3. Cut a `release/x.y.z` or `hotfix/x.y.z` branch
**Release checks** verifies the marketing version matches the branch name, build
numbers agree across all targets and exceed the build at the highest older
`v*` tag, and `CHANGELOG.md` has a `## x.y.z` section. Without tags (a shallow
clone) the build-number comparison is skipped with a notice, so the job checks
out full history. Android's version is only noted when it differs: an iOS
release never waits on a Play build ("Android release" below).
iOS (with the advisory Europe/Berlin and release build jobs) + Lint +
Localization also run.

### 4. Tag `vX.Y.Z`
**Release** creates a GitHub Release. Notes come from the `## X.Y.Z` section of
`CHANGELOG.md` (curated), falling back to a commit list if that section is
missing.

### 5. Scheduled
Nightly UI tests (default branch) — skipped when nothing the suite builds or
drives changed since the last commit a run tested: unit tests, docs, store
material and scripts do not count. Weekly CodeQL and gitleaks, weekly Dependabot
updates for GitHub Actions and DredfitCore's Swift dependencies.

## Release procedure

The App Store build itself is produced and uploaded manually from Xcode (Archive
→ Distribute) — the automation covers everything around it. Recommended order:

1. **Bump the version.** Set `MARKETING_VERSION` (x.y.z) and bump
   `CURRENT_PROJECT_VERSION` (build) in the Xcode project — all targets.
   `MARKETING_VERSION` is the product version of both platforms: the next
   Android build takes it as its `dredfit.versionName` ("Android release"
   below). Android's file is not part of an iOS release, and its check only
   notes a difference.
2. **Update `CHANGELOG.md`** with a `## x.y.z` section. These lines become the
   GitHub Release notes verbatim.
3. **Run the engine gates** — `python3 scripts/check_engine_gates.py`. Five
   commands out of the local `reference/`; the runner fails on any that dies
   before its first check, which is how three of six went unnoticed on engine
   3.0.0. CI cannot do this one: the contour is not in the repository.
4. **Rebuild the marketing site** if content changed:
   `python3 sitegen/build.py` (writes `docs/`), commit the result. *`sitegen/`
   is a local-only tool — it is not in CI, so this step is manual.*
5. **Run UI tests locally** — they don't gate CI, so this is the only place the
   full flow is actually checked. Erase the simulator first (an app installed by
   hand makes the runner fail preflight), then:

   ```sh
   xcrun simctl shutdown all && xcrun simctl erase "iPhone 17 Pro"
   set -o pipefail
   xcodebuild test -project ios/Dredfit.xcodeproj -scheme Dredfit -testPlan Dredfit \
     -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
     -parallel-testing-enabled NO -retry-tests-on-failure -test-iterations 3 \
     CODE_SIGNING_ALLOWED=NO
   ```

   `-parallel-testing-enabled NO` is required: simulator clones exhaust the host
   and fail to connect, which looks like a test failure but isn't. Judge the run
   by `** TEST SUCCEEDED **` and `Executed N tests, with 0 failures`, not by the
   pipe's exit code.
6. **Create the `release/x.y.z` branch and push.** Confirm **Release checks**,
   **iOS**, **Lint**, and **Localization** are green. A red advisory job inside
   a green iOS run (Europe/Berlin, Release build) does not block, but look at
   why before you merge.
7. **Merge to `main`** (and back-merge `main` → `develop`).
8. **Tag `vX.Y.Z` and push the tag.** The **Release** workflow publishes the
   GitHub Release.
9. **Archive & upload the build** from Xcode.

Sanity-check the version/changelog before you push:

```sh
python3 scripts/check_version.py release/1.8.0
```

## Android release

The Android app carries the iOS app's product version (owner decision,
11.10.2026): `dredfit.versionName` in `android/gradle.properties` is the
tree's `MARKETING_VERSION`, and `dredfit.versionCode` is Play's own counter.
An Android-only fix ships the same versionName with the next code — 2.5.0
build 2. `python3 scripts/check_version.py --android` holds both, and
`android/tools/build-release.sh` runs it before it asks for the key; an iOS
release only notes a difference. Google Play gets an App Bundle built and
signed on the owner's Mac by that script; the Android workflow builds the
same release unsigned on every change and gates nothing. Why the version
code counts as it does, how the key is handled and why R8 is on:
[`android/README.md`](../android/README.md), "Releasing".

1. **Bump the version** in `android/gradle.properties`: `dredfit.versionCode`
   +1 for every bundle uploaded to Play, whatever the track.
   `dredfit.versionName` moves only with the product version, to iOS's
   `MARKETING_VERSION`.
2. **Update `CHANGELOG.md`.** Android's notes are always their own
   `## x.y.z (Android)` section, above iOS's `## x.y.z` — iOS's may have
   shipped long before, with a GitHub Release made from it as it stood — and
   an Android-only fix adds its lines there. `check_version.py --android`
   fails without it; `python3 scripts/changelog_section.py "x.y.z (Android)"`
   prints it.
3. **Run the connected suite** on an emulator — never on a phone; CI does not
   run it:

   ```sh
   export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
   export ANDROID_HOME=~/Library/Android/sdk
   cd android && ANDROID_SERIAL=emulator-5554 ./gradlew :app:connectedDebugAndroidTest
   ```

4. **Reach `main`** through the `release/x.y.z` or `hotfix/x.y.z` branch of
   steps 6 and 7 above, x.y.z being the product version. The bundle is built
   from `main` so that its tag names a commit that stays: a squash merge
   discards a PR branch's own commits.
5. **Build the bundle** from `main` as origin has it (the script fetches and
   refuses anything else, a dirty `android/` or a traced run):
   `android/tools/build-release.sh`. macOS asks whether `security` may read
   the `dredfit-release-keystore` item; the script prints the bundle's path,
   the version, the commit, the tag to give it and the upload certificate's
   SHA-256. Stopped midway, it leaves no bundle behind.
6. **Google Play Console.**
   - **The first upload sets up Play App Signing, and that choice cannot be
     undone**: which key signs what Play delivers — one Google generates, or
     one uploaded to it — is fixed for the app from then on. **Open question
     for the owner, before choosing:** the SHA-256 of
     `~/keys/dredfit-release.jks` was registered for Android developer
     verification on 05.10.2026. Check in Play Console what that
     registration expects of the app-signing key; it is not decided here.
   - Afterwards App integrity must show the SHA-256 the script printed as the
     upload key certificate.
   - Internal testing → create a release, upload
     `android/app/build/outputs/bundle/release/app-release.aab`, add the
     release notes (≤ 500 characters per language), roll out to the testers.
   - The declarations Play asks for — the `health` foreground service,
     Health Connect, Data safety — are listed in `android/README.md` under
     "Play Console".
7. **Tag `android-vX.Y.Z+CODE`** on the commit the script printed, and push
   the tag — one tag per uploaded bundle:

   ```sh
   git tag android-v2.5.0+1 <commit> && git push origin android-v2.5.0+1
   ```

   - **The form.** The code rides as semver build metadata (`+1`), which is
     what it is: the same version, another build. `git check-ref-format`
     accepts it; a `-b1` suffix would read as a pre-release of 2.5.0.
     `check_version.py --android` reads the codes from these names, of
     every version.
   - **Not `vX.Y.Z`.** `v2.5.0` already names the iOS release on `main`, a
     tag names one commit, and moving a published tag rewrites a shipped
     release. The `android-v` prefix is outside both `v*` patterns:
     `release.yml` makes no GitHub Release for it (and does not overwrite
     iOS's), and `check_version.py` compares iOS build numbers with `v*`
     tags only.
   - **A GitHub Release** for the Android section, if wanted, is made by
     hand:

     ```sh
     python3 scripts/changelog_section.py "2.5.0 (Android)" > notes.md
     gh release create android-v2.5.0+1 --verify-tag --latest=false \
       --title "Android 2.5.0 (1)" --notes-file notes.md
     ```

## Branch protection

CI results only *block* if branch protection requires them. Apply it once:

```sh
./scripts/setup_branch_protection.sh          # apply to develop + main
./scripts/setup_branch_protection.sh --dry-run # preview the payload
```

What it sets, and why (tuned for a solo maintainer):

- **Required status checks** on `develop` and `main`: `iOS: engine tests`,
  `iOS: app unit tests`, `iOS: SwiftLint`, `Localization: String Catalogs`. A PR can't merge until these are green.
- **`enforce_admins: false`** — you can still push the direct release plumbing
  (main → develop back-merges, release/* → main) as an admin without a PR. Turn
  it on if you want those gated too.
- **No required reviewers** (solo repo); force-pushes and deletions are blocked;
  conversations must be resolved.

The advisory checks (CodeQL, PR title, the secret scan, and the iOS release
build and Europe/Berlin jobs) are deliberately **not** required, so a third-party action outage can never wedge your merges. Promote any of them to required by adding its check-run name to
`CONTEXTS` in `scripts/setup_branch_protection.sh` and re-running.

## Local helpers (`scripts/`)

| Script | What it does |
|---|---|
| `check_localization.py` | Fails if any shipping language (de, es, fr, it, pt-BR, ru) is missing a translation. Run with no args to check all tracked `*.xcstrings`. |
| `check_translation_rules.py` | Fails if a shipped translation breaks a rule the completeness check cannot see: ru `ё` and formal `вы`, fr `U+00A0`/`U+202F`/apostrophe and `vous`, it apostrophe and `Lei`, de `—`/`Min.`/`Workout`/`Sie`, es `usted`, weight units, double spaces, placeholder parity. Proves every rule can still fail before it reports success; `--list` prints the rules. Exceptions with their reasons live in `scripts/translation_rules_config.json`. |
| `check_version.py <release/x.y.z \| x.y.z>` | Verifies marketing version, build-number agreement, a build number above the highest older `v*` tag (a notice, not a failure, when the tags are missing), and a changelog section; notes an Android version that differs. `--android` instead gates an Android build: `dredfit.versionName` equals `MARKETING_VERSION`, and `dredfit.versionCode` is a positive integer above every code an `android-vX.Y.Z+CODE` tag carries. Tests: `test_check_version.py` (CI's gate-contract job). |
| `check_engine_gates.py` | Runs every engine gate the `TESTPLAN.md` table names and fails on any that did not print its clean line. `--contract` parses the table without running anything — that is what CI does, since `reference/` is gitignored and never on a runner. |
| `changelog_section.py <version>` | Prints the `CHANGELOG.md` section for a version (used for release notes). |
| `setup_branch_protection.sh` | Applies branch protection (above). |
| `localization_config.json` | Required locales + keys intentionally identical to the source (punctuation, brand name). |

### Adding an intentionally-untranslated string
If a key is the same in every language (a separator, the brand name), either set
`shouldTranslate: false` on it in Xcode, or add it under `allow_untranslated` in
`scripts/localization_config.json`. Otherwise the Localization check treats a
missing translation as a failure.

## Reproducible Xcode version

macOS jobs select Xcode via the shared composite action
[`.github/actions/setup-xcode`](actions/setup-xcode), pinned to major **26**
with a fallback to the latest stable if that major isn't on the runner. To move
to a new Xcode major, change the `default` in
`.github/actions/setup-xcode/action.yml` (one place, all jobs).

### Compiler warnings are errors in CI

Every compile in `ci.yml` treats a compiler warning as an error:
`swift test --parallel -Xswiftc -warnings-as-errors` for the core package, and
`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES` on the
`xcodebuild` command line of the app unit tests, the Europe/Berlin run and the
Release build. The settings live in the workflow, not in `project.pbxproj`, so
a local build in Xcode is never blocked by them.

The consequence is deliberate: when the runner gets a new Xcode, or the pinned
major moves, any new compiler warning fails the job that compiles it until the
code is fixed. In the two required jobs that blocks a merge — and the app
unit-test job builds every test target, the UI-test sources included, so a
warning in `ios/DredfitUITests` blocks one too, although the UI tests themselves
gate nothing. A warning that only the Release build sees (say, a value that
only `#if DEBUG` code reads, left unused without it) reddens the advisory
`release-build` job alone.
Reproduce a red run locally by passing the same flags:

```sh
xcodebuild build-for-testing -project ios/Dredfit.xcodeproj -scheme Dredfit \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
cd ios/DredfitCore && swift test --parallel -Xswiftc -warnings-as-errors
```

Build-tool notices that are not compiler diagnostics (for example
`appintentsmetadataprocessor`'s "Metadata extraction skipped") are not affected.
SwiftLint is not run with `--strict`: its warning/error split is intentional,
and only its errors fail the Lint job.

### SwiftLint version

SwiftLint in CI runs from a pinned container image (`lint.yml`). Dependabot
does not bump container images, so move that tag by hand, together with the
local `swiftlint`.
