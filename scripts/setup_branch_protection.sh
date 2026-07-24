#!/usr/bin/env bash
# Apply branch protection to develop and main so the CI gates actually block.
#
# Requires the GitHub CLI (`gh`) authenticated as a repo admin. Run it once;
# re-run any time the required checks change.
#
#     ./scripts/setup_branch_protection.sh            # apply
#     ./scripts/setup_branch_protection.sh --dry-run  # print the payload only
#
# Design (tuned for a solo maintainer who pushes release plumbing directly):
#   * Required status checks gate every PULL REQUEST — the merge button stays
#     disabled until the core gates are green.
#   * enforce_admins = false — you (admin) can still push the direct release
#     back-merges (main -> develop, release/* -> main) without a PR.
#   * No required reviewers — solo repo.
#   * Force-pushes and branch deletion are blocked.
#
# See .github/WORKFLOWS.md for the full rationale.
set -euo pipefail

REPO="dredfort42/dredfit"
BRANCHES=("develop" "main")

# These names must match the check-run names exactly (the job `name:` fields).
CONTEXTS=(
  "DredfitCore package tests"
  "Dredfit app unit tests (iOS Simulator, no UI)"
  "SwiftLint"
  "Localization"
)

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# Build the required_status_checks.contexts JSON array.
contexts_json=$(printf '%s\n' "${CONTEXTS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')

payload=$(cat <<JSON
{
  "required_status_checks": { "strict": false, "contexts": ${contexts_json} },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
)

for branch in "${BRANCHES[@]}"; do
  echo "== ${REPO} @ ${branch} =="
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "$payload"
    continue
  fi
  echo "$payload" | gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "repos/${REPO}/branches/${branch}/protection" \
    --input - > /dev/null
  echo "  protection applied."
done

echo "Done. Verify at: https://github.com/${REPO}/settings/branches"
