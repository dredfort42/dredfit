# CI/CD & release automation

How the GitHub Actions in this repo fit together, what gates a merge, and the
step-by-step release procedure. All workflows live in
[`.github/workflows/`](workflows); shared helpers live in
[`scripts/`](../scripts) and [`.github/actions/`](actions).

## Workflows at a glance

| Workflow | File | Trigger | Gates a merge? | Runtime |
|---|---|---|---|---|
| **CI** — unit tests (Core + app) | `ci.yml` | push/PR to `main`, `develop`, `release/**`, `hotfix/**` | ✅ **required** | ~5–15 min |
| **Lint** — SwiftLint | `lint.yml` | same | ✅ **required** | ~30 s |
| **Localization** — String Catalog completeness | `localization.yml` | same | ✅ **required** | ~10 s |
| **UI Tests** | `ui-tests.yml` | nightly + manual | ❌ non-gating | ~20–45 min |
| **CodeQL** — Swift security scan | `codeql.yml` | push to `main`/`develop` + weekly | ❌ advisory | ~15 min |
| **PR Title** — Conventional Commits | `pr-title.yml` | PR | ❌ advisory | ~5 s |
| **Secret Scan** — gitleaks | `gitleaks.yml` | push/PR + weekly | ❌ advisory | ~1 min |
| **Release Checks** — version/changelog | `release-checks.yml` | push to `release/**`, `hotfix/**` | ❌ advisory* | ~5 s |
| **Release** — GitHub Release | `release.yml` | tag `v*` | — | ~15 s |

\* Release Checks is advisory in GitHub's sense (not in the required-checks list
because it only runs on release branches), but treat a red run as a hard stop:
it means the version or changelog is wrong.

**The gate is unit tests, not UI tests.** UI tests are slow and occasionally
flaky on shared runners, so they run nightly and block nothing. Before cutting a
release you run them locally (see the release procedure below).

## The pipeline by stage

### 1. Open / update a pull request → `develop` (or `main`)
Runs and **must be green to merge**: CI (Core + app unit tests), Lint,
Localization. Also runs (advisory): PR Title, Secret Scan. Branch protection
keeps the merge button disabled until the required checks pass — see
[Branch protection](#branch-protection).

### 2. Push to `develop` / `main`
Same required checks re-run on the branch head, plus CodeQL and Secret Scan.

### 3. Cut a `release/x.y.z` or `hotfix/x.y.z` branch
**Release Checks** verifies the marketing version matches the branch name, build
numbers agree across all targets, and `CHANGELOG.md` has a `## x.y.z` section.
CI + Lint + Localization also run.

### 4. Tag `vX.Y.Z`
**Release** creates a GitHub Release. Notes come from the `## X.Y.Z` section of
`CHANGELOG.md` (curated), falling back to a commit list if that section is
missing.

### 5. Scheduled
Nightly UI tests (default branch), weekly CodeQL and gitleaks, weekly Dependabot
updates for GitHub Actions and DredfitCore's Swift dependencies.

## Release procedure

The App Store build itself is produced and uploaded manually from Xcode (Archive
→ Distribute) — the automation covers everything around it. Recommended order:

1. **Bump the version.** Set `MARKETING_VERSION` (x.y.z) and bump
   `CURRENT_PROJECT_VERSION` (build) in the Xcode project — all targets.
2. **Update `CHANGELOG.md`** with a `## x.y.z` section. These lines become the
   GitHub Release notes verbatim.
3. **Rebuild the marketing site** if content changed:
   `python3 sitegen/build.py` (writes `docs/`), commit the result. *`sitegen/`
   is a local-only tool — it is not in CI, so this step is manual.*
4. **Run UI tests locally** — they don't gate CI. See `instructions/GIT_FLOW.md`.
5. **Create the `release/x.y.z` branch and push.** Confirm **Release Checks**,
   **CI**, **Lint**, and **Localization** are green.
6. **Merge to `main`** (and back-merge `main` → `develop`).
7. **Tag `vX.Y.Z` and push the tag.** The **Release** workflow publishes the
   GitHub Release.
8. **Archive & upload the build** from Xcode.

Sanity-check the version/changelog before you push:

```sh
python3 scripts/check_version.py release/1.7.0
```

## Branch protection

CI results only *block* if branch protection requires them. Apply it once:

```sh
./scripts/setup_branch_protection.sh          # apply to develop + main
./scripts/setup_branch_protection.sh --dry-run # preview the payload
```

What it sets, and why (tuned for a solo maintainer):

- **Required status checks** on `develop` and `main`: `DredfitCore package
  tests`, `Dredfit app unit tests (iOS Simulator, no UI)`, `SwiftLint`,
  `Localization`. A PR can't merge until these are green.
- **`enforce_admins: false`** — you can still push the direct release plumbing
  (main → develop back-merges, release/* → main) as an admin without a PR. Turn
  it on if you want those gated too.
- **No required reviewers** (solo repo); force-pushes and deletions are blocked;
  conversations must be resolved.

The advisory checks (CodeQL, PR Title, gitleaks) are deliberately **not**
required, so a third-party action outage can never wedge your merges. Promote any of them to required by adding its check-run name to
`CONTEXTS` in `scripts/setup_branch_protection.sh` and re-running.

## Local helpers (`scripts/`)

| Script | What it does |
|---|---|
| `check_localization.py` | Fails if any shipping language (es, pt-BR, ru) is missing a translation. Run with no args to check all tracked `*.xcstrings`. |
| `check_version.py <release/x.y.z \| x.y.z>` | Verifies marketing version, build-number agreement, and a changelog section. |
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
